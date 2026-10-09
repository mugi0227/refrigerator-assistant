import SwiftUI

enum Theme {
    static let green = Color(red:0.26,green:0.41,blue:0.30)
    static let background = Color(red:0.965,green:0.969,blue:0.953)
    static let ink = Color(red:0.12,green:0.18,blue:0.16)
    static let card = Color.white
    static let line = Color(red:0.89,green:0.91,blue:0.88)
    static let amber = Color(red:0.99,green:0.94,blue:0.85)
    static let orange = Color(red:0.66,green:0.37,blue:0.09)
    static let redSoft = Color(red:0.98,green:0.90,blue:0.88)
    static let red = Color(red:0.69,green:0.23,blue:0.19)
    static let greenSoft = Color(red:0.92,green:0.95,blue:0.90)
    static let fridgeInner = Color(red:0.93,green:0.96,blue:0.95)
    static let freezerInner = Color(red:0.90,green:0.93,blue:0.97)
    static let glass = Color(red:0.76,green:0.84,blue:0.82)
    static let wood = Color(red:0.78,green:0.60,blue:0.42)
    static let woodBack = Color(red:0.97,green:0.94,blue:0.89)
}

/// 3D food illustrations bundled from Microsoft Fluent Emoji (MIT). Every rule points at an asset in Assets.xcassets/Food.
enum FoodIcon {
    private static let produce = ["トマト":"tomato","にんじん":"carrot","キャベツ":"leafy","ブロッコリー":"broccoli","ほうれん草":"leafy","きゅうり":"cucumber","玉ねぎ":"onion","じゃがいも":"potato","ピーマン":"bellpepper","なす":"eggplant","レタス":"leafy","大根":"leafy","バナナ":"banana","りんご":"apple","きのこ":"mushroom"]
    // First match wins, so narrower words come first (牛乳 before 牛, すいか before いか).
    private static let rules: [(String,String)] = [
        ("卵|たまご|タマゴ|egg","egg"), ("ヨーグルト|yogurt","bowl"), ("チーズ|cheese","cheese"), ("バター|マーガリン|butter","butter"),
        ("アイス|ice ?cream","icecream"), ("プリン|ゼリー","pudding"), ("ケーキ|cake","cake"), ("チョコ","chocolate"),
        ("牛乳|豆乳|ミルク|乳飲料|milk","milk"), ("ジュース|juice","juice"), ("コーラ|サイダー|炭酸|ソーダ","soda"), ("コーヒー|coffee","coffee"),
        ("茶|tea","tea"), ("ビール|beer","beer"), ("ワイン|wine","wine"), ("日本酒|酒","sake"), ("^水$|ウォーター|water","water"),
        ("豆腐|とうふ|tofu","tofu"), ("納豆|なっとう","beans"), ("枝豆|えだまめ|そら豆|えんどう","peapod"),
        ("ベーコン|ハム|bacon|ham","bacon"), ("ソーセージ|ウインナー|ウィンナー|sausage","sausage"), ("鶏|チキン|ささみ|手羽|chicken","chicken"),
        ("肉|豚|牛|ステーキ|meat|pork|beef","meat"), ("えび|エビ|海老|shrimp","shrimp"), ("^いか|イカ|烏賊|たこ|タコ","squid"), ("あさり|しじみ|貝|牡蠣","oyster"),
        ("刺身|寿司|すし","sushi"), ("ちくわ|かまぼこ|はんぺん","fishcake"), ("すいか|スイカ|西瓜","watermelon"),
        ("魚|鮭|さけ|サーモン|さば|鯖|あじ|鯵|ぶり|鰤|たら|鱈|まぐろ|fish|salmon","fish"),
        ("餃子|ぎょうざ|ギョーザ","dumpling"), ("弁当|惣菜|そうざい","bento"), ("ピザ|pizza","pizza"), ("パスタ|スパゲ","pasta"),
        ("うどん|そば|ラーメン|麺|焼きそば|noodle","noodle"), ("おにぎり","riceball"), ("ご飯|ごはん|米|rice","rice"), ("パン|bread","bread"),
        ("白菜|小松菜|水菜|チンゲン|青菜|ほうれん","leafy"), ("ねぎ|ネギ|葱|大葉|バジル|パセリ|ハーブ|ニラ|にら","herb"), ("もやし|スプラウト|豆苗","sprout"),
        ("さつまいも|さつま芋","sweetpotato"), ("いも|芋","potato"), ("かぼちゃ|南瓜","pumpkin"), ("とうもろこし|コーン|corn","corn"), ("にんにく|ニンニク|garlic","garlic"),
        ("しょうが|生姜|ショウガ|ginger","ginger"), ("唐辛子|とうがらし|チリ","chili"), ("パプリカ","bellpepper"), ("しいたけ|えのき|しめじ|まいたけ|エリンギ","mushroom"),
        ("アボカド|avocado","avocado"), ("レモン|lemon","lemon"), ("みかん|オレンジ|orange","orange"), ("いちご|苺|イチゴ|strawberr","strawberry"),
        ("ぶどう|葡萄|ブドウ|grape","grapes"), ("もも|桃|peach","peach"), ("メロン|melon","melon"), ("キウイ|kiwi","kiwi"),
        ("パイン|pineapple","pineapple"), ("さくらんぼ|チェリー|cherr","cherry"), ("ブルーベリー|blueberr","blueberry"), ("梨|pear","pear"), ("マンゴー|mango","mango"),
        ("缶","canned"), ("キムチ|漬物|漬け|ジャム|味噌|みそ|佃煮","jar"), ("マヨ|ケチャップ|ソース|ドレッシング|醤油|しょうゆ|ポン酢|たれ|タレ","sauce"), ("冷凍","frozen")
    ]
    static func asset(for name: String) -> String {
        let value = FoodRules.canonical(name)
        if let key = produce[value] { return "food-"+key }
        for (pattern,key) in rules where value.range(of:pattern,options:[.regularExpression,.caseInsensitive]) != nil { return "food-"+key }
        return "food-plate"
    }
}

