import Foundation

/// One pinned file of a model. LFS files carry the SHA-256 from Hugging Face
/// metadata at the pinned revision; small config files are checked by size.
struct ModelFile {
    let remote: String, local: String, bytes: Int64, sha256: String?
}

/// Selectable on-device models. Gemma runs on LiteRT-LM as one `.litertlm`
/// file; Qwen3.5 runs on MLX as a directory of safetensors and configs.
enum AIModelChoice: String, CaseIterable, Identifiable {
    case e2b, e4b, qwen35
    var id: String { rawValue }
    var title: String { [.e2b:"Gemma 4 E2B",.e4b:"Gemma 4 E4B",.qwen35:"Qwen3.5 4B"][self]! }
    var shortTitle: String { [.e2b:"E2B",.e4b:"E4B",.qwen35:"Qwen3.5"][self]! }
    var summary: String {
        [.e2b:"約2.6GB · 速い・標準",
         .e4b:"約3.7GB · 高精度・遅め（Proなどメモリの多い機種向け）",
         .qwen35:"約3.1GB · MLXで動作・試験的（Proなどメモリの多い機種向け）"][self]!
    }
    var usesMLX: Bool { self == .qwen35 }
    var available: Bool {
        #if canImport(MLXVLM)
        return true
        #else
        return !usesMLX
        #endif
    }
    var base: String {
        [.e2b:"https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/b3ca0d2f076785a8f4b2219ddbd2bdb99954eae1/",
         .e4b:"https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/2eee7ac325f20eb8c9ac1d0e972f7c84663062da/",
         .qwen35:"https://huggingface.co/mlx-community/Qwen3.5-4B-MLX-4bit/resolve/32f3e8ecf65426fc3306969496342d504bfa13f3/"][self]!
    }
    /// Gemma is stored as a single file; MLX models as a folder of these files.
    var folder: String? { usesMLX ? "qwen3.5-4b-mlx-32f3e8ec":nil }
    var files: [ModelFile] {
        switch self {
        case .e2b: return [ModelFile(remote:"gemma-4-E2B-it.litertlm",local:"gemma-4-e2b-native-b3ca0d2f.litertlm",bytes:2_588_147_712,sha256:"181938105e0eefd105961417e8da75903eacda102c4fce9ce90f50b97139a63c")]
        case .e4b: return [ModelFile(remote:"gemma-4-E4B-it.litertlm",local:"gemma-4-e4b-native-2eee7ac3.litertlm",bytes:3_659_530_240,sha256:"0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0")]
        case .qwen35:
            return [("config.json",3_366,nil),("chat_template.jinja",7_756,nil),("preprocessor_config.json",390,nil),
                    ("processor_config.json",1_300,nil),("video_preprocessor_config.json",385,nil),("tokenizer_config.json",1_139,nil),
                    ("model.safetensors.index.json",101_944,nil),
                    ("tokenizer.json",19_989_343,"87a7830d63fcf43bf241c3c5242e96e62dd3fdc29224ca26fed8ea333db72de4"),
                    ("model.safetensors",3_034_300_695,"5fb9acd0246866381cf8c5c354c6db1019f6498eec4ccb4f5edcc71ffeacb2db")]
                .map { ModelFile(remote:$0.0,local:$0.0,bytes:Int64($0.1),sha256:$0.2) }
        }
    }
    var expectedBytes: Int64 { files.reduce(0) { $0 + $1.bytes } }
}

