import SwiftUI

// The WebView and camera are not constructed while the probe is displayed.
struct ProbeLandingView: View {
    @State private var showInventory = ProcessInfo.processInfo.arguments.contains("--inventory-ui-test")
    @State private var running = false
    @State private var status = "保存済みモデルで、公開成功例の画像認識を試します。"
    @State private var logFiles: [URL] = []
    private let runner = ReferenceProbe()
    private let model = ModelStore()

    var body: some View {
        if showInventory {
            FridgeWebView()
        } else {
            NavigationStack {
                Form {
                    Section {
                        Text("Gemma 4 画像認識の比較").font(.title2.bold())
                        Text("v0.2.7 · 公開ライブラリの比較版").foregroundStyle(.secondary)
                        Text("カメラを使わず、リンゴと赤い画像を読み取ります。モデルと在庫はそのまま使います。")
                    }
                    Section("テスト") {
                        if running { ProgressView() }
                        Text(status).textSelection(.enabled).accessibilityIdentifier("probeStatus")
                        Button("比較テストを開始") { start() }
                            .disabled(running).accessibilityIdentifier("startReferenceProbe")
                        Text("起動には数分かかる場合があります。実行中はこの画面を開いたままにしてください。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Section("結果") {
                        if !logFiles.isEmpty {
                            ShareLink(items: logFiles) { Label("結果と内部ログを共有", systemImage: "square.and.arrow.up") }
                                .disabled(running)
                        }
                        Text("アプリが閉じても、途中の記録は「ファイル」→「このiPhone内」→「Fridge」→「GemmaProbe」に残ります。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Section {
                        Button("通常の冷蔵庫画面を開く") { showInventory = true }
                            .disabled(running)
                        Text("比較画面へ戻るには、アプリを終了して開き直します。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("Gemma比較")
            }
            .task { loadLatestLog() }
        }
    }

    private var logsRoot: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GemmaProbe", isDirectory: true)
    }
    private func loadLatestLog() {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: logsRoot, includingPropertiesForKeys: nil)) ?? []
        if let latest = dirs.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }).first { collectLogs(latest) }
    }
    private func collectLogs(_ directory: URL) {
        logFiles = ["result.json", "phases.txt", "native-stderr.txt", "apple-partial.txt", "red-partial.txt"].map { directory.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }
    private func start() {
        guard model.saved else {
            status = "保存済みモデルが見つかりません。通常画面の設定でモデルを保存してから、アプリを開き直してください。"
            return
        }
        running = true; UIApplication.shared.isIdleTimerDisabled = true
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let output = logsRoot.appendingPathComponent(stamp + "-" + String(UUID().uuidString.prefix(8)), isDirectory: true)
        let url = model.model
        Task {
            defer {
                running = false; UIApplication.shared.isIdleTimerDisabled = false; collectLogs(output)
            }
            do {
                _ = try await runner.run(model: url, output: output) { message in
                    await MainActor.run { status = message }
                }
            } catch { status = "失敗：\(error.localizedDescription)\n「結果と内部ログを共有」で記録を送れます。" }
        }
    }
}
