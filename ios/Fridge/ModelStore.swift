import Foundation

final class ModelStore: NSObject, URLSessionDownloadDelegate {
    static let expectedBytes: Int64 = 2_588_147_712
    static let source = URL(string: "https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/b3ca0d2f076785a8f4b2219ddbd2bdb99954eae1/gemma-4-E2B-it.litertlm")!
    let directory: URL
    let model: URL
    let cache: URL
    var onProgress: ((String, Int64, Int64) -> Void)?
    private var task: URLSessionDownloadTask?
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
        model = directory.appendingPathComponent("gemma-4-e2b-native-b3ca0d2f.litertlm")
        cache = directory.appendingPathComponent("runtime-cache", isDirectory: true)
        super.init()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var excluded = directory; var values = URLResourceValues(); values.isExcludedFromBackup = true
        try? excluded.setResourceValues(values)
    }

    var saved: Bool { (try? model.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) == Self.expectedBytes } ?? false }

    func obtain() async throws -> URL {
        if saved { onProgress?("cached", Self.expectedBytes, Self.expectedBytes); return model }
        return try await withCheckedThrowingContinuation { promise in
            stateQueue.async {
                guard self.continuation == nil else { promise.resume(throwing: FridgeError.message("モデルのダウンロード中です。")); return }
                self.continuation = promise
                self.onProgress?("downloading", 0, Self.expectedBytes)
                let request = self.session.downloadTask(with: Self.source)
                self.task = request; request.resume()
            }
        }
    }

    func cancel() { stateQueue.async { self.task?.cancel() } }

    func importFile(_ source: URL) throws {
        let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard Int64(size) == Self.expectedBytes else { throw FridgeError.message("iOS用のgemma-4-E2B-it.litertlm（約2.6GB）を選んでください。Safari用gpu/webファイルは使用できません。") }
        let temporary = directory.appendingPathComponent(UUID().uuidString + ".partial")
        defer { try? FileManager.default.removeItem(at: temporary) }
        onProgress?("saving", 0, Self.expectedBytes)
        try FileManager.default.copyItem(at: source, to: temporary)
        if FileManager.default.fileExists(atPath: model.path) { _ = try FileManager.default.replaceItemAt(model, withItemAt: temporary) }
        else { try FileManager.default.moveItem(at: temporary, to: model) }
        onProgress?("saved", Self.expectedBytes, Self.expectedBytes)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let now = Date(); guard now.timeIntervalSince(lastProgress) >= 0.25 || totalBytesWritten == Self.expectedBytes else { return }; lastProgress = now
        onProgress?("downloading", totalBytesWritten, Self.expectedBytes)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            guard let response = downloadTask.response as? HTTPURLResponse, response.statusCode == 200 else { throw FridgeError.message("モデル配信元に接続できませんでした。通信を確認してください。") }
            onProgress?("saving", Self.expectedBytes, Self.expectedBytes)
            guard Int64(try location.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) == Self.expectedBytes else { throw FridgeError.message("モデルのダウンロードが途中で切れました。再度お試しください。") }
            if FileManager.default.fileExists(atPath: model.path) { _ = try FileManager.default.replaceItemAt(model, withItemAt: location) }
            else { try FileManager.default.moveItem(at: location, to: model) }
            onProgress?("saved", Self.expectedBytes, Self.expectedBytes)
            complete(.success(model))
        } catch { complete(.failure(error)) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { complete(.failure(error)) }
    }
    private func complete(_ result: Result<URL, Error>) {
        stateQueue.async { let promise = self.continuation; self.continuation = nil; self.task = nil; promise?.resume(with: result) }
    }
}
