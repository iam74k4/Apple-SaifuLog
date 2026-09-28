import Foundation

/// 正規化済みの一行を文字単位で読み、金額・日付・割り勘の人数を拾い出す。
///
/// ルールベースの解析、AI の出力の検査（`AmountParser`）、日付の表記の解釈（`DateExpression`）が
/// すべてここを通る。数字の読み方を 1 か所にまとめ、どこで読んでも同じ結果になるようにするため。
///
/// 文字の位置は `[Character]` の添字で持つ。メモを作るときに「使った部分」を
/// 位置で取り除く必要があり、String.Index より扱いやすいため。
struct EntryScan {
    struct Amount: Equatable {
        /// 金額（円）。
        var value: Int
        /// 入力中の位置。前の「¥」と後ろの「円」も含む。
        var range: Range<Int>
    }

    struct Segment: Equatable {
        var range: Range<Int>
        /// その区間の金額（区間内の最後の数字）。
        var amount: Amount
    }

    let chars: [Character]
    /// 日付や割り勘の言い回しとして使い終えた文字。メモから除く。
    private(set) var consumed: [Bool]
    /// 金額とみなした数字（入力の順）。
    private(set) var amounts: [Amount] = []
    /// 何日前か。日付の言い回しが無ければ nil。
    private(set) var daysAgo: Int?
    /// 入力にあった日付の言い回しが指す日（何日前か）をすべて。AI が返した日付の表記が、
    /// 入力に書かれた日を指しているかの突き合わせ（`ExtractedEntry`）に使う。
    private(set) var dateCandidates: [Int] = []
    /// 割り勘の人数。「割り勘」の語と「N人」の両方があったときだけ入る。
    private(set) var splitCount: Int?
    /// 「N人」「N名」の N（入力の順）。割り勘の語が無くても入る。
    private(set) var peopleCounts: [Int] = []
    /// 割り勘の語（「割り勘」「わりかん」など）があったか。
    private(set) var hasSplitWord = false

    init(_ normalizedText: String, now: Date, calendar: Calendar) {
        chars = Array(normalizedText)
        consumed = Array(repeating: false, count: chars.count)
        scanDateWords()
        scanNumbers(now: now, calendar: calendar)
    }

    // MARK: - 区切り

    /// 「スーパー2480とドラッグ1200」のような複数件の入力を、1 件ずつの区間に分ける。
    ///
    /// 金額を含まない区間は次の区間につなげる（「ランチとコーヒー 1200」は 1 件）。
    /// 末尾に金額の無い区間が残ったら、直前の区間につなげる。金額が 1 つも無ければ空配列。
    func segments() -> [Segment] {
        var pieces: [Range<Int>] = []
        var start = 0
        for i in chars.indices where !consumed[i] && isSeparator(at: i) {
            pieces.append(start..<i)
            start = i + 1
        }
        pieces.append(start..<chars.count)

        var result: [Segment] = []
        var pendingStart = 0
        for piece in pieces {
            guard let amount = amounts.last(where: { piece.contains($0.range.lowerBound) }) else { continue }
            result.append(Segment(range: pendingStart..<piece.upperBound, amount: amount))
            pendingStart = piece.upperBound + 1
        }
        if let last = result.last, pendingStart < chars.count {
            result[result.count - 1].range = last.range.lowerBound..<chars.count
        }
        return result
    }

    /// `i` の文字で件を区切るか。
    ///
    /// 「、」「/」などの記号はいつでも区切る。「と」と空白は、語の一部や語の間にも出てくるので、
    /// 金額の直後にあるときだけ区切りとみなす。
    private func isSeparator(at i: Int) -> Bool {
        let c = chars[i]
        if Self.separators.contains(c) { return true }
        // 「と」は金額の直後（「2480とドラッグ」「850円と」）だけ。「ひとり」「おとうふ」「とんかつ」の
        // ように語の中や頭の「と」で割ると、メモが語の途中で切れた記録ができるため。
        if c == "と" { return endsAmount(at: i) }
        // 金額の直後の空白は、次に語が続くなら区切る（「パン200 おとうふ100」「ランチ850 とんかつ弁当900」）。
        // 次が数字なら区切らない。「ランチ 850 900」「ビール 500 2本」は 1 件として読む。
        if c.isWhitespace, endsAmount(at: i), let next = chars[(i + 1)...].firstIndex(where: { !$0.isWhitespace }) {
            return !chars[next].isASCIIDigit && !Self.yenMarks.contains(chars[next])
        }
        return false
    }

