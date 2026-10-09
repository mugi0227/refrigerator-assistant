import Foundation
import Combine

enum FridgeError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

enum FoodRules {
    static let locations = ["fridge":"冷蔵", "freezer":"冷凍", "pantry":"常温"]
    static let expiryTypes = ["unknown":"期限未設定", "best_before":"賞味期限", "use_by":"消費期限", "estimate":"使い切り目安"]
    static let units = ["個", "本", "パック", "束", "袋", "g", "ml"]
    static let shelf = ["トマト":5,"にんじん":7,"キャベツ":7,"ブロッコリー":3,"ほうれん草":3,"きゅうり":4,"玉ねぎ":7,"じゃがいも":7,"ピーマン":5,"なす":4,"レタス":3,"大根":7,"バナナ":3,"りんご":7,"きのこ":3]
    static func clean(_ text: String) -> String { String(text.precomposedStringWithCompatibilityMapping.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)) }
    static func canonical(_ text: String) -> String {
        let value = clean(text)
        let aliases = ["apple":"りんご","apples":"りんご","リンゴ":"りんご","林檎":"りんご","tomato":"トマト","tomatoes":"トマト","とまと":"トマト","carrot":"にんじん","carrots":"にんじん","人参":"にんじん","ニンジン":"にんじん","cabbage":"キャベツ","broccoli":"ブロッコリー","spinach":"ほうれん草","cucumber":"きゅうり","キュウリ":"きゅうり","胡瓜":"きゅうり","onion":"玉ねぎ","onions":"玉ねぎ","たまねぎ":"玉ねぎ","タマネギ":"玉ねぎ","potato":"じゃがいも","potatoes":"じゃがいも","ジャガイモ":"じゃがいも","green pepper":"ピーマン","bell pepper":"ピーマン","eggplant":"なす","ナス":"なす","茄子":"なす","lettuce":"レタス","daikon":"大根","だいこん":"大根","banana":"バナナ","bananas":"バナナ","mushroom":"きのこ","mushrooms":"きのこ","egg":"卵","eggs":"卵","たまご":"卵","milk":"牛乳"]
        return aliases[value.lowercased()] ?? value
    }
    static func dateFormatter() -> DateFormatter {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier:"en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT:0); f.dateFormat = "yyyy-MM-dd"; f.isLenient = false; return f
    }
    static func validDate(_ text: String) -> Bool {
        guard text.range(of:"^20[0-9]{2}-[0-9]{2}-[0-9]{2}$", options:.regularExpression) != nil,
              let date = dateFormatter().date(from:text) else { return false }
        return dateFormatter().string(from:date) == text
    }
    static var today: String { let f = dateFormatter(); f.timeZone = .current; return f.string(from:Date()) }
    static func days(_ text: String?, now: String = today) -> Int? {
        guard let text, validDate(text), let a = dateFormatter().date(from:text), let b = dateFormatter().date(from:now) else { return nil }
        return Int((a.timeIntervalSince(b)/86400).rounded())
    }
    static func plan(_ name: String, freshness: Double, overrides: [String:Int]) -> String {
        let count = overrides[canonical(name)] ?? shelf[canonical(name)] ?? 3
        let factors = [0.4,1.0,1.2], index = min(2,max(0,Int(freshness)))
        let date = dateFormatter().date(from:today)!.addingTimeInterval(Double(max(1,Int((Double(count)*factors[index]).rounded())))*86400)
        return dateFormatter().string(from:date)
    }
    static func dateFromLabel(_ raw: String) -> String? {
        let text = raw.precomposedStringWithCompatibilityMapping
        let regex = try! NSRegularExpression(pattern:"(?:^|[^0-9])(20[0-9]{2}|[0-9]{2})\\s*[年./-]\\s*([0-9]{1,2})\\s*[月./-]\\s*([0-9]{1,2})(?:日|\\b)")
        guard let m = regex.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)) else { return nil }
        let ns = text as NSString, y = ns.substring(with:m.range(at:1))
        let value = String(format:"%04d-%02d-%02d",Int(y)! + (y.count == 2 ? 2000:0),Int(ns.substring(with:m.range(at:2)))!,Int(ns.substring(with:m.range(at:3)))!)
        return validDate(value) ? value:nil
    }
    static func validGTIN(_ text: String) -> Bool {
        guard [8,12,13,14].contains(text.count), text.allSatisfy({ $0.isASCII && $0.isNumber }) else { return false }
        let digits = text.compactMap(\.wholeNumberValue)
        let sum = digits.dropLast().reversed().enumerated().reduce(0) { $0 + $1.element * ($1.offset % 2 == 0 ? 3:1) }
        return (10-sum%10)%10 == digits.last!
    }
    static func gtin(_ text: String) -> String? { validGTIN(text) ? String(repeating:"0",count:14-text.count)+text:nil }
}

