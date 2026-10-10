// Fridge modification to john-rocky/swift-litert-lm (Apache-2.0).
import Foundation

/// Native destructors wait for callback_thread_pool. A stream context can drop
/// its last Conversation reference on that same pool, so never delete inline.
enum DeferredNativeRelease {
    struct Handle: @unchecked Sendable {
        let pointer: OpaquePointer
        init(_ pointer: OpaquePointer) { self.pointer = pointer }
    }
    private static let queue = DispatchQueue(label: "jp.mugilab.litert.native-release", qos: .utility)
    static func enqueue(_ release: @escaping @Sendable () -> Void) {
        queue.async(execute: release)
    }
}
