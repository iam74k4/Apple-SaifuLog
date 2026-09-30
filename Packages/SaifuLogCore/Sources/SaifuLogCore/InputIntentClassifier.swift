import Foundation

/// ひとこと入力の文が、記録か質問か。
public enum InputIntent: Hashable, Sendable {
    /// 記録（ひとこと入力として読んで保存する）。
    case record
    /// 家計への質問（保存しない）。
    case question
    /// 金額があるのに質問の語も含み、どちらか決められない。記録にはしない（誤って記録しないため）。
    /// 画面は、書き直しを頼む案内を出して、送った文を入力欄に戻す（docs/design.md §9 の質問の決め事）。
    case unclear
}

/// 入力の文が記録か質問かを決める（純粋な関数）。
///
/// 記録と質問を同じ入力欄に打つので、見分けはコードで決める（AI に任せない。どちらで読んでも同じ見分けにし、テストで
/// 境目を確かめるため）。**誤って記録にならないことを優先する**（質問の文を支出として保存すると、合計が黙って狂うため）。
///
/// 決め事（上から順に見る）:
/// 1. 「?」（全角も）・「いくら」・「どれくらい」・「何円」・「何件」・「何回」・「教えて」・「ですか」などの、はっきり質問を表す語があれば
///    質問（金額があっても。「ランチ850円って高い?」を記録しない）。ただし「いくら丼」は品目なので見ない。
/// 2. 記録として読める金額があり（記録の読み取りと同じ `EntryInput` で 1 件以上）、上の語が無ければ、記録。ただし「残り」「使える」
///    「予算」「収支」「件数」「内訳」、後ろに金額の続かない「合計」も含むなら、決められない（`unclear`）。「スーパー 合計2480」の
///    ように金額を添えた「合計」は、記録の書き方（添えた額。§4-4）なので記録のまま。
/// 3. 金額が無ければ、質問の語（「合計」「使った」「支出」「収入」「予算」「一番」「何」など）があるか、期間の語（「今月」「先月」など）に
///    カテゴリの表示名（「食費」「カフェ」など）が続くか、期間の語だけの文（「先月」）なら質問。それ以外は記録として扱い、これまでどおり
///    「金額が見つかりませんでした」を出す（「ランチ」と金額を書き忘れた文を、質問として答えないため）。
public enum InputIntentClassifier {
    /// - Parameters:
    ///   - now: 日付の言い回し（「9/26」「3日前」を金額と見分ける）の基準の日時。送った瞬間の日時を渡す。
    ///   - calendar: 同じく日付を見分ける暦。
    public static func classify(_ text: String, now: Date, calendar: Calendar) -> InputIntent {
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
            return containsAmbiguousWord(normalized) ? .unclear : .record
        }
        if containsAmbiguousWord(normalized) || containsQuestionWord(normalized) || asksAboutPeriod(normalized) {
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

    /// 金額が無いときに、質問とみなす語。
    static let questionWords = [
        "合計", "総額", "使った", "つかった", "支出", "出費", "収入", "一番", "いちばん", "最も", "もっとも",
        "何", "どれ", "どう", "カテゴリ", "毎日", "日割り",
    ]

    /// カテゴリの表示名（「光熱・通信」は「光熱費」「通信費」とも書くので、分けた語も）。
    static let categoryNames = EntryCategory.allCases.map(\.displayName) + ["光熱", "通信"]

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

    /// 期間の語に、カテゴリの表示名が続くか、期間の語だけの文か（「先月の食費」「今日のカフェ」「先月」「年初からの食費」）。
    ///
    /// カテゴリはキーワードではなく表示名だけを見る。「昨日 ランチ」のような、金額を書き忘れた記録を質問として答えないため。
    static func asksAboutPeriod(_ text: String) -> Bool {
        var chars = Array(text)
        let words = QuestionParser.sinceYearStartPhrases + QuestionParser.periodWords.map(\.0) + ["直近", "過去", "最近"]
        let found = QuestionParser.ranges(of: words, in: chars)
            + QuestionParser.recentDayPhrases(in: chars).map(\.range)
        guard !found.isEmpty else { return false }
        for range in found {
            for index in range { chars[index] = " " }
        }
        let rest = String(chars)
        if categoryNames.contains(where: { rest.contains($0) }) {
            return true
        }
        // 期間の語のほかに、助詞・記号・空白しか無い。
        let leftovers = rest.filter { !$0.isWhitespace && !"はのもをにで、。!.".contains($0) }
        return leftovers.isEmpty
    }
}
