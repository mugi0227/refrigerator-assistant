import SwiftUI

struct InventoryToast: Equatable { let id = UUID(); let text: String; let eventID: String? }

struct InventoryView: View {
    @EnvironmentObject private var store: HouseholdStore
    @EnvironmentObject private var model: NativeAppModel
    @Binding var tab: Int
    @AppStorage("inventoryLayout") private var layout = "shelf"
    @State private var search = ""
    @State private var editing: Food?
    @State private var selected: Food?
    @State private var editAfterDetail: Food?
    @State private var toast: InventoryToast?
    private var foods: [Food] { store.active.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    if let failure = store.failure { Text(failure).font(.footnote).foregroundStyle(Theme.red) }
                    HStack {
                        Text("\(store.active.count)品").font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        Picker("表示",selection:$layout) { Text("棚").tag("shelf"); Text("リスト").tag("list") }
                            .pickerStyle(.segmented).frame(width:132)
                    }
                    let soon = store.active.filter { $0.urgency == .soon || $0.urgency == .expired }
                    if !soon.isEmpty, search.isEmpty { SoonStrip(foods:soon) { selected = $0 } }
                    if layout == "list" {
                        LazyVStack(spacing:8) { ForEach(foods) { food in FoodRow(food:food,open:{ selected = food },minus:{ act(food,.minus) }) } }
                        if foods.isEmpty, !search.isEmpty { Text("見つかりません").font(.subheadline).foregroundStyle(.secondary).frame(maxWidth:.infinity) }
                    } else {
                        FridgeShelves(foods:foods,open:{ selected = $0 },move:{ food,place in move(food,to:place) })
                    }
                    if store.active.isEmpty { emptyHint }
                }.padding(.horizontal,16).padding(.bottom,90)
            }
            .background(Theme.background)
            .navigationTitle("冷蔵庫")
            .searchable(text:$search,prompt:"食品をさがす")
            .toolbar {
                ToolbarItem(placement:.topBarTrailing) {
                    Button { newFood() } label: { Image(systemName:"plus").font(.body.bold()).frame(width:34,height:34).background(Theme.green,in:Circle()).foregroundStyle(.white) }
                        .accessibilityLabel("食品を追加").accessibilityIdentifier("addFood")
                }
            }
            .sheet(item:$selected,onDismiss:{ if let food = editAfterDetail { editAfterDetail = nil; editing = food } }) { food in
                FoodDetailSheet(foodID:food.id,act:{ act($0,$1) },move:{ move($0,to:$1) },edit:{ editAfterDetail = $0; selected = nil })
            }
            .sheet(item:$editing) { food in
                FoodEditor(food:food,presets:food.name.isEmpty) { next in
                    try store.put(next); show(food.name.isEmpty ? "\(next.name)を追加しました":"\(next.name)を保存しました")
                }
            }
            .overlay(alignment:.bottom) { if let toast { ToastView(toast:toast) { undo(toast) }.padding(.bottom,12).transition(.move(edge:.bottom).combined(with:.opacity)) } }
            .animation(.snappy,value:toast)
            .task(id:toast) { guard toast != nil else { return }; try? await Task.sleep(nanoseconds:4_000_000_000); if !Task.isCancelled { toast = nil } }
        }
    }
    private var emptyHint: some View {
        VStack(spacing:10) {
            Text("まだ何も入っていません").font(.subheadline).foregroundStyle(.secondary)
            HStack {
                Button("手入力で追加") { newFood() }.buttonStyle(.bordered)
                Button("スキャン") { tab = 2 }.buttonStyle(.borderedProminent).tint(Theme.green)
            }
        }.frame(maxWidth:.infinity).padding(.top,4)
    }
    private func newFood() { var food = Food(); food.location = store.state.settings.location; editing = food }
    private func show(_ text: String) { toast = InventoryToast(text:text,eventID:store.state.events.first?.id) }
    private func act(_ food: Food, _ action: FoodAction) {
        do {
            switch action {
            case .minus: try store.consume(id:food.id,amount:min(1,food.quantity)); show("\(food.name)を\(min(1,food.quantity).formatted())\(food.unit)減らしました")
            case .plus: var next = food; next.quantity = ((food.quantity+1)*1000).rounded()/1000; try store.put(next); show("\(food.name)を1\(food.unit)増やしました")
            case .finish: try store.consume(id:food.id,amount:food.quantity); show("\(food.name)を使い切りました")
            }
        } catch { model.alert = error.localizedDescription }
    }
    private func move(_ food: Food, to place: String) {
        guard food.location != place else { return }
        do { var next = food; next.location = place; try store.put(next); show("\(food.name)を\(FoodRules.locations[place] ?? "")へ移しました") }
        catch { model.alert = error.localizedDescription }
    }
    private func undo(_ toast: InventoryToast) {
        guard let id = toast.eventID else { return }
        do { try store.undo(id); self.toast = InventoryToast(text:"元に戻しました",eventID:nil) } catch { model.alert = error.localizedDescription }
    }
}

