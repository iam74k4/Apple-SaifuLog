import Foundation

/// 支出のカテゴリ。組み込みの 8 種と、利用者が作ったカテゴリ（`custom`。docs/design.md §8）。
///
/// rawValue は保存に使うので、表示名を変えても rawValue は変えないこと。
/// 変えると保存済みの記録がすべて「その他」に落ちる。作ったカテゴリの rawValue は「custom:」と ID（`CategoryCatalog` の
/// `CustomCategoryInfo.id`。UUID の小文字の文字列）で、名前は持たない（名前を変えても記録を書き換えずに済むように）。
///
/// 作ったカテゴリの名前・記号・色は、カテゴリの一覧（`CategoryCatalog`）から引く。この型だけで決まる表示名・記号・
/// キーワードは組み込みのものだけで、作ったカテゴリには「その他」と同じものを返す（一覧を渡し忘れても落ちないように）。
/// AI の選択肢とキーワード辞書は組み込みの 8 種だけ（`builtIns`）。
///
/// 型名を `Category` にしないのは、Objective-C ランタイムの `Category` とぶつかり、
/// Foundation や SwiftUI を import したアプリ側で「ambiguous for type lookup」になるため。
public enum EntryCategory: Hashable, Sendable, Identifiable {
    case food
    case daily
    case transport
    case cafe
    case entertainment
    case utilities
    case medical
    case other
    /// 利用者が作ったカテゴリ。値は ID（`CustomCategoryInfo.id`）。
    case custom(String)

    /// 組み込みのカテゴリ（定義の順。「その他」が最後）。AI の選択肢・キーワード辞書・並びの基準に使う。
    public static let builtIns: [EntryCategory] = [
        .food, .daily, .transport, .cafe, .entertainment, .utilities, .medical, .other,
    ]

    /// 作ったカテゴリの rawValue の頭。
    public static let customPrefix = "custom:"

    public var id: String { rawValue }

    /// 利用者が作ったカテゴリか。
    public var isCustom: Bool {
        customID != nil
    }

    /// 作ったカテゴリの ID。組み込みのカテゴリは nil。
    public var customID: String? {
        if case .custom(let id) = self { return id }
        return nil
    }

    /// 並びの基準（組み込みは定義の順、作ったカテゴリは「その他」の前に ID の順）。同じ額の行の順を、開くたびに変えないために使う
    /// （`CategoryBreakdown`）。画面の並びは、利用者が決めた順（`CategoryCatalog.all`）にする。
    public static func areInStandardOrder(_ lhs: EntryCategory, _ rhs: EntryCategory) -> Bool {
        let left = lhs.standardRank
        let right = rhs.standardRank
        if left.rank != right.rank { return left.rank < right.rank }
        return left.id < right.id
    }

    private var standardRank: (rank: Int, id: String) {
        switch self {
        case .custom(let id): (EntryCategory.builtIns.count - 1, id)
        case .other: (EntryCategory.builtIns.count, "")
        default: (EntryCategory.builtIns.firstIndex(of: self) ?? 0, "")
        }
    }

    /// 日本語の表示名。AI への指示とルールベース解析でもこの名前を使う。作ったカテゴリは「その他」（名前は `CategoryCatalog` から引く）。
    public var displayName: String {
        switch self {
        case .food: "食費"
        case .daily: "日用品"
        case .transport: "交通"
        case .cafe: "カフェ"
        case .entertainment: "娯楽"
        case .utilities: "光熱・通信"
        case .medical: "医療"
        case .other, .custom: "その他"
        }
    }

    /// SF Symbols の名前。作ったカテゴリは「その他」と同じ（記号は `CategoryCatalog` から引く）。
    public var symbolName: String {
        switch self {
        case .food: "fork.knife"
        case .daily: "basket"
        case .transport: "tram"
        case .cafe: "cup.and.saucer"
        case .entertainment: "ticket"
        case .utilities: "bolt"
        case .medical: "cross.case"
        case .other, .custom: "tag"
        }
    }

