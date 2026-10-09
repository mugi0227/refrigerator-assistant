import SwiftUI
import AVFoundation
import PhotosUI
import UniformTypeIdentifiers

private let fridgeGreen = Color(red:0.26,green:0.41,blue:0.30)
private let fridgeBackground = Color(red:0.969,green:0.973,blue:0.949)

struct NativeRootView: View {
    @StateObject private var store = HouseholdStore()
    @StateObject private var model = NativeAppModel()
    @Environment(\.scenePhase) private var scene
    @State private var tab = 0
    var body: some View {
        TabView(selection:$tab) {
            InventoryView().tabItem { Label("冷蔵庫",systemImage:"refrigerator") }.tag(0)
            ShoppingView().tabItem { Label("買い物",systemImage:"basket") }.tag(1)
            NativeScanView().tabItem { Label("スキャン",systemImage:"viewfinder") }.tag(2)
            RecipesView().tabItem { Label("献立",systemImage:"fork.knife") }.tag(3)
            NativeSettingsView().tabItem { Label("設定",systemImage:"gearshape") }.tag(4)
        }
        .environmentObject(store).environmentObject(model).tint(fridgeGreen)
        .onChange(of:tab) { _, value in if value != 2 { Task { await model.stopCamera() } } }
        .onChange(of:scene) { _, value in if value != .active { Task { await model.background() } } }
        .alert("確認",isPresented:Binding(get:{model.alert != nil},set:{if !$0 { model.alert = nil }})) { Button("OK",role:.cancel) {} } message: { Text(model.alert ?? "") }
    }
}

struct InventoryView: View {
    @EnvironmentObject private var store: HouseholdStore
    @EnvironmentObject private var model: NativeAppModel
    @State private var search = ""
    @State private var location = "all"
    @State private var editing: Food?
    @State private var consuming: Food?
    @State private var amount = "1"
    private var foods: [Food] {
        store.active.filter { food in
            (search.isEmpty || food.name.localizedCaseInsensitiveContains(search)) &&
            (location == "all" || food.location == location || (location == "soon" && (FoodRules.days(food.expiryDate) ?? 999) <= 3))
        }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment:.leading,spacing:12) {
                        Text("fridge.").font(.system(size:36,weight:.bold,design:.serif)).foregroundStyle(fridgeGreen)
                        Text("冷蔵庫のなかを、ひと目で。").font(.title3.bold())
                        Text("\(store.active.count)件の食品 · そろそろ使いたい \(store.active.filter{(FoodRules.days($0.expiryDate) ?? 999) <= 3}.count)件").font(.subheadline)
                        Button("＋ 手入力") { var food = Food(); food.location = store.state.settings.location; editing = food }.buttonStyle(.borderedProminent)
                    }.padding(.vertical,8)
                }
                if let failure = store.failure { Section { Text(failure).foregroundStyle(.red) } }
                Section {
                    Picker("表示する食品",selection:$location) {
                        Text("すべて").tag("all"); Text("そろそろ").tag("soon"); Text("冷蔵").tag("fridge"); Text("冷凍").tag("freezer"); Text("常温").tag("pantry")
                    }
                    ForEach(foods) { food in
                        VStack(alignment:.leading,spacing:8) {
                            HStack { Text(food.name).font(.headline); Spacer(); Text("\(food.quantity.formatted())\(food.unit)").monospacedDigit() }
                            Text("\(FoodRules.locations[food.location] ?? "") · \(FoodRules.expiryTypes[food.expiryType] ?? "") \(food.expiryDate ?? "")").font(.caption).foregroundStyle((FoodRules.days(food.expiryDate) ?? 99) < 0 ? Color.red:Color.secondary)
                            if food.opened { Text("開封済み").font(.caption) }
                            if !food.notes.isEmpty { Text(food.notes).font(.caption) }
                            HStack {
                                Button("編集") { editing = food }.buttonStyle(.bordered)
                                Button("消費する") { amount = food.quantity >= 1 ? "1":String(food.quantity); consuming = food }.buttonStyle(.bordered)
                            }
                        }.padding(.vertical,6)
                    }
                    if foods.isEmpty { ContentUnavailableView("食品はまだありません",systemImage:"refrigerator",description:Text("手入力やスキャンから登録できます。")) }
                }
                Section { Text("使い切り目安は予定を立てるための通知日です。食品の安全性や鮮度を保証しません。").font(.caption) }
            }
            .scrollContentBackground(.hidden).background(fridgeBackground)
            .navigationTitle("冷蔵庫").navigationBarTitleDisplayMode(.inline)
            .searchable(text:$search,prompt:"食品をさがす")
            .sheet(item:$editing) { food in FoodEditor(food:food) { next in try store.put(next) } }
            .alert("消費する数量",isPresented:Binding(get:{consuming != nil},set:{if !$0 { consuming = nil }})) {
                TextField("数量",text:$amount).keyboardType(.decimalPad)
                Button("消費する") { guard let food = consuming else { return }; do { try store.consume(id:food.id,amount:Double(amount) ?? 0) } catch { model.alert = error.localizedDescription }; consuming = nil }
                Button("すべて使い切った") { guard let food = consuming else { return }; do { try store.consume(id:food.id,amount:food.quantity) } catch { model.alert = error.localizedDescription }; consuming = nil }
                Button("キャンセル",role:.cancel) { consuming = nil }
            } message: { Text(consuming.map { "\($0.name) · 在庫 \($0.quantity.formatted())\($0.unit)" } ?? "") }
        }
    }
}