    /// `i` の直前で金額が終わっているか（`i` が金額の範囲のすぐ後ろか）。
    private func endsAmount(at i: Int) -> Bool {
        amounts.contains { $0.range.upperBound == i }
    }

    /// 区間の文字から、使い終えた部分と `excluding` を除き、空白と端の記号を整えた文字列。
    func text(in range: Range<Int>, excluding: Range<Int>? = nil) -> String {
        var raw = ""
        for i in range where !consumed[i] && !(excluding?.contains(i) ?? false) {
            raw.append(chars[i])
        }
        var words = raw.split(whereSeparator: \.isWhitespace)
        // 空白で区切った跡に 1 語で残る「と」（「スーパー2480 と ドラッグ1200」の 2 件目の頭）は落とす。
        while words.first == "と" { words.removeFirst() }
        while words.last == "と" { words.removeLast() }
        var text = words.joined(separator: " ")
            .trimmingCharacters(in: Self.trimmedEdges)
        // 金額や割り勘の語を抜いた跡に残る助詞（「ランチで850」の「で」、「1000円を」の「を」）を落とす。
        // 先頭の「で」は「でんき」のような語の頭でありうるので、先頭は「を」だけにする。
        while let last = text.last, Self.trailingParticles.contains(last) {
            text.removeLast()
            text = text.trimmingCharacters(in: Self.trimmedEdges)
        }
        while text.first == "を" {
            text.removeFirst()
            text = text.trimmingCharacters(in: Self.trimmedEdges)
        }
        return text
    }

    // MARK: - 日付の語

    private mutating func scanDateWords() {
        for (word, days) in Self.dateWords {
            guard let range = firstRange(of: word) else { continue }
            consume(range)
            setDaysAgo(days)
        }
    }

    // MARK: - 数字

    private mutating func scanNumbers(now: Date, calendar: Calendar) {
        let numbers = Self.numbers(in: chars)
        var people: [(count: Int, range: Range<Int>)] = []
        var i = 0
        while i < numbers.count {
            let number = numbers[i]
            let end = number.range.upperBound
            let next = i + 1 < numbers.count ? numbers[i + 1] : nil

            // 「2026/9/26」。年から書いた日付は、年も含めて使い終える。
            // 年を残すと、2026 が ¥2,026 の記録になり、「/」で別の件にも分かれてしまうため。
            if number.isPlainInteger, number.range.count == 4, i + 2 < numbers.count,
               Self.isMonthOrDay(numbers[i + 1]), Self.isMonthOrDay(numbers[i + 2]),
               isJoinedBySlash(number, numbers[i + 1]), isJoinedBySlash(numbers[i + 1], numbers[i + 2]) {
                let month = numbers[i + 1]
                let day = numbers[i + 2]
                if let days = DateExpression.daysAgo(
                    year: number.value, month: month.value, day: day.value, now: now, calendar: calendar
                ) {
                    setDaysAgo(days)
                }
                consume(number.range.lowerBound..<day.range.upperBound)
                i += 3
                continue
            }
            // 「9/26」。1〜2 桁どうしを「/」でつないだものは日付の表記とみなし、日付として成り立たなくても
            // （9/31、13/5）使い終える。残すと、数字が金額になり、「/」で別の件にも分かれて、
            // 余計な記録が黙って増えるため。
            if Self.isMonthOrDay(number), let next, Self.isMonthOrDay(next), isJoinedBySlash(number, next) {
                if let days = DateExpression.daysAgo(month: number.value, day: next.value, now: now, calendar: calendar) {
                    setDaysAgo(days)
                }
                consume(number.range.lowerBound..<next.range.upperBound)
                i += 2
                continue
            }
            // 「9月26日」。成り立たない日付（9月31日）は、「月」「日」が数量の語なので金額にもならない。
            if number.isPlainInteger, let next, next.isPlainInteger, next.range.lowerBound == end + 1,
               has("月", at: end), has("日", at: next.range.upperBound),
               let days = DateExpression.daysAgo(month: number.value, day: next.value, now: now, calendar: calendar) {
                setDaysAgo(days)
                consume(number.range.lowerBound..<(next.range.upperBound + 1))
                i += 2
                continue
            }
            // 「3日前」。1 年より前は書き間違いとみなして日付にしない。
            if number.isPlainInteger, has("日前", at: end), number.value <= 366 {
                setDaysAgo(number.value)
                consume(number.range.lowerBound..<(end + 2))
                i += 1
                continue
            }
            // 「4人」「4名」。割り勘の語があるかは最後に見る。「3人前」は量なので人数にしない。
            if number.isPlainInteger, (has("人", at: end) && !has("人前", at: end)) || has("名", at: end) {
                let upper = has("で", at: end + 1) ? end + 2 : end + 1
                people.append((number.value, number.range.lowerBound..<upper))
                i += 1
                continue
            }

            var range = number.range
            if has("円", at: end) {
                range = range.lowerBound..<(end + 1)
            } else if Self.counters.contains(where: { has($0, at: end) }) {
                // 「2杯」「3個」は数量で、金額ではない。
                i += 1
                continue
            }
            if range.lowerBound > 0, Self.yenMarks.contains(chars[range.lowerBound - 1]) {
                range = (range.lowerBound - 1)..<range.upperBound
            }
            if number.value > 0 {
                amounts.append(Amount(value: number.value, range: range))
            }
            i += 1
        }

        peopleCounts = people.map(\.count)

        // 人数だけでは割り勘とみなさない（「4人でランチ 4000」は 4000 円を払ったのかもしれない）。
        var splitWord: Range<Int>?
        for word in Self.splitWords where splitWord == nil {
            splitWord = firstRange(of: word)
        }
        hasSplitWord = splitWord != nil
        if let word = splitWord, let first = people.first, (2...100).contains(first.count) {
            splitCount = first.count
            consume(word)
            consume(first.range)
        }
    }

