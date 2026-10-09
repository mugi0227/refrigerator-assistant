import Foundation
import LiteRTFoundation

// Unmodified high-level API retained as the comparison control.
enum VerifiedGemma {
    static func makeRenewable(_ model: URL) async throws -> FridgeChat {
        #if targetEnvironment(simulator)
        let backend: Backend = .cpu(threadCount: 1)
        #else
        let backend: Backend = .gpu
        #endif
        return try await FridgeChat(modelFileURL: model, modalities: .textImage,
            visualTokenBudget: 280, enableBenchmark: true, backend: backend)
    }
    static func make(_ model: URL) async throws -> LiteRTChat {
        #if targetEnvironment(simulator)
        // Avoid oversubscribing the hosted ARM simulator's CPU. This branch
        // never changes the physical iPhone's verified Metal configuration.
        let backend: Backend = .cpu(threadCount: 1)
        #else
        let backend: Backend = .gpu
        #endif
        return try await LiteRTChat(modelFileURL: model, modalities: .textImage,
            visualTokenBudget: 280, enableBenchmark: true, backend: backend)
    }
}