enum FoodAction { case minus, plus, finish }

struct ToastView: View {
    let toast: InventoryToast
    let undo: () -> Void
    var body: some View {
        HStack(spacing:12) {
            Text(toast.text).font(.subheadline).lineLimit(2)
            if toast.eventID != nil { Button("元に戻す",action:undo).font(.subheadline.bold()).foregroundStyle(Color(red:0.86,green:0.93,blue:0.66)).accessibilityIdentifier("undoToast") }
        }.foregroundStyle(.white).padding(.horizontal,16).padding(.vertical,12)
            .background(Theme.ink,in:RoundedRectangle(cornerRadius:16,style:.continuous))
            .shadow(color:.black.opacity(0.2),radius:12,y:6).padding(.horizontal,16)
    }
}

struct SoonStrip: View {
    let foods: [Food]
    let open: (Food) -> Void
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            Label("期限が近い",systemImage:"clock.badge.exclamationmark").font(.caption.bold()).foregroundStyle(Theme.orange)
            ScrollView(.horizontal,showsIndicators:false) {
                HStack(spacing:8) {
                    ForEach(foods) { food in
                        Button { open(food) } label: {
                            HStack(spacing:6) {
                                FoodIconView(name:food.name,size:24)
                                Text(food.name).font(.subheadline.bold()).lineLimit(1)
                                Text(food.daysText).font(.caption).foregroundStyle(food.urgency == .expired ? Theme.red:Theme.orange)
                            }.padding(.leading,8).padding(.trailing,12).frame(minHeight:40)
                                .background(food.urgency == .expired ? Theme.redSoft:Theme.amber,in:Capsule())
                        }.buttonStyle(.plain).foregroundStyle(Theme.ink)
                    }
                }
            }
        }.padding(12).background(Theme.card,in:RoundedRectangle(cornerRadius:18,style:.continuous))
            .overlay(RoundedRectangle(cornerRadius:18,style:.continuous).stroke(Theme.amber,lineWidth:1.5))
    }
}

/// An open fridge (glass shelves + freezer drawer) and a wooden pantry shelf. Each row of slots sits on its own plank.
struct FridgeShelves: View {
    let foods: [Food]
    let open: (Food) -> Void
    let move: (Food,String) -> Void
    var body: some View {
        VStack(spacing:22) {
            VStack(spacing:0) {
                VStack(spacing:8) {
                    ShelfCompartment(title:"冷蔵",foods:foods.filter { $0.location == "fridge" },minRows:2,inner:Theme.fridgeInner,plank:Theme.glass,lamp:true,open:open,move:move)
                    ShelfCompartment(title:"冷凍",symbol:"snowflake",foods:foods.filter { $0.location == "freezer" },minRows:1,inner:Theme.freezerInner,plank:Theme.glass,open:open,move:move)
                }.padding(8)
                    .background(RoundedRectangle(cornerRadius:30,style:.continuous).fill(LinearGradient(colors:[.white,Color(white:0.955)],startPoint:.top,endPoint:.bottom)))
                    .overlay(RoundedRectangle(cornerRadius:30,style:.continuous).stroke(Color(red:0.80,green:0.85,blue:0.83),lineWidth:2))
                    .shadow(color:.black.opacity(0.08),radius:18,y:10)
                HStack {
                    UnevenRoundedRectangle(bottomLeadingRadius:4,bottomTrailingRadius:4).fill(Color(red:0.80,green:0.85,blue:0.83)).frame(width:22,height:8)
                    Spacer()
                    UnevenRoundedRectangle(bottomLeadingRadius:4,bottomTrailingRadius:4).fill(Color(red:0.80,green:0.85,blue:0.83)).frame(width:22,height:8)
                }.padding(.horizontal,30)
            }
            ShelfCompartment(title:"常温",symbol:"cabinet",foods:foods.filter { $0.location == "pantry" },minRows:1,inner:Theme.woodBack,plank:Theme.wood,open:open,move:move)
                .padding(8).background(Theme.woodBack,in:RoundedRectangle(cornerRadius:22,style:.continuous))
                .overlay(RoundedRectangle(cornerRadius:22,style:.continuous).stroke(Color(red:0.87,green:0.75,blue:0.60),lineWidth:2))
        }
    }
}

