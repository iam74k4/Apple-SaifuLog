import Foundation

/// 正規化済みの一行を文字単位で読み、金額・日付・割り勘の人数を拾い出して、件ごとの区間に分ける。
///
/// ルールベースの解析、AI の出力の検査（`ExtractedEntry`・`AmountParser`）、日付の表記の解釈
/// （`DateExpression`）がすべてここを通る。数字の読み方を 1 か所にまとめ、どこで読んでも同じ結果に
/// なるようにするため。
///
/// 文字の位置は `[Character]` の添字で持つ。メモを作るときに「使った部分」を
/// 位置で取り除く必要があり、String.Index より扱いやすいため。
struct EntryScan {
    struct Amount: Hashable, Sendable {
        /// 金額（円）。マイナスを付けて書かれていても正の数で持つ。
        var value: Int
        /// 入力中の位置。前の「¥」「-」「1人あたり」と後ろの「円」も含む。
        var range: Range<Int>
        /// 「1人あたり3000」「1人3000」のように、1 人分として書かれた額か。割り勘でもこの額は割らない。
        var isPerPerson = false
        /// 「返金 -500」のようにマイナスを付けて書かれたか。返金として収入で記録する。
        var isNegative = false
        /// 同じ区間で正の金額の後ろに置いたマイナスの額（「ランチ 850(-100引き)」の -100）か。
        /// 値引きの説明なので、その件の金額にも返金（収入）にもしない。`segments()` が付ける。
        var isDiscount = false
        /// 「500×3」のような掛け算の単価（個数でない方）。掛け算でなければ nil。
        /// AI が単価だけを抜き出しても、掛けた額の金額と突き合わせられるようにするため。
        var unitPrice: Int?
    }

    /// 日付の言い回し 1 つ（「昨日」「9/26」「2025年9月26日」「26日」など）。
    struct DatePhrase: Hashable, Sendable {
        /// 入力中の位置。後ろの助詞（「昨日の」の「の」）も含む。
        var range: Range<Int>
        /// 何日前か（負の数は未来の日）。「9/31」のように日付として成り立たなければ nil。
        var daysAgo: Int?
    }

    /// 割り勘の語と、その語に最も近い「N人」の組。
    struct SplitPhrase: Hashable, Sendable {
        var count: Int
        var wordRange: Range<Int>
        var countRange: Range<Int>

        var lowerBound: Int { min(wordRange.lowerBound, countRange.lowerBound) }
    }

    /// 1 件分の区間と、その件に割り当てた金額・日付・割り勘。
    struct Segment: Hashable, Sendable {
        var range: Range<Int>
        /// その件の金額。1 人分として書かれた額があればそれを、無ければ区間の最後の金額を採る（値引きの額は採らない）。
        var amount: Amount
        /// 区間の中の金額すべて（入力の順）。AI が返した金額の突き合わせに使う。
        var amounts: [Amount]
        /// その件の日付（何日前か）。日付が書かれていなければ nil（今日）。
        var daysAgo: Int?
        /// 区間に書かれた日付と、この件に割り当てた日付。AI が返した日付の突き合わせに使う。
        var dateCandidates: [Int]
        /// その件にかかる割り勘。1 人分の額（`Amount.isPerPerson`）のときも入るので、割るかは使う側で決める。
        var split: SplitPhrase?
    }

    let chars: [Character]
    /// 日付・時刻・電話番号など、金額ではないと読み終えた文字。メモから除く。
    private(set) var consumed: [Bool]
    /// 日付の形で書かれているが、日付として成り立たなかった文字（「9/31」、9 月の「31日」、2026 年の「2月29日」）。
    /// 金額にはしないが、メモには残す。黙って消すと今日の記録として保存され、読めなかったことに気づけないため。
    private var unreadDate: [Bool]
    /// 金額とみなした数字（入力の順）。
    private(set) var amounts: [Amount] = []
    /// 日付の言い回し（入力の順）。
    private(set) var dates: [DatePhrase] = []
    /// 「N人」「N名」の N と位置（入力の順）。割り勘の語が無くても入る。
    private(set) var people: [(count: Int, range: Range<Int>)] = []
    /// 割り勘の語と人数の組（語の順）。
    private(set) var splits: [SplitPhrase] = []
    /// 金額を先に書く並び（「850 ランチ 400 コーヒー」）か。区切り方が変わる。
    private var amountFirst = false

    init(_ normalizedText: String, now: Date, calendar: Calendar) {
        chars = Array(normalizedText)
        consumed = Array(repeating: false, count: chars.count)
        unreadDate = consumed
        scanDateWords()
        scanNumericDates(now: now, calendar: calendar)
        scanAmounts()
        scanSplits()
        // 金額から書き始め、最後の金額の後ろにも語があるときだけ、金額を先に書く並びとみなす
        // （「850 ランチ 400 コーヒー」）。最後が金額で終わる入力（「109で服 5000」）は、ふつうの並びで
        // 最初の数字が品目の一部。金額を先に書く並びとして読むと、「109」と「5000」の 2 件に割れてしまう。
        if amounts.count >= 2, let first = chars.indices.first(where: { !consumed[$0] && !chars[$0].isWhitespace }),
           first == amounts[0].range.lowerBound {
            let last = amounts[amounts.count - 1].range.upperBound
            amountFirst = (last..<chars.count).contains { isWordCharacter(at: $0) }
        }
    }

    /// 入力にある日付のうち、最初に書かれたものが何日前か。日付が無ければ nil。
    var daysAgo: Int? {
        dates.sorted { $0.range.lowerBound < $1.range.lowerBound }.lazy.compactMap(\.daysAgo).first
    }

    // MARK: - 区切り

