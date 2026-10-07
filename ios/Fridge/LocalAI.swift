import Foundation
import LiteRTLM

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
    private var engine: Engine?
    private var busy = false
    nonisolated let cancellation = InferenceCancellation()
    func isReady() async -> Bool { guard let engine else { return false }; return await engine.isInitialized() }

    func load(_ model: URL, cache: URL) async throws {
        guard !busy else { throw FridgeError.message("AIの処理中です。終了してから操作してください。") }
        engine = nil
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        // Native CPU execution uses disk-backed weights; no browser/WASM model copy.
        let config = try EngineConfig(modelPath: model.path, backend: .cpu(threadCount: 4),
            visionBackend: .cpu(threadCount: 2), maxNumTokens: 2048, cacheDir: cache.path)
        let next = Engine(engineConfig: config)
        try await next.initialize()
        engine = next
    }

    func unload() throws {
        guard !busy else { throw FridgeError.message("AIの処理中です。停止してからメモリを解放してください。") }
        engine = nil
    }

    func infer(prompt: String, image: Data?, maxOutputTokens: Int) async throws -> [String: Any] {
        guard let engine else { throw FridgeError.message("設定でGemmaを起動してください。") }
        guard !busy else { throw FridgeError.message("AIは処理中です。") }
        busy = true
        let started = Date()
        defer { busy = false; cancellation.set(nil) }
        let config = ConversationConfig(samplerConfig: try SamplerConfig(topK: 1, topP: 1, temperature: 0),
            thinkingConfig: ThinkingConfig(enableThinking: false, thinkingTokenBudget: 0),
            visualTokenBudget: image == nil ? nil : 256)
        let conversation = try await engine.createConversation(with: config)
        cancellation.set(conversation)
        let watchdog = DispatchWorkItem { [cancellation] in cancellation.cancel() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 90, execute: watchdog)
        defer { watchdog.cancel() }
        var content: [Content] = []
        if let image { content.append(.imageData(image)) }
        content.append(.text(prompt))
        let reply = try await conversation.sendMessage(Message(contents: Contents(contents: content)),
            maxOutputTokens: min(max(maxOutputTokens, 1), 1000))
        return ["text": reply.toString, "ms": Date().timeIntervalSince(started) * 1000]
    }
}