struct Food: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name = "", quantity = 1.0, unit = "個", location = "fridge", kind = "packaged"
    var barcode: String?
    var expiryType = "unknown", expiryDate: String?
    var freshness = 1.0, addedOn = FoodRules.today, opened = false, notes = "", source = "manual", rev = 1
    func validated(allowZero: Bool = false) throws -> Food {
        var f = self; f.name = FoodRules.clean(name); f.notes = FoodRules.clean(notes)
        guard !f.name.isEmpty, !f.name.hasPrefix("未登録の商品"), !id.isEmpty, id.count <= 80,
              quantity.isFinite, quantity >= (allowZero ? 0:0.001), quantity <= 100000,
              FoodRules.units.contains(unit), FoodRules.locations[location] != nil,
              FoodRules.expiryTypes[expiryType] != nil, freshness.isFinite, (0...2).contains(freshness), rev > 0,
              ["produce","packaged","eggs"].contains(kind) else { throw FridgeError.message("食品名・数量・単位・保存場所を確認してください。") }
        if expiryType == "unknown" { guard expiryDate == nil else { throw FridgeError.message("期限の種類を選んでください。") } }
        else { guard let expiryDate, FoodRules.validDate(expiryDate) else { throw FridgeError.message("期限の日付を確認してください。") } }
        if !FoodRules.validDate(f.addedOn) { f.addedOn = FoodRules.today }
        if let barcode { f.barcode = FoodRules.gtin(barcode) }
        return f
    }
}
struct Staple: Codable, Identifiable {
    var id = UUID().uuidString, name = "", unit = "個"
    var minimum = 1.0, target = 3.0
    func validate() throws {
        guard !FoodRules.clean(name).isEmpty, FoodRules.units.contains(unit), minimum.isFinite, target.isFinite, minimum > 0, target >= minimum, target <= 100000 else { throw FridgeError.message("補充ラインと目標数量を確認してください。") }
    }
}
struct ShoppingItem: Codable, Identifiable { var id = UUID().uuidString, name: String; var done = false }
struct FoodChange: Codable { var before: Food?; var after: Food }
struct FoodEvent: Codable, Identifiable { var id = UUID().uuidString, kind: String, at = ISO8601DateFormatter().string(from:Date()); var changes: [FoodChange]; var undone = false }
struct ProductEntry: Codable { var name: String, kind = "packaged", unit = "個" }
struct HouseholdSettings: Codable {
    var sound = true, interval = 1200, confirmMs = 5000, location = "fridge", externalLookup = false, shelfDays: [String:Int] = [:]
    enum CodingKeys: String, CodingKey { case sound, interval, confirmMs, location, externalLookup, shelfDays }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy:CodingKeys.self)
        sound = try c.decodeIfPresent(Bool.self,forKey:.sound) ?? true
        interval = try c.decodeIfPresent(Int.self,forKey:.interval) ?? 1200
        location = try c.decodeIfPresent(String.self,forKey:.location) ?? "fridge"
        externalLookup = try c.decodeIfPresent(Bool.self,forKey:.externalLookup) ?? false
        shelfDays = try c.decodeIfPresent([String:Int].self,forKey:.shelfDays) ?? [:]
        if ![600,1200,2500].contains(interval) { interval = 1200 }
        if FoodRules.locations[location] == nil { location = "fridge" }
        shelfDays = shelfDays.filter { FoodRules.shelf[$0.key] != nil && (1...60).contains($0.value) }
    }
}
struct Household: Codable {
    var version = 1, items: [Food] = [], events: [FoodEvent] = [], staples: [Staple] = [], shopping: [ShoppingItem] = []
    var settings = HouseholdSettings(), productCache: [String:ProductEntry] = [:]
    static func importBackup(_ data: Data) throws -> Household {
        guard data.count <= 5*1024*1024, let object = try JSONSerialization.jsonObject(with:data) as? [String:Any], object["version"] as? Int == 1,
              let items = object["items"] as? [[String:Any]], items.count <= 10000,
              object["staples"] is [[String:Any]], object["shopping"] is [[String:Any]] else { throw FridgeError.message("対応するバックアップではありません。") }
        var safe = object; safe["events"] = []; safe["productCache"] = [:]; safe["settings"] = object["settings"] ?? [:]
        var home = try JSONDecoder().decode(Household.self,from:JSONSerialization.data(withJSONObject:safe))
        home.items = try home.items.map { try $0.validated(allowZero:true) }
        guard Set(home.items.map(\.id)).count == home.items.count else { throw FridgeError.message("在庫IDが重複しています。") }
        home.staples = Array(home.staples.prefix(200)); for row in home.staples { try row.validate() }
        guard Set(home.staples.map(\.id)).count == home.staples.count else { throw FridgeError.message("常備品IDが重複しています。") }
        home.shopping = home.shopping.prefix(200).map { ShoppingItem(name:FoodRules.clean($0.name),done:$0.done) }.filter { !$0.name.isEmpty }
        home.settings.externalLookup = false
        return home
    }
}