    /// 「スーパー2480とドラッグ1200」のような複数件の入力を、1 件ずつの区間に分ける。
    ///
    /// - 金額を含まない区間は次の区間につなげる（「ランチとコーヒー 1200」は 1 件）。
    ///   末尾に金額の無い区間が残ったら、直前の区間につなげる。金額が 1 つも無ければ空配列
    /// - 「、」「。」「/」などの強い区切りで分かれた部分を 1 つの文とみなし、日付と割り勘は文ごとに割り当てる
    ///   （「昨日 焼肉12000 4人で割り勘、今日 ランチ 850」のランチは割らず、今日にする）
    ///   - 日付: その件の区間に書かれた日付。無ければ、同じ文の最後の件の後ろに置いた日付
    ///     （「スーパー2480とドラッグ1200 昨日」）、前の件の日付（先頭に置いた共通の日付を引き継ぐ）、
    ///     最後に独立して置いた日付（「ランチ850、コーヒー400、昨日」）の順に使う
    ///   - 割り勘: その件の区間に書かれた割り勘。無ければ、同じ文の最後の件の後ろ・最初の件の前に置いた
    ///     割り勘（「焼肉12000と飲み物3000 3人で割り勘」は両方割る）、最後に独立して置いた割り勘の順に使う。
    ///     割り勘は前の件から引き継がない
    func segments() -> [Segment] {
        guard !amounts.isEmpty else { return [] }
        let inAmount = amountMask()

        // 区切りの位置。width 0 は文字を挟まない境目（「スーパー2480ドラッグ1200」）。
        // afterAmount は、金額の直後の「と」・空白で区切ったか。
        var cuts: [(position: Int, width: Int, isStrong: Bool, afterAmount: Bool)] = []
        for i in chars.indices where !consumed[i] && !inAmount[i] {
            if Self.clauseSeparators.contains(chars[i]) {
                cuts.append((i, 1, true, false))
            } else if isWeakSeparator(at: i) {
                cuts.append((i, 1, false, !Self.weakSeparators.contains(chars[i])))
            } else if startsEntryWithoutSeparator(at: i) {
                cuts.append((i, 0, false, true))
            }
        }
        var pieces: [(range: Range<Int>, afterStrong: Bool, afterAmount: Bool)] = []
        var start = 0
        var afterStrong = true
        var afterAmount = false
        for cut in cuts {
            pieces.append((start..<cut.position, afterStrong, afterAmount))
            start = cut.position + cut.width
            afterStrong = cut.isStrong
            afterAmount = cut.afterAmount
        }
        pieces.append((start..<chars.count, afterStrong, afterAmount))

        // 金額の無い区間を前後につなげ、件と文（clause）を決める。
        var drafts: [(range: Range<Int>, amounts: [Amount], clause: Int)] = []
        var pendingStart: Int?
        var startsClause = true
        var clause = -1
        // 最後の件の後ろに、強い区切りを挟んで置いた金額の無い部分（「、昨日」）の始まり。
        var trailingStart: Int?
        for piece in pieces {
            if piece.afterStrong { startsClause = true }
            let pieceAmounts = amounts.filter { piece.range.contains($0.range.lowerBound) }
            guard !pieceAmounts.isEmpty else {
                // 金額の直後の空白で切れた、金額の無い部分（「焼肉 12000 割り勘 4人、カフェ 800」の「割り勘 4人」）は、
                // 直前の件の続き。次の件につなげると、強い区切りを越えて割り勘や日付が次の件にかかってしまう。
                if piece.afterAmount, pendingStart == nil, let last = drafts.indices.last {
                    drafts[last].range = drafts[last].range.lowerBound..<piece.range.upperBound
                    continue
                }
                if pendingStart == nil { pendingStart = piece.range.lowerBound }
                if !drafts.isEmpty, piece.afterStrong, trailingStart == nil { trailingStart = piece.range.lowerBound }
                continue
            }
            if startsClause {
                clause += 1
                startsClause = false
            }
            drafts.append(((pendingStart ?? piece.range.lowerBound)..<piece.range.upperBound, pieceAmounts, clause))
            pendingStart = nil
            trailingStart = nil
        }
        if pendingStart != nil, let last = drafts.indices.last {
            drafts[last].range = drafts[last].range.lowerBound..<chars.count
        }

        // 文ごとの、最後の件の後ろ・最初の件の前に置いた日付と割り勘。
        let validDates = dates.filter { $0.daysAgo != nil }.sorted { $0.range.lowerBound < $1.range.lowerBound }
        var clauseTrailingDate: [Int: Int] = [:]
        var clauseTrailingSplit: [Int: SplitPhrase] = [:]
        var clauseLeadingSplit: [Int: SplitPhrase] = [:]
        var lastDraftOfClause: [Int: Int] = [:]
        var firstDraftOfClause: [Int: Int] = [:]
        for (k, draft) in drafts.enumerated() {
            lastDraftOfClause[draft.clause] = k
            if firstDraftOfClause[draft.clause] == nil { firstDraftOfClause[draft.clause] = k }
        }
        for (clause, k) in lastDraftOfClause {
            let draft = drafts[k]
            let afterAmounts = draft.amounts.last!.range.upperBound
            clauseTrailingDate[clause] = validDates.first {
                draft.range.contains($0.range.lowerBound) && $0.range.lowerBound >= afterAmounts
            }?.daysAgo
            clauseTrailingSplit[clause] = splits.first {
                draft.range.contains($0.wordRange.lowerBound) && $0.lowerBound >= afterAmounts
            }
        }
        for (clause, k) in firstDraftOfClause {
            let draft = drafts[k]
            let beforeAmounts = draft.amounts[0].range.lowerBound
            clauseLeadingSplit[clause] = splits.first {
                draft.range.contains($0.wordRange.lowerBound) && $0.wordRange.upperBound <= beforeAmounts
                    && $0.countRange.upperBound <= beforeAmounts
            }
        }
        let trailingDate = trailingStart.flatMap { start in validDates.first { $0.range.lowerBound >= start }?.daysAgo }
        let trailingSplit = trailingStart.flatMap { start in splits.first { $0.lowerBound >= start } }

        var result: [Segment] = []
        for (k, draft) in drafts.enumerated() {
            let isLastOfClause = lastDraftOfClause[draft.clause] == k
            let isFirstOfClause = firstDraftOfClause[draft.clause] == k
            let ownDates = validDates.filter { draft.range.contains($0.range.lowerBound) }.compactMap(\.daysAgo)

            var daysAgo = ownDates.first
            if daysAgo == nil, !isLastOfClause { daysAgo = clauseTrailingDate[draft.clause] }
            if daysAgo == nil, let previous = result.last { daysAgo = previous.daysAgo }
            if daysAgo == nil { daysAgo = trailingDate }

            var split = splits.first { draft.range.contains($0.wordRange.lowerBound) }
            if split == nil, !isLastOfClause { split = clauseTrailingSplit[draft.clause] }
            if split == nil, !isFirstOfClause { split = clauseLeadingSplit[draft.clause] }
            if split == nil { split = trailingSplit }

            var candidates = ownDates
            if let daysAgo, !candidates.contains(daysAgo) { candidates.append(daysAgo) }
            // 正の金額の後ろに置いたマイナスの額（「ランチ 850(-100引き)」）は値引きの説明。最後の金額として採ると、
            // 850 円の支出が 100 円の返金（収入）にすり替わるため、その件の金額の候補から外す。
            var segmentAmounts = draft.amounts
            if let firstPositive = segmentAmounts.firstIndex(where: { !$0.isNegative }) {
                for j in segmentAmounts.indices where j > firstPositive && segmentAmounts[j].isNegative {
                    segmentAmounts[j].isDiscount = true
                }
            }
            let usable = segmentAmounts.filter { !$0.isDiscount }
            result.append(Segment(
                range: draft.range,
                amount: usable.last(where: \.isPerPerson) ?? usable.last!,
                amounts: segmentAmounts,
                daysAgo: daysAgo,
                dateCandidates: candidates,
                split: split
            ))
        }
        return result
    }

