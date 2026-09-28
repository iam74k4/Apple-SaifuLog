import Foundation

/// 端末内 AI が書いた答えの一言を、ツールの結果（`LedgerAnswerFacts`）と突き合わせる。
///
/// 一言に、ツールの結果に書いていない数字が 1 つでもあれば使わない（画面には定型文を出す）。端末内のモデルは小さく、
/// 言い回しの中で数字を書き換えたり作ったりすることがあるため（docs/design.md §3-4・§14 の「数字の作り話」）。
/// 回答カードの大きな数字はツールが計算した値をそのまま出すので、ここで捨てても答えは変わらない。
///
/// 数字の読み方:
/// - 半角・全角の数字、桁区切り、「1万2300」「2.5万」のような位は、記録の読み取りと同じ読み方（`EntryScan.numbers`）で数に直す。
/// - 数字は、前後の語で種類に分け、ツールの結果の同じ種類の数字とだけ比べる（値が同じでも、種類が違えば別の数字）。
///   - 「¥」を前に付けたか「円」を後ろに付けた数字は金額（「¥5」と書いて 5 件と一致させない）。
///   - 「件」「回」「度」が続く数字は件数、「日」が続く数字は日数（「残り3日」「1日あたり」）、「%」が続く数字は割合。
///   - 日付の数字は日付の形のときだけ比べる（「2026年」の年、「9月」の月、「9月30日」「9/30」の日）。結果の文の期間の
///     日付（「2026年9月1日から…」）の数字を、「30件」「9件」のような件数や、種類の無い数字と一致させないため。
///   - 種類の無い数字は、結果の金額・件数・日数・割合のどれかと比べる（日付の数字とは比べない）。
///   - 結果の文に無い数え方（「人」「割」「週」「か月」「時」など）の数字は、確かめられないので使わない。
/// - 漢数字は、位（十・百・千・万・億）を含む 2 文字以上か、後ろに円・件・回・日などの数える語が続くときだけ数とみなす
///   （「一番」「一言」「十分」は数ではない）。
/// - 数に直せない数字（桁が多すぎる、小数の割合、半角以外の数字の記号）があれば、確かめられないので使わない。
///
/// 符号と向き: 数字が合っていても、収支の向きを逆に書いた一言（黒字なのに「赤字」「マイナス」「-¥3,000」「支出が収入より
/// 多い」）は使わない。一言に書いた向きが、結果の文の向き（収支の「+」「-」と「収入が支出より多い」などの注記）に無ければ捨てる。
/// 収支ではない答え（支出の合計・予算など）の結果の文には向きが無いので、向きを書いた一言はいつも捨てる。
public enum AnswerSentenceCheck {
    /// 一言として受け入れる長さの上限（文字数）。長い文は一言ではなく、確かめる数字も増えるので使わない。
    public static let maximumLength = 160

    /// 一言を使ってよいか。空・長すぎる・ツールの結果に無い数字や向きを含むなら false。
    public static func accepts(_ sentence: String, facts: String) -> Bool {
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maximumLength else { return false }
        let found = numbers(in: trimmed)
        guard found.isReadable else { return false }
        guard found.isAllowed(by: numbers(in: facts)) else { return false }
        return directions(in: trimmed).isSubset(of: directions(in: facts))
    }

    /// 数字の種類。
    enum Kind: Hashable {
        /// 金額（「¥」か「円」付き）。
        case yen
        /// 件数（「件」「回」「度」付き）。
        case count
        /// 日数（「日」付きで、日付の日ではないもの）。
        case days
        /// 割合（「%」付き）。
        case percent
        /// 日付の年（「2026年」）。
        case year
        /// 日付の月（「9月」「9/30」の 9）。
        case month
        /// 日付の日（「9月30日」「9/30」の 30）。
        case dayOfMonth
        /// 種類の無い数字。
        case plain
        /// 結果の文に無い数え方（「3人」「8割」「2週」「3か月」「12時」など）。
        case other
    }

    /// 文の中の数字。
    struct Numbers: Equatable {
        /// 種類ごとの数字。
        var values: [Kind: Set<Int>] = [:]
        /// すべての数字を数に直せたか。
        var isReadable = true

        subscript(kind: Kind) -> Set<Int> {
            values[kind] ?? []
        }

        mutating func insert(_ value: Int, as kind: Kind) {
            values[kind, default: []].insert(value)
        }

        /// どの数字も、ツールの結果（`allowed`）の同じ種類の数字にあるか。種類の無い数字は、結果の金額・件数・日数・割合・
        /// 種類の無い数字のどれかにあればよい（日付の数字とは比べない）。
        func isAllowed(by allowed: Numbers) -> Bool {
            let loose = allowed[.yen].union(allowed[.count]).union(allowed[.days]).union(allowed[.percent]).union(allowed[.plain])
            return values.allSatisfy { kind, found in
                found.isSubset(of: kind == .plain ? loose : allowed[kind])
            }
        }
    }

