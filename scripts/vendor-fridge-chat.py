"""Extract the proven local-file initializer and stream from pinned LiteRTChat.

The resulting source adds only explicit conversation renewal, retaining the
engine, upstream warmup, sampler, backends and stream Task. No runtime fork.
Run with a path to the upstream Sources/LiteRTFoundation/LiteRTChat.swift.
"""
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding='utf-8')
start = source.index('  public convenience init(\n    modelFileURL')
end = source.index('\n  /// Bring up a chat session from **any Hugging', start)
initializer = source[start:end].replace('public convenience init', 'init')
initializer = initializer.replace('    self.init(\n      model: nil, modalities: modalities, modelPath: url.path,\n      engine: engine, conversation: conversation)', '''    self.engine = engine
    self.conversation = conversation
    self.conversationConfig = ConversationConfig(
      samplerConfig: activeSampler, thinkingConfig: thinking,
      visualTokenBudget: conversationVisualTokenBudget)''')
start = source.index('  public func stream(')
end = source.index('\n  /// Generate a full response', start)
stream = source[start:end].replace('    var contents:', '''    // Take a strong snapshot; renewal is serialized by NativeAI.
    guard let conversation = currentConversation() else {
      return AsyncThrowingStream { $0.finish(throwing: FridgeError.message("AIの会話を準備してください。")) }
    }
    var contents:''')
stream = stream.replace(', audio: AudioInput? = nil', '').replace('    if let audio { contents.append(audio.content) }\n', '')
header = '''// Derived from john-rocky/swift-litert-lm, LiteRTChat.swift, Apache-2.0 license.
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
'''
Path('ios/Fridge/FridgeChat.swift').write_text(header + initializer + '\n' + stream + '\n}\n', encoding='utf-8')
