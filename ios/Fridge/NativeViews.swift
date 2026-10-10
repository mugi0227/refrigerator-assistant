import SwiftUI
import AVFoundation
import PhotosUI
import UniformTypeIdentifiers

struct NativeRootView: View {
    @StateObject private var store = HouseholdStore()
    @StateObject private var model = NativeAppModel()
    @Environment(\.scenePhase) private var scene
    @State private var tab = 0
    var body: some View {
        TabView(selection:$tab) {
            InventoryView(tab:$tab).tabItem { Label("冷蔵庫",systemImage:"refrigerator") }.tag(0)
            ShoppingView().tabItem { Label("買い物",systemImage:"cart") }.tag(1)
            NativeScanView().tabItem { Label("スキャン",systemImage:"barcode.viewfinder") }.tag(2)
            RecipesView().tabItem { Label("献立",systemImage:"fork.knife") }.tag(3)
            NativeSettingsView().tabItem { Label("設定",systemImage:"gearshape") }.tag(4)
        }
        .environmentObject(store).environmentObject(model).tint(Theme.green)
        .preferredColorScheme(tab == 2 ? .dark:.light)
        .task { await model.autoStartAI() }
        .onChange(of:tab) { _, value in Task { if value == 2 { await model.startCamera(store:store) } else { await model.stopCamera() } } }
        .onChange(of:scene) { _, value in
            if value == .background { Task { await model.background() } }
            else if value == .active, tab == 2, model.capturedImage == nil { Task { await model.startCamera(store:store) } }
        }
        .alert("確認",isPresented:Binding(get:{model.alert != nil},set:{if !$0 { model.alert = nil }})) { Button("OK",role:.cancel) {} } message: { Text(model.alert ?? "") }
    }
}

struct FoodPreset: Identifiable { var id: String { name }; let name: String; let quantity: Double; let unit: String; var kind: String?; var location: String? }