struct FoodIconView: View {
    let name: String
    var size: CGFloat = 44
    var body: some View {
        Image(FoodIcon.asset(for:name)).resizable().interpolation(.high).scaledToFit()
            .frame(width:size,height:size)
            .shadow(color:.black.opacity(0.14),radius:size*0.05,y:size*0.05)
            .accessibilityHidden(true)
    }
}

enum Urgency { case none, fine, soon, expired }

extension FoodRules {
    static func after(days: Int) -> String {
        let f = dateFormatter(); return f.string(from:f.date(from:today)!.addingTimeInterval(Double(days)*86400))
    }
    static func guessKind(_ name: String) -> String {
        let value = canonical(name); return shelf[value] != nil ? "produce":value == "卵" ? "eggs":"packaged"
    }
}

extension Food {
    var daysLeft: Int? { FoodRules.days(expiryDate) }
    var urgency: Urgency { guard let d = daysLeft else { return .none }; return d < 0 ? .expired:d <= 3 ? .soon:.fine }
    var daysText: String {
        guard let d = daysLeft else { return "期限なし" }
        return d < 0 ? "\(-d)日過ぎ":d == 0 ? "今日まで":d == 1 ? "明日まで":"あと\(d)日"
    }
    var amountText: String { "\(quantity.formatted())\(unit)" }
    var placeText: String { FoodRules.locations[location] ?? "" }
}

struct ExpiryChip: View {
    let food: Food
    var body: some View {
        let prefix = ["best_before":"賞味","use_by":"消費","estimate":"目安"][food.expiryType].map { $0+" " } ?? ""
        let date = food.expiryDate.map { " · "+$0.dropFirst(5).replacingOccurrences(of:"-",with:"/") } ?? ""
        Text(prefix+food.daysText+date).font(.caption.weight(.medium)).lineLimit(1)
            .padding(.horizontal,8).padding(.vertical,4)
            .foregroundStyle(food.urgency == .expired ? Theme.red:food.urgency == .soon ? Theme.orange:food.urgency == .none ? Color.secondary:Theme.green)
            .background(food.urgency == .expired ? Theme.redSoft:food.urgency == .soon ? Theme.amber:food.urgency == .none ? Color(white:0.94):Theme.greenSoft,in:Capsule())
    }
}
