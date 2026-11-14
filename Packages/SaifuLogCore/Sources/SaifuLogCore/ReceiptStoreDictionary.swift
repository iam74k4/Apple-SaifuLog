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

    /// ひとこと入力の品目（利用者が打った文）に当たるチェーンの名前のカテゴリ。当たらなければ nil。
    ///
    /// レシートの店名の行と違い、打った品目は店の名前とは限らない。店の種類の語（「スーパー」「カフェ」「弁当」）と、ほかの意味にも
    /// なる名前（「ライフ」「サミット」「コスモス」）は当てない（「ライフカード 年会費」「サミットの参加費」を食費にしないため）。
    /// 英字の名前は、前後が英字でないところだけ当てる（`KeywordMatcher.firstRange`。"dcm" を別の英語の語の中に当てない）。
    /// 仮名の名前も、語の途中には当てない（`matchesKanaName`。「ライオンキング」の「イオン」、「ジョナサンへのプレゼント」の
    /// 「ジョナサン」を、店の名前として食費にしないため）。
    static func chainCategory(forTypedItem item: String) -> EntryCategory? {
        let chars = Array(item)
        let foldedChars = chars.map { KeywordMatcher.fold(String($0)) }
        let haystack = foldedChars.joined()
        var best: (category: EntryCategory, length: Int)?
        for entry in entries {
            for word in entry.words where !typedItemExclusions.contains(word) {
                let needle = KeywordMatcher.fold(word)
                guard needle.count > (best?.length ?? 0) else { continue }
                let found = isKana(needle.first) && isKana(needle.last)
                    ? matchesKanaName(needle, in: chars, folded: foldedChars, haystack: haystack)
                    : KeywordMatcher.firstRange(of: needle, in: haystack) != nil
                guard found else { continue }
                best = (entry.category, needle.count)
            }
        }
        return best?.category
    }

    /// 打った品目の中に、仮名のチェーンの名前（そろえた形の `needle`）が 1 つの語として書かれているか。
    ///
    /// - 前がカタカナなら語の途中（「ライオン」の「イオン」）。ひらがな（助詞）・漢字・数字・空白・記号の後ろか、文の頭なら語の頭。
    /// - 後ろが仮名なら語の途中（「イオンモール」「ジョナサンへ」）。ただし場所を示す「で」（「ジョナサンで夕食」「マツキヨで買い物」）は
    ///   語の終わりとみなす。人の名前と同じチェーンの名前（ジョナサン）は「へ」「と」「に」が続くと人を指すことが多く、見分けられない
    ///   ので当てない（当てなければ、返事でカテゴリを聞き返すだけで済む）。
    ///
    /// そろえた形（`KeywordMatcher.fold`）はひらがなをカタカナにするので、ひらがなの助詞とカタカナの名前の境目を見るため、前後の文字は
    /// そろえる前の文字で見る。そろえて 1 文字にならない文字がある文は、これまでどおり文字の並びで当てる。
    private static func matchesKanaName(
        _ needle: String, in chars: [Character], folded: [String], haystack: String
    ) -> Bool {
        guard folded.allSatisfy({ $0.count == 1 }) else { return haystack.contains(needle) }
        let flat = folded.compactMap(\.first)
        let word = Array(needle)
        guard flat.count >= word.count else { return false }
        for start in 0...(flat.count - word.count) where Array(flat[start..<(start + word.count)]) == word {
            let end = start + word.count
            let startsWord = start == 0 || !isKatakana(chars[start - 1])
            let endsWord = end == chars.count || !isKana(chars[end]) || chars[end] == "で"
            if startsWord && endsWord { return true }
        }
        return false
    }

    /// ひらがなかカタカナ（長音の記号を含む）か。
    private static func isKana(_ character: Character?) -> Bool {
        guard let scalar = character?.unicodeScalars.first else { return false }
        return (0x3041...0x309F).contains(scalar.value) || isKatakana(character)
    }

    /// カタカナ（長音の記号を含む）か。
    private static func isKatakana(_ character: Character?) -> Bool {
        guard let scalar = character?.unicodeScalars.first else { return false }
        return (0x30A1...0x30FA).contains(scalar.value) || (0x30FC...0x30FF).contains(scalar.value)
    }

    /// 打った品目には当てない語（店の種類の語と、ほかの意味にもなるチェーンの名前）。
    static let typedItemExclusions: Set<String> = [
        "スーパー", "マーケット", "食品館", "生協", "コープ", "COOP", "CO-OP", "八百屋", "青果", "精肉", "鮮魚",
        "ベーカリー", "パン屋", "惣菜", "弁当", "コンビニ", "ドラッグストア", "ドラッグ", "ホームセンター",
        "カフェ", "CAFE", "Cafe", "珈琲", "コーヒー",
        "ライフ", "サミット", "オーケー", "コスモス", "クリエイト", "ポプラ", "フレスコ", "ベルク", "万代", "ココス",
    ]

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