/// Add/confirm one food. Common foods are one tap; kind, estimate date and icon follow the name so few fields need touching.
struct FoodEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: HouseholdStore
    @State var food: Food
    var presets = false
    var save: (Food) throws -> Void
    @State private var error = ""
    @State private var picked: String?
    private static let common: [(String,Double,String)] = [("牛乳",1,"本"),("卵",10,"個"),("ヨーグルト",1,"個"),("豆腐",1,"パック"),("納豆",3,"パック"),("チーズ",1,"個"),("ハム",1,"パック"),("豚肉",1,"パック"),("鶏肉",1,"パック"),("鮭",1,"パック"),("トマト",3,"個"),("キャベツ",1,"個"),("玉ねぎ",3,"個"),("にんじん",3,"本"),("きゅうり",3,"本"),("レタス",1,"個"),("もやし",1,"袋"),("きのこ",1,"パック"),("バナナ",3,"本"),("りんご",2,"個")]
    // Recently stocked foods first (used-up ones are the usual re-buys), then common staples.
    private var presetList: [FoodPreset] {
        var seen = Set<String>(), list: [FoodPreset] = []
        for item in store.state.items.sorted(by:{ $0.addedOn > $1.addedOn }) where list.count < 8 {
            let key = FoodRules.canonical(item.name)
            guard !seen.contains(key), !item.name.hasPrefix("未登録") else { continue }
            seen.insert(key)
            list.append(FoodPreset(name:item.name,quantity:Self.common.first { FoodRules.canonical($0.0) == key }?.1 ?? 1,unit:item.unit,kind:item.kind,location:item.location))
        }
        for (name,quantity,unit) in Self.common where !seen.contains(FoodRules.canonical(name)) { seen.insert(FoodRules.canonical(name)); list.append(FoodPreset(name:name,quantity:quantity,unit:unit)) }
        return list
    }
    private var expiryType: Binding<String> {
        Binding(get:{ food.expiryType },set:{ type in
            food.expiryType = type
            if type == "unknown" { food.expiryDate = nil }
            else if type == "estimate" { food.expiryDate = FoodRules.plan(food.name,freshness:food.freshness,overrides:store.state.settings.shelfDays) }
            else if food.expiryDate == nil { food.expiryDate = FoodRules.today }
        })
    }
    private var date: Binding<Date> { Binding(get:{FoodRules.dateFormatter().date(from:food.expiryDate ?? FoodRules.today) ?? Date()},set:{food.expiryDate = FoodRules.dateFormatter().string(from:$0)}) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    if presets { presetGrid }
                    HStack(alignment:.bottom,spacing:12) {
                        FoodIconView(name:food.name,size:42).frame(width:60,height:60)
                            .background(Theme.card,in:RoundedRectangle(cornerRadius:18,style:.continuous))
                        VStack(alignment:.leading,spacing:6) {
                            Text("食品名").font(.caption).foregroundStyle(.secondary)
                            TextField("例：牛乳",text:$food.name).font(.title3).padding(.horizontal,12).frame(minHeight:48)
                                .background(Theme.card,in:RoundedRectangle(cornerRadius:14,style:.continuous))
                                .accessibilityLabel("食品名").accessibilityIdentifier("foodName")
                        }
                    }
                    field("数量") {
                        HStack(spacing:10) {
                            HStack(spacing:0) {
                                Button { step(-1) } label: { Image(systemName:"minus").frame(width:48,height:48) }.accessibilityLabel("1減らす")
                                TextField("数量",value:$food.quantity,format:.number).keyboardType(.decimalPad).multilineTextAlignment(.center)
                                    .font(.title3.bold()).frame(minWidth:56).accessibilityIdentifier("quantity")
                                Button { step(1) } label: { Image(systemName:"plus").frame(width:48,height:48) }.accessibilityLabel("1増やす")
                            }.background(Theme.card,in:RoundedRectangle(cornerRadius:14,style:.continuous)).foregroundStyle(Theme.green)
                            Picker("単位",selection:$food.unit) { ForEach(FoodRules.units,id:\.self) { Text($0).tag($0) } }
                                .pickerStyle(.menu).frame(maxWidth:.infinity,minHeight:48).background(Theme.card,in:RoundedRectangle(cornerRadius:14,style:.continuous))
                        }
                    }
                    field("保存場所") {
                        Picker("保存場所",selection:$food.location) { Text("冷蔵").tag("fridge"); Text("冷凍").tag("freezer"); Text("常温").tag("pantry") }.pickerStyle(.segmented)
                    }
                    field("期限") {
                        if food.expiryType == "unknown", let date = food.expiryDate { Text("読み取った日付：\(date)。種類を選んでください。").font(.footnote) }
                        Picker("期限の種類",selection:expiryType) { Text("賞味").tag("best_before"); Text("消費").tag("use_by"); Text("目安").tag("estimate"); Text("なし").tag("unknown") }
                            .pickerStyle(.segmented)
                        if food.expiryType != "unknown" {
                            DatePicker("日付",selection:date,displayedComponents:.date).environment(\.timeZone,TimeZone(secondsFromGMT:0)!)
                                .padding(.horizontal,12).frame(minHeight:48).background(Theme.card,in:RoundedRectangle(cornerRadius:14,style:.continuous))
                        }
                        HStack(spacing:8) {
                            ForEach([3,7,14,30],id:\.self) { days in
                                Button([3:"3日後",7:"1週間",14:"2週間",30:"1か月"][days] ?? "") {
                                    food.expiryDate = FoodRules.after(days:days)
                                    if food.expiryType == "unknown" { food.expiryType = food.kind == "produce" ? "estimate":"best_before" }
                                }.font(.subheadline.weight(.semibold)).frame(maxWidth:.infinity,minHeight:38)
                                    .background(Theme.greenSoft,in:Capsule()).foregroundStyle(Theme.green)
                            }
                        }
                    }
                    if food.kind == "produce" {
                        field("状態") {
                            Picker("状態",selection:$food.freshness) { Text("早めに使う").tag(0.0); Text("普通").tag(1.0); Text("新鮮").tag(2.0) }.pickerStyle(.segmented)
                            Text("目安日は選んだ状態から計算する予定日です。安全性は判定しません。").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    DisclosureGroup("詳細") {
                        VStack(alignment:.leading,spacing:12) {
                            Picker("食品の種類",selection:$food.kind) { Text("包装された商品").tag("packaged"); Text("野菜・果物").tag("produce"); Text("卵").tag("eggs") }
                            Toggle("開封済み（印字の期限は未開封時のもの）",isOn:$food.opened)
                            TextField("メモ",text:$food.notes,axis:.vertical).padding(10).background(Theme.card,in:RoundedRectangle(cornerRadius:12,style:.continuous))
                            if let barcode = food.barcode { Text("商品コード：\(barcode)").font(.caption).textSelection(.enabled) }
                        }.padding(.top,8)
                    }.font(.subheadline).tint(.secondary)
                    if !error.isEmpty { Text(error).font(.footnote).foregroundStyle(Theme.red) }
                }.padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .safeAreaInset(edge:.bottom) {
                Button(action:submit) { Text(presets ? "追加する":"保存する").font(.headline).frame(maxWidth:.infinity,minHeight:52) }
                    .buttonStyle(.borderedProminent).tint(Theme.green).clipShape(RoundedRectangle(cornerRadius:16,style:.continuous))
                    .padding(.horizontal,16).padding(.vertical,8).background(.bar).accessibilityIdentifier("saveFood")
            }
            .navigationTitle(presets ? "食品を追加":"食品を確認").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement:.confirmationAction) { Button("保存",action:submit).accessibilityIdentifier("saveFoodToolbar") }
            }
            .onChange(of:food.name) { _, name in if presets { applyKind(FoodRules.guessKind(name)) } }
            .onChange(of:food.kind) { _, kind in if kind == "produce", food.expiryType == "unknown" { expiryType.wrappedValue = "estimate" } }
            .onChange(of:food.freshness) { _, _ in if food.expiryType == "estimate" { expiryType.wrappedValue = "estimate" } }
        }
    }
    private var presetGrid: some View {
        ScrollView(.horizontal,showsIndicators:false) {
            LazyHGrid(rows:[GridItem(.fixed(74),spacing:8),GridItem(.fixed(74))],spacing:8) {
                ForEach(presetList) { preset in
                    Button { apply(preset) } label: {
                        VStack(spacing:3) { FoodIconView(name:preset.name,size:32); Text(preset.name).font(.caption2).lineLimit(1).foregroundStyle(Theme.ink) }
                            .frame(width:70,height:74)
                            .background(picked == preset.id ? Theme.greenSoft:Theme.card,in:RoundedRectangle(cornerRadius:16,style:.continuous))
                            .overlay(RoundedRectangle(cornerRadius:16,style:.continuous).stroke(picked == preset.id ? Theme.green:.clear,lineWidth:1.5))
                    }.buttonStyle(.plain).accessibilityLabel(preset.name).accessibilityIdentifier("preset-\(preset.name)")
                }
            }.padding(.horizontal,16)
        }.padding(.horizontal,-16)
    }
    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment:.leading,spacing:8) { Text(title).font(.caption).foregroundStyle(.secondary); content() }
    }
    private func step(_ delta: Double) { let next = ((food.quantity+delta)*1000).rounded()/1000; if next > 0 { food.quantity = next } }
    private func applyKind(_ kind: String) {
        food.kind = kind
        if kind == "produce", ["unknown","estimate"].contains(food.expiryType) { expiryType.wrappedValue = "estimate" }
        else if kind != "produce", food.expiryType == "estimate" { expiryType.wrappedValue = "unknown" }
    }
    private func apply(_ preset: FoodPreset) {
        picked = preset.id; food.name = preset.name; food.quantity = preset.quantity; food.unit = preset.unit
        if let location = preset.location { food.location = location }
        applyKind(preset.kind ?? FoodRules.guessKind(preset.name))
    }
    private func submit() { do { try save(try food.validated()); dismiss() } catch { self.error = error.localizedDescription } }
}

