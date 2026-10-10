import Foundation
import CoreImage
import MLX
import MLXLMCommon
import MLXVLM
import Tokenizers

/// Qwen3.5 (vision) on MLX. Each request uses a fresh `ChatSession`, so no
/// earlier image or answer carries over, matching the LiteRT Gemma path.
final class MLXVision: @unchecked Sendable {
    private let container: ModelContainer
    private init(_ container: ModelContainer) { self.container = container }

    static func load(_ directory: URL) async throws -> MLXVision {
        // Freed GPU buffers otherwise stay cached up to the memory limit; keep
        // the app well below the iOS per-process ceiling.
        Memory.cacheLimit = 64 * 1024 * 1024
        return MLXVision(try await VLMModelFactory.shared.loadContainer(from: directory, using: TransformersTokenizerLoader()))
    }

    func stream(_ prompt: String, image: Data?) -> AsyncThrowingStream<String, Error> {
        let session = ChatSession(container,
            generateParameters: GenerateParameters(maxTokens: 1024, temperature: 0),
            // About 640×640 pixels: enough for printed dates, ~400 image tokens.
            processing: UserInput.Processing(resize: nil, maxPixels: 640 * 640),
            // Answer directly; the template otherwise opens a <think> block.
            additionalContext: ["enable_thinking": false])
        let images = image.flatMap { CIImage(data: $0, options: [.applyOrientationProperty: true]) }.map { [UserInput.Image.ciImage($0)] } ?? []
        return session.streamResponse(to: prompt, images: images)
    }
}

/// Adapts swift-transformers' tokenizer to mlx-swift-lm, as its
/// `#huggingFaceTokenizerLoader` macro does, without the downloader.
private struct TransformersTokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        TokenizerBridge(upstream: try await AutoTokenizer.from(modelFolder: directory))
    }
}

private struct TokenizerBridge: MLXLMCommon.Tokenizer {
    let upstream: any Tokenizers.Tokenizer
    func encode(text: String, addSpecialTokens: Bool) -> [Int] { upstream.encode(text: text, addSpecialTokens: addSpecialTokens) }
    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String { upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens) }
    func convertTokenToId(_ token: String) -> Int? { upstream.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { upstream.convertIdToToken(id) }
    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }
    func applyChatTemplate(messages: [[String: any Sendable]], tools: [[String: any Sendable]]?, additionalContext: [String: any Sendable]?) throws -> [Int] {
        do { return try upstream.applyChatTemplate(messages: messages, tools: tools, additionalContext: additionalContext) }
        catch Tokenizers.TokenizerError.missingChatTemplate { throw MLXLMCommon.TokenizerError.missingChatTemplate }
    }
}