struct FoodEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: HouseholdStore
    @State var food: Food
    var save: (Food) throws -> Void
    @State private var error = ""
    private var date: Binding<Date> { Binding(get:{FoodRules.dateFormatter().date(from:food.expiryDate ?? FoodRules.today) ?? Date()},set:{food.expiryDate = FoodRules.dateFormatter().string(from:$0)}) }
    var body: some View {
        NavigationStack {
            Form {
                Section("食品") {
                    TextField("食品名",text:$food.name).accessibilityIdentifier("foodName")
                    HStack { Text("数量"); Spacer(); TextField("数量",value:$food.quantity,format:.number).keyboardType(.decimalPad).multilineTextAlignment(.trailing); Picker("単位",selection:$food.unit) { ForEach(FoodRules.units,id:\.self) { Text($0).tag($0) } }.labelsHidden() }
                    Picker("保存場所",selection:$food.location) { Text("冷蔵").tag("fridge"); Text("冷凍").tag("freezer"); Text("常温").tag("pantry") }
                    Picker("食品の種類",selection:$food.kind) { Text("包装された商品").tag("packaged"); Text("野菜・果物").tag("produce"); Text("卵").tag("eggs") }
                    if let barcode = food.barcode { Text("商品コード：\(barcode)").font(.caption).textSelection(.enabled) }
                }
                Section("期限") {
                    if food.expiryType == "unknown", let date = food.expiryDate { Text("読み取った日付：\(date)。賞味・消費期限を選んでください。") }
                    Picker("期限の種類",selection:$food.expiryType) { Text("期限未設定").tag("unknown"); Text("賞味期限").tag("best_before"); Text("消費期限").tag("use_by"); Text("使い切り目安").tag("estimate") }
                        .onChange(of:food.expiryType) { _, type in if type == "unknown" { food.expiryDate = nil } else if food.expiryDate == nil { food.expiryDate = FoodRules.today } }
                    if food.expiryType != "unknown" { DatePicker("日付",selection:date,displayedComponents:.date).environment(\.timeZone,TimeZone(secondsFromGMT:0)!) }
                    if food.kind == "produce" {
                        Picker("目安の調整",selection:$food.freshness) { Text("早めに使いたい").tag(0.0); Text("普通").tag(1.0); Text("余裕を持つ").tag(2.0) }
                        Button("使い切り目安を設定") { food.expiryType = "estimate"; food.expiryDate = FoodRules.plan(food.name,freshness:food.freshness,overrides:store.state.settings.shelfDays) }
                    }
                    Toggle("開封済み",isOn:$food.opened)
                    Text("印字の賞味・消費期限は未開封・表示条件での期限です。目安と安全性は別に確認してください。").font(.caption)
                }
                Section("メモ") { TextField("メモ",text:$food.notes,axis:.vertical) }
                if !error.isEmpty { Section { Text(error).foregroundStyle(.red) } }
                Section { Button("保存する") { do { try save(try food.validated()); dismiss() } catch { self.error = error.localizedDescription } }.accessibilityIdentifier("saveFood") }
            }
            .navigationTitle("食品を確認").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.cancellationAction) { Button("キャンセル") { dismiss() } }; ToolbarItem(placement:.confirmationAction) { Button("保存") { do { try save(try food.validated()); dismiss() } catch { self.error = error.localizedDescription } }.accessibilityIdentifier("saveFoodToolbar") } }
        }
    }
}

