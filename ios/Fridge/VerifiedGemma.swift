import Foundation
import LiteRTFoundation

// One construction path for the physical-device-proven probe and the app.
// Keep upstream defaults, including Hi prewarm, sampler, image slots and flags.
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