@MainActor final class HouseholdStore: ObservableObject {
    @Published private(set) var state = Household()
    @Published var failure: String?
    private let file: URL
    private(set) var writable = true
    init(file: URL? = nil) {
        self.file = file ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("fridge-native-v1.json")
        if FileManager.default.fileExists(atPath:self.file.path) {
            do { state = try JSONDecoder().decode(Household.self,from:Data(contentsOf:self.file)); guard state.version == 1 else { throw FridgeError.message("保存形式が対応していません。") } }
            catch { writable = false; failure = "在庫を開けませんでした。元のファイルは保持しています。\n\(error.localizedDescription)" }
        }
    }
    func update(_ edit: (inout Household) throws -> Void) throws {
        guard writable else { throw FridgeError.message("保存ファイルの読み込みに失敗しています。バックアップを復元してください。") }
        var next = state; try edit(&next); try save(next); state = next
    }
    private func save(_ value: Household) throws {
        try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
        try JSONEncoder().encode(value).write(to:file,options:.atomic)
    }
    func record(_ kind: String, _ changes: [FoodChange], in home: inout Household) {
        home.events.insert(FoodEvent(kind:kind,changes:changes),at:0); home.events = Array(home.events.prefix(200))
    }
    func put(_ food: Food) throws {
        var food = try food.validated()
        try update { home in
            let index = home.items.firstIndex { $0.id == food.id }, before = index.map { home.items[$0] }
            food.rev = (before?.rev ?? 0)+1
            if let index { home.items[index] = food } else { home.items.append(food) }
            if let code = food.barcode { home.productCache[code] = ProductEntry(name:food.name,kind:food.kind,unit:food.unit) }
            record(before == nil ? "add":"edit",[FoodChange(before:before,after:food)],in:&home)
        }
    }
    func consume(id: String, amount: Double) throws {
        try update { home in
            guard let i = home.items.firstIndex(where:{$0.id == id}), amount.isFinite, amount > 0, amount <= home.items[i].quantity else { throw FridgeError.message("消費量が在庫を超えています。") }
            let before = home.items[i]; home.items[i].quantity = ((before.quantity-amount)*1000).rounded()/1000; home.items[i].rev += 1
            record("consume",[FoodChange(before:before,after:home.items[i])],in:&home)
        }
    }
    func consume(candidate: Food) throws {
        try update { home in
            let lots = home.items.indices.filter { i in
                let f = home.items[i]
                let same = (candidate.barcode != nil && f.barcode != nil) ? candidate.barcode == f.barcode : FoodRules.canonical(f.name) == FoodRules.canonical(candidate.name)
                return same && f.location == candidate.location && f.unit == candidate.unit && f.quantity > 0
            }.sorted { (home.items[$0].expiryDate ?? "9999") < (home.items[$1].expiryDate ?? "9999") }
            guard candidate.quantity.isFinite, candidate.quantity > 0, lots.reduce(0.0,{$0+home.items[$1].quantity})+1e-8 >= candidate.quantity else { throw FridgeError.message("一致する在庫が足りません。保存場所・単位・数量を確認してください。") }
            var rest = candidate.quantity, changes: [FoodChange] = []
            for i in lots where rest > 1e-8 {
                let before = home.items[i], take = min(rest,before.quantity); rest -= take
                home.items[i].quantity = ((before.quantity-take)*1000).rounded()/1000; home.items[i].rev += 1
                changes.append(FoodChange(before:before,after:home.items[i]))
            }
            record("consume",changes,in:&home)
        }
    }
    func undo(_ id: String) throws {
        try update { home in
            guard let index = home.events.firstIndex(where:{$0.id == id}), !home.events[index].undone else { throw FridgeError.message("この操作は取り消せません。") }
            let changes = home.events[index].changes
            for change in changes { guard home.items.contains(change.after) else { throw FridgeError.message("その後に変更されています。食品を個別に編集してください。") } }
            for change in changes {
                let i = home.items.firstIndex { $0.id == change.after.id }!
                if var before = change.before { before.rev = change.after.rev+1; home.items[i] = before } else { home.items.remove(at:i) }
            }
            home.events[index].undone = true
        }
    }
    func restore(_ data: Data) throws {
        let next = try Household.importBackup(data)
        if FileManager.default.fileExists(atPath:file.path) { try FileManager.default.copyItem(at:file,to:file.deletingLastPathComponent().appendingPathComponent("fridge-before-restore-\(UUID().uuidString).json")) }
        try save(next); state = next; writable = true; failure = nil
    }
    func export() throws -> Data { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]; return try encoder.encode(state) }
    var active: [Food] { state.items.filter { $0.quantity > 0 }.sorted { ($0.expiryDate ?? "9999") < ($1.expiryDate ?? "9999") } }
    func have(_ staple: Staple) -> Double { active.filter { FoodRules.canonical($0.name) == FoodRules.canonical(staple.name) && $0.unit == staple.unit }.reduce(0,{$0+$1.quantity}) }
}
