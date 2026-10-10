import Foundation

/// Pinned LiteRT-LM builds. Size and SHA-256 come from the Hugging Face LFS
/// metadata at the pinned revision, so a swapped upstream file is rejected.
enum GemmaVariant: String, CaseIterable, Identifiable {
    case e2b, e4b
    var id: String { rawValue }
    var title: String { self == .e2b ? "Gemma 4 E2B":"Gemma 4 E4B" }
    var summary: String { self == .e2b ? "約2.6GB · 速い・標準":"約3.7GB · 高精度・遅め（Proなどメモリの多い機種向け）" }
    var expectedBytes: Int64 { self == .e2b ? 2_588_147_712:3_659_530_240 }
    var sha256: String { self == .e2b ? "181938105e0eefd105961417e8da75903eacda102c4fce9ce90f50b97139a63c":"0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0" }
    var source: URL {
        URL(string: self == .e2b
            ? "https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/b3ca0d2f076785a8f4b2219ddbd2bdb99954eae1/gemma-4-E2B-it.litertlm"
            : "https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/2eee7ac325f20eb8c9ac1d0e972f7c84663062da/gemma-4-E4B-it.litertlm")!
    }
    var fileName: String { self == .e2b ? "gemma-4-e2b-native-b3ca0d2f.litertlm":"gemma-4-e4b-native-2eee7ac3.litertlm" }
}

final class ModelStore: NSObject, URLSessionDownloadDelegate {
    let directory: URL
    let cache: URL
    /// Changing the variant only selects which file to use; callers unload the engine first.
    var variant: GemmaVariant {
        didSet { UserDefaults.standard.set(variant.rawValue, forKey: "gemmaVariant") }
    }
    var model: URL { file(variant) }
    var onProgress: ((String, Int64, Int64) -> Void)?
    private var task: URLSessionDownloadTask?
    private var downloading = GemmaVariant.e2b
    private var continuation: CheckedContinuation<URL, Error>?
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
        variant = GemmaVariant(rawValue: UserDefaults.standard.string(forKey: "gemmaVariant") ?? "") ?? .e2b
        super.init()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var excluded = directory; var values = URLResourceValues(); values.isExcludedFromBackup = true
        try? excluded.setResourceValues(values)
    }

    func file(_ value: GemmaVariant) -> URL { directory.appendingPathComponent(value.fileName) }
    var saved: Bool { isSaved(variant) }
    func isSaved(_ value: GemmaVariant) -> Bool {
        (try? file(value).resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) == value.expectedBytes } ?? false
    }
    func delete(_ value: GemmaVariant) throws {
        if FileManager.default.fileExists(atPath: file(value).path) { try FileManager.default.removeItem(at: file(value)) }
    }

    func obtain() async throws -> URL {
        let value = variant
        if saved { onProgress?("cached", value.expectedBytes, value.expectedBytes); return model }
        return try await withCheckedThrowingContinuation { promise in
            stateQueue.async {
                guard self.continuation == nil else { promise.resume(throwing: FridgeError.message("モデルのダウンロード中です。")); return }
                self.continuation = promise; self.downloading = value
                self.onProgress?("downloading", 0, value.expectedBytes)
                let request = self.session.downloadTask(with: value.source)
                self.task = request; request.resume()
            }
        }
    }

    func cancel() { stateQueue.async { self.task?.cancel() } }

    /// Recognizes the variant by exact size and selects it; the SHA-256 is checked when the engine starts.
    func importFile(_ source: URL) throws {
        let size = Int64(try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        guard let value = GemmaVariant.allCases.first(where: { $0.expectedBytes == size }) else {
            throw FridgeError.message("iOS用のgemma-4-E2B-it.litertlm（約2.6GB）またはgemma-4-E4B-it.litertlm（約3.7GB）を選んでください。Safari用gpu/webファイルは使用できません。")
        }
        let target = file(value), temporary = directory.appendingPathComponent(UUID().uuidString + ".partial")
        defer { try? FileManager.default.removeItem(at: temporary) }
        onProgress?("saving", 0, value.expectedBytes)
        try FileManager.default.copyItem(at: source, to: temporary)
        if FileManager.default.fileExists(atPath: target.path) { _ = try FileManager.default.replaceItemAt(target, withItemAt: temporary) }
        else { try FileManager.default.moveItem(at: temporary, to: target) }
        variant = value
        onProgress?("saved", value.expectedBytes, value.expectedBytes)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let now = Date(), expected = downloading.expectedBytes
        guard now.timeIntervalSince(lastProgress) >= 0.25 || totalBytesWritten == expected else { return }; lastProgress = now
        onProgress?("downloading", totalBytesWritten, expected)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let value = downloading, target = file(value)
        do {
            guard let response = downloadTask.response as? HTTPURLResponse, response.statusCode == 200 else { throw FridgeError.message("モデル配信元に接続できませんでした。通信を確認してください。") }
            onProgress?("saving", value.expectedBytes, value.expectedBytes)
            guard Int64(try location.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) == value.expectedBytes else { throw FridgeError.message("モデルのダウンロードが途中で切れました。再度お試しください。") }
            if FileManager.default.fileExists(atPath: target.path) { _ = try FileManager.default.replaceItemAt(target, withItemAt: location) }
            else { try FileManager.default.moveItem(at: location, to: target) }
            onProgress?("saved", value.expectedBytes, value.expectedBytes)
            complete(.success(target))
        } catch { complete(.failure(error)) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { complete(.failure(error)) }
    }
    private func complete(_ result: Result<URL, Error>) {
        stateQueue.async { let promise = self.continuation; self.continuation = nil; self.task = nil; promise?.resume(with: result) }
    }
}