struct ShelfCompartment: View {
    let title: String
    var symbol: String?
    let foods: [Food]
    var minRows = 1
    let inner: Color
    let plank: Color
    var lamp = false
    let open: (Food) -> Void
    let move: (Food,String) -> Void
    @Environment(\.horizontalSizeClass) private var sizeClass
    var body: some View {
        let columns = sizeClass == .regular ? 6:4
        let rows = max(minRows,(foods.count+columns-1)/columns)
        VStack(alignment:.leading,spacing:0) {
            HStack(spacing:4) {
                if let symbol { Image(systemName:symbol) }
                Text(title).bold()
                Text("\(foods.count)")
            }.font(.caption).foregroundStyle(.secondary).padding(.leading,6).padding(.bottom,4)
            ForEach(0..<rows,id:\.self) { row in
                HStack(alignment:.bottom,spacing:0) {
                    ForEach(0..<columns,id:\.self) { column in
                        let index = row*columns+column
                        if index < foods.count {
                            ShelfTile(food:foods[index]) { open(foods[index]) }
                                .contextMenu {
                                    ForEach(["fridge","freezer","pantry"].filter { $0 != foods[index].location },id:\.self) { place in
                                        Button("\(FoodRules.locations[place] ?? "")へ移す",systemImage:"arrow.right.circle") { move(foods[index],place) }
                                    }
                                }
                        } else { Color.clear.frame(maxWidth:.infinity) }
                    }
                }.frame(height:96)
                LinearGradient(colors:[plank.opacity(0.45),plank],startPoint:.top,endPoint:.bottom)
                    .frame(height:5).clipShape(Capsule()).padding(.bottom,6)
            }
        }.padding(.horizontal,6).padding(.top,10)
            .background(RoundedRectangle(cornerRadius:22,style:.continuous).fill(inner))
            .overlay(alignment:.top) {
                if lamp {
                    Capsule().fill(Color(red:1,green:0.97,blue:0.82)).frame(width:48,height:5)
                        .shadow(color:Color(red:1,green:0.88,blue:0.55),radius:8)
                }
            }
    }
}

