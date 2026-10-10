import Foundation

/// Persist before entering a native model loader: jetsam/abort never runs Swift's defer.
/// The first upgrade from a version without this guard also starts with automatic AI off.
final class AIStartupGuard: @unchecked Sendable {
    struct Attempt: Codable {
        var model: String
        var phase: String
        var started: Date
    }
    private let defaults: UserDefaults
    private let marker: URL
    private let lock = NSLock()
    private var previous: Attempt?
    var interruption: Attempt? { lock.lock(); defer { lock.unlock() }; return previous }
    var automaticStart: Bool {
        get { defaults.bool(forKey: "aiAutomaticStartV1") }
        set { defaults.set(newValue, forKey: "aiAutomaticStartV1"); defaults.synchronize() }
    }

    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0], defaults: UserDefaults = .standard) {
        self.defaults = defaults
        marker = directory.appendingPathComponent("AIStartup/attempt.json")
        if FileManager.default.fileExists(atPath: marker.path) {
            previous = (try? JSONDecoder().decode(Attempt.self, from: Data(contentsOf: marker)))
                ?? Attempt(model: "", phase: "AIの起動途中", started: Date())
            automaticStart = false
        }
    }

    func begin(model: String) throws {
        lock.lock(); defer { lock.unlock() }
        try FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
        let attempt = Attempt(model: model, phase: "モデルの保存・起動を開始", started: Date())
        try JSONEncoder().encode(attempt).write(to: marker, options: .atomic)
        previous = nil
    }

    func phase(_ value: String) {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: marker), var attempt = try? JSONDecoder().decode(Attempt.self, from: data) else { return }
        attempt.phase = value
        try? JSONEncoder().encode(attempt).write(to: marker, options: .atomic)
    }

    /// Only remove the marker after the loader returned (success, error, or cancellation).
    func finish() {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: marker)
    }
}
