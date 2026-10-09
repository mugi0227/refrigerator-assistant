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
    private var chat: LiteRTChat?
    private var cancelled = false
    func attach(_ value: LiteRTChat) throws {
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
    static let runtimeLabel = "Verified LiteRTChat 1c12d404 / simulator: CPU text + CPU vision"
    #else
    static let runtimeLabel = "Verified LiteRTChat 1c12d404 / device: Metal text + CPU vision"
    #endif
    private var model: URL?
    private var startupChat: LiteRTChat?
    private var ready = false
    private var busy = false
    nonisolated let cancellation = InferenceCancellation()
    func isReady() -> Bool { ready }

    func load(_ model: URL, cache: URL) async throws {
        guard !busy else { throw FridgeError.message("AIの処理中です。終了してから操作してください。") }
        busy = true; defer { busy = false }
        ready = false; self.model = nil; startupChat = nil
        let operation = InferenceOperation(); cancellation.set(operation)
        defer { operation.clear(); cancellation.set(nil) }
        logger.info("Starting \(Self.runtimeLabel, privacy: .public)")
        // Keep the bridge signature; let the proven library choose its cache.
        let chat = try await VerifiedGemma.make(model)
        try operation.attach(chat)
        try operation.check()
        startupChat = chat; self.model = model
    }

    func unload() throws {
        guard !busy else { throw FridgeError.message("AIの処理中です。停止してからメモリを解放してください。") }
        ready = false; startupChat = nil; model = nil
    }

    func checkImageInference() async throws {
        guard !busy, let chat = startupChat else { throw FridgeError.message("設定でGemmaを起動してください。") }
        busy = true
        let operation = InferenceOperation(); cancellation.set(operation)
        defer { startupChat = nil; operation.clear(); cancellation.set(nil); busy = false }
        do {
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
            ready = false; model = nil; operation.cancel()
            logger.error("Image readiness check failed: \(error.localizedDescription, privacy: .public)")
            throw FridgeError.message("画像AIの起動テストに失敗しました。モデルは保存されています。\n\(error.localizedDescription)")
        }
    }

    func infer(prompt: String, image: Data?, maxOutputTokens: Int) async throws -> [String: Any] {
        guard ready, let model else { throw FridgeError.message("設定でGemmaを起動してください。") }
        guard !busy else { throw FridgeError.message("AIは処理中です。") }
        busy = true
        let operation = InferenceOperation(); cancellation.set(operation)
        defer { operation.clear(); cancellation.set(nil); busy = false }
        let started = Date()
        // No public reset API: make an independent conversation for each item.
        // This costs initialization time but avoids stale-image answers and
        // accumulated history exhausting the 2048-token context while scanning.
        let chat = try await VerifiedGemma.make(model)
        try operation.attach(chat)
        let text = try await response(chat, operation: operation, prompt: prompt, image: image, maxOutputTokens: maxOutputTokens)
        return ["text": text, "ms": Date().timeIntervalSince(started) * 1000]
    }

    private func response(_ chat: LiteRTChat, operation: InferenceOperation, prompt: String,
                          image: Data?, maxOutputTokens: Int) async throws -> String {
        try operation.check()
        let watchdog = DispatchWorkItem { operation.cancel() }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 90, execute: watchdog)
        defer { watchdog.cancel() }
        // Public stream has no response token-limit argument. Bound bytes
        // conservatively instead; never submit truncated JSON to the parser.
        let maxBytes = min(max(maxOutputTokens, 32), 1000) * 16
        var text = ""
        do {
            for try await delta in chat.stream(prompt, image: image) {
                try operation.check()
                text += delta
                guard text.utf8.count <= maxBytes else { throw FridgeError.message("AIの回答が長すぎます。もう一度読み取ってください。") }
            }
            try operation.check()
            return text
        } catch { operation.cancel(); throw error }
    }
}
