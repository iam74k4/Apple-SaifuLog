import Foundation

/// 一行の入力を、1 件ずつの区間（`InputSegment`）に分けたもの。
///
/// 区切り方はコードで決め、端末内 AI には区間ごとに 1 件ずつ読ませる。1 回の生成で記録の配列を返させると、
/// 1 件の入力にも余分な要素や同じ記録の繰り返しが返り、そのまま保存されてしまうため。
/// AI の結果は `ExtractedEntry.resolveAll(_:against:)`（全件）か `ExtractedEntry.resolved(against:)`（1 件）で
/// この区間と突き合わせてから使う。
///
/// ルールベースの解析（`RuleBasedParser`）も同じ区間から記録を作る。どちらで読んでも件の分け方と、
/// 件ごとの日付・割り勘の割り当てが変わらないようにするため。
public struct EntryInput: Sendable, Hashable {
    /// 元の入力。
    public let text: String
    /// 1 件ずつの区間（入力の順）。金額が 1 つも無ければ空。
    public let segments: [InputSegment]

    /// - Parameters:
    ///   - now: 「昨日」「9/26」を解釈する基準の日時。
    ///   - calendar: タイムゾーンだけを使う（日付はグレゴリオ暦で数える。`DateExpression`）。
    public init(_ text: String, now: Date, calendar: Calendar) {
        self.text = text
        let scan = EntryScan(TextNormalizer.normalize(text), now: now, calendar: calendar)
        segments = scan.segments().enumerated().map { index, segment in
            InputSegment(index: index, scan: scan, segment: segment, now: now, calendar: calendar)
        }
    }

    /// 区間ごとにルールベースで読んだ記録（`RuleBasedParser` と同じ結果）。
    public var ruleBasedEntries: [ParsedEntry] {
        segments.map(\.ruleBasedEntry)
    }
}

/// 入力のうち 1 件分の区間。
public struct InputSegment: Sendable, Hashable {
    /// 入力の中で何件目か（0 から）。
    public let index: Int
    /// この件の区間の文字列（表記ゆれをそろえた入力の一部）。AI にはこれを 1 件として読ませる。
    ///
    /// 「昨日 スーパー2480とドラッグ1200」の 2 件目は「ドラッグ1200」で、「昨日」を含まない。
    /// 日付や割り勘がほかの件に書かれていても、突き合わせ（`ExtractedEntry.resolved(against:)`）で
    /// この件に割り当てた日付・人数を使うので、区間に書かれていなくてよい。
    public let text: String
    /// この区間をルールベースで読んだ記録。AI がこの件だけ読めなかったときの代わりにも使える。
    public let ruleBasedEntry: ParsedEntry

    /// 区間の中の金額と、その金額を採ったときのメモ（金額・割り勘の語を除いた残り）。採らない額（`isSupplementary`。
    /// 値引きの説明・税抜きの値段・合計・おつり・ポイント）も含む。
    let candidates: [Candidate]
    /// ルールベースで採った金額の位置（`candidates` の添字）。
    let chosenIndex: Int
    /// この件の日付（何日前か）。日付が無ければ nil（今日）。
    let daysAgo: Int?
    /// 区間に書かれた日付と、この件に割り当てた日付。
    let dateCandidates: [Int]
    /// この件にかかる割り勘の人数。1 人分の額にはかけない。
    let splitCount: Int?
    /// 区間の文字列から、日付など使い終えた部分を除いたもの。収入やカテゴリの判定に使う。
    let contextText: String
    /// ルールベースで推定したカテゴリ。
    let ruleCategory: EntryCategory
    let now: Date
    let calendar: Calendar

    struct Candidate: Sendable, Hashable {
        var amount: EntryScan.Amount
        /// この金額を採ったときに記録する額。マイナスを付けない値引き（「850 100円引き」）を引いた額。
        var value: Int
        var memo: String
    }

