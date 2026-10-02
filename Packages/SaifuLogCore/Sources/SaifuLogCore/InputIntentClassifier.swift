import Foundation

/// ひとこと入力の文が、記録か質問か。
public enum InputIntent: Hashable, Sendable {
    /// 記録（ひとこと入力として読んで保存する）。
    case record
    /// 家計への質問（保存しない）。
    case question
    /// 金額があるのに質問の語や比べる語も含み、どちらか決められない。記録にはしない（誤って記録しないため）。
    /// 画面は、書き直しを頼む案内を出して、送った文を入力欄に戻す（docs/design.md §9 の質問の決め事）。
    case unclear
    /// 前の記録を直そうとする文（「さっきのを900に直して」「850じゃなくて950」）。金額があっても記録にはしない
    /// （記録すると、直したつもりの支出が二重に記録されるため）。画面は、記録を直す方法を案内する。
    case correction
}

/// 入力の文が記録か質問かを決める（純粋な関数）。
///
/// 記録と質問を同じ入力欄に打つので、見分けはコードで決める（AI に任せない。どちらで読んでも同じ見分けにし、テストで
/// 境目を確かめるため）。**誤って記録にならないことを優先する**（質問の文を支出として保存すると、合計が黙って狂うため）。
///
/// 決め事（上から順に見る）:
/// 1. 「?」（全角も）・「いくら」・「どれくらい」・「何円」・「何件」・「何回」・「教えて」・「ですか」などの、はっきり質問を表す語があれば
///    質問（金額があっても。「ランチ850円って高い?」を記録しない）。ただし「いくら丼」は品目なので見ない。
/// 2. 記録として読める金額があり（記録の読み取りと同じ `EntryInput` で 1 件以上）、上の語が無ければ、記録。ただし
///    - 「訂正」「修正」「じゃなく」「ではなく」「間違えた」、または前の記録を指す語（「さっき」「前の」「今の」「直前」）と直す語
///      （「直して」「直す」「変えて」「変更」「にして」）の組を含むなら、前の記録を直そうとする文（`correction`）。「間違えて」
///      （「間違えて買ったパン 300」）と「お直し」（「ズボンのお直し 1500」）は記録にも書くので見ない
///    - 「残り」「使える」「予算」「収支」「件数」「内訳」、後ろに金額の続かない「合計」、比べる語（「超え」「多い」「少ない」「以上」
///      「以下」「増え」「減っ」）も含むなら、決められない（`unclear`）。「スーパー 合計2480」のように金額を添えた「合計」は、
///      記録の書き方（添えた額。§4-4）なので記録のまま。「より」だけでは比べる文にしない（「母より 10000」は記録）
/// 3. 金額が無ければ、質問の語（「合計」「使った」「支出」「収入」「予算」「一番」「何」など）があるか、期間の語（「今月」「先月」など）に
///    カテゴリの表示名（「食費」「カフェ」など）が続くか、期間の語だけの文（「先月」）なら質問。それ以外は記録として扱い、これまでどおり
///    「金額が見つかりませんでした」を出す（「ランチ」と金額を書き忘れた文を、質問として答えないため）。
public enum InputIntentClassifier {
    /// - Parameters:
    ///   - now: 日付の言い回し（「9/26」「3日前」を金額と見分ける）の基準の日時。送った瞬間の日時を渡す。
    ///   - calendar: 同じく日付を見分ける暦。
    ///   - catalog: カテゴリの一覧。期間の語に続く作ったカテゴリの名前（「先月の衣服」）も、質問の手がかりにする。
    public static func classify(
        _ text: String, now: Date, calendar: Calendar, catalog: CategoryCatalog = .builtIn
    ) -> InputIntent {
        let normalized = TextNormalizer.normalize(text)
        if containsStrongQuestionWord(normalized) { return .question }

        // 直近 N 日の日数（「3日間」の 3）や「1日あたり」の 1 を金額として数えないよう、先に取り除いてから金額を探す。
        var chars = Array(normalized)
        for match in QuestionParser.recentDayPhrases(in: chars) {
            for index in match.range { chars[index] = " " }
        }
        for range in QuestionParser.ranges(of: QuestionParser.dailyAllowancePhrases, in: chars) {
            for index in range { chars[index] = " " }
        }
        let hasAmount = !EntryInput(String(chars), now: now, calendar: calendar).segments.isEmpty

        if hasAmount {
            if containsCorrectionWord(normalized) { return .correction }
            return containsAmbiguousWord(normalized) || containsComparisonWord(normalized) ? .unclear : .record
        }
        if containsAmbiguousWord(normalized) || containsQuestionWord(normalized)
            || asksAboutPeriod(normalized, customNames: catalog.customs.map(\.name)) {
            return .question
        }
        return .record
    }

    // MARK: - 語

    /// はっきり質問を表す語。金額があっても質問にする。
    static let strongQuestionWords = [
        "?", "教えて", "おしえて", "いくら", "幾ら", "どれくらい", "どれぐらい", "どのくらい", "どのぐらい", "何円", "なんえん",
        "何件", "なんけん", "何回", "なんかい", "何日", "何に", "なにに", "なんぼ", "ですか", "ますか", "でしょうか", "だっけ",
    ]

    /// 「いくら」でも品目の名前のもの（「いくら丼 1500」を質問にしない）。
    static let strongQuestionWordExceptions = ["いくら丼", "いくらどん", "いくら軍艦", "いくらご飯", "いくらごはん"]

