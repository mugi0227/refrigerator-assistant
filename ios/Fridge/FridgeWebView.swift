import SwiftUI
import WebKit
import UniformTypeIdentifiers

struct FridgeWebView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.setURLSchemeHandler(BundleScheme(), forURLScheme: "fridge")
        // randomUUID is secure-context-only. The bundled custom origin still has
        // getRandomValues, which provides the same cryptographic UUID entropy.
        config.userContentController.addUserScript(WKUserScript(source: """
            if (typeof crypto.randomUUID !== 'function') {
              Object.defineProperty(crypto, 'randomUUID', { value: () => {
                const bytes = crypto.getRandomValues(new Uint8Array(16));
                bytes[6] = (bytes[6] & 15) | 64; bytes[8] = (bytes[8] & 63) | 128;
                const hex = Array.from(bytes, b => b.toString(16).padStart(2, '0'));
                return hex.slice(0,4).join('')+'-'+hex.slice(4,6).join('')+'-'+hex.slice(6,8).join('')+'-'+hex.slice(8,10).join('')+'-'+hex.slice(10).join('');
              }});
            }
            """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        config.userContentController.add(context.coordinator, name: "fridge")
        let web = WKWebView(frame: .zero, configuration: config)
        web.backgroundColor = UIColor(red: 0.969, green: 0.973, blue: 0.949, alpha: 1)
        web.isOpaque = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.navigationDelegate = context.coordinator; web.uiDelegate = context.coordinator
        context.coordinator.attach(web)
        web.load(URLRequest(url: URL(string: "fridge://localhost/index.html")!))
        return web
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate, UIDocumentPickerDelegate {
        private weak var web: WKWebView?
        private let ai = LocalAI(), model = ModelStore(), camera = NativeCamera()
        private var importing: String?
        private var loading = false
        private var active = true

        func attach(_ web: WKWebView) {
            self.web = web
            model.onProgress = { [weak self] phase, loaded, total in self?.emit(["type": "modelProgress", "progress": ["phase": phase, "loaded": loaded, "total": total]]) }
            camera.onFrame = { [weak self] jpeg, codes in self?.emit(["type": "cameraFrame", "jpeg": jpeg, "codes": codes]) }
            NotificationCenter.default.addObserver(self, selector: #selector(background), name: UIApplication.didEnterBackgroundNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(foreground), name: UIApplication.willEnterForegroundNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(memoryWarning), name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        }
        deinit { NotificationCenter.default.removeObserver(self) }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            // A remote page/iframe must never gain camera, file or inference access.
            guard message.frameInfo.isMainFrame, message.frameInfo.request.url?.scheme == "fridge",
                message.frameInfo.request.url?.host == "localhost", let body = message.body as? [String: Any],
                let id = body["id"] as? String, let action = body["action"] as? String else { return }
            let args = body["args"] as? [String: Any] ?? [:]
            Task { @MainActor in
                do {
                    switch action {
                    case "modelStatus": reply(id, ["saved": model.saved])
                    case "loadModel":
                        guard !loading, importing == nil else { throw FridgeError.message("モデルの操作が終わってからお試しください。") }
                        loading = true; defer { loading = false }
                        let path = try await model.obtain()
                        guard active else { throw FridgeError.message("アプリを開いてからAIを起動してください。モデルは保存されています。") }
                        emit(["type": "modelProgress", "progress": ["phase": "initializing"]])
                        try await ai.load(path, cache: model.cache)
                        guard active, await ai.isReady() else { try? await ai.unload(); throw FridgeError.message("AIの起動中にアプリが中断されました。開いた状態で再度お試しください。") }
                        reply(id, ["ready": true])
                    case "cancelDownload": model.cancel(); reply(id, [:])
                    case "unloadModel": try await ai.unload(); reply(id, [:])
                    case "infer":
                        guard active else { throw FridgeError.message("アプリを開いた状態で読み取ってください。") }
                        guard let prompt = args["prompt"] as? String, prompt.utf8.count <= 30000 else { throw FridgeError.message("AIへの入力が長すぎます。") }
                        let image = (args["useImage"] as? Bool == true) ? try camera.image() : nil
                        let result = try await ai.infer(prompt: prompt, image: image, maxOutputTokens: args["maxOutputTokens"] as? Int ?? 256)
                        reply(id, result)
                    case "cancelInference": ai.cancellation.cancel(); reply(id, [:])
                    case "cameraStart": try await camera.start(); reply(id, [:])
                    case "cameraStop": await camera.stop(); reply(id, [:])
                    case "importModel":
                        guard !loading, importing == nil else { throw FridgeError.message("モデルの操作が終わってからお試しください。") }
                        try await ai.unload()
                        importing = id
                        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data], asCopy: false)
                        picker.delegate = self; picker.allowsMultipleSelection = false
                        guard let presenter = presenter() else { importing = nil; throw FridgeError.message("ファイル選択画面を開けませんでした。") }
                        presenter.present(picker, animated: true)
                    case "shareBackup":
                        guard let json = args["json"] as? String, json.utf8.count < 5 * 1024 * 1024 else { throw FridgeError.message("バックアップのサイズが大きすぎます。") }
                        let destination = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("fridge-backup.json")
                        try Data(json.utf8).write(to: destination, options: .atomic)
                        let share = UIActivityViewController(activityItems: [destination], applicationActivities: nil)
                        guard let presenter = presenter() else { throw FridgeError.message("書き出し画面を開けませんでした。") }
                        share.popoverPresentationController?.sourceView = presenter.view
                        share.popoverPresentationController?.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
                        presenter.present(share, animated: true); reply(id, [:])
                    default: throw FridgeError.message("未対応のiOS操作です。")
                    }
                } catch { fail(id, error) }
            }
        }

        private func emit(_ message: [String: Any]) {
            guard let bytes = try? JSONSerialization.data(withJSONObject: message), let json = String(data: bytes, encoding: .utf8) else { return }
            DispatchQueue.main.async { [weak self] in self?.web?.evaluateJavaScript("window.fridgeNativeReceive?.(\(json))", completionHandler: nil) }
        }
        private func reply(_ id: String, _ result: [String: Any]) { emit(["id": id, "result": result]) }
        private func fail(_ id: String, _ error: Error) { let ns = error as NSError; emit(["id": id, "error": error.localizedDescription, "errorName": ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled ? "AbortError" : "Error"]) }
        private func presenter() -> UIViewController? {
            guard let scene = web?.window?.windowScene, var root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return nil }
            while let next = root.presentedViewController { root = next }; return root
        }
        @objc private func background() {
            active = false; ai.cancellation.cancel()
            Task { await camera.stop(); try? await ai.unload(); emit(["type": "engineUnloaded"]) }
        }
        @objc private func foreground() { active = true }
        @objc private func memoryWarning() { ai.cancellation.cancel(); Task { try? await ai.unload(); emit(["type": "engineUnloaded"]) } }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            guard let id = importing else { return }; importing = nil
            emit(["id": id, "error": "ファイル選択を中止しました", "errorName": "AbortError"])
        }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let id = importing, let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            Task {
                defer { importing = nil }
                do { try await Task.detached { [model] in try model.importFile(url) }.value; reply(id, ["saved": true]) }
                catch { fail(id, error) }
                if scoped { url.stopAccessingSecurityScopedResource() }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.cancel); return }
            decisionHandler(url.scheme == "fridge" && url.host == "localhost" ? .allow : .cancel)
        }
        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            let alert = UIAlertController(title: "冷蔵庫の相棒", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel) { _ in completionHandler(false) })
            alert.addAction(UIAlertAction(title: "続ける", style: .default) { _ in completionHandler(true) })
            guard let presenter = presenter() else { completionHandler(false); return }; presenter.present(alert, animated: true)
        }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            ai.cancellation.cancel(); Task { await camera.stop(); try? await ai.unload() }; webView.reload()
        }
    }
}

final class BundleScheme: NSObject, WKURLSchemeHandler {
    private let root = Bundle.main.resourceURL!.appendingPathComponent("Resources/Web", isDirectory: true).standardizedFileURL
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        let path = url.path == "/" ? "index.html" : String(url.path.dropFirst())
        let file = root.appendingPathComponent(path).standardizedFileURL
        guard file.path.hasPrefix(root.path + "/"), let data = try? Data(contentsOf: file) else { task.didFailWithError(FridgeError.message("アプリの画面を読み込めませんでした。")); return }
        let types = ["html": "text/html", "js": "text/javascript", "css": "text/css", "svg": "image/svg+xml", "png": "image/png"]
        let response = URLResponse(url: url, mimeType: types[file.pathExtension] ?? "application/octet-stream", expectedContentLength: data.count, textEncodingName: "utf-8")
        task.didReceive(response); task.didReceive(data); task.didFinish()
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}
