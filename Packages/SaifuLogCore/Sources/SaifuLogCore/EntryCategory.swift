import Foundation

/// 支出のカテゴリ（v1 は 8 種で固定）。
///
/// rawValue は保存に使うので、表示名を変えても rawValue は変えないこと。
/// 変えると保存済みの記録がすべて「その他」に落ちる。
///
/// 型名を `Category` にしないのは、Objective-C ランタイムの `Category` とぶつかり、
/// Foundation や SwiftUI を import したアプリ側で「ambiguous for type lookup」になるため。
public enum EntryCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case food
    case daily
    case transport
    case cafe
    case entertainment
    case utilities
    case medical
    case other

    public var id: String { rawValue }

    /// 日本語の表示名。AI への指示とルールベース解析でもこの名前を使う。
    public var displayName: String {
        switch self {
        case .food: "食費"
        case .daily: "日用品"
        case .transport: "交通"
        case .cafe: "カフェ"
        case .entertainment: "娯楽"
        case .utilities: "光熱・通信"
        case .medical: "医療"
        case .other: "その他"
        }
    }

    /// SF Symbols の名前。
    public var symbolName: String {
        switch self {
        case .food: "fork.knife"
        case .daily: "basket"
        case .transport: "tram"
        case .cafe: "cup.and.saucer"
        case .entertainment: "ticket"
        case .utilities: "bolt"
        case .medical: "cross.case"
        case .other: "tag"
        }
    }

    /// ルールベース解析で使うキーワード。ひらがなはカタカナに寄せて照合するので、どちらで書いてもよい。
    ///
    /// 1 文字の語は他の語の一部に当たりやすい（「本」は「日本」「2本」にも当たる）ため、
    /// 誤爆しにくいものだけにしている。
    public var keywords: [String] {
        switch self {
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

    /// 表示名から引く（AI の出力をカテゴリに戻すときに使う）。
    public init?(displayName: String) {
        guard let match = Self.allCases.first(where: { $0.displayName == displayName }) else { return nil }
        self = match
    }

    /// 文に含まれるキーワードからカテゴリを推定する。当たらなければ `.other`。
    ///
    /// 複数当たったときは長い語を優先し（「ドラッグストア」は「薬」より強い手がかり）、
    /// 同じ長さなら先に出てきた語を採る。
    public static func guess(from text: String) -> EntryCategory {
        let haystack = KeywordMatcher.fold(text)
        var best: (category: EntryCategory, length: Int, position: Int)?
        for category in allCases {
            for keyword in category.keywords {
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
        return best?.category ?? .other
    }
}