struct ShoppingView: View {
    @EnvironmentObject private var store: HouseholdStore
    @EnvironmentObject private var model: NativeAppModel
    @State private var name = ""
    @State private var staple: Staple?
    var body: some View {
        NavigationStack {
            List {
                Section("そろそろ補充") {
                    ForEach(store.state.staples.filter { store.have($0) < $0.minimum }) { row in
                        VStack(alignment:.leading,spacing:5) { Text(row.name).font(.headline); Text("在庫 \(store.have(row).formatted())\(row.unit) · 買い足す目安 \(max(0,row.target-store.have(row)).formatted())\(row.unit)").font(.subheadline) }
                    }
                    Text("常備品が補充ラインを下回ると表示されます。").font(.caption).foregroundStyle(.secondary)
                }
                Section("買い物メモ") {
                    HStack { TextField("買うもの",text:$name); Button("追加") { perform { let value = FoodRules.clean(name); guard !value.isEmpty else { return }; try store.update { $0.shopping.append(ShoppingItem(name:value)) }; name = "" } } }
                    ForEach(store.state.shopping) { row in
                        Button { perform { try store.update { home in if let i = home.shopping.firstIndex(where:{$0.id == row.id}) { home.shopping[i].done.toggle() } } } } label: { Label(row.name,systemImage:row.done ? "checkmark.circle.fill":"circle").strikethrough(row.done) }
                            .swipeActions { Button("削除",role:.destructive) { perform { try store.update { $0.shopping.removeAll { $0.id == row.id } } } } }
                    }
                }
                Section("常備したいもの") {
                    Button("＋ 常備品") { staple = Staple() }
                    ForEach(store.state.staples) { row in
                        Button { staple = row } label: { VStack(alignment:.leading) { Text(row.name); Text("\(row.minimum.formatted())\(row.unit)を下回ったら、\(row.target.formatted())\(row.unit)まで補充").font(.caption) } }
                            .swipeActions { Button("削除",role:.destructive) { perform { try store.update { $0.staples.removeAll { $0.id == row.id } } } } }
                    }
                }
            }.navigationTitle("買い物").scrollContentBackground(.hidden).background(fridgeBackground)
                .sheet(item:$staple) { row in StapleEditor(row:row) }
        }
    }
    private func perform(_ action: () throws -> Void) { do { try action() } catch { model.alert = error.localizedDescription } }
}
struct StapleEditor: View {
    @EnvironmentObject private var store: HouseholdStore
    @Environment(\.dismiss) private var dismiss
    @State var row: Staple
    @State private var error = ""
    var body: some View {
        NavigationStack {
            Form {
                TextField("食品名",text:$row.name)
                Picker("単位",selection:$row.unit) { ForEach(FoodRules.units,id:\.self) { Text($0).tag($0) } }
                LabeledContent("補充ライン") { TextField("補充ライン",value:$row.minimum,format:.number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                LabeledContent("補充後の目標") { TextField("補充後の目標",value:$row.target,format:.number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                Text(error).foregroundStyle(.red)
                Button("保存する") {
                    do { row.name = FoodRules.clean(row.name); try row.validate(); try store.update { home in if let i = home.staples.firstIndex(where:{$0.id == row.id}) { home.staples[i] = row } else { home.staples.append(row) } }; dismiss() }
                    catch { self.error = error.localizedDescription }
                }
            }.navigationTitle("常備品").toolbar { ToolbarItem(placement:.cancellationAction) { Button("キャンセル") { dismiss() } } }
        }
    }
}

struct RecipesView: View {
    @EnvironmentObject private var model: NativeAppModel
    @EnvironmentObject private var store: HouseholdStore
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("あるものから、今夜の献立。").font(.title2.bold())
                    Text("期限切れとして登録した食品は候補から除きます。調理前には実物の状態を確認してください。").font(.subheadline)
                    Button("在庫から献立を考える") { Task { await model.makeRecipes(store:store) } }.disabled(!model.aiReady || model.aiBusy || store.active.isEmpty)
                    if !model.aiReady { Text("設定でAIを起動してください。").font(.caption) }
                    if model.recipeBusy { ProgressView("献立を考えています…"); Button("中止") { model.cancelAI() } }
                }
                ForEach(model.recipes) { recipe in
                    Section(recipe.name) {
                        Text("使うもの："+recipe.ingredients.joined(separator:"、"))
                        if !recipe.missing.isEmpty { Text("買い足すもの："+recipe.missing.joined(separator:"、")) }
                        ForEach(Array(recipe.steps.enumerated()),id:\.offset) { index, step in Text("\(index+1). \(step)") }
                        Button("不足分を買い物メモへ") { do { try store.update { home in for name in recipe.missing where !home.shopping.contains(where:{$0.name == FoodRules.clean(name) && !$0.done}) { home.shopping.append(ShoppingItem(name:FoodRules.clean(name))) } } } catch { model.alert = error.localizedDescription } }
                    }
                }
            }.navigationTitle("献立").scrollContentBackground(.hidden).background(fridgeBackground)
        }
    }
}

