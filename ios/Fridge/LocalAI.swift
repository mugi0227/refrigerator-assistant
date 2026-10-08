import Foundation
import LiteRTLM
import UIKit
import OSLog

enum FridgeError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

// Cancellation must not wait behind synchronous native inference on the actor.
final class InferenceCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var conversation: Conversation?
    func set(_ value: Conversation?) { lock.lock(); conversation = value; lock.unlock() }
    func cancel() { lock.lock(); let current = conversation; lock.unlock(); try? current?.cancel() }
}

actor LocalAI {
    private let logger = Logger(subsystem: "jp.mugilab.fridge", category: "LocalAI")
    #if targetEnvironment(simulator)
    static let runtimeLabel = "LiteRT-LM 0.15.0 / simulator: CPU text + CPU vision"
    #else
    static let runtimeLabel = "LiteRT-LM 0.15.0 / device: Metal text + CPU vision"
    #endif
    private var engine: Engine?
    private var busy = false
    nonisolated let cancellation = InferenceCancellation()
    func isReady() async -> Bool { guard let engine else { return false }; return await engine.isInitialized() }

    func load(_ model: URL, cache: URL) async throws {
        guard !busy else { throw FridgeError.message("AIの処理中です。終了してから操作してください。") }
        engine = nil
        // Keep compiler caches separate from the failed 0.18.0 configurations.
        // Model weights stay at their existing persistent path.
        let runtimeCache = cache.appendingPathComponent("litert-0.15.0-metal-text-cpu-vision", isDirectory: true)
        try FileManager.default.createDirectory(at: runtimeCache, withIntermediateDirectories: true)
        // Physical-device logs confirm STABLEHLO_COMPOSITE fails with GPU vision.
        // Use the backends in the published 0.15.0 device report. Passing on this
        // device still requires both text and image readiness checks below.
        // Simulator Metal has different limits and cannot validate device GPU execution.
        #if targetEnvironment(simulator)
        let textBackend: Backend = .cpu(threadCount: 4)
        #else
        let textBackend: Backend = .gpu
        #endif
        logger.info("Starting \(Self.runtimeLabel, privacy: .public)")
        let config = try EngineConfig(modelPath: model.path, backend: textBackend,
            visionBackend: .cpu(), maxNumTokens: 2048, cacheDir: runtimeCache.path)
        let next = Engine(engineConfig: config)
        try await next.initialize()
        engine = next
        logger.info("Engine initialized; image readiness check still required")
    }

    func unload() throws {
        guard !busy else { throw FridgeError.message("AIの処理中です。停止してからメモリを解放してください。") }
        engine = nil
    }

    func checkImageInference() async throws {
        // The published device implementation warms GPU decoding on a throwaway
        // text conversation before sending an image. Also distinguish failures
        // in text generation from failures in the vision encoder.
        do {
            logger.info("Checking text generation before image inference")
            let result = try await infer(prompt: "Reply exactly BLUE-47.", image: nil, maxOutputTokens: 16)
            guard let text = result["text"] as? String, text.contains("BLUE-47") else {
                throw FridgeError.message("文章AIの起動検査で正しい回答を確認できませんでした。")
            }
            logger.info("Text readiness check succeeded")
        } catch {
            logger.error("Text readiness check failed: \(error.localizedDescription, privacy: .public)")
            try? unload()
            throw FridgeError.message("文章AIの起動テストに失敗しました。モデルは保存されています。\n\(error.localizedDescription)")
        }
        let jpeg = await MainActor.run {
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            return UIGraphicsImageRenderer(size: CGSize(width: 384, height: 384), format: format).image { context in
                UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 384, height: 384))
            }.jpegData(compressionQuality: 0.85)!
        }
        // Initialization alone can succeed on a device whose vision executor fails.
        // Check a synthetic image before reporting that scanning is ready.
        do {
            logger.info("Checking synthetic 384px JPEG image")
            let result = try await infer(prompt: "Name the color of this image. Answer with one English word.", image: jpeg, maxOutputTokens: 8)
            guard let text = result["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw FridgeError.message("画像AIから回答がありませんでした。")
            }
            guard text.lowercased().contains("red") else {
                throw FridgeError.message("起動検査の画像を正しく読み取れませんでした。")
            }
            logger.info("Image readiness check succeeded")
        } catch {
            logger.error("Image readiness check failed: \(error.localizedDescription, privacy: .public)")
            try? unload()
            throw FridgeError.message("画像AIの起動テストに失敗しました。モデルは保存されています。\n\(error.localizedDescription)")
        }
    }

    func infer(prompt: String, image: Data?, maxOutputTokens: Int) async throws -> [String: Any] {
        guard let engine else { throw FridgeError.message("設定でGemmaを起動してください。") }
        guard !busy else { throw FridgeError.message("AIは処理中です。") }
        busy = true
        let started = Date()
        defer { busy = false; cancellation.set(nil) }
        let config = ConversationConfig(samplerConfig: try SamplerConfig(topK: 1, topP: 1, temperature: 0),
            thinkingConfig: ThinkingConfig(enableThinking: false, thinkingTokenBudget: 0),
            visualTokenBudget: image == nil ? nil : 280)
        let conversation = try await engine.createConversation(with: config)
        cancellation.set(conversation)
        let watchdog = DispatchWorkItem { [cancellation] in cancellation.cancel() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 90, execute: watchdog)
        defer { watchdog.cancel() }
        var content: [Content] = [.text(prompt)]
        if let image { content.append(.imageData(image)) }
        // The synchronous C API discards its error and returns null. The stream
        // callback includes the native executor error; aggregate deltas so the
        // existing UI and food JSON parser keep receiving a complete response.
        var text = ""
        for try await chunk in conversation.sendMessageStream(
            Message(contents: Contents(contents: content)),
            maxOutputTokens: min(max(maxOutputTokens, 1), 1000)) {
            text += chunk.toString
        }
        return ["text": text, "ms": Date().timeIntervalSince(started) * 1000]
    }
}
