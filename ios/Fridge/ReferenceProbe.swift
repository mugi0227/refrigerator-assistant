import Foundation
import CryptoKit
import Darwin
import UIKit
import LiteRTLM
import LiteRTFoundation

// The upstream package is pinned in project.yml. No copied Engine/Conversation
// implementation: this calls the published local-file initializer directly.
actor ReferenceProbe {
    static let revision = "1c12d404153b8e261d48da584f6f80465e294ac2"
    static let modelSHA256 = "181938105e0eefd105961417e8da75903eacda102c4fce9ce90f50b97139a63c"
    private var running = false

    func run(model: URL, output: URL, progress: @escaping @Sendable (String) async -> Void) async throws -> URL {
        guard !running else { throw FridgeError.message("比較テストは実行中です。") }
        running = true
        defer { running = false }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let journal = try ProbeJournal(directory: output)
        // Capture the native runtime's stderr directly to a file: no pipe buffer
        // that could block inference, and the file survives a process crash.
        let capture = try ProbeStderr(url: output.appendingPathComponent("native-stderr.txt"))
        defer { capture.restore() }
        var result: [String: Any] = [
            "referenceRevision": Self.revision, "modelExpectedSHA256": Self.modelSHA256,
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "device": Self.deviceIdentifier(), "physicalMemory": ProcessInfo.processInfo.physicalMemory,
            "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            "configuration": ["visionBackend": "CPU", "maxNumImages": 16, "visualTokenBudget": 280,
                "maxNumTokens": 2048, "topK": 40, "topP": 0.95, "temperature": 0.8,
                "prewarm": true, "enableBenchmark": true, "speculativeDecoding": false, "thinking": "upstream default"] as [String: Any]
        ]
        #if targetEnvironment(simulator)
        let backend: Backend = .cpu(threadCount: 4)
        result["environment"] = "Simulator: CPU text; does not validate device Metal"
        #else
        let backend: Backend = .gpu
        result["environment"] = "Physical iPhone: GPU text, CPU vision"
        #endif
        let report = output.appendingPathComponent("result.json")
        func save() throws { try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: report, options: .atomic) }
        func step(_ text: String) async {
            journal.append(text + " | footprint=" + String(LiteRTChat.memoryFootprintBytes()))
            await progress(text)
        }
        do {
            result["status"] = "checking-model"; try save()
            await step("保存済みモデルを照合中（約2.6GB）")
            let digest = try Self.sha256(model)
            result["modelActualSHA256"] = digest
            result["modelBytes"] = try model.resourceValues(forKeys: [.fileSizeKey]).fileSize
            try save()
            guard digest == Self.modelSHA256 else {
                throw FridgeError.message("モデルのSHA256が配布元と一致しません。ログを共有してください。保存ファイルは変更していません。")
            }
            result["status"] = "initializing-reference"; try save()
            await step("公開ライブラリを起動中（文章の事前生成を含む）")
            let previousBenchmark = ExperimentalFlags.enableBenchmark
            let previousSpeculative = ExperimentalFlags.enableSpeculativeDecoding
            defer {
                ExperimentalFlags.enableBenchmark = previousBenchmark
                ExperimentalFlags.enableSpeculativeDecoding = previousSpeculative
            }
            let chat = try await LiteRTChat(modelFileURL: model, modalities: .textImage,
                visualTokenBudget: 280, enableBenchmark: true, backend: backend)
            result["initializationAndPrewarmSucceeded"] = true
            journal.append("reference initialized, including upstream Hi warmup")
            // Same fixture and prompt as the published G0 vision test, first
            // image in the user conversation after its throwaway warmup.
            guard let appleURL = Bundle.main.url(forResource: "apple", withExtension: "png", subdirectory: "Probe") else {
                throw FridgeError.message("比較用のリンゴ画像が見つかりません。")
            }
            let apple = try Data(contentsOf: appleURL)
            result["appleSHA256"] = SHA256.hash(data: apple).map { String(format: "%02x", $0) }.joined()
            result["status"] = "apple-image"; try save()
            await step("リンゴ画像を認識中")
            let appleReply = try await Self.respond(chat, prompt: "What object is in this image? Answer in one word.", image: apple,
                partial: output.appendingPathComponent("apple-partial.txt"))
            result["appleResponse"] = appleReply
            result["appleRecognized"] = appleReply.lowercased().contains("apple")
            journal.append("APPLE: " + appleReply); try save()
            let red = await MainActor.run {
                let format = UIGraphicsImageRendererFormat(); format.scale = 1
                return UIGraphicsImageRenderer(size: CGSize(width: 384, height: 384), format: format).image { context in
                    UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 384, height: 384))
                }.jpegData(compressionQuality: 0.85)!
            }
            result["status"] = "red-image"; try save()
            await step("Fridgeと同じ赤いJPEG画像を認識中")
            let redReply = try await Self.respond(chat, prompt: "Name the color of this image. Answer with one English word.", image: red,
                partial: output.appendingPathComponent("red-partial.txt"))
            result["redResponse"] = redReply
            result["redRecognized"] = redReply.lowercased().contains("red")
            journal.append("RED: " + redReply)
            let passed = result["appleRecognized"] as? Bool == true && result["redRecognized"] as? Bool == true
            result["status"] = passed ? "passed" : "responses-did-not-match"
            try save()
            await step(passed ? "成功：リンゴと赤色を認識しました" : "回答は生成されましたが、画像の正答を確認できませんでした")
            // No reference Engine survives this run. The regular app is opened
            // only after this function returns, avoiding two resident models.
            return report
        } catch {
            result["failedPhase"] = result["status"]
            result["status"] = "failed"; result["error"] = error.localizedDescription
            try? save()
            await step("失敗：" + error.localizedDescription)
            throw error
        }
    }

    private static func respond(_ chat: LiteRTChat, prompt: String, image: Data, partial: URL) async throws -> String {
        // Native calls can block Swift's cooperative executor. Use an OS queue
        // for cancellation, with a cleared holder so the delayed block does not
        // retain an otherwise released engine until the deadline.
        let holder = ProbeCancellation(chat)
        let timeout = DispatchWorkItem { holder.cancel() }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 120, execute: timeout)
        defer { timeout.cancel(); holder.clear() }
        // LiteRTChat.respond itself only aggregates this public stream. Save
        // each delta to distinguish stalled prefill from slow/looping decoding.
        FileManager.default.createFile(atPath: partial.path, contents: nil)
        let file = try FileHandle(forWritingTo: partial)
        defer { try? file.close() }
        var response = ""
        for try await delta in chat.stream(prompt, image: image) {
            response += delta
            try file.write(contentsOf: Data(delta.utf8))
        }
        return response
    }

    static func sha256(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        var hash = SHA256()
        while let block = try file.read(upToCount: 4 * 1024 * 1024), !block.isEmpty {
            try Task.checkCancellation(); hash.update(data: block)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    private static func deviceIdentifier() -> String {
        var info = utsname(); uname(&info)
        return withUnsafeBytes(of: &info.machine) { String(cString: $0.baseAddress!.assumingMemoryBound(to: CChar.self)) }
    }
}

private final class ProbeCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var chat: LiteRTChat?
    init(_ chat: LiteRTChat) { self.chat = chat }
    func clear() { lock.lock(); chat = nil; lock.unlock() }
    func cancel() {
        lock.lock(); let current = chat; lock.unlock()
        fputs("FRIDGE_PROBE: 120 second image deadline; requesting cancellation\n", stderr); fflush(stderr)
        try? current?.cancel()
    }
}