final class ModelStore: NSObject, URLSessionDownloadDelegate {
    let directory: URL
    let cache: URL
    /// Changing the variant only selects which model to use; callers unload the engine first.
    var variant: AIModelChoice {
        didSet { UserDefaults.standard.set(variant.rawValue, forKey: "gemmaVariant") }
    }
    /// The `.litertlm` file for Gemma, or the model folder for MLX.
    var model: URL { location(variant) }
    var onProgress: ((String, Int64, Int64) -> Void)?
    private var task: URLSessionDownloadTask?
    // Current download: which model, which file, and bytes already finished before it.
    private var downloading = (choice: AIModelChoice.e2b, file: AIModelChoice.e2b.files[0], offset: Int64(0))
    private var continuation: CheckedContinuation<Void, Error>?
    private var lastProgress = Date.distantPast
    private let stateQueue = DispatchQueue(label: "fridge.model-store")
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 45 * 60
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
        return URLSession(configuration: config, delegate: self, delegateQueue: queue)
    }()

    override init() {
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FridgeModels", isDirectory: true)
        cache = directory.appendingPathComponent("runtime-cache", isDirectory: true)
        let selected = AIModelChoice(rawValue: UserDefaults.standard.string(forKey: "gemmaVariant") ?? "") ?? .e2b
        variant = selected.available ? selected : .e2b
        super.init()
        if selected != variant { UserDefaults.standard.set(variant.rawValue, forKey: "gemmaVariant") }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var excluded = directory; var values = URLResourceValues(); values.isExcludedFromBackup = true
        try? excluded.setResourceValues(values)
    }

    func location(_ value: AIModelChoice) -> URL {
        value.folder.map { directory.appendingPathComponent($0, isDirectory: true) } ?? file(value.files[0], of: value)
    }
    func file(_ item: ModelFile, of value: AIModelChoice) -> URL {
        (value.folder.map { directory.appendingPathComponent($0, isDirectory: true) } ?? directory).appendingPathComponent(item.local)
    }
    private func complete(_ item: ModelFile, of value: AIModelChoice) -> Bool {
        (try? file(item, of: value).resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) == item.bytes } ?? false
    }
    var saved: Bool { isSaved(variant) }
    func isSaved(_ value: AIModelChoice) -> Bool { value.files.allSatisfy { complete($0, of: value) } }
    func delete(_ value: AIModelChoice) throws {
        let target = location(value)
        if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
    }

    /// Downloads only the missing files, so an interrupted multi-file model resumes per file.
    func obtain() async throws -> URL {
        let value = variant
        var offset: Int64 = 0
        for item in value.files {
            if !complete(item, of: value) { try await download(item, of: value, offset: offset) }
            offset += item.bytes
        }
        onProgress?("cached", value.expectedBytes, value.expectedBytes)
        return location(value)
    }
    private func download(_ item: ModelFile, of value: AIModelChoice, offset: Int64) async throws {
        try await withCheckedThrowingContinuation { (promise: CheckedContinuation<Void, Error>) in
            stateQueue.async {
                guard self.continuation == nil else { promise.resume(throwing: FridgeError.message("モデルのダウンロード中です。")); return }
                self.continuation = promise; self.downloading = (value, item, offset)
                self.onProgress?("downloading", offset, value.expectedBytes)
                let request = self.session.downloadTask(with: URL(string: value.base + item.remote)!)
                self.task = request; request.resume()
            }
        }
    }

    func cancel() { stateQueue.async { self.task?.cancel() } }

    /// Recognizes a Gemma file by exact size and selects it; the SHA-256 is checked when the engine starts.
    func importFile(_ source: URL) throws {
        let size = Int64(try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        guard let value = AIModelChoice.allCases.first(where: { !$0.usesMLX && $0.expectedBytes == size }) else {
            throw FridgeError.message("iOS用のgemma-4-E2B-it.litertlm（約2.6GB）またはgemma-4-E4B-it.litertlm（約3.7GB）を選んでください。Safari用gpu/webファイルは使用できません。Qwen3.5は設定の「モデルを保存して起動」で取得します。")
        }
        let target = location(value), temporary = directory.appendingPathComponent(UUID().uuidString + ".partial")
        defer { try? FileManager.default.removeItem(at: temporary) }
        onProgress?("saving", 0, value.expectedBytes)
        try FileManager.default.copyItem(at: source, to: temporary)
        if FileManager.default.fileExists(atPath: target.path) { _ = try FileManager.default.replaceItemAt(target, withItemAt: temporary) }
        else { try FileManager.default.moveItem(at: temporary, to: target) }
        variant = value
        onProgress?("saved", value.expectedBytes, value.expectedBytes)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let now = Date(), current = downloading
        guard now.timeIntervalSince(lastProgress) >= 0.25 || totalBytesWritten == current.file.bytes else { return }; lastProgress = now
        onProgress?("downloading", current.offset + totalBytesWritten, current.choice.expectedBytes)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let current = downloading, target = file(current.file, of: current.choice)
        do {
            guard let response = downloadTask.response as? HTTPURLResponse, response.statusCode == 200 else { throw FridgeError.message("モデル配信元に接続できませんでした。通信を確認してください。") }
            guard Int64(try location.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) == current.file.bytes else { throw FridgeError.message("モデルのダウンロードが途中で切れました。再度お試しください。") }
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: target.path) { _ = try FileManager.default.replaceItemAt(target, withItemAt: location) }
            else { try FileManager.default.moveItem(at: location, to: target) }
            onProgress?("saved", current.offset + current.file.bytes, current.choice.expectedBytes)
            finish(.success(()))
        } catch { finish(.failure(error)) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
    }
    private func finish(_ result: Result<Void, Error>) {
        stateQueue.async { let promise = self.continuation; self.continuation = nil; self.task = nil; promise?.resume(with: result) }
    }
}
