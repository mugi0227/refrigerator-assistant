// Derived from john-rocky/swift-litert-lm, LiteRTChat.swift, Apache-2.0 license.
// Pinned revision: 1c12d404153b8e261d48da584f6f80465e294ac2.
// Local-file initializer and stream body retained by scripts/vendor-fridge-chat.py.
// See THIRD_PARTY_NOTICES.md. The unmodified LiteRTChat remains in ReferenceProbe.
import Foundation
import LiteRTFoundation

final class FridgeChat {
  private let engine: Engine
  private let conversationConfig: ConversationConfig
  private var conversation: Conversation?
  private let lock = NSLock()
  private func currentConversation() -> Conversation? {
    lock.lock(); defer { lock.unlock() }; return conversation
  }
  private func replaceConversation(_ value: Conversation?) {
    lock.lock(); conversation = value; lock.unlock()
  }
  // NativeAI must serialize this against stream; cancel may run concurrently.
  func resetConversation() async throws {
    replaceConversation(nil)
    let next = try await engine.createConversation(with: conversationConfig)
    replaceConversation(next)
  }
  func cancel() throws { try currentConversation()?.cancel() }
  init(
    modelFileURL url: URL,
    modalities: Modality = .all,
    visionBackend: Backend = .cpu(),
    audioBackend: Backend = .cpu(),
    visualTokenBudget: Int32? = nil,
    maxTokens: Int = 2048,
    minimumDeviceRAM: Int64? = nil,
    enableBenchmark: Bool = false,
    speculativeDecoding: Bool = false,
    sampler: SamplerConfig? = nil,
    prewarm: Bool = true,
    thinking: ThinkingConfig? = nil,
    backend: Backend = .gpu
  ) async throws {
    if let need = minimumDeviceRAM {
      let ram = Int64(ProcessInfo.processInfo.physicalMemory)
      if ram < need {
        throw LiteRTChatError.insufficientMemory(haveBytes: ram, needBytes: need)
      }
    }
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw LiteRTChatError.modelFileNotFound(url)
    }

    ExperimentalFlags.optIntoExperimentalAPIs()
    if enableBenchmark { ExperimentalFlags.enableBenchmark = true }
    ExperimentalFlags.enableSpeculativeDecoding = speculativeDecoding

    // Applied per conversation, not via the process-wide flag.
    let conversationVisualTokenBudget =
      modalities.contains(.vision) ? visualTokenBudget : nil

    let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    let config = try EngineConfig(
      modelPath: url.path,
      backend: backend,
      visionBackend: modalities.contains(.vision) ? visionBackend : nil,
      audioBackend: modalities.contains(.audio) ? audioBackend : nil,
      maxNumTokens: maxTokens,
      cacheDir: caches?.path,
      // Engine default is 1 image/conversation (a 2nd image overwrites the 1st);
      // allow several so multi-image chats work when vision is enabled.
      maxNumImages: modalities.contains(.vision) ? 16 : nil
    )
    let engine = Engine(engineConfig: config)
    try await engine.initialize()

    let activeSampler = try sampler ?? SamplerConfig(topK: 40, topP: 0.95, temperature: 0.8)
    if prewarm {
      let warmup = try await engine.createConversation(
        with: ConversationConfig(
          samplerConfig: activeSampler, visualTokenBudget: conversationVisualTokenBudget))
      for try await _ in warmup.sendMessageStream(Message("Hi")) {}
    }
    let conversation = try await engine.createConversation(
      with: ConversationConfig(
        samplerConfig: activeSampler, thinkingConfig: thinking,
        visualTokenBudget: conversationVisualTokenBudget))

    self.engine = engine
    self.conversation = conversation
    self.conversationConfig = ConversationConfig(
      samplerConfig: activeSampler, thinkingConfig: thinking,
      visualTokenBudget: conversationVisualTokenBudget)
  }

  public func stream(
    _ prompt: String, image: Data? = nil, images: [Data] = []
  ) -> AsyncThrowingStream<String, Error> {
    // Take a strong snapshot; renewal is serialized by NativeAI.
    guard let conversation = currentConversation() else {
      return AsyncThrowingStream { $0.finish(throwing: FridgeError.message("AIの会話を準備してください。")) }
    }
    var contents: [Content] = [.text(prompt)]
    if let image { contents.append(.imageData(image)) }
    contents.append(contentsOf: images.map { .imageData($0) })
    let message = Message(contents: contents)

    return AsyncThrowingStream { continuation in
      let task = Task {
        do {
          for try await chunk in conversation.sendMessageStream(message) {
            let delta = chunk.toString
            if !delta.isEmpty { continuation.yield(delta) }
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

}