    /// `i` の文字（「と」・空白・「+」）で件を区切るか。「、」などの強い区切りは `clauseSeparators`。
    ///
    /// 「と」と空白は、語の一部や語の間にも出てくるので、金額の直後にあるときだけ区切りとみなす。
    /// 金額を先に書く並び（「850 ランチ 400 コーヒー」）では、反対に次の金額の直前で区切る。
    /// どちらの並びでも、次の金額が前の金額の説明（1 人分の額・値引き）なら空白では区切らない（`continuesPreviousAmount(after:)`）。
    private func isWeakSeparator(at i: Int) -> Bool {
        let c = chars[i]
        if Self.weakSeparators.contains(c) { return true }
        guard c == "と" || c.isWhitespace else { return false }
        if amountFirst {
            // 語の後ろ、次の金額の前（「850 ランチ 400」の 400 の前）。「850 900」のように金額が続くところでは区切らない。
            guard let next = nextNonSpace(from: i + 1), amounts.contains(where: { $0.range.lowerBound == next }),
                  let previous = previousNonSpace(before: i)
            else { return false }
            if c.isWhitespace, continuesPreviousAmount(after: i) { return false }
            return !amounts.contains { $0.range.upperBound == previous + 1 }
        }
        guard endsAmount(at: i) else { return false }
        // 「と」は金額の直後（「2480とドラッグ」「850円と」）だけ。「ひとり」「おとうふ」「とんかつ」の
        // ように語の中や頭の「と」で割ると、メモが語の途中で切れた記録ができるため。
        if c == "と" { return true }
        // 金額の直後の空白は、次に語が続くなら区切る（「パン200 おとうふ100」「ランチ850 とんかつ弁当900」）。
        // 次が数字なら区切らない。「ランチ 850 900」「ビール 500 2本」は 1 件として読む。
        guard let next = nextNonSpace(from: i + 1), !continuesPreviousAmount(after: i) else { return false }
        return !chars[next].isASCIIDigit && !Self.yenMarks.contains(chars[next])
    }

    /// `i` の後ろで次に出てくる金額が、前の金額と同じ件の説明か。
    ///
    /// - 同じ文の中の 1 人分の額（「焼肉 12000 ひとり3000」「12000 焼肉 4人で割り勘 1人3000」の 1人3000）。
    ///   総額と 1 人分の額を別の件にすると、同じ支出を 2 度記録してしまう
    /// - 金額のすぐ後ろ（空白だけを挟む）か括弧の中のマイナスの額（「ランチ 1000 -200」「ランチ 850 (-100引き)」）。
    ///   値引きの説明で、別の返金の記録ではない。語を挟んだもの（「ランチ 850 返金 -500」）は別の件
    private func continuesPreviousAmount(after i: Int) -> Bool {
        guard let next = amounts.first(where: { $0.range.lowerBound > i }) else { return false }
        let between = i..<next.range.lowerBound
        if between.contains(where: { !consumed[$0] && Self.clauseSeparators.contains(chars[$0]) }) { return false }
        if next.isPerPerson { return true }
        guard next.isNegative, endsAmount(at: i), let start = nextNonSpace(from: i + 1) else { return false }
        if start == next.range.lowerBound { return true }
        return Self.openingPunctuation.contains(chars[start]) && nextNonSpace(from: start + 1) == next.range.lowerBound
    }

    /// 区切りの文字を挟まずに次の件が始まるか（「スーパー2480ドラッグ1200」の「ド」の前）。
    ///
    /// 型番や店名の数字（「iPhone15ケース2000」「セブン11で500」「100円ショップで500円」）で割らないよう、
    /// 次の条件がすべてそろうときだけ区切る。
    /// - 金額の直後から次の金額の直前までが、カタカナの 1 語だけ（空白を挟まない）。
    ///   「ドラクエ12ソフト 8000」「コーラ500ペットボトル 160」のように、語の後ろに空白を置いて金額を
    ///   書いたものは、数字が品目の一部（型番や容量）なので割らない
    /// - 金額が 2 桁以上で、前に英字が付いていない
    private func startsEntryWithoutSeparator(at i: Int) -> Bool {
        guard !amountFirst, Self.isKatakana(chars[i]),
              let amount = amounts.first(where: { $0.range.upperBound == i })
        else { return false }
        if amount.range.lowerBound > 0, chars[amount.range.lowerBound - 1].isASCIILetter { return false }
        guard chars[amount.range].filter(\.isASCIIDigit).count >= 2,
              let next = amounts.first(where: { $0.range.lowerBound >= i })
        else { return false }
        var j = i
        while j < next.range.lowerBound, !consumed[j], Self.isKatakana(chars[j]) { j += 1 }
        return j == next.range.lowerBound
    }

    /// `i` の文字が、語の一部（使い終えておらず、空白や区切りの記号でない）か。
    private func isWordCharacter(at i: Int) -> Bool {
        !consumed[i] && !chars[i].isWhitespace && !Self.clauseSeparators.contains(chars[i])
            && !Self.weakSeparators.contains(chars[i])
    }

    /// `i` の直前で金額が終わっているか（`i` が金額の範囲のすぐ後ろか）。
    private func endsAmount(at i: Int) -> Bool {
        amounts.contains { $0.range.upperBound == i }
    }

    private func amountMask() -> [Bool] {
        var mask = Array(repeating: false, count: chars.count)
        for amount in amounts {
            for i in amount.range { mask[i] = true }
        }
        return mask
    }

    // MARK: - メモ

