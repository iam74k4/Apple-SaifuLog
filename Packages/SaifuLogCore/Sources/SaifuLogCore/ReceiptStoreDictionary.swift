import Foundation

/// 店名から、レシート全体の既定のカテゴリを推定する辞書。
///
/// 品名がキーワード辞書（`EntryCategory.keywords`）に当たらない品目（「ブレンドS」「PB ポテト」）は、店の種類で分ける。
/// スーパー・コンビニは食費、ドラッグストア・100円ショップ・ホームセンターは日用品、カフェはカフェ。
/// 名前はレシートの上の方に印字される表記（カタカナ・英字）で持ち、ひらがな・カタカナと英字の大小は問わずに照合する。
enum ReceiptStoreDictionary {
    /// 店の種類を表す語と、チェーンの名前。長い語を先に見る（`category(forStoreName:)`）。
    static let entries: [(words: [String], category: EntryCategory)] = [
        (
            [
                "スーパー", "マーケット", "食品館", "イオン", "AEON", "イトーヨーカドー", "ヨーカドー", "西友", "SEIYU",
                "ライフ", "マルエツ", "サミット", "オーケー", "業務スーパー", "いなげや", "ヤオコー", "成城石井",
                "まいばすけっと", "ベルク", "ロピア", "東急ストア", "京王ストア", "阪急オアシス", "万代", "平和堂",
                "マックスバリュ", "フレスコ", "生協", "コープ", "COOP", "CO-OP", "八百屋", "青果", "精肉", "鮮魚",
                "ベーカリー", "パン屋", "惣菜", "弁当",
            ],
            .food
        ),
        (
            [
                "コンビニ", "セブン-イレブン", "セブンイレブン", "7-ELEVEN", "7-Eleven", "ローソン", "LAWSON",
                "ファミリーマート", "FamilyMart", "ミニストップ", "MINISTOP", "デイリーヤマザキ", "セイコーマート",
                "NewDays", "ポプラ",
            ],
            .food
        ),
        (
            [
                "マクドナルド", "モスバーガー", "ケンタッキー", "吉野家", "すき家", "松屋", "ガスト", "サイゼリヤ",
                "ココス", "デニーズ", "ジョナサン", "バーミヤン", "丸亀製麺", "日高屋", "くら寿司", "スシロー",
            ],
            .food
        ),
        (
            [
                "ドラッグストア", "ドラッグ", "マツモトキヨシ", "マツキヨ", "ウエルシア", "ツルハ", "スギ薬局",
                "サンドラッグ", "ココカラファイン", "コスモス", "クリエイト", "キリン堂", "カワチ",
                "ダイソー", "DAISO", "セリア", "キャンドゥ", "無印良品", "ニトリ", "カインズ", "コーナン", "DCM",
                "ホームセンター",
            ],
            .daily
        ),
        (
            [
                "カフェ", "CAFE", "Cafe", "珈琲", "コーヒー", "スターバックス", "STARBUCKS", "ドトール", "DOUTOR",
                "タリーズ", "TULLY'S", "コメダ", "サンマルク", "エクセルシオール", "ベローチェ", "プロント", "PRONTO",
            ],
            .cafe
        ),
    ]

    /// 店名に当たる語の中でいちばん長いもののカテゴリ。当たらなければ nil。
    static func category(forStoreName name: String) -> EntryCategory? {
        match(in: name)?.category
    }

    /// 行にチェーンの名前か店の種類の語が含まれるか（店名の行を探すのに使う）。
    static func containsStoreWord(_ text: String) -> Bool {
        match(in: text) != nil
    }

    private static func match(in text: String) -> (category: EntryCategory, length: Int)? {
        let haystack = KeywordMatcher.fold(text)
        var best: (category: EntryCategory, length: Int)?
        for entry in entries {
            for word in entry.words {
                let needle = KeywordMatcher.fold(word)
                guard haystack.contains(needle), needle.count > (best?.length ?? 0) else { continue }
                best = (entry.category, needle.count)
            }
        }
        return best
    }
}