private final class ProbeJournal {
    private let handle: FileHandle
    private let started = Date()
    init(directory: URL) throws {
        let url = directory.appendingPathComponent("phases.txt")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
    }
    func append(_ line: String) {
        let text = String(format: "%.3fs ", Date().timeIntervalSince(started)) + line + "\n"
        try? handle.write(contentsOf: Data(text.utf8)); try? handle.synchronize()
    }
    deinit { try? handle.close() }
}

private final class ProbeStderr {
    private var saved: Int32 = -1
    init(url: URL) throws {
        let fd = Darwin.open(url.path, O_WRONLY | O_CREAT | O_TRUNC, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw FridgeError.message("内部ログの保存先を作成できません。") }
        defer { Darwin.close(fd) }
        fflush(stderr)
        saved = dup(STDERR_FILENO)
        guard saved >= 0 else { throw FridgeError.message("内部ログの取得を開始できません。") }
        guard dup2(fd, STDERR_FILENO) >= 0 else {
            Darwin.close(saved); saved = -1
            throw FridgeError.message("内部ログの出力先を変更できません。")
        }
    }
    func restore() {
        guard saved >= 0 else { return }
        fflush(stderr); fsync(STDERR_FILENO)
        dup2(saved, STDERR_FILENO); Darwin.close(saved); saved = -1
    }
    deinit { restore() }
}
