import Foundation
import LiteRTFoundation

// Unmodified high-level API retained as the comparison control.
enum VerifiedGemma {
    static func make(_ model: URL) async throws -> LiteRTChat {
        #if targetEnvironment(simulator)
        let backend: Backend = .cpu(threadCount: 4)
        #else
        let backend: Backend = .gpu
        #endif
        return try await LiteRTChat(modelFileURL: model, modalities: .textImage,
            visualTokenBudget: 280, enableBenchmark: true, backend: backend)
    }
}

// The published easy-mode API does not expose conversation reset. This adapter
// preserves its local-file initializer's settings and warmup while exposing
// fresh conversations on ONE engine for the app's independent camera requests.
// Source: john-rocky/swift-litert-lm @ 1c12d404, Sources/LiteRTFoundation/LiteRTChat.swift.
// Adapted under Apache-2.0; license included in Resources/Probe/LICENSE.txt.
final class VerifiedGemmaSession {
    private let engine: Engine
    private let sampler: SamplerConfig

    private init(engine: Engine, sampler: SamplerConfig) {
        self.engine = engine; self.sampler = sampler
    }

    static func load(_ model: URL) async throws -> VerifiedGemmaSession {
        ExperimentalFlags.optIntoExperimentalAPIs()
        ExperimentalFlags.enableBenchmark = true
        ExperimentalFlags.enableSpeculativeDecoding = false
        #if targetEnvironment(simulator)
        let backend: Backend = .cpu(threadCount: 4)
        #else
        let backend: Backend = .gpu
        #endif
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        let config = try EngineConfig(modelPath: model.path, backend: backend,
            visionBackend: .cpu(), audioBackend: nil, maxNumTokens: 2048,
            cacheDir: caches?.path, maxNumImages: 16)
        let engine = Engine(engineConfig: config)
        try await engine.initialize()
        let sampler = try SamplerConfig(topK: 40, topP: 0.95, temperature: 0.8)
        let session = VerifiedGemmaSession(engine: engine, sampler: sampler)
        let warmup = try await session.conversation()
        for try await _ in warmup.sendMessageStream(Message("Hi")) {}
        return session
    }

    func conversation() async throws -> Conversation {
        try await engine.createConversation(with: ConversationConfig(
            samplerConfig: sampler, visualTokenBudget: 280))
    }
}