    static func numbers(in text: String) -> Numbers {
        let chars = Array(TextNormalizer.normalize(text))
        var result = Numbers()
        var covered = Array(repeating: false, count: chars.count)

        for token in EntryScan.numbers(in: chars, skipping: covered) {
            for index in token.range { covered[index] = true }
            // 位の無い小数（「44.5%」）は、ツールの結果には無い書き方なので確かめられない。
            if token.hasFraction, !token.hasUnit {
                result.isReadable = false
                continue
            }
            result.insert(token.value, as: kind(of: token.range, in: chars))
        }
        // 数に直せなかった半角の数字（桁が多すぎるなど）と、半角以外の数字の記号（「①」など）。
        for (index, char) in chars.enumerated() where !covered[index] {
            if char.isASCIIDigit || (char.isWholeNumber && !kanjiDigits.keys.contains(char) && !kanjiUnits.keys.contains(char)) {
                result.isReadable = false
            }
        }
        for kanji in kanjiNumbers(in: chars, skipping: covered) {
            result.insert(kanji.value, as: kind(of: kanji.range, in: chars))
        }
        return result
    }

    /// 数字の種類を、前後の語から決める。
    private static func kind(of range: Range<Int>, in chars: [Character]) -> Kind {
        var before = range.lowerBound - 1
        while before >= 0, chars[before] == " " { before -= 1 }
        // 「¥」の後ろの符号（「¥-3,000」）は飛ばして見る。
        var yenMark = before
        while yenMark >= 0, ["-", "+", " "].contains(chars[yenMark]) { yenMark -= 1 }
        if yenMark >= 0, chars[yenMark] == "¥" { return .yen }

        var after = range.upperBound
        while after < chars.count, chars[after] == " " { after += 1 }
        let next: Character? = after < chars.count ? chars[after] : nil
        let nextNext: Character? = after + 1 < chars.count ? chars[after + 1] : nil
        // 日付の「9/30」の 30（前が「数字/」）。
        let followsMonthSlash = before >= 1 && chars[before] == "/" && chars[before - 1].isASCIIDigit

        switch next {
        case "円": return .yen
        case "件", "回", "度": return .count
        case "%": return .percent
        case "年": return .year
        case "月": return .month
        case "日":
            // 「9月30日」「9/30日」の 30 は日付の日、それ以外（「残り3日」「1日あたり」「7日間」）は日数。
            let followsMonth = before >= 0 && chars[before] == "月"
            return followsMonth || followsMonthSlash ? .dayOfMonth : .days
        default:
            break
        }
        if next == "/", nextNext?.isASCIIDigit == true { return .month }
        if let next, ["か", "ヶ", "カ", "ケ"].contains(next), nextNext == "月" { return .other }
        if followsMonthSlash { return .dayOfMonth }
        if let next, otherCounters.contains(next) { return .other }
        return .plain
    }

    // MARK: - 向き

    /// 収支の向き。
    enum Direction: Hashable {
        /// 収入が支出より多い（黒字）。
        case surplus
        /// 支出が収入より多い（赤字）。
        case deficit
        /// 収入と支出が同じ。
        case even
        /// 向きを書いたが、どちらか読めない（「支出が収入より」の後ろに多い・少ないが無い）。結果の文にはこの向きが無いので捨てる。
        case unknown
    }