    // MARK: - 数字の読み取り

    struct NumberToken: Equatable {
        var value: Int
        var range: Range<Int>
        /// 小数点も「万」「千」も含まない整数か。日付や人数はこの形のときだけ読む。
        var isPlainInteger: Bool
    }

    /// 「850」「1.5万」「25万」「1万2千」「1万2000」「3千5」を数に直して、位置とともに返す。
    ///
    /// 「1万5」「3千5」は話し言葉で 15000 / 3500 を指すので、「万」「千」の後ろが 1 桁だけのときは
    /// 1 つ下の位として読む。
    static func numbers(in chars: [Character]) -> [NumberToken] {
        var result: [NumberToken] = []
        var i = 0
        while i < chars.count {
            guard chars[i].isASCIIDigit else {
                i += 1
                continue
            }
            let start = i
            let head = decimal(in: chars, from: i)
            i = head.end
            guard var value = head.value else { continue }
            var isPlain = !head.hasFraction

            if i < chars.count, chars[i] == "万" {
                isPlain = false
                value *= 10_000
                i += 1
                if i < chars.count, chars[i].isASCIIDigit {
                    let rest = decimal(in: chars, from: i)
                    if let restValue = rest.value {
                        if rest.end < chars.count, chars[rest.end] == "千" {
                            value += restValue * 1_000
                            i = rest.end + 1
                        } else {
                            value += rest.digitCount == 1 && !rest.hasFraction ? restValue * 1_000 : restValue
                            i = rest.end
                        }
                    }
                }
            } else if i < chars.count, chars[i] == "千" {
                isPlain = false
                value *= 1_000
                i += 1
                if i < chars.count, chars[i].isASCIIDigit {
                    let rest = decimal(in: chars, from: i)
                    if let restValue = rest.value {
                        value += rest.digitCount == 1 && !rest.hasFraction ? restValue * 100 : restValue
                        i = rest.end
                    }
                }
            }

            if let int = roundedInt(value) {
                result.append(NumberToken(value: int, range: start..<i, isPlainInteger: isPlain))
            }
        }
        return result
    }

    /// `from` から始まる「123」「1.5」を読む。桁が多すぎるもの（電話番号など）は value が nil。
    private static func decimal(
        in chars: [Character], from start: Int
    ) -> (value: Decimal?, end: Int, digitCount: Int, hasFraction: Bool) {
        var i = start
        while i < chars.count, chars[i].isASCIIDigit { i += 1 }
        let integerDigits = i - start
        var hasFraction = false
        if i + 1 < chars.count, chars[i] == ".", chars[i + 1].isASCIIDigit {
            hasFraction = true
            i += 1
            while i < chars.count, chars[i].isASCIIDigit { i += 1 }
        }
        guard integerDigits <= maximumDigits else { return (nil, i, integerDigits, hasFraction) }
        let value = Decimal(string: String(chars[start..<i]), locale: Locale(identifier: "en_US_POSIX"))
        return (value, i, integerDigits, hasFraction)
    }

