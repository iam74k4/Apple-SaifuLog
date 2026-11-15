import Foundation

/// 利用者が登録したクレジットカード（名前・締め日・引き落とし日）。docs/design.md §8-2 のカードの決め事。
///
/// 保存の型（アプリの `PaymentCardRow`）から値だけを渡す。記録はカードの ID だけを持つ（`CardLedgerRecord.cardID`）ので、
/// 名前や日付を変えても記録は書き換えない。カードの記録は、使った日の支出として数える（今月使った額・予算・まとめはこれまでどおり）。
/// カードの締めと引き落としは、その支出をいつ払うかの見通しで、引き落としを支出として記録し直すことはしない（二重に数えるため）。
public struct PaymentCard: Sendable, Hashable, Identifiable {
    /// ID（作った端末で UUID から決める）。記録の `cardID` が指す。
    public var id: String
    /// 名前（「楽天カード」「メインのカード」）。文に書くと、そのカードで払った記録にする（`PaymentLinker`）。
    public var name: String
    /// 締め日（1〜31。31 と、その月に無い日は月末）。
    public var closingDay: Int
    /// 引き落とし日（1〜31。31 と、その月に無い日は月末）。
    public var paymentDay: Int
    /// 締めた月から何か月後に引き落とすか（1 = 翌月、2 = 翌々月）。
    public var paymentMonthOffset: Int
    /// いつものカードか。「カードで」「クレカで」のように名前を書かずにカードと書いた記録を、このカードにする。
    public var isDefault: Bool

    public init(id: String, name: String, closingDay: Int, paymentDay: Int, paymentMonthOffset: Int = 1, isDefault: Bool = false) {
        self.id = id
        self.name = name
        self.closingDay = closingDay
        self.paymentDay = paymentDay
        self.paymentMonthOffset = paymentMonthOffset
        self.isDefault = isDefault
    }

    /// 締め日・引き落とし日に選べる日（31 は月末）。
    public static let dayRange = 1...31
    /// 引き落とす月（締めた月の何か月後か）に選べる値。
    public static let monthOffsetRange = 1...2
    /// 登録できるカードの数。
    public static let maximumCount = 10
    /// 名前の長さの上限（文字数）。返事の行と設定の一覧に 1 行で収まるように。
    public static let maximumNameLength = 20

    /// 名前を確かめ、前後の空白を除いた名前を返す。空・長すぎる・ほかのカードと同じ名前（ひらがな・カタカナと英字の大小を
    /// 問わない。文の中でどちらのカードか決められないため）なら、その理由。
    ///
    /// - Parameter editing: 直しているカードの ID（そのカード自身の名前とは重なりとみなさない）。
    public static func validateName(_ name: String, among cards: [PaymentCard], editing: String? = nil) -> Result<String, CardNameIssue> {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        guard trimmed.count <= maximumNameLength else { return .failure(.tooLong) }
        let folded = KeywordMatcher.fold(trimmed)
        if cards.contains(where: { $0.id != editing && KeywordMatcher.fold($0.name) == folded }) {
            return .failure(.duplicate)
        }
        return .success(trimmed)
    }

    /// 「カードで」と名前を書かずに書いた記録に使うカード。いつものカード、無ければカードが 1 枚だけならそのカード。
    /// 2 枚以上あっていつものカードを決めていなければ nil（どちらか決められないので、カードの記録にしない）。
    public static func defaultCard(in cards: [PaymentCard]) -> PaymentCard? {
        cards.first(where: \.isDefault) ?? (cards.count == 1 ? cards.first : nil)
    }
}

/// カードの名前の問題。
public enum CardNameIssue: Error, Equatable, Sendable {
    case empty
    case tooLong
    case duplicate
}

/// カードの 1 回分の締め（使った期間・締め日・引き落とし日）。
public struct CardStatement: Sendable, Hashable {
    public let cardID: String
    /// 締めた月。
    public let closingMonth: RecurringMonth
    /// 使った日時がこの期間に入る記録を、この締めで払う（前の締め日の翌日の 0 時から、締め日の翌日の 0 時まで）。
    public let period: DateInterval
    /// 締め日（その日の 0 時）。
    public let closingDate: Date
    /// 引き落とし日（その日の 0 時）。
    public let paymentDate: Date
}

extension PaymentCard {
    /// `month` に締める分。暦で日付を作れなければ nil（実際には起きない）。
    ///
    /// 日付は西暦で、`timeZone` の時間帯で数える（くり返しの記録と同じ。端末の暦が和暦でも同じ日を指すように）。
    public func statement(closingIn month: RecurringMonth, timeZone: TimeZone) -> CardStatement? {
        let calendar = RecurringSchedule.calendar(timeZone)
        guard let closingDate = Self.startOfDay(in: month, day: closingDay, calendar: calendar, timeZone: timeZone),
              let previousClosing = Self.startOfDay(in: month.adding(months: -1), day: closingDay, calendar: calendar, timeZone: timeZone),
              let end = calendar.date(byAdding: .day, value: 1, to: closingDate),
              let start = calendar.date(byAdding: .day, value: 1, to: previousClosing),
              let paymentDate = Self.startOfDay(
                  in: month.adding(months: paymentMonthOffset), day: paymentDay, calendar: calendar, timeZone: timeZone
              )
        else { return nil }
        return CardStatement(
            cardID: id, closingMonth: month, period: DateInterval(start: start, end: end), closingDate: closingDate,
            paymentDate: paymentDate
        )
    }

