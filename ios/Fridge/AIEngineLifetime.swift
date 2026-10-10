import Foundation

/// The native runtime has hung or failed after engine teardown/recreation.
/// Reuse a resident model's conversations; start another engine in a fresh process.
struct AIEngineLifetime {
    enum LoadAction: Equatable { case initialize, reuse, relaunch }
    private var attemptedModel: String?
    private var resident = false

    func action(for model: URL) -> LoadAction {
        guard let attemptedModel else { return .initialize }
        return resident && attemptedModel == model.standardizedFileURL.path ? .reuse : .relaunch
    }
    mutating func begin(_ model: URL) {
        precondition(attemptedModel == nil, "Native engine initialization requires a fresh process")
        attemptedModel = model.standardizedFileURL.path
    }
    mutating func ready() { resident = true }
    mutating func released() { resident = false }
    var requiresRelaunch: Bool { attemptedModel != nil && !resident }
    static let relaunchMessage = "選んだAIを起動するには、アプリ切替画面でFridgeを上へスワイプして完全に終了し、開き直してください。モデルと在庫は保存したままです。"
}
