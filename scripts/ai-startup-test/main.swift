import Foundation

// Exercise the actual persisted guard without booting Simulator or loading a model.
let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
let suite = "Fridge-AIStartup-\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
defer {
    defaults.removePersistentDomain(forName: suite)
    try? FileManager.default.removeItem(at: directory)
}
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

// Upgrading 0.3.8: the legacy model choice must not trigger an immediate load.
defaults.set("qwen35", forKey: "gemmaVariant")
let first = AIStartupGuard(directory: directory, defaults: defaults)
check(!first.automaticStart, "Legacy install should open with automatic AI off")
check(first.interruption == nil, "A first install should not claim a previous crash")

try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let inventory = directory.appendingPathComponent("inventory.json")
let model = directory.appendingPathComponent("saved-model")
let sentinel = Data("preserve-existing-data".utf8)
try sentinel.write(to: inventory); try sentinel.write(to: model)

first.automaticStart = true
try first.begin(model: "qwen35")
first.phase("MLXでモデルを読み込み中")
// Simulate a process dying: deliberately omit finish, then construct a new guard.
let afterCrash = AIStartupGuard(directory: directory, defaults: defaults)
check(!afterCrash.automaticStart, "An interrupted startup must turn automatic AI off")
check(afterCrash.interruption?.model == "qwen35", "Recover the interrupted model")
check(afterCrash.interruption?.phase == "MLXでモデルを読み込み中", "Recover the last startup stage")
let reopenedAgain = AIStartupGuard(directory: directory, defaults: defaults)
check(reopenedAgain.interruption != nil, "Recovery remains visible until a manual attempt")

try reopenedAgain.begin(model: "e2b")
check(reopenedAgain.interruption == nil, "A manual retry clears the displayed interruption")
reopenedAgain.finish()
let afterSuccess = AIStartupGuard(directory: directory, defaults: defaults)
check(afterSuccess.interruption == nil, "A returned loader must not look like a crash")
afterSuccess.automaticStart = true
check(AIStartupGuard(directory: directory, defaults: defaults).automaticStart, "An explicit setting survives restart")
try afterSuccess.begin(model: "e2b"); afterSuccess.finish()
check(AIStartupGuard(directory: directory, defaults: defaults).interruption == nil, "A handled failure/cancel also completes the attempt")

let marker = directory.appendingPathComponent("AIStartup/attempt.json")
try Data("broken-json".utf8).write(to: marker)
let corrupt = AIStartupGuard(directory: directory, defaults: defaults)
check(!corrupt.automaticStart && corrupt.interruption != nil, "A corrupt crash marker must fail closed")
check(defaults.string(forKey: "gemmaVariant") == "qwen35", "Recovery must preserve the selected model")
let savedInventory = try Data(contentsOf: inventory), savedModel = try Data(contentsOf: model)
check(savedInventory == sentinel, "Recovery must preserve inventory")
check(savedModel == sentinel, "Recovery must preserve the downloaded model")
print("AI startup recovery checks passed: legacy upgrade, interrupted load, repeated launch, manual retry, setting persistence, corrupt marker, data preservation.")