    init(index: Int, scan: EntryScan, segment: EntryScan.Segment, now: Date, calendar: Calendar) {
        self.index = index
        self.now = now
        self.calendar = calendar
        var text = String(scan.chars[segment.range]).trimmingCharacters(in: Self.trimmedEdges)
        // 「スーパー2480 と ドラッグ1200」の 2 件目の頭に 1 語で残る「と」は落とす。
        if text.hasPrefix("と ") {
            text = text.dropFirst().trimmingCharacters(in: Self.trimmedEdges)
        }
        self.text = text
        daysAgo = segment.daysAgo
        dateCandidates = segment.dateCandidates
        splitCount = segment.split?.count
        contextText = scan.text(in: segment.range)
        ruleCategory = EntryCategory.guess(from: contextText)

        let splitRanges = segment.split.map { [$0.wordRange, $0.countRange] } ?? []
        let amountRanges = segment.amounts.map(\.range)
        // 税抜きの値段・合計・おつりは、どの金額を採ってもメモから除く（記録した額と違う金額が並んで紛らわしいため）。
        let omittedRanges = segment.amounts.filter(\.role.isOmittedFromMemo).map(\.range)
        candidates = segment.amounts.indices.map { k in
            let amount = segment.amounts[k]
            // 割り勘の語と人数はメモから除く（割った内容は assemble が書き足す）。
            // 1 人分の額を採るときは、区間のほかの金額（総額）も除く。残すと「焼肉 12000」のように、記録した額と
            // 違う金額がメモに並ぶため。1 人分であることも assemble が「（4人で割り勘・1人分）」と書き足す。
            let excluded = (amount.isPerPerson ? amountRanges : [amount.range]) + splitRanges + omittedRanges
            return Candidate(
                amount: amount, value: segment.recordedValue(at: k),
                memo: scan.text(in: segment.range, excluding: excluded)
            )
        }
        chosenIndex = candidates.firstIndex { $0.amount == segment.amount } ?? candidates.count - 1

        let chosen = candidates[chosenIndex]
        ruleBasedEntry = ParsedEntry.assemble(
            total: chosen.value,
            category: ruleCategory,
            isIncome: chosen.amount.isNegative || IncomeRule.isIncome(contextText),
            item: chosen.memo,
            daysAgo: segment.daysAgo ?? 0,
            splitCount: splitCount ?? 1,
            isPerPerson: chosen.amount.isPerPerson
        )
    }

    /// `value` 円の金額が区間に書かれていれば、その金額。ルールベースで採った金額を優先する。
    ///
    /// 掛け算（「500×3」）は、単価の 500 でも掛けた額の 1500 でも、掛けた額の金額と突き合わせる。
    /// 個数の 3 は突き合わせない。その件の金額に採らない額（`isSupplementary`。「ランチ 850(-100引き)」の 100、
    /// 「1000円 (税込1100円)」の 1000、「850 100円引き」の 100、合計・おつり・ポイント）も突き合わせない。
    /// その額を記録すると、850 円の支出が 100 円の記録になるため（ルールベースで読み直させる）。
    func candidate(matching value: Int) -> Candidate? {
        let matches = { (candidate: Candidate) in
            !candidate.amount.isSupplementary
                && (candidate.amount.value == value || candidate.amount.unitPrice == value)
        }
        if matches(candidates[chosenIndex]) { return candidates[chosenIndex] }
        return candidates.first(where: matches)
    }

    /// AI が返した品目が区間に書かれた言葉なら、メモにする品目を返す。
    ///
    /// - 品目そのものが、ルールベースのメモ（`memo`。その件の金額・日付・割り勘の語を除いた区間の文字列）に
    ///   含まれていれば、品目をそのまま返す。「セブン11」「100円ショップ」のように数字を含む店名や品名から、
    ///   数字を抜いて「セブン」「ショップ」にしないため（ルールベースのメモと食い違わないように）
    /// - そうでなければ、品目から金額・日付・人数・割り勘の語を除いたもの（「昨日の焼肉 12000」→「焼肉」）が
    ///   区間に書かれていれば、それを返す
    /// - 除くと空になるとき（「昨日」だけ）や、区間に無い言葉（指示文の一部や作った品目）なら nil
    ///
    /// どちらも、空白の有無とひらがな・カタカナの違いは問わない（「ドラッグ ストア」「らんち」）。
    func groundedItem(from modelItem: String, memo: String) -> String? {
        let cleaned = EntryScan(TextNormalizer.normalize(modelItem), now: now, calendar: calendar).textWithoutNumbers()
        guard !cleaned.isEmpty else { return nil }
        let original = TextNormalizer.normalize(modelItem).trimmingCharacters(in: .whitespacesAndNewlines)
        if Self.folded(memo).contains(Self.folded(original)) { return original }
        return Self.folded(text).contains(Self.folded(cleaned)) ? cleaned : nil
    }

    /// 照合用に、空白を除いてひらがな・カタカナと英字の大小をそろえた文字列。
    private static func folded(_ text: String) -> String {
        KeywordMatcher.fold(text.filter { !$0.isWhitespace })
    }

    private static let trimmedEdges = CharacterSet.whitespacesAndNewlines
        .union(CharacterSet(charactersIn: "、,。/;+"))
}