    /// 区間の文字から、使い終えた部分と `excluding` を除き、空白と端の記号を整えた文字列。
    func text(in range: Range<Int>, excluding: [Range<Int>] = []) -> String {
        var raw = ""
        for i in range where (!consumed[i] || unreadDate[i]) && !excluding.contains(where: { $0.contains(i) }) {
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

    /// 金額・日付・人数・割り勘の語をすべて除いた文字列。AI が返した品目から、品目でない部分を取り除くのに使う。
    func textWithoutNumbers() -> String {
        let ranges = amounts.map(\.range) + people.map(\.range) + splitWordRanges()
        return text(in: 0..<chars.count, excluding: ranges)
    }

    // MARK: - 日付

    /// 「昨日」「一昨日」などの語。同じ語が何度出てきても、すべて日付として使い終える。
    private mutating func scanDateWords() {
        for (word, days) in Self.dateWords {
            while let range = firstRange(of: word) {
                consumeDate(range, daysAgo: days)
            }
        }
    }

    /// 数字で書いた日付・時刻・電話番号を、金額を読む前に使い終える。
    ///
    /// 先に済ませるのは、「9/26」「12:30」「090-1234-5678」の数字を金額として読まないため。
    private mutating func scanNumericDates(now: Date, calendar: Calendar) {
        var i = 0
        while i < chars.count {
            guard let run = digitRun(at: i) else {
                i += 1
                continue
            }
            i = matchNumericDate(run, at: i, now: now, calendar: calendar) ?? run.end
        }
    }

    /// `i` から始まる数字の並びが日付・時刻・電話番号の表記なら使い終え、その後ろの位置を返す。
    private mutating func matchNumericDate(
        _ a: (value: Int, end: Int, length: Int), at i: Int, now: Date, calendar: Calendar
    ) -> Int? {
        let n = chars.count
        // 小数や時刻の後ろ半分（「1.5」の 5、「12:30」の 30）から読み始めない。
        if i >= 2, chars[i - 1] == "." || chars[i - 1] == ":", chars[i - 2].isASCIIDigit { return nil }

        // 「3日前」。1 年より前は書き間違いとみなして日付にしない。
        if has("日前", at: a.end), a.value <= 366 {
            return consumeDate(i..<(a.end + 2), daysAgo: a.value)
        }

        // 和暦（「R7/9/26」「令和7年9月26日」）。
        var eraBase: Int?
        var start = i
        if a.length <= 2 {
            if i >= 1, let base = Self.eraLetters[chars[i - 1]], i < 2 || !chars[i - 2].isASCIILetter, !consumed[i - 1] {
                eraBase = base
                start = i - 1
            } else if i >= 2, let era = Self.eraWords.first(where: { has($0.name, at: i - 2) }), !consumed[i - 2] {
                eraBase = era.base
                start = i - 2
            }
        }
        // 年の数字を西暦にする。4 桁はそのまま、2 桁は 2000 年代、和暦は元号の年から。
        let year: Int? = eraBase.map { $0 + a.value } ?? (a.length == 4 ? a.value : a.length == 2 ? 2000 + a.value : nil)

        // 「2025年9月26日」。成り立たない日付（2026年2月30日）も、全体を日付の表記として使い終える。
        // 「年」「月」の後ろの空白（「2025年 9月 26日」）は読み飛ばす。
        if let year, has("年", at: a.end), let m = digitRun(at: skippingSpaces(from: a.end + 1)), m.length <= 2,
           has("月", at: m.end), let d = digitRun(at: skippingSpaces(from: m.end + 1)), d.length <= 2, has("日", at: d.end) {
            let days = DateExpression.daysAgo(year: year, month: m.value, day: d.value, now: now, calendar: calendar)
            return consumeDate(start..<(d.end + 1), daysAgo: days)
        }
        // 「9月26日」。成り立たない日付（9月31日）も使い終える（「31日」だけを今月の日として読まないため）。
        if eraBase == nil, a.length <= 2, has("月", at: a.end), let d = digitRun(at: skippingSpaces(from: a.end + 1)),
           d.length <= 2, has("日", at: d.end) {
            let days = DateExpression.daysAgo(month: a.value, day: d.value, now: now, calendar: calendar)
            return consumeDate(i..<(d.end + 1), daysAgo: days)
        }

        // 「/」「-」「.」でつないだ日付（「2026/9/26」「25/9/26」「9/26」「9-26」「9.26」）と電話番号。
        if a.end < n, Self.dateSeparators.contains(chars[a.end]), let b = digitRun(at: a.end + 1) {
            let separator = chars[a.end]
            // 「-」「.」は日付のほかに、型番（「PS5-2」）・版（「ver1.2」）・小数（「1.5」）・幅（「3-4人」）にも使う。
            // 英字や「.」に続く数字は日付にしない（和暦の略記「R7」の R は除く）。「/」は日付のほかにほぼ使わないので見ない。
            let isDateContext = separator == "/" || eraBase != nil
                || !(i >= 1 && (chars[i - 1].isASCIILetter || chars[i - 1] == "."))
            // 3 つ組を先に見る。「25/9/26」の「25/9」だけを日付にすると、残った 26 が ¥26 の記録になるため。
            if b.end < n, chars[b.end] == separator, let c = digitRun(at: b.end + 1) {
                let followedByMore = c.end + 1 < n && chars[c.end] == separator && chars[c.end + 1].isASCIIDigit
                if !followedByMore, isDateContext, b.length <= 2, c.length <= 2,
                   year != nil || (separator == "/" && a.length <= 2) {
                    // 年から書いた日付は、年も含めて使い終える。年を残すと、2026 が ¥2,026 の記録になるため。
                    let days = year.flatMap {
                        DateExpression.daysAgo(year: $0, month: b.value, day: c.value, now: now, calendar: calendar)
                    }
                    return consumeDate(start..<c.end, daysAgo: days)
                }
                // 「090-1234-5678」のように「-」で 3 つ以上つないだ数字（電話番号など）は、金額にも日付にもしない。
                if separator == "-", eraBase == nil {
                    var end = c.end
                    while end + 1 < n, chars[end] == "-", let next = digitRun(at: end + 1) { end = next.end }
                    consume(i..<end)
                    return end
                }
            }
            if eraBase == nil, a.length <= 2, b.length <= 2 {
                let days = DateExpression.daysAgo(month: a.value, day: b.value, now: now, calendar: calendar)
                // 後ろに人数や数量の語が続くもの（「3-4人」「2-3個」）は幅で、日付ではない。
                let followedByQuantity = Self.startsQuantity(chars, at: b.end)
                switch separator {
                case "/":
                    // 1〜2 桁どうしを「/」でつないだものは、日付として成り立たなくても（9/31、13/5）使い終える。
                    // 残すと、数字が金額になり、「/」で別の件にも分かれて、余計な記録が黙って増えるため。
                    return consumeDate(i..<b.end, daysAgo: days)
                case "-" where days != nil && isDateContext && !followedByQuantity:
                    return consumeDate(i..<b.end, daysAgo: days)
                case "." where days != nil && isDateContext && !followedByQuantity && b.length == 2
                    && !isDecimalAmount(endingAt: b.end):
                    // 「.」でつないだ月日は、日を 2 桁で書いたとき（「9.26」「10.05」）だけ日付にする。
                    // 「1.5」「10.5」は小数として書くことが多く、日付として読むと何か月も前や先の記録に黙ってなるため。
                    // 「8.5万」「1.5L」のように位や単位が続くものも小数として読む。
                    return consumeDate(i..<b.end, daysAgo: days)
                default:
                    break
                }
            }
        }

        // 「12:30」。時刻は金額にも区切りにもしない。
        if a.length <= 2, a.value <= 24, a.end < n, chars[a.end] == ":", let b = digitRun(at: a.end + 1),
           b.length == 2, b.value <= 59 {
            consume(i..<b.end)
            return b.end
        }

        // 「26日」。日だけのときは今月のその日。「3日間」「1日分」「2日目」「3日後」「2泊3日」は期間や順番、
        // 「1日1回」「1日あたり」は割合なので読まない。
        if eraBase == nil, a.length <= 2, (1...31).contains(a.value), has("日", at: a.end),
           !(a.end + 1 < n && Self.dayCountSuffixes.contains(chars[a.end + 1])), !(i >= 1 && chars[i - 1] == "泊"),
           !Self.perDayWords.contains(where: { has($0, at: a.end + 1) }),
           !(digitRun(at: a.end + 1).map { Self.startsQuantity(chars, at: $0.end) } ?? false) {
            let days = DateExpression.daysAgo(day: a.value, now: now, calendar: calendar)
            return consumeDate(i..<(a.end + 1), daysAgo: days)
        }
        return nil
    }

    /// 「9.26」の後ろに位や単位が続き、小数（「8.5万」「1.5L」）として読むべきか。
    private func isDecimalAmount(endingAt end: Int) -> Bool {
        guard end < chars.count else { return false }
        if Self.smallUnits[chars[end]] != nil || Self.bigUnits[chars[end]] != nil || chars[end] == "円" { return true }
        return Self.counters.contains { has($0, at: end) }
    }

    /// 日付の表記を使い終え、直後の助詞も一緒に使い終える。その後ろの位置を返す。
    ///
    /// 「昨日の飲み会」の「の」を残すと、メモが「の飲み会」になるため（助詞の見分け方は `takesParticle(at:)`）。
    /// 日付として成り立たないもの（`daysAgo` が nil）は、金額としては読まないが、メモには残す（`unreadDate`）。
    @discardableResult
    private mutating func consumeDate(_ range: Range<Int>, daysAgo: Int?) -> Int {
        var end = range.upperBound
        if end < chars.count, !consumed[end], takesParticle(at: end) {
            end += 1
        }
        consume(range.lowerBound..<end)
        if daysAgo == nil {
            for j in range.lowerBound..<end { unreadDate[j] = true }
        }
        dates.append(DatePhrase(range: range.lowerBound..<end, daysAgo: daysAgo))
        return end
    }

    /// 日付の直後の `i` の文字が、日付と一緒に使い終える助詞（「の」「は」「も」「に」）か。
    ///
    /// 次がひらがなのときは、語の頭（「昨日のり」「今日はちみつ」「昨日もやし」「昨日にんじん」）のことがあるので分けて見る。
    /// - 次が「お」「ご」（「昨日のお茶」「今日もご飯」）なら助詞。語の頭に付く丁寧の「お」「ご」なので
    /// - 「の」「は」は、続くひらがなが 1 文字だけ（「のり」「のど飴」「のみ」）か、知っている語（「はちみつ」）なら語の頭。
    ///   それ以外（「昨日のうどん」「昨日はそば」）は助詞。助詞として使うことが多いので、語の頭とみなすのは狭くする
    /// - 「も」「に」は語の頭とみなす（「もやし」「にんじん」「にら」）
    private func takesParticle(at i: Int) -> Bool {
        let c = chars[i]
        guard Self.dateParticles.contains(c) else { return false }
        guard i + 1 < chars.count, Self.isHiragana(chars[i + 1]) else { return true }
        if Self.honorificPrefixes.contains(chars[i + 1]) { return true }
        guard c == "の" || c == "は" else { return false }
        var runEnd = i + 1
        while runEnd < chars.count, Self.isHiragana(chars[runEnd]) { runEnd += 1 }
        if runEnd - (i + 1) == 1 { return false }
        return !Self.wordsStartingWithParticle.contains(String(chars[i..<runEnd]))
    }

    /// `i` から始まる、使い終えていない半角数字の並び。数字の途中からは読まない。
    private func digitRun(at i: Int) -> (value: Int, end: Int, length: Int)? {
        guard i < chars.count, chars[i].isASCIIDigit, !consumed[i],
              i == 0 || !chars[i - 1].isASCIIDigit
        else { return nil }
        var end = i
        var value = 0
        while end < chars.count, chars[end].isASCIIDigit, !consumed[end] {
            // 桁が多すぎるもの（電話番号など）は日付にならないので、桁あふれする前に打ち切る。
            guard end - i < Self.maximumDigits else { return nil }
            value = value * 10 + Int(chars[end].asciiValue! - 0x30)
            end += 1
        }
        return (value, end, end - i)
    }

    // MARK: - 金額と人数

    private mutating func scanAmounts() {
        let numbers = Self.numbers(in: chars, skipping: consumed)
        // 記号のすぐ後ろの数字（「コーヒー×2 800」の 2）。ほかに金額があれば個数とみなして捨てる。
        var afterMultiplySign: [Amount] = []
        var k = 0
        while k < numbers.count {
            let number = numbers[k]
            let end = number.range.upperBound

            // 「4人」「4名」。割り勘の語があるかは後で見る。「3人前」は量なので人数にしない。
            if number.isPlainInteger, !number.hasLeadingZero,
               (has("人", at: end) && !has("人前", at: end)) || has("名", at: end) {
                let upper = has("で", at: end + 1) ? end + 2 : end + 1
                // 「3-4人」の「3-」も人数の表記に含める（下の幅の読み方で金額にしなかった数字を、メモにも残さない）。
                var lower = number.range.lowerBound
                if k >= 1, isQuantityRange(numbers[k - 1], number) { lower = numbers[k - 1].range.lowerBound }
                people.append((number.value, lower..<upper))
                k += 1
                continue
            }
            // 「3-4人」「2〜3個」の 3・2 は人数や数量の幅の下限で、金額ではない（上限の方を人数や数量として読む）。
            if k + 1 < numbers.count, isQuantityRange(number, numbers[k + 1]) {
                k += 1
                continue
            }
            // 「500×3」。単価と個数を掛けた額を 1 つの金額にする。個数を金額として採らないため。
            if k + 1 < numbers.count, let product = product(of: number, and: numbers[k + 1]) {
                amounts.append(product)
                k += 2
                continue
            }
            if let amount = amount(from: number) {
                // 「×2」「x2」のように記号に続けて書いた数字は、個数のことが多い（前に単価が無い「コーヒー×2 800」）。
                // ほかに金額が無ければ金額として読む（「x 500」「×500」を「金額が無い」にしない）。
                let lower = number.range.lowerBound
                if lower >= 1, isMultiplySign(at: lower - 1), amount.range.lowerBound == lower {
                    afterMultiplySign.append(amount)
                } else {
                    amounts.append(amount)
                }
            }
            k += 1
        }
        if amounts.isEmpty { amounts = afterMultiplySign }
    }

    /// `low` と `high` が「3-4人」「2〜3個」のような、人数や数量の幅か。
    private func isQuantityRange(_ low: NumberToken, _ high: NumberToken) -> Bool {
        let sign = low.range.upperBound
        guard low.isPlainInteger, high.isPlainInteger, sign < chars.count, Self.rangeSigns.contains(chars[sign]),
              !consumed[sign], high.range.lowerBound == sign + 1
        else { return false }
        return Self.startsQuantity(chars, at: high.range.upperBound)
    }

    /// 数字 1 つを金額として読む。量・日時・小数・電話番号などで金額でなければ nil。
    private func amount(from number: NumberToken) -> Amount? {
        let end = number.range.upperBound
        var upper = end
        var hasYenSuffix = false
        // 後ろの「円」（「850 円」のように空白を挟んでも含める）。
        if let next = nextNonSpace(from: end), chars[next] == "円", !consumed[next] {
            upper = next + 1
            hasYenSuffix = true
        } else if Self.counters.contains(where: { has($0, at: end) }) {
            // 「2杯」「3個」は数量で、金額ではない。
            return nil
        }
        // 小数は、位（万・千）か「円」が付くときだけ金額にする。「3.14」のような数字を金額にしないため。
        if number.hasFraction, !number.hasUnit, !hasYenSuffix { return nil }
        // 先頭が 0 の 2 桁以上（「09012345678」）は電話番号などで、金額ではない。
        if number.hasLeadingZero { return nil }
        guard number.value > 0 else { return nil }
        let prefix = amountPrefix(before: number.range.lowerBound)
        return Amount(
            value: number.value, range: prefix.lowerBound..<upper,
            isPerPerson: prefix.isPerPerson, isNegative: prefix.isNegative
        )
    }

    /// 「500×3」「400 ×2」「3x500円」を、掛けた額の金額にする。掛け算の形でなければ nil。
    private func product(of left: NumberToken, and right: NumberToken) -> Amount? {
        // どちらかが個数（1〜999 の整数）のときだけ掛ける。「1200×1500」のような寸法を金額にしないため。
        let isQuantity = { (token: NumberToken) in token.isPlainInteger && !token.hasLeadingZero && (1...999).contains(token.value) }
        var j = left.range.upperBound
        if has("円", at: j) {
            j += 1
        } else if isQuantity(left), let counter = Self.counters.first(where: { has($0, at: j) }) {
            j += counter.count   // 「2個×300」
        }
        guard let sign = nextNonSpace(from: j), isMultiplySign(at: sign),
              let rightStart = nextNonSpace(from: sign + 1), rightStart == right.range.lowerBound
        else { return nil }
        guard isQuantity(left) || isQuantity(right), left.value > 0, right.value > 0,
              !(left.hasFraction && !left.hasUnit), !(right.hasFraction && !right.hasUnit)
        else { return nil }
        let (value, overflow) = left.value.multipliedReportingOverflow(by: right.value)
        guard !overflow, value <= Self.maximumValue else { return nil }
        var upper = right.range.upperBound
        if let next = nextNonSpace(from: upper), chars[next] == "円" {
            upper = next + 1
        } else if let counter = (Self.counters + ["人", "名"]).first(where: { has($0, at: upper) }) {
            // 「500×3本」の「本」、「850 × 2人」の「人」も金額の範囲に含め、メモに残さない。
            upper += counter.count
        }
        let prefix = amountPrefix(before: left.range.lowerBound)
        // 単価は個数でない方。どちらも個数の形（「3×500」）なら大きい方。
        let unitPrice = isQuantity(left) && isQuantity(right) ? max(left.value, right.value)
            : isQuantity(left) ? right.value : left.value
        return Amount(
            value: value, range: prefix.lowerBound..<upper,
            isPerPerson: prefix.isPerPerson, isNegative: prefix.isNegative, unitPrice: unitPrice
        )
    }

    /// 金額の前に付く「¥」「-」「1人あたり」を読み、金額の範囲の始まりを返す。
    private func amountPrefix(before start: Int) -> (lowerBound: Int, isPerPerson: Bool, isNegative: Bool) {
        var lower = start
        var isNegative = false
        // 「-500」「返金-500」「¥-500」「-¥500」「返金 ー500」。
        func takeMinus() {
            guard lower > 0, !consumed[lower - 1] else { return }
            let before: Character? = lower >= 2 ? chars[lower - 2] : nil
            switch chars[lower - 1] {
            case "-":
                // 数字どうしの間の「-」（「9-26」「03-1234」）と、英字に続けた「-」（型番）は符号にしない。
                guard before.map({ !$0.isASCIIDigit && !$0.isASCIILetter }) ?? true else { return }
            case "ー":
                // 日本語の入力では「-」が長音記号「ー」になる。語から離して置いたときだけ符号にする。
                // 「コーヒー500」の「ー」は語の一部。
                guard before.map({ $0.isWhitespace || Self.yenMarks.contains($0) || Self.openingPunctuation.contains($0) })
                        ?? true
                else { return }
            default:
                return
            }
            isNegative = true
            lower -= 1
        }
        takeMinus()
        if let previous = previousNonSpace(before: lower), Self.yenMarks.contains(chars[previous]), !consumed[previous] {
            lower = previous
            if !isNegative { takeMinus() }
        }
        // 「1人あたり3000」「一人 3000」。
        var isPerPerson = false
        let beforePrefix = previousNonSpace(before: lower).map { $0 + 1 } ?? lower
        for prefix in Self.perPersonPrefixes {
            let length = prefix.count
            let prefixStart = beforePrefix - length
            guard prefixStart >= 0, has(prefix, at: prefixStart),
                  !(prefixStart..<beforePrefix).contains(where: { consumed[$0] }),
                  prefixStart == 0 || !chars[prefixStart - 1].isASCIIDigit
            else { continue }
            isPerPerson = true
            lower = prefixStart
            break
        }
        return (lower, isPerPerson, isNegative)
    }

    private func isMultiplySign(at i: Int) -> Bool {
        guard !consumed[i] else { return false }
        if Self.multiplySigns.contains(chars[i]) { return true }
        // 英字の x は、英単語の一部（「max」）でないときだけ。
        guard chars[i] == "x" || chars[i] == "X" else { return false }
        return !(i > 0 && chars[i - 1].isASCIILetter) && !(i + 1 < chars.count && chars[i + 1].isASCIILetter)
    }

    // MARK: - 割り勘

    /// 割り勘の語ごとに、最も近い「N人」（2〜100 人）を組にする。
    ///
    /// 人数だけでは割り勘とみなさない（「4人でランチ 4000」は 4000 円を払ったのかもしれない）。
    /// 最も近い人数を採るのは、「友達3人と焼肉 12000 4人で割り勘」の 3 人で割らないため。
    private mutating func scanSplits() {
        var used = Set<Int>()
        for word in splitWordRanges() {
            let nearest = people.indices
                .filter { !used.contains($0) && (2...100).contains(people[$0].count) }
                .min { distance(people[$0].range, word) < distance(people[$1].range, word) }
            guard let nearest else { continue }
            used.insert(nearest)
            splits.append(SplitPhrase(count: people[nearest].count, wordRange: word, countRange: people[nearest].range))
        }
    }

    /// 割り勘の語の位置（入力の順）。
    private func splitWordRanges() -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var i = 0
        while i < chars.count {
            if !consumed[i], let word = Self.splitWords.first(where: { has($0, at: i) }) {
                ranges.append(i..<(i + word.count))
                i += word.count
            } else {
                i += 1
            }
        }
        return ranges
    }

    private func distance(_ a: Range<Int>, _ b: Range<Int>) -> Int {
        if a.upperBound <= b.lowerBound { return b.lowerBound - a.upperBound }
        if b.upperBound <= a.lowerBound { return a.lowerBound - b.upperBound }
        return 0
    }

    // MARK: - 数字の読み取り

    struct NumberToken: Equatable {
        var value: Int
        var range: Range<Int>
        /// 小数点も「万」「千」などの位も含まない整数か。日付や人数はこの形のときだけ読む。
        var isPlainInteger: Bool
        var hasFraction: Bool
        /// 「万」「千」などの位を含むか。
        var hasUnit: Bool
        /// 「090」のように 0 で始まる 2 桁以上の数字か。
        var hasLeadingZero: Bool
    }

    /// 「850」「1.5万」「25万」「1万2千500」「1千万」「5百」「1億2000万」を数に直して、位置とともに返す。
    ///
    /// 十・百・千を 1 つの「万のまとまり」の中で足し合わせ、万・億でまとまりを繰り上げる。
    /// 「1万5」「3千5」は話し言葉で 15000 / 3500 を指すので、位の後ろが 1 桁だけのときは 1 つ下の位として読む。
    /// `skipping` が真の文字（日付として使い終えた数字など）は読まない。
    static func numbers(in chars: [Character], skipping skipped: [Bool]) -> [NumberToken] {
        func isDigit(_ i: Int) -> Bool { i < chars.count && !skipped[i] && chars[i].isASCIIDigit }
        var result: [NumberToken] = []
        var i = 0
        while i < chars.count {
            guard isDigit(i) else {
                i += 1
                continue
            }
            let start = i
            let head = decimal(in: chars, skipping: skipped, from: i)
            i = head.end
            guard let headValue = head.value else { continue }

            var total: Decimal = 0          // 万・億で繰り上げた分
            var group: Decimal = 0          // いまの万のまとまり（千・百・十で足した分）
            var pending: Decimal? = headValue  // まだ位を付けていない数字
            var lastUnit: Decimal = 1       // 直前に使った位
            var smallLimit: Decimal = 10_000   // まとまりの中で次に使える位の上限（千→百→十の順）
            var bigLimit = Decimal.greatestFiniteMagnitude  // 次に使える大きな位の上限（億→万の順）
            var hasUnit = false
            var hasFraction = head.hasFraction
            var end = i

            func acceptsUnit(at index: Int) -> Bool {
                guard index < chars.count, !skipped[index] else { return false }
                if let unit = smallUnits[chars[index]] { return unit < smallLimit }
                if let unit = bigUnits[chars[index]] { return unit < bigLimit }
                return false
            }

            while acceptsUnit(at: i) {
                if let unit = smallUnits[chars[i]] {
                    guard let value = pending else { break }
                    group += value * unit
                    smallLimit = unit
                    lastUnit = unit
                } else if let unit = bigUnits[chars[i]] {
                    guard pending != nil || group > 0 else { break }
                    total += (group + (pending ?? 0)) * unit
                    group = 0
                    smallLimit = 10_000
                    bigLimit = unit
                    lastUnit = unit
                }
                pending = nil
                hasUnit = true
                i += 1
                end = i
                // 位の後ろの数字。次にまた位が続けばその位の数、続かなければ末尾の端数として読む。
                guard isDigit(i) else { continue }
                let rest = decimal(in: chars, skipping: skipped, from: i)
                guard let restValue = rest.value else { break }
                if acceptsUnit(at: rest.end) {
                    pending = restValue
                    hasFraction = hasFraction || rest.hasFraction
                    i = rest.end
                    continue
                }
                // 「1万2人」の 2 は人数なので、位の続きにしない。
                if startsQuantity(chars, at: rest.end) { break }
                if rest.digitCount == 1, !rest.hasFraction, lastUnit >= 10 {
                    group += restValue * (lastUnit / 10)   // 「1万5」「3千5」
                } else if restValue < lastUnit {
                    group += restValue                      // 「1万2000」「3千500」
                } else {
                    break                                   // 「1万20000」は別の数として読む
                }
                hasFraction = hasFraction || rest.hasFraction
                end = rest.end
                break
            }
            if !hasUnit, let value = pending { group += value }
            i = end

            if let int = roundedInt(total + group) {
                result.append(NumberToken(
                    value: int, range: start..<end,
                    isPlainInteger: !hasUnit && !hasFraction,
                    hasFraction: hasFraction,
                    hasUnit: hasUnit,
                    hasLeadingZero: chars[start] == "0" && head.digitCount >= 2
                ))
            }
        }
        return result
    }

    /// `from` から始まる「123」「1.5」を読む。桁が多すぎるもの（電話番号など）は value が nil。
    private static func decimal(
        in chars: [Character], skipping skipped: [Bool], from start: Int
    ) -> (value: Decimal?, end: Int, digitCount: Int, hasFraction: Bool) {
        func isDigit(_ i: Int) -> Bool { i < chars.count && !skipped[i] && chars[i].isASCIIDigit }
        var i = start
        while isDigit(i) { i += 1 }
        let integerDigits = i - start
        var hasFraction = false
        if i < chars.count, chars[i] == ".", !skipped[i], isDigit(i + 1) {
            hasFraction = true
            i += 1
            while isDigit(i) { i += 1 }
        }
        guard integerDigits <= maximumDigits else { return (nil, i, integerDigits, hasFraction) }
        let value = Decimal(string: String(chars[start..<i]), locale: Locale(identifier: "en_US_POSIX"))
        return (value, i, integerDigits, hasFraction)
    }

    private static func roundedInt(_ value: Decimal) -> Int? {
        guard value >= 0, value <= Decimal(maximumValue) else { return nil }
        return Int(NSDecimalNumber(decimal: value).doubleValue.rounded())
    }

    /// `index` から人数や数量の語（「人」「名」「本」「杯」…）が始まるか。
    private static func startsQuantity(_ chars: [Character], at index: Int) -> Bool {
        let rest = chars[min(index, chars.count)...]
        return (["人", "名"] + counters).contains { rest.starts(with: $0) }
    }

    // MARK: - 補助

    private func has(_ word: String, at index: Int) -> Bool {
        guard index >= 0 else { return false }
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

    /// `index` から空白を読み飛ばした位置（空白でなければ `index` のまま）。
    private func skippingSpaces(from index: Int) -> Int {
        nextNonSpace(from: index) ?? chars.count
    }

    /// `index` 以降で最初の空白でない文字の位置。
    private func nextNonSpace(from index: Int) -> Int? {
        var i = index
        while i < chars.count, chars[i].isWhitespace { i += 1 }
        return i < chars.count ? i : nil
    }

    /// `index` より前で最後の空白でない文字の位置。
    private func previousNonSpace(before index: Int) -> Int? {
        var i = index - 1
        while i >= 0, chars[i].isWhitespace { i -= 1 }
        return i >= 0 ? i : nil
    }

    private static func isKatakana(_ c: Character) -> Bool {
        guard let scalar = c.unicodeScalars.first, c.unicodeScalars.count == 1 else { return false }
        return (0x30A1...0x30FA).contains(scalar.value) || scalar.value == 0x30FC
    }

    private static func isHiragana(_ c: Character) -> Bool {
        guard let scalar = c.unicodeScalars.first, c.unicodeScalars.count == 1 else { return false }
        return (0x3041...0x3096).contains(scalar.value)
    }

    // MARK: - 辞書

    /// 12 桁（1 兆円未満）を超える数字は金額とみなさない。家計簿の 1 件としてありえず、
    /// 電話番号やカード番号の貼り付けを金額にしてしまうのを防ぐため。
    /// 上限の額は、記録を直すシートで保存できる上限（`EntryAmountInput.maximumAmount`）と同じものを使う
    /// （ひとことで記録できた額を、直すときに保存できないことがないように）。
    private static let maximumDigits = String(EntryAmountInput.maximumAmount).count
    private static let maximumValue = EntryAmountInput.maximumAmount

    private static let smallUnits: [Character: Decimal] = ["十": 10, "百": 100, "千": 1_000]
    private static let bigUnits: [Character: Decimal] = ["万": 10_000, "億": 100_000_000]

    /// 長い語を先に置く（「一昨日」を「昨日」より先に見ないと、1 日ずれる）。
    /// ひらがなの「きょう」は「きょうだい」などに当たるので入れない（今日は既定値なので困らない）。
    private static let dateWords: [(String, Int)] = [
        ("一昨日", 2), ("おととい", 2), ("おとつい", 2), ("昨日", 1), ("きのう", 1), ("今日", 0), ("本日", 0),
    ]

    /// 日付の直後にあれば、日付と一緒に使い終える助詞（`takesParticle(at:)`）。
    private static let dateParticles: Set<Character> = ["の", "は", "も", "に"]
    /// 語の頭に付く丁寧の「お」「ご」。日付の後ろの助詞の次にあれば、助詞の方を使い終える（「昨日のお茶」）。
    private static let honorificPrefixes: Set<Character> = ["お", "ご"]
    /// 「の」「は」で始まり、ひらがなで書くことのある品目。日付の直後にあっても、頭の「の」「は」を助詞として取らない。
    /// ひらがなの続きがちょうどこの語のときだけ当てる（「のりんご」は「の」＋「りんご」）。
    private static let wordsStartingWithParticle: Set<String> = [
        "のりたま", "のどあめ", "のみもの", "はちみつ", "はみがき", "はぶらし", "はさみ", "はがき", "はんこ",
        "はんかち", "はまぐり", "はるさめ",
    ]
    /// 「N日」の後ろにあれば、日付ではなく期間や順番（「3日間」「1日分」「2日目」「3日後」）。
    private static let dayCountSuffixes: Set<Character> = ["前", "間", "分", "目", "後"]

    /// 「N日」の後ろにあれば、日付ではなく割合（「1日あたり」）。
    private static let perDayWords = ["あたり", "当たり", "につき", "ごと"]

    /// 年月日をつなぐ記号。
    private static let dateSeparators: Set<Character> = ["/", "-", "."]
    /// 和暦の略記（「R7/9/26」）と、その元号の 0 年にあたる西暦。
    private static let eraLetters: [Character: Int] = ["R": 2018, "r": 2018, "H": 1988, "h": 1988]
    private static let eraWords: [(name: String, base: Int)] = [("令和", 2018), ("平成", 1988)]

    private static let splitWords = ["割り勘", "割勘", "わりかん", "ワリカン"]

    private static let yenMarks: Set<Character> = ["¥", "\\"]
    /// 人数や数量の幅（「3-4人」「2〜3個」）をつなぐ記号。
    private static let rangeSigns: Set<Character> = ["-", "~", "〜"]
    /// 長音記号「ー」の前にあっても符号として読む記号。
    private static let openingPunctuation: Set<Character> = ["(", "（", "[", "「", ":", "：", "="]
    private static let multiplySigns: Set<Character> = ["×", "✕", "*"]

    /// 1 人分の額を表す、金額の前の言い回し。長いものを先に置く。
    private static let perPersonPrefixes = [
        "1人あたり", "1人当たり", "1人につき", "1人分", "1人", "1名あたり", "1名当たり", "1名",
        "一人あたり", "一人当たり", "一人につき", "一人分", "一人",
        "ひとりあたり", "ひとり当たり", "ひとりにつき", "ひとり分", "ひとり",
    ]

    /// いつでも区切りとみなし、文の区切りにもなる記号。「・」は「光熱・通信」のように語の中でも使うので入れない。
    private static let clauseSeparators: Set<Character> = ["、", ",", "。", "\n", "\r", ";", "/"]
    /// いつでも区切りとみなすが、同じ文の中の区切りとして扱う記号。
    /// 「と」と空白は金額の直後だけ区切る（`isWeakSeparator(at:)`）。
    private static let weakSeparators: Set<Character> = ["+"]

    /// メモの前後から取り除く記号。
    private static let trimmedEdges = CharacterSet.whitespacesAndNewlines
        .union(CharacterSet(charactersIn: "、,。.・/:;+-"))

    private static let trailingParticles: Set<Character> = ["を", "で"]

    /// 数字の直後にあれば、その数字は量や日時であって金額ではない。
    private static let counters = [
        "個", "本", "杯", "枚", "回", "泊", "冊", "点", "着", "足", "台", "缶", "箱", "袋", "皿", "錠", "粒",
        "匹", "頭", "羽", "部", "巻", "話", "席", "件", "人前", "時", "分", "秒", "日", "週", "ヶ月", "ヵ月",
        "ケ月", "カ月", "か月", "月", "年", "歳", "才", "度", "番", "階", "号", "位", "割", "倍", "均", "%",
        "kg", "g", "mg", "ml", "mL", "l", "L", "km", "m", "cm", "mm", "GB", "インチ",
        "ミリ", "センチ", "メートル", "キロ", "グラム", "リットル", "ギガ", "パック", "セット", "ダース",
        "カートン", "ポイント", "pt", "ページ", "カロリー", "kcal",
    ]
}

extension Character {
    /// 半角の英字か。
    var isASCIILetter: Bool {
        guard let ascii = asciiValue else { return false }
        return (0x41...0x5A).contains(ascii) || (0x61...0x7A).contains(ascii)
    }
}