    /// `date` に使った記録を払う締め。
    public func statement(containing date: Date, timeZone: TimeZone) -> CardStatement? {
        let month = RecurringMonth(containing: date, timeZone: timeZone)
        guard let current = statement(closingIn: month, timeZone: timeZone) else { return nil }
        // 締め日を過ぎて使った記録は、次の月の締めで払う。
        return date < current.period.end ? current : statement(closingIn: month.adding(months: 1), timeZone: timeZone)
    }

    /// `now` の日より後（その日を含む）に引き落とす締めのうち、いちばん早いもの。
    ///
    /// 翌々月に引き落とすカードでは、まだ締めていない今の締めより前に、締めた後でまだ引き落としていない締めがある。
    public func nextPaymentStatement(after now: Date, timeZone: TimeZone) -> CardStatement? {
        let today = RecurringSchedule.calendar(timeZone).startOfDay(for: now)
        guard let current = statement(containing: now, timeZone: timeZone) else { return nil }
        let candidates = (0...(paymentMonthOffset + 1)).reversed().compactMap { back in
            statement(closingIn: current.closingMonth.adding(months: -back), timeZone: timeZone)
        }
        return candidates.filter { $0.paymentDate >= today }.min { $0.paymentDate < $1.paymentDate }
    }

    /// その月の `day` 日の 0 時（その月に無い日なら月末）。
    private static func startOfDay(in month: RecurringMonth, day: Int, calendar: Calendar, timeZone: TimeZone) -> Date? {
        guard let clamped = RecurringSchedule.day(in: month, dayOfMonth: day, timeZone: timeZone) else { return nil }
        return calendar.date(from: DateComponents(year: month.year, month: month.month, day: clamped))
    }
}

/// カードの記録を数えるのに使う記録の形（集計の形に、払ったカードを足したもの）。
public protocol CardLedgerRecord: LedgerRecord {
    /// 払ったカードの ID。現金やほかの払い方（カードを決めていない記録）は空。
    var cardID: String { get }
}

/// ある締めで払う記録の合計。
public struct CardStatementSummary: Sendable, Hashable {
    public let statement: CardStatement
    /// その締めで払う支出の合計（円）。
    public let total: Int
    /// その締めで払う支出の件数。
    public let count: Int

    /// その締めで払う記録（そのカードの支出で、使った日時が締めの期間に入るもの）を数える。
    ///
    /// 収入は数えない（カードの記録にしないため。`PaymentLinker`）。
    public init(statement: CardStatement, records: some Sequence<some CardLedgerRecord>) {
        self.statement = statement
        var total = 0
        var count = 0
        for record in records
        where !record.isIncome && record.cardID == statement.cardID && statement.period.contains(record.spentAt)
            && record.spentAt < statement.period.end {
            total += record.amount
            count += 1
        }
        self.total = total
        self.count = count
    }
}

/// 期間の支出を、払ったカードごとに分けた合計（月のまとめの「支払い方法」）。
public struct PaymentBreakdown: Sendable, Hashable {
    public struct Row: Sendable, Hashable, Identifiable {
        /// カード。現金・その他の行は nil。
        public let card: PaymentCard?
        public let amount: Int
        public let count: Int

        public var id: String { card?.id ?? "" }
    }

    /// カードの並びの順（使った額の無いカードは除く）で、最後に現金・その他（あれば）。
    public let rows: [Row]

    /// - Parameters:
    ///   - interval: 使った日時がこの期間に入る支出を数える（始まりは含み、終わりは含まない。`LedgerSummary` と同じ区切り）。
    ///   - cards: いまのカードの一覧。一覧に無いカード（ほかの端末で消した）を指す記録は、現金・その他に数える。
    public init(records: some Sequence<some CardLedgerRecord>, interval: DateInterval, cards: [PaymentCard]) {
        var totals: [String: (amount: Int, count: Int)] = [:]
        let known = Set(cards.map(\.id))
        for record in records where !record.isIncome && record.spentAt >= interval.start && record.spentAt < interval.end {
            let key = known.contains(record.cardID) ? record.cardID : ""
            totals[key, default: (0, 0)].amount += record.amount
            totals[key, default: (0, 0)].count += 1
        }
        var rows = cards.compactMap { card in
            totals[card.id].map { Row(card: card, amount: $0.amount, count: $0.count) }
        }
        if let other = totals[""] {
            rows.append(Row(card: nil, amount: other.amount, count: other.count))
        }
        self.rows = rows
    }

    /// カードで払った記録が無い（現金・その他だけか、記録が無い）。
    public var hasCardRecords: Bool {
        rows.contains { $0.card != nil }
    }
}
