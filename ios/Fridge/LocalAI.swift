import Foundation
import LiteRTFoundation
import UIKit
import OSLog

enum FridgeError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

// Each request owns cancellation. An old watchdog cannot cancel a later request,
// and cancellation requested during initialization is remembered.
final class InferenceOperation: @unchecked Sendable {
    private let lock = NSLock()
    private var chat: Conversation?
    private var cancelled = false
    func attach(_ value: Conversation) throws {
        lock.lock(); chat = value; let stopped = cancelled; lock.unlock()
        if stopped { try? value.cancel(); throw CancellationError() }
    }
    func cancel() {
        lock.lock(); cancelled = true; let current = chat; lock.unlock()
        try? current?.cancel()
    }
    func check() throws {
        lock.lock(); let stopped = cancelled; lock.unlock()
        if stopped { throw CancellationError() }
        try Task.checkCancellation()
    }
    func clear() { lock.lock(); chat = nil; lock.unlock() }
}

final class InferenceCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var operation: InferenceOperation?
    func set(_ value: InferenceOperation?) { lock.lock(); operation = value; lock.unlock() }
    func cancel() { lock.lock(); let current = operation; lock.unlock(); current?.cancel() }
}

actor LocalAI {
    private let logger = Logger(subsystem: "jp.mugilab.fridge", category: "LocalAI")
    #if targetEnvironment(simulator)
    static let runtimeLabel = "Verified Gemma 1c12d404 / simulator: CPU text + CPU vision"
    #else
    static let runtimeLabel = "Verified Gemma 1c12d404 / device: Metal text + CPU vision"
    #endif
    private var session: VerifiedGemmaSession?
    private var ready = false
    private var busy = false
    nonisolated let cancellation = InferenceCancellation()
    func isReady() -> Bool { ready }

    func load(_ model: URL, cache: URL) async throws {
        guard !busy else { throw FridgeError.message("AIの処理中です。終了してから操作してください。") }
        busy = true; defer { busy = false }
        ready = false; session = nil
        let operation = InferenceOperation(); cancellation.set(operation)
        defer { operation.clear(); cancellation.set(nil) }
        logger.info("Starting \(Self.runtimeLabel, privacy: .public)")
        // Keep the bridge signature; let the proven library choose its cache.
        let next = try await VerifiedGemmaSession.load(model)
        try operation.check()
        session = next
    }

    func unload() throws {
        guard !busy else { throw FridgeError.message("AIの処理中です。停止してからメモリを解放してください。") }
        ready = false; session = nil
    }

    func checkImageInference() async throws {
        guard !busy, let session else { throw FridgeError.message("設定でGemmaを起動してください。") }
        busy = true
        let operation = InferenceOperation(); cancellation.set(operation)
        defer { operation.clear(); cancellation.set(nil); busy = false }
        do {
            let chat = try await session.conversation()
            try operation.attach(chat)
            // Same proven sequence: upstream Hi warmup, Apple, red JPEG.
            guard let url = Bundle.main.url(forResource: "apple", withExtension: "png", subdirectory: "Probe") else {
                throw FridgeError.message("起動検査の画像が見つかりません。")
            }
            let apple = try await response(chat, operation: operation,
                prompt: "What object is in this image? Answer in one word.", image: Data(contentsOf: url), maxOutputTokens: 32)
            guard apple.lowercased().contains("apple") else { throw FridgeError.message("リンゴ画像を正しく読み取れませんでした。") }
            let red = await MainActor.run {
                let format = UIGraphicsImageRendererFormat(); format.scale = 1
                return UIGraphicsImageRenderer(size: CGSize(width: 384, height: 384), format: format).image { context in
                    UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 384, height: 384))
                }.jpegData(compressionQuality: 0.85)!
            }
            let color = try await response(chat, operation: operation,
                prompt: "Name the color of this image. Answer with one English word.", image: red, maxOutputTokens: 32)
            guard color.lowercased().contains("red") else { throw FridgeError.message("赤い画像を正しく読み取れませんでした。") }
            ready = true
            logger.info("Verified startup: Apple and Red succeeded")
        } catch {
            ready = false; self.session = nil; operation.cancel()
            logger.error("Image readiness check failed: \(error.localizedDescription, privacy: .public)")
            throw FridgeError.message("画像AIの起動テストに失敗しました。モデルは保存されています。\n\(error.localizedDescription)")
        }
    }

    func infer(prompt: String, image: Data?, maxOutputTokens: Int) async throws -> [String: Any] {
        guard ready, let session else { throw FridgeError.message("設定でGemmaを起動してください。") }
        guard !busy else { throw FridgeError.message("AIは処理中です。") }
        busy = true
        let operation = InferenceOperation(); cancellation.set(operation)
        defer { operation.clear(); cancellation.set(nil); busy = false }
        let started = Date()
        // Keep the verified engine resident; discard only per-request history.
        let chat = try await session.conversation()
        try operation.attach(chat)
        let text = try await response(chat, operation: operation, prompt: prompt, image: image, maxOutputTokens: maxOutputTokens)
        return ["text": text, "ms": Date().timeIntervalSince(started) * 1000]
    }

    private func response(_ chat: Conversation, operation: InferenceOperation, prompt: String,
                          image: Data?, maxOutputTokens: Int) async throws -> String {
        try operation.check()
        let watchdog = DispatchWorkItem { operation.cancel() }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 90, execute: watchdog)
        defer { watchdog.cancel() }
        var content: [Content] = [.text(prompt)]
        if let image { content.append(.imageData(image)) }
        var text = ""
        do {
            for try await delta in chat.sendMessageStream(Message(contents: content),
                maxOutputTokens: min(max(maxOutputTokens, 1), 1000)) {
                try operation.check()
                text += delta.toString
            }
            try operation.check()
            return text
        } catch { operation.cancel(); throw error }
    }
}