struct ShoppingView: View {
    @EnvironmentObject private var store: HouseholdStore
    @EnvironmentObject private var model: NativeAppModel
    @State private var name = ""
    @State private var staple: Staple?
    @State private var stocking: Food?
    @State private var stockingMemo: String?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("買うもの",text:$name).onSubmit(add)
                        Button("追加",action:add).buttonStyle(.borderedProminent).tint(Theme.green)
                    }
                }
                let needs = store.state.staples.filter { store.have($0) < $0.minimum }
                if !needs.isEmpty {
                    Section("補充が必要") {
                        ForEach(needs) { row in
                            let buy = max(0,row.target-store.have(row))
                            HStack(spacing:12) {
                                FoodIconView(name:row.name,size:32)
                                VStack(alignment:.leading,spacing:2) { Text(row.name).font(.headline); Text("あと\(buy.formatted())\(row.unit)（いま\(store.have(row).formatted())\(row.unit)）").font(.caption).foregroundStyle(.secondary) }
                                Spacer()
                                Button("買った") { stock(row.name,quantity:buy,unit:row.unit,memo:nil) }.buttonStyle(.bordered).tint(Theme.green)
                            }
                        }
                    }
                }
                Section("メモ") {
                    ForEach(store.state.shopping) { row in
                        HStack(spacing:12) {
                            Button { perform { try store.update { home in if let i = home.shopping.firstIndex(where:{$0.id == row.id}) { home.shopping[i].done.toggle() } } } } label: {
                                HStack(spacing:12) {
                                    Image(systemName:row.done ? "checkmark.circle.fill":"circle").font(.title3).foregroundStyle(row.done ? Theme.green:.secondary)
                                    FoodIconView(name:row.name,size:28).opacity(row.done ? 0.45:1)
                                    Text(row.name).strikethrough(row.done).foregroundStyle(row.done ? Color.secondary:Theme.ink)
                                    Spacer()
                                }.contentShape(Rectangle())
                            }.buttonStyle(.borderless).accessibilityLabel(row.name)
                            if !row.done { Button("買った") { stock(row.name,quantity:1,unit:"個",memo:row.id) }.buttonStyle(.bordered).tint(Theme.green) }
                        }.swipeActions { Button("削除",role:.destructive) { perform { try store.update { $0.shopping.removeAll { $0.id == row.id } } } } }
                    }
                    if store.state.shopping.isEmpty { Text("メモはありません").foregroundStyle(.secondary) }
                }
                Section {
                    ForEach(store.state.staples) { row in
                        Button { staple = row } label: {
                            HStack(spacing:12) {
                                FoodIconView(name:row.name,size:28)
                                VStack(alignment:.leading) { Text(row.name).foregroundStyle(Theme.ink); Text("\(row.minimum.formatted())\(row.unit)未満で補充 → \(row.target.formatted())\(row.unit)まで").font(.caption).foregroundStyle(.secondary) }
                            }
                        }.swipeActions { Button("削除",role:.destructive) { perform { try store.update { $0.staples.removeAll { $0.id == row.id } } } } }
                    }
                    Button("＋ 常備品を追加") { staple = Staple() }
                } header: { Text("常備品") } footer: { Text("在庫が補充ラインを下回ると「補充が必要」に出ます。") }
            }.navigationTitle("買い物").scrollContentBackground(.hidden).background(Theme.background)
                .sheet(item:$staple) { row in StapleEditor(row:row) }
                .sheet(item:$stocking) { food in
                    FoodEditor(food:food,presets:true) { next in
                        try store.put(next)
                        if let memo = stockingMemo { try store.update { home in if let i = home.shopping.firstIndex(where:{$0.id == memo}) { home.shopping[i].done = true } } }
                    }
                }
        }
    }
    private func add() { perform { let value = FoodRules.clean(name); guard !value.isEmpty else { return }; try store.update { $0.shopping.append(ShoppingItem(name:value)) }; name = "" } }
    private func stock(_ name: String, quantity: Double, unit: String, memo: String?) {
        var food = Food(); food.name = name; food.quantity = max(1,quantity); food.unit = unit; food.location = store.state.settings.location
        food.kind = FoodRules.guessKind(name)
        if food.kind == "produce" { food.expiryType = "estimate"; food.expiryDate = FoodRules.plan(name,freshness:1,overrides:store.state.settings.shelfDays) }
        stockingMemo = memo; stocking = food
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
                HStack { FoodIconView(name:row.name,size:32); TextField("食品名",text:$row.name) }
                Picker("単位",selection:$row.unit) { ForEach(FoodRules.units,id:\.self) { Text($0).tag($0) } }
                LabeledContent("補充ライン") { TextField("補充ライン",value:$row.minimum,format:.number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                LabeledContent("補充後の目標") { TextField("補充後の目標",value:$row.target,format:.number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                if !error.isEmpty { Text(error).foregroundStyle(.red) }
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
        let usable = store.active.filter { (FoodRules.days($0.expiryDate) ?? 0) >= 0 }
        NavigationStack {
            List {
                Section {
                    Text("使える食材\(usable.count)品から、3つの献立を提案します。").font(.subheadline).foregroundStyle(.secondary)
                    ScrollView(.horizontal,showsIndicators:false) {
                        HStack(spacing:6) { ForEach(usable) { food in HStack(spacing:4) { FoodIconView(name:food.name,size:20); Text(food.name).font(.caption) }.padding(.horizontal,8).padding(.vertical,5).background(Theme.greenSoft,in:Capsule()) } }
                    }
                    Button("献立を提案") { Task { await model.makeRecipes(store:store) } }.buttonStyle(.borderedProminent).tint(Theme.green)
                        .disabled(!model.aiReady || model.aiBusy || store.active.isEmpty)
                    if !model.aiReady { Text("献立の提案には、設定で端末内AIを起動してください。").font(.caption).foregroundStyle(.secondary) }
                    if model.recipeBusy { ProgressView("献立を考えています…"); Button("中止") { model.cancelAI() } }
                } footer: { Text("期限切れの食品は除きます。調理前に実物の状態を確認してください。") }
                ForEach(model.recipes) { recipe in
                    Section(recipe.name) {
                        Text("使うもの："+recipe.ingredients.joined(separator:"、"))
                        if !recipe.missing.isEmpty { Text("買い足すもの："+recipe.missing.joined(separator:"、")) }
                        ForEach(Array(recipe.steps.enumerated()),id:\.offset) { index, step in Text("\(index+1). \(step)") }
                        Button("不足分を買い物メモへ") { do { try store.update { home in for name in recipe.missing where !home.shopping.contains(where:{$0.name == FoodRules.clean(name) && !$0.done}) { home.shopping.append(ShoppingItem(name:FoodRules.clean(name))) } } } catch { model.alert = error.localizedDescription } }
                    }
                }
            }.navigationTitle("献立").scrollContentBackground(.hidden).background(Theme.background)
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
                    Text("v\(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "") · ネイティブ版")
                    Text("写真と在庫はこの端末で処理・保存します。")
                }
                Section("野菜の読み取り・献立の準備") {
                    Picker("モデル",selection:Binding(get:{ model.variant },set:{ value in model.variant = value; Task { await model.selectVariant(value) } })) {
                        ForEach(GemmaVariant.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).disabled(model.loading || model.aiBusy).accessibilityIdentifier("gemmaVariant")
                    Text("\(model.variant.summary)。保存済みならアプリを開くと自動で起動します。E4Bは読み取りが正確な代わりに時間とメモリを多く使います。").font(.subheadline)
                    Text(model.status).textSelection(.enabled).accessibilityIdentifier("aiStatus")
                    if !model.aiErrorDetail.isEmpty { DisclosureGroup("エラーの詳細") { Text(model.aiErrorDetail).font(.caption).textSelection(.enabled) } }
                    if model.loading { ProgressView(value:model.progress); Button("ダウンロード・生成を中止") { model.cancelAI() } }
                    Text(model.modelSaved ? "モデル：保存済み":"モデル：未保存").font(.caption)
                    Button(model.modelSaved ? "保存したモデルで起動":"モデルを保存して起動") { Task { await model.loadAI() } }.disabled(model.loading || model.aiBusy).accessibilityIdentifier("loadAI")
                    Button("モデルをファイルから") { modelImport = true }.disabled(model.loading || model.aiBusy)
                    Button("メモリを解放") { Task { await model.unloadAI() } }.disabled(!model.aiReady || model.loading || model.aiBusy)
                    ForEach(GemmaVariant.allCases.filter { $0 != model.variant && model.models.isSaved($0) }) { other in
                        Button("保存済みの\(other.title)を削除",role:.destructive) { model.deleteModel(other) }.disabled(model.loading)
                    }
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
                    Picker("期限を探す間隔",selection:setting(\.interval)) { Text("短め · 0.6秒").tag(600); Text("標準 · 1.2秒").tag(1200); Text("ゆったり · 2.5秒").tag(2500) }
                    Picker("最初の保存場所",selection:setting(\.location)) { Text("冷蔵").tag("fridge"); Text("冷凍").tag("freezer"); Text("常温").tag("pantry") }
                }
                Section("データと移行") {
                    Text("旧版の「設定 → データとバックアップ → 書き出す」で保存したJSONを読み込めます。旧WebViewの在庫を直接開く機能はありません。アプリを削除せず更新してください。").font(.subheadline)
                    Button("バックアップを書き出す") { do { backup = JSONBackup(data:try store.export()); exporting = true } catch { model.alert = error.localizedDescription } }
                    Button("バックアップを読み込む") { importing = true }
                    Text("端末間の自動同期・バックグラウンド期限通知はありません。").font(.caption)
                }
                Section("詳細設定") {
                    NavigationLink("野菜の使い切り目安") {
                        Form {
                            Section {
                                ForEach(FoodRules.shelf.keys.sorted(),id:\.self) { name in
                                    Stepper("\(name) · \(store.state.settings.shelfDays[name] ?? FoodRules.shelf[name]!)日",value:Binding(get:{store.state.settings.shelfDays[name] ?? FoodRules.shelf[name]!},set:{ value in do { try store.update { $0.settings.shelfDays[name] = value } } catch { model.alert = error.localizedDescription } }),in:1...60)
                                }
                                Text("変更は今後の登録に適用します。保存期間や安全性を保証する値ではありません。").font(.caption)
                            }
                        }.navigationTitle("使い切り目安")
                    }
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