    private static func roundedInt(_ value: Decimal) -> Int? {
        guard value >= 0, value <= Decimal(maximumValue) else { return nil }
        return Int(NSDecimalNumber(decimal: value).doubleValue.rounded())
    }

    // MARK: - 補助

    private func has(_ word: String, at index: Int) -> Bool {
        var i = index
        for c in word {
            guard i < chars.count, chars[i] == c else { return false }
            i += 1
        }
        return true
    }

    /// まだ使っていない文字の中で、`word` が最初に現れる位置。
    private func firstRange(of word: String) -> Range<Int>? {
        let length = word.count
        guard length > 0, chars.count >= length else { return nil }
        for start in 0...(chars.count - length) where has(word, at: start) {
            let range = start..<(start + length)
            if !range.contains(where: { consumed[$0] }) { return range }
        }
        return nil
    }

    private mutating func consume(_ range: Range<Int>) {
        for i in range where i < consumed.count { consumed[i] = true }
    }

    /// 最初に見つけた日付を採る。ほかの日付も突き合わせ用に残す。
    private mutating func setDaysAgo(_ days: Int) {
        if daysAgo == nil { daysAgo = days }
        dateCandidates.append(days)
    }

    /// `first` と `second` が「/」1 文字だけを挟んで並んでいるか（「9/26」）。
    private func isJoinedBySlash(_ first: NumberToken, _ second: NumberToken) -> Bool {
        has("/", at: first.range.upperBound) && second.range.lowerBound == first.range.upperBound + 1
    }

    /// 月や日として読める形（1〜2 桁の素の整数）か。
    private static func isMonthOrDay(_ token: NumberToken) -> Bool {
        token.isPlainInteger && token.range.count <= 2
    }

    // MARK: - 辞書

    /// 12 桁（1 兆円未満）を超える数字は金額とみなさない。家計簿の 1 件としてありえず、
    /// 電話番号やカード番号の貼り付けを金額にしてしまうのを防ぐため。
    private static let maximumDigits = 12
    private static let maximumValue = 999_999_999_999

    /// 長い語を先に置く（「一昨日」を「昨日」より先に見ないと、1 日ずれる）。
    /// ひらがなの「きょう」は「きょうだい」などに当たるので入れない（今日は既定値なので困らない）。
    private static let dateWords: [(String, Int)] = [
        ("一昨日", 2), ("おととい", 2), ("おとつい", 2), ("昨日", 1), ("きのう", 1), ("今日", 0), ("本日", 0),
    ]

    private static let splitWords = ["割り勘", "割勘", "わりかん", "ワリカン"]

    private static let yenMarks: Set<Character> = ["¥", "\\"]

    /// いつでも区切りとみなす記号。「・」は「光熱・通信」のように語の中でも使うので入れない。
    /// 「と」と空白は金額の直後だけ区切る（`isSeparator(at:)`）。
    private static let separators: Set<Character> = ["、", ",", "\n", ";", "+", "/"]

    /// メモの前後から取り除く記号。
    private static let trimmedEdges = CharacterSet.whitespacesAndNewlines
        .union(CharacterSet(charactersIn: "、,。.・/:;+"))

    private static let trailingParticles: Set<Character> = ["を", "で"]

    /// 数字の直後にあれば、その数字は量や日時であって金額ではない。
    private static let counters = [
        "個", "本", "杯", "枚", "回", "泊", "冊", "点", "着", "足", "台", "缶", "箱", "袋", "皿", "錠", "粒",
        "匹", "頭", "羽", "部", "巻", "話", "席", "件", "人前", "時", "分", "秒", "日", "週", "ヶ月", "ヵ月",
        "ケ月", "カ月", "か月", "月", "年", "歳", "才", "度", "番", "階", "号", "位", "割", "倍", "均", "%",
        "kg", "g", "mg", "ml", "mL", "l", "L", "km", "m", "cm", "mm", "GB", "インチ",
    ]
}