struct JSONBackup: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents:data) }
}
struct NativeSettingsView: View {
    @EnvironmentObject private var model: NativeAppModel
    @EnvironmentObject private var store: HouseholdStore
    @State private var importing = false
    @State private var modelImport = false
    @State private var exporting = false
    @State private var backup = JSONBackup(data:Data())
    @State private var restoreData: Data?
    @State private var restoreConfirm = false
    @State private var logURL: URL?
    private func setting<T>(_ path: WritableKeyPath<HouseholdSettings,T>) -> Binding<T> {
        Binding(get:{store.state.settings[keyPath:path]},set:{ value in do { try store.update { $0.settings[keyPath:path] = value } } catch { model.alert = error.localizedDescription } })
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("fridge.").font(.system(size:32,weight:.bold,design:.serif)).foregroundStyle(fridgeGreen)
                    Text("v\(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "") · ネイティブ版")
                    Text("写真と在庫はこの端末で処理・保存します。")
                }
                Section("野菜の読み取り・献立の準備") {
                    Text("Gemma 4 E2B").font(.headline)
                    Text("保存済みの約2.6GBモデルを引き継ぎます。公開ライブラリによる起動検査後、同じAIを使って読み取ります。").font(.subheadline)
                    Text(model.status).textSelection(.enabled).accessibilityIdentifier("aiStatus")
                    if model.loading { ProgressView(value:model.progress); Button("ダウンロード・生成を中止") { model.cancelAI() } }
                    Text(model.modelSaved ? "モデル：保存済み":"モデル：未保存").font(.caption)
                    Button(model.modelSaved ? "保存したモデルで起動":"モデルを保存して起動") { Task { await model.loadAI() } }.disabled(model.loading || model.aiBusy).accessibilityIdentifier("loadAI")
                    Button("モデルをファイルから") { modelImport = true }.disabled(model.loading || model.aiBusy)
                    Button("メモリを解放") { Task { await model.unloadAI() } }.disabled(!model.aiReady || model.loading || model.aiBusy)
                    Text("食品・献立ごとに会話を新しくし、前の画像や回答を引き継ぎません。起動したモデルは保持します。失敗時の記録は「ファイル」内のFridge → NativeAIに残ります。").font(.caption)
                    Button("最新のAIログを準備") {
                        do {
                            let root = FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("NativeAI")
                            let folders = try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:[.contentModificationDateKey,.isDirectoryKey]).filter { (try? $0.resourceValues(forKeys:[.isDirectoryKey]).isDirectory) == true }
                            guard let latest = folders.sorted(by:{ ((try? $0.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast) > ((try? $1.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }).first else { return }
                            let combined = ["phases.txt","native-stderr.txt"].map { name in name+"\n"+((try? String(contentsOf:latest.appendingPathComponent(name),encoding:.utf8)) ?? "") }.joined(separator:"\n\n")
                            let output = root.appendingPathComponent("latest-log.txt"); try combined.write(to:output,atomically:true,encoding:.utf8); logURL = output
                        } catch { model.alert = error.localizedDescription }
                    }.disabled(model.loading || model.aiBusy)
                    if let logURL { ShareLink("AIログを共有",item:logURL) }
                }
                Section("読み取りと保存") {
                    Toggle("検知音・登録音",isOn:setting(\.sound))
                    Toggle("バーコードから商品名を探す",isOn:setting(\.externalLookup))
                    Text("オンの場合はOpen Food Factsに番号だけを送ります。写真は送信しません。未収録の商品は手入力できます。").font(.caption)
                    Picker("読み取り間隔",selection:setting(\.interval)) { Text("短め · 0.6秒").tag(600); Text("標準 · 1.2秒").tag(1200); Text("ゆったり · 2.5秒").tag(2500) }
                    Picker("最初の保存場所",selection:setting(\.location)) { Text("冷蔵").tag("fridge"); Text("冷凍").tag("freezer"); Text("常温").tag("pantry") }
                }
                Section("野菜の使い切り目安") {
                    ForEach(FoodRules.shelf.keys.sorted(),id:\.self) { name in
                        Stepper("\(name) · \(store.state.settings.shelfDays[name] ?? FoodRules.shelf[name]!)日",value:Binding(get:{store.state.settings.shelfDays[name] ?? FoodRules.shelf[name]!},set:{ value in do { try store.update { $0.settings.shelfDays[name] = value } } catch { model.alert = error.localizedDescription } }),in:1...60)
                    }
                    Text("変更は今後の登録に適用します。保存期間や安全性を保証する値ではありません。").font(.caption)
                }
                Section("データと移行") {
                    Text("旧版の「設定 → データとバックアップ → 書き出す」で保存したJSONを読み込めます。旧WebViewの在庫を直接開く機能はありません。アプリを削除せず更新してください。").font(.subheadline)
                    Button("バックアップを書き出す") { do { backup = JSONBackup(data:try store.export()); exporting = true } catch { model.alert = error.localizedDescription } }
                    Button("バックアップを読み込む") { importing = true }
                    Text("端末間の自動同期・バックグラウンド期限通知はありません。").font(.caption)
                }
                Section("最近の操作") {
                    ForEach(store.state.events.prefix(12)) { event in
                        VStack(alignment:.leading,spacing:8) {
                            Text("\(["add":"追加","edit":"編集","consume":"消費"][event.kind] ?? event.kind)：\(event.changes.first?.after.name ?? "")")
                            Text(event.at).font(.caption).foregroundStyle(.secondary)
                            if event.undone { Text("取消済み").font(.caption) } else { Button("取り消す") { do { try store.undo(event.id) } catch { model.alert = error.localizedDescription } } }
                        }
                    }
                }
            }.navigationTitle("設定")
                .fileExporter(isPresented:$exporting,document:backup,contentType:.json,defaultFilename:"fridge-backup-\(FoodRules.today)") { result in if case .failure(let error) = result { model.alert = error.localizedDescription } }
                .fileImporter(isPresented:$importing,allowedContentTypes:[.json]) { result in
                    do {
                        let url = try result.get(), access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                        guard (try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? Int.max) <= 5*1024*1024 else { throw FridgeError.message("5MB以下のバックアップを選んでください。") }
                        let data = try Data(contentsOf:url); _ = try Household.importBackup(data); restoreData = data; restoreConfirm = true
                    } catch { model.alert = error.localizedDescription }
                }
                .fileImporter(isPresented:$modelImport,allowedContentTypes:[.data]) { result in switch result { case .success(let url): Task { await model.importModel(url) }; case .failure(let error): model.alert = error.localizedDescription } }
                .confirmationDialog("現在の在庫をバックアップの内容に置き換えますか？",isPresented:$restoreConfirm,titleVisibility:.visible) {
                    Button("読み込んで置き換える",role:.destructive) { do { if let restoreData { try store.restore(restoreData) }; restoreData = nil } catch { model.alert = error.localizedDescription } }
                    Button("キャンセル",role:.cancel) { restoreData = nil }
                }
        }
    }
}