struct ShelfTile: View {
    let food: Food
    let open: () -> Void
    var body: some View {
        Button(action:open) {
            VStack(spacing:2) {
                ZStack(alignment:.topTrailing) {
                    if food.urgency == .soon || food.urgency == .expired {
                        Circle().fill(food.urgency == .expired ? Theme.redSoft:Theme.amber).frame(width:52,height:52)
                    }
                    FoodIconView(name:food.name,size:44).frame(width:52,height:52)
                    if food.quantity != 1 {
                        Text(food.amountText).font(.system(size:10,weight:.bold)).foregroundStyle(.white).fixedSize()
                            .padding(.horizontal,5).padding(.vertical,2).background(Theme.ink,in:Capsule()).offset(x:12,y:-2)
                    }
                }
                Text(food.name).font(.caption2.bold()).lineLimit(1).foregroundStyle(Theme.ink)
                Text(food.daysText).font(.system(size:10,weight:food.urgency == .soon || food.urgency == .expired ? .semibold:.regular))
                    .foregroundStyle(food.urgency == .expired ? Theme.red:food.urgency == .soon ? Theme.orange:Color.secondary)
            }.frame(maxWidth:.infinity).padding(.horizontal,2).padding(.bottom,4).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel("\(food.name) \(food.amountText) \(food.daysText)")
    }
}

struct FoodRow: View {
    let food: Food
    let open: () -> Void
    let minus: () -> Void
    var body: some View {
        HStack(spacing:12) {
            Button(action:open) {
                HStack(spacing:12) {
                    FoodIconView(name:food.name,size:38)
                    VStack(alignment:.leading,spacing:2) {
                        Text(food.name).font(.headline).foregroundStyle(Theme.ink).lineLimit(1)
                        Text("\(food.amountText) · \(food.placeText)\(food.opened ? " · 開封済み":"")").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength:4)
                    ExpiryChip(food:food)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("\(food.name) \(food.amountText) \(food.daysText)")
            Button(action:minus) { Image(systemName:"minus").font(.body.bold()).frame(width:40,height:40).background(Theme.greenSoft,in:Circle()).foregroundStyle(Theme.green) }
                .buttonStyle(.plain).accessibilityLabel("\(food.name)を減らす")
        }.padding(.leading,12).padding(.trailing,8).padding(.vertical,8)
            .background(Theme.card,in:RoundedRectangle(cornerRadius:16,style:.continuous))
    }
}

struct FoodDetailSheet: View {
    @EnvironmentObject private var store: HouseholdStore
    @Environment(\.dismiss) private var dismiss
    let foodID: String
    let act: (Food,FoodAction) -> Void
    let move: (Food,String) -> Void
    let edit: (Food) -> Void
    var body: some View {
        Group {
            if let food = store.state.items.first(where:{ $0.id == foodID && $0.quantity > 0 }) { content(food) }
            else { Color.clear.onAppear { dismiss() } }
        }
        .presentationDetents([.height(470)]).presentationDragIndicator(.visible)
        .presentationCornerRadius(30).presentationBackground(Theme.background)
    }
    private func content(_ food: Food) -> some View {
        VStack(spacing:14) {
            FoodIconView(name:food.name,size:76).frame(width:112,height:112)
                .background(Circle().fill(.white).shadow(color:.black.opacity(0.08),radius:14,y:6))
                .padding(.top,24)
            Text(food.name).font(.title2.bold()).multilineTextAlignment(.center).accessibilityIdentifier("detailName")
            Text("\(food.amountText) · \(food.placeText)\(food.opened ? " · 開封済み":"")").font(.subheadline).foregroundStyle(.secondary)
            ExpiryChip(food:food)
            if !food.notes.isEmpty { Text(food.notes).font(.footnote).foregroundStyle(.secondary) }
            HStack(spacing:10) {
                action("−\(min(1,food.quantity).formatted())","減らす","consumeOne") { act(food,.minus) }
                action("＋1","増やす","addOne") { act(food,.plus) }
                action("✓","使い切り","consumeAll") { act(food,.finish) }
            }.padding(.top,6)
            HStack(spacing:10) {
                Menu {
                    ForEach(["fridge","freezer","pantry"].filter { $0 != food.location },id:\.self) { place in
                        Button("\(FoodRules.locations[place] ?? "")へ移す") { move(food,place); dismiss() }
                    }
                } label: { Label("移動",systemImage:"arrow.left.arrow.right").frame(maxWidth:.infinity,minHeight:46) }
                Button { edit(food) } label: { Label("編集",systemImage:"pencil").frame(maxWidth:.infinity,minHeight:46) }.accessibilityIdentifier("editFood")
            }.font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                .background(Theme.card,in:RoundedRectangle(cornerRadius:16,style:.continuous))
            Spacer(minLength:0)
        }.padding(.horizontal,20)
    }
    private func action(_ value: String, _ title: String, _ id: String, run: @escaping () -> Void) -> some View {
        Button { run(); dismiss() } label: {
            VStack(spacing:4) { Text(value).font(.title2.bold()).foregroundStyle(Theme.ink); Text(title).font(.caption).foregroundStyle(.secondary) }
                .frame(maxWidth:.infinity,minHeight:76)
                .background(Theme.card,in:RoundedRectangle(cornerRadius:18,style:.continuous))
        }.buttonStyle(.plain).accessibilityIdentifier(id)
    }
}