    /// 金額と一緒に書かれると、記録か質問か決められない語。記録の文にはまず書かない語だけにする（「使った」「一番」は
    /// 「コンビニで使った 500」「一番搾り 300」のように記録にも書くので入れない）。
    static let ambiguousWords = ["残り", "のこり", "使える", "つかえる", "予算", "収支", "件数", "内訳"]

    /// 金額と一緒に書かれると、前の記録を直そうとする文とみなす語。記録の文にはまず書かない語だけにする（「間違えて」は
    /// 「間違えて買ったパン 300」のように記録にも書くので入れない）。
    static let correctionWords = ["訂正", "修正", "じゃなく", "ではなく", "間違えた", "まちがえた"]

    /// 直す語を含むが、品目の名前のもの（「修正テープ 200」を、記録を直す文にしない）。
    static let correctionWordExceptions = ["修正テープ", "修正液", "修正ペン", "訂正印", "お直し"]

    /// 前の記録を指す語。直す語（`editWords`）と組のときだけ、記録を直す文とみなす（「今のランチ 900」は記録）。
    static let referenceWords = ["さっき", "先ほど", "前の", "今の", "直前"]

    /// 記録を直す語。「直し」は「直して」「直しといて」も含む（「お直し」は `correctionWordExceptions` で除く）。
    static let editWords = ["直し", "直す", "変えて", "変更", "にして"]

    /// 金額と一緒に書かれると、比べる文（「今月の食費 3万超えた」「先月より5000円多い」）とみなす語。記録か質問か決められない。
    /// 「より」だけは入れない（「母より 10000」のように、もらった相手を書く記録にも使うため）。
    static let comparisonWords = ["超え", "多い", "少ない", "以上", "以下", "増え", "減っ"]

    /// 比べる語を含むが、品目や記録の言い回しのもの（「多い日用 ナプキン 500」「お腹減ったからラーメン 900」）。
    static let comparisonWordExceptions = ["多い日", "少ない日", "増えるワカメ", "増えるわかめ", "腹減", "腹が減"]

    /// 金額が無いときに、質問とみなす語。
    static let questionWords = [
        "合計", "総額", "使った", "つかった", "支出", "出費", "収入", "一番", "いちばん", "最も", "もっとも",
        "何", "どれ", "どう", "カテゴリ", "毎日", "日割り",
    ]

    /// カテゴリの表示名（「光熱・通信」は「光熱費」「通信費」とも書くので、分けた語も）。
    static let categoryNames = EntryCategory.builtIns.map(\.displayName) + ["光熱", "通信"]

    static func containsStrongQuestionWord(_ text: String) -> Bool {
        var haystack = text
        for exception in strongQuestionWordExceptions {
            haystack = haystack.replacingOccurrences(of: exception, with: "\u{0}")
        }
        return strongQuestionWords.contains { haystack.contains($0) }
    }

    static func containsAmbiguousWord(_ text: String) -> Bool {
        if ambiguousWords.contains(where: { text.contains($0) }) { return true }
        // 「合計」は、後ろに金額（空白・「:」・「¥」を挟んでもよい）が続けば、記録に添えた額（「スーパー 合計2480」）。
        let chars = Array(text)
        for range in QuestionParser.ranges(of: ["合計"], in: chars) {
            var next = range.upperBound
            while next < chars.count, [" ", ":", "¥", "="].contains(chars[next]) { next += 1 }
            if next >= chars.count || !chars[next].isASCIIDigit { return true }
        }
        return false
    }

    static func containsQuestionWord(_ text: String) -> Bool {
        questionWords.contains { text.contains($0) }
    }

    /// 前の記録を直そうとする文か（`correctionWords`、または前の記録を指す語と直す語の組）。
    static func containsCorrectionWord(_ text: String) -> Bool {
        let haystack = masking(correctionWordExceptions, in: text)
        if correctionWords.contains(where: { haystack.contains($0) }) { return true }
        return referenceWords.contains { haystack.contains($0) } && editWords.contains { haystack.contains($0) }
    }

    /// 比べる文か（`comparisonWords`）。
    static func containsComparisonWord(_ text: String) -> Bool {
        let haystack = masking(comparisonWordExceptions, in: text)
        return comparisonWords.contains { haystack.contains($0) }
    }

    /// `words` に当たる部分を、使われない文字で埋めた文。前後がつながって新しい語ができないようにするため（空白では埋めない）。
    private static func masking(_ words: [String], in text: String) -> String {
        words.reduce(text) { $0.replacingOccurrences(of: $1, with: "\u{0}") }
    }

    /// 期間の語に、カテゴリの表示名が続くか、期間の語だけの文か（「先月の食費」「今日のカフェ」「先月」「年初からの食費」）。
    ///
    /// カテゴリはキーワードではなく表示名だけを見る。「昨日 ランチ」のような、金額を書き忘れた記録を質問として答えないため。
    static func asksAboutPeriod(_ text: String, customNames: [String] = []) -> Bool {
        var chars = Array(text)
        let words = QuestionParser.sinceYearStartPhrases + QuestionParser.periodWords.map(\.0) + ["直近", "過去", "最近"]
        let found = QuestionParser.ranges(of: words, in: chars)
            + QuestionParser.recentDayPhrases(in: chars).map(\.range)
        guard !found.isEmpty else { return false }
        for range in found {
            for index in range { chars[index] = " " }
        }
        let rest = String(chars)
        let names = categoryNames + customNames.map(TextNormalizer.normalize).filter { !$0.isEmpty }
        if names.contains(where: { rest.contains($0) }) {
            return true
        }
        // 期間の語のほかに、助詞・記号・空白しか無い。
        let leftovers = rest.filter { !$0.isWhitespace && !"はのもをにで、。!.".contains($0) }
        return leftovers.isEmpty
    }
}