    /// ルールベース解析で使うキーワード。ひらがなはカタカナに寄せて照合するので、どちらで書いてもよい。
    /// 作ったカテゴリには無い（作ったカテゴリには、文の中の名前と修正の記憶で当てる。`CategoryMemory`）。
    ///
    /// 1 文字の語は他の語の一部に当たりやすい（「本」は「日本」「2本」にも当たる）ため、
    /// 誤爆しにくいものだけにしている。
    public var keywords: [String] {
        switch self {
        case .custom:
            []
        case .food:
            [
                "食費", "ランチ", "昼食", "昼ごはん", "昼飯", "朝食", "朝ごはん", "夕食", "夕飯", "晩ごはん",
                "夜ごはん", "ごはん", "ご飯", "弁当", "定食", "外食", "スーパー", "コンビニ", "食材", "食料品",
                "惣菜", "焼肉", "寿司", "ラーメン", "うどん", "そば", "カレー", "牛丼", "ピザ", "パン",
                "おにぎり", "居酒屋", "飲み会", "マック", "マクドナルド", "ガスト", "出前", "デリバリー", "お菓子",
                "野菜", "肉", "魚", "卵", "米", "牛乳",
            ]
        case .daily:
            [
                "日用品", "ドラッグストア", "ドラッグ", "洗剤", "ティッシュ", "トイレットペーパー", "シャンプー",
                "歯ブラシ", "歯磨き", "ゴミ袋", "電池", "消耗品", "雑貨", "文房具", "化粧品", "100均", "百均",
                "ダイソー", "無印", "バスタオル",
            ]
        case .transport:
            [
                "交通", "電車", "地下鉄", "バス", "タクシー", "新幹線", "飛行機", "運賃", "切符", "定期",
                "suica", "pasmo", "icoca", "ガソリン", "駐車場", "駐車", "高速", "レンタカー",
            ]
        case .cafe:
            [
                "カフェ", "コーヒー", "珈琲", "喫茶", "ラテ", "紅茶", "スタバ", "スターバックス", "ドトール",
                "タリーズ", "コメダ", "フラペチーノ", "ケーキ",
            ]
        case .entertainment:
            [
                "娯楽", "映画", "ゲーム", "カラオケ", "ライブ", "コンサート", "チケット", "漫画", "マンガ",
                "書籍", "本屋", "雑誌", "旅行", "美術館", "博物館", "遊園地", "ボウリング", "趣味",
            ]
        case .utilities:
            [
                "光熱", "電気", "ガス", "水道", "通信", "携帯", "スマホ", "電話", "インターネット",
                "ネット代", "光回線", "wifi", "wi-fi", "プロバイダ",
            ]
        case .medical:
            [
                "医療", "病院", "クリニック", "診察", "通院", "歯医者", "歯科", "眼科", "皮膚科", "内科",
                "薬局", "処方", "目薬", "薬",
            ]
        case .other:
            // ほかのカテゴリの短い語に誤って当たる語（「パンツ」の「パン」、「ガスト」の「ガス」など）を
            // 長い語で受け止めるために置く。ここに当たったときは「その他」になる。
            ["洋服", "パンツ", "美容院", "美容室", "散髪", "プレゼント", "ご祝儀"]
        }
    }

    /// 組み込みのカテゴリの表示名から引く（AI の出力をカテゴリに戻すときに使う）。
    public init?(displayName: String) {
        guard let match = Self.builtIns.first(where: { $0.displayName == displayName }) else { return nil }
        self = match
    }

    /// 文に含まれるキーワードからカテゴリを推定する。当たらなければ `.other`。
    ///
    /// 複数当たったときは長い語を優先し（「ドラッグストア」は「薬」より強い手がかり）、
    /// 同じ長さなら先に出てきた語を採る。
    public static func guess(from text: String) -> EntryCategory {
        bestMatch(in: text, includingDisplayNames: false) ?? .other
    }

    /// 文に含まれるキーワードか表示名から、カテゴリを探す。どれにも当たらなければ nil。
    ///
    /// `guess(from:)` と同じ選び方（長い語を優先し、同じ長さなら先に出てきた語）。当たらなかったことと
    /// 「その他」に当たったことを見分けたいとき（家計への質問で、カテゴリを聞かれたかどうか）に使う。
    /// 表示名も見るのは、「その他」のようにキーワードに入れていない表示名で聞かれることがあるため（記録の読み取りの
    /// `guess(from:)` は表示名を見ない。見ると「その他 肉 500」のような記録のカテゴリが変わるため）。
    public static func matched(in text: String) -> EntryCategory? {
        bestMatch(in: text, includingDisplayNames: true)
    }

    private static func bestMatch(in text: String, includingDisplayNames: Bool) -> EntryCategory? {
        let haystack = KeywordMatcher.fold(text)
        var best: (category: EntryCategory, length: Int, position: Int)?
        for category in builtIns {
            for keyword in category.keywords + (includingDisplayNames ? [category.displayName] : []) {
                let needle = KeywordMatcher.fold(keyword)
                guard let range = haystack.range(of: needle) else { continue }
                let length = needle.count
                let position = haystack.distance(from: haystack.startIndex, to: range.lowerBound)
                if let current = best,
                   current.length > length || (current.length == length && current.position <= position) {
                    continue
                }
                best = (category, length, position)
            }
        }
        return best?.category
    }
}

extension EntryCategory: RawRepresentable {
    /// 保存した値から戻す。知らない値（空の ID の作ったカテゴリを含む）は nil。
    public init?(rawValue: String) {
        switch rawValue {
        case "food": self = .food
        case "daily": self = .daily
        case "transport": self = .transport
        case "cafe": self = .cafe
        case "entertainment": self = .entertainment
        case "utilities": self = .utilities
        case "medical": self = .medical
        case "other": self = .other
        default:
            guard rawValue.hasPrefix(Self.customPrefix) else { return nil }
            let id = String(rawValue.dropFirst(Self.customPrefix.count))
            guard !id.isEmpty else { return nil }
            self = .custom(id)
        }
    }

    public var rawValue: String {
        switch self {
        case .food: "food"
        case .daily: "daily"
        case .transport: "transport"
        case .cafe: "cafe"
        case .entertainment: "entertainment"
        case .utilities: "utilities"
        case .medical: "medical"
        case .other: "other"
        case .custom(let id): Self.customPrefix + id
        }
    }
}

extension EntryCategory: Codable {
    /// rawValue の文字列で書く（組み込みのカテゴリは、列挙型の rawValue で書いていたときと同じ形）。
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let category = EntryCategory(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "知らないカテゴリ: \(rawValue)")
        }
        self = category
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