    /// 文に書いた収支の向き（「黒字」「赤字」「プラス」「マイナス」、金額の前の「+」「-」、「収入が支出より多い」などの比べ）。
    static func directions(in text: String) -> Set<Direction> {
        let chars = Array(TextNormalizer.normalize(text))
        let joined = String(chars)
        var result: Set<Direction> = []
        if ["黒字", "プラス"].contains(where: { joined.contains($0) }) { result.insert(.surplus) }
        if ["赤字", "マイナス"].contains(where: { joined.contains($0) }) { result.insert(.deficit) }
        if ["収入と支出が同じ", "支出と収入が同じ"].contains(where: { joined.contains($0) }) { result.insert(.even) }

        // 金額の前の符号（「+¥3,000」「-3,000円」「¥-3,000」）。前が数字の「-」（「9-30」）は範囲やつなぎなので見ない。
        for (index, char) in chars.enumerated() where char == "+" || char == "-" {
            var previous = index - 1
            while previous >= 0, chars[previous] == " " { previous -= 1 }
            if previous >= 0, chars[previous].isASCIIDigit { continue }
            var next = index + 1
            while next < chars.count, chars[next] == " " { next += 1 }
            guard next < chars.count, chars[next] == "¥" || chars[next].isASCIIDigit else { continue }
            result.insert(char == "+" ? .surplus : .deficit)
        }

        // 「支出が収入より多い」「収入の方が少ない」のような比べ。主語の後ろ、文の終わりまでの「多」「上回」「少な」「下回」で決める。
        let comparisons: [(subject: [String], incomeIsSubject: Bool)] = [
            (["収入が支出より", "収入は支出より", "収入の方が", "収入のほうが"], true),
            (["支出が収入より", "支出は収入より", "支出の方が", "支出のほうが"], false),
        ]
        for comparison in comparisons {
            for range in QuestionParser.ranges(of: comparison.subject, in: chars) {
                var end = range.upperBound
                while end < chars.count, !["。", "\n", "!", "?"].contains(chars[end]) { end += 1 }
                let tail = String(chars[range.upperBound..<end])
                let more = ["多", "上回"].compactMap { tail.range(of: $0)?.lowerBound }.min()
                let less = ["少な", "下回"].compactMap { tail.range(of: $0)?.lowerBound }.min()
                let subjectIsLarger: Bool
                switch (more, less) {
                case let (more?, less?): subjectIsLarger = more < less
                case (.some, nil): subjectIsLarger = true
                case (nil, .some): subjectIsLarger = false
                case (nil, nil):
                    result.insert(.unknown)
                    continue
                }
                result.insert(subjectIsLarger == comparison.incomeIsSubject ? .surplus : .deficit)
            }
        }
        return result
    }

    // MARK: - 漢数字

    private static let kanjiDigits: [Character: Int] = [
        "〇": 0, "一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9,
    ]
    private static let kanjiUnits: [Character: Int] = ["十": 10, "百": 100, "千": 1_000, "万": 10_000, "億": 100_000_000]
    /// 結果の文に無い数え方の語。続く数字は確かめられないので、種類を `other` にする（結果の文の数字と一致させない）。
    private static let otherCounters: Set<Character> = ["人", "割", "個", "週", "時", "分", "秒", "歳", "枚", "杯", "品", "位"]
    /// 漢数字の後ろに続くと、数として書いたとみなす語の頭。「分」「位」などは入れない（「十分」「一位」を数として読まない）。
    private static let counters: Set<Character> = ["円", "件", "回", "度", "日", "月", "年", "%", "人", "割", "個", "週"]

    /// 数として書いた漢数字（上の決め事）と、その位置。`skipping` が真の文字（半角の数字と一緒に読んだ位。「25万」の「万」）は見ない。
    private static func kanjiNumbers(in chars: [Character], skipping skipped: [Bool]) -> [(value: Int, range: Range<Int>)] {
        func isKanjiNumeral(_ index: Int) -> Bool {
            !skipped[index] && (kanjiDigits[chars[index]] != nil || kanjiUnits[chars[index]] != nil)
        }
        var result: [(value: Int, range: Range<Int>)] = []
        var i = 0
        while i < chars.count {
            guard isKanjiNumeral(i) else {
                i += 1
                continue
            }
            let start = i
            while i < chars.count, isKanjiNumeral(i) { i += 1 }
            let run = Array(chars[start..<i])
            let next: Character? = i < chars.count ? chars[i] : nil
            let hasUnit = run.contains { kanjiUnits[$0] != nil }
            let followedByCounter = next.map { counters.contains($0) } ?? false
                || (i + 1 < chars.count && ["か", "ヶ", "カ", "ケ"].contains(chars[i]) && chars[i + 1] == "月")
            guard (run.count >= 2 && hasUnit) || followedByCounter, let value = kanjiValue(run) else { continue }
            result.append((value, start..<i))
        }
        return result
    }

    /// 「三千二百」「一万二千」「二十五」を数に直す。
    private static func kanjiValue(_ run: [Character]) -> Int? {
        var total = 0      // 万・億で繰り上げた分
        var group = 0      // いまの万のまとまり
        var digit: Int?    // まだ位を付けていない数字
        for char in run {
            if let value = kanjiDigits[char] {
                // 位を挟まずに数字が続くもの（「二〇二六」）は、桁を並べた書き方として読む。
                digit = (digit ?? 0) * 10 + value
            } else if let unit = kanjiUnits[char] {
                if unit >= 10_000 {
                    // 前に数の無い「万」（「万円」）は 1 万と読む。
                    total += (group + (digit ?? (group == 0 ? 1 : 0))) * unit
                    group = 0
                } else {
                    group += (digit ?? 1) * unit
                }
                digit = nil
            }
        }
        let value = total + group + (digit ?? 0)
        return value >= 0 ? value : nil
    }
}
