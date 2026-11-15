import Foundation

/// カードの利用額と引き落としの質問（「楽天カードの利用額は？」「次の引き落としはいくら？」）。docs/design.md §8-2。
///
/// 決まりで読み、端末内 AI には渡さない（AI の質問の選択肢（期間・知りたいこと・カテゴリ）にカードは無く、締めの期間は
/// 暦の期間と違うため）。数字はコードが数える（`CardStatementSummary`）。カードを登録していなければ読まない（ふつうの質問として答える）。
public struct CardQuestion: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        /// 次の引き落とし（日と額）。「引き落とし」「請求」、カードの語と「支払い」「払う」。
        case nextPayment
        /// 今の締め（まだ締めていない分）の利用額。
        case currentUsage
        /// 前の締め（締めた分）の利用額。「先月」「前回」。
        case previousUsage
    }

    public let kind: Kind
    /// 聞いたカード（登録した順）。名前を書かなければ、登録したすべて。
    public let cardIDs: [String]

    /// 質問の文を読む。カードのことを聞いていなければ nil。
    ///
    /// - カードの名前を書いた（「楽天カードの利用額は？」）: そのカード。「カード」「クレカ」だけなら、登録したすべて
    /// - 「引き落とし」「請求」は、カードの語が無くてもカードの質問とみなす（「次の引き落としはいくら？」）。「支払い」「払う」は、
    ///   カードの語があるときだけ（「今月の支払いは？」は、ふつうの質問）
    public static func read(_ text: String, cards: [PaymentCard]) -> CardQuestion? {
        guard !cards.isEmpty else { return nil }
        let chars = Array(TextNormalizer.normalize(text))
        let folded = KeywordMatcher.fold(String(chars))
        let mentions = PaymentLinker(cards: cards).mentions(in: chars, requireRightBoundary: false).filter(\.kind.isCard)
        let named = mentions.compactMap { mention -> String? in
            if case .card(let id) = mention.kind { return id }
            return nil
        }
        let asksBill = billWords.contains { folded.contains($0) }
        guard !mentions.isEmpty || asksBill else { return nil }
        let ids = named.isEmpty ? cards.map(\.id) : cards.map(\.id).filter(named.contains)
        let kind: Kind
        if asksBill || (!mentions.isEmpty && paymentWords.contains { folded.contains($0) }) {
            kind = .nextPayment
        } else if previousWords.contains(where: { folded.contains($0) }) {
            kind = .previousUsage
        } else {
            kind = .currentUsage
        }
        return CardQuestion(kind: kind, cardIDs: ids)
    }

    /// 質問に答える締め（カードごと）。
    public func statements(cards: [PaymentCard], now: Date, timeZone: TimeZone) -> [(card: PaymentCard, statement: CardStatement)] {
        cards.filter { cardIDs.contains($0.id) }.compactMap { card in
            let statement: CardStatement?
            switch kind {
            case .nextPayment:
                statement = card.nextPaymentStatement(after: now, timeZone: timeZone)
            case .currentUsage:
                statement = card.statement(containing: now, timeZone: timeZone)
            case .previousUsage:
                statement = card.statement(containing: now, timeZone: timeZone).flatMap {
                    card.statement(closingIn: $0.closingMonth.adding(months: -1), timeZone: timeZone)
                }
            }
            return statement.map { (card, $0) }
        }
    }

    private static let billWords = ["引き落とし", "引き落し", "引落", "請求"].map(KeywordMatcher.fold)
    private static let paymentWords = ["支払", "払う", "払い", "引かれ"].map(KeywordMatcher.fold)
    private static let previousWords = ["先月", "前月", "前回", "この前の締め"].map(KeywordMatcher.fold)
}

/// カードの質問の答え（カードごとの締めと額）。保存しない。
public struct CardAnswer: Sendable, Hashable {
    public struct Row: Sendable, Hashable, Identifiable {
        public let card: PaymentCard
        public let summary: CardStatementSummary

        public var id: String { card.id }
    }

    public let kind: CardQuestion.Kind
    /// 引き落としの質問は引き落とし日の早い順、利用額の質問はカードの並びの順。
    public let rows: [Row]

    /// 額の合計（カードが 2 枚以上のときに出す）。
    public var total: Int { rows.reduce(0) { $0 + $1.summary.total } }

    /// - Parameter records: 使った日時が期間に入る記録を読む（締めの期間をまとめた期間を渡す）。
    public init<Record: CardLedgerRecord>(
        question: CardQuestion, cards: [PaymentCard], now: Date, timeZone: TimeZone, records: (DateInterval) throws -> [Record]
    ) rethrows {
        let statements = question.statements(cards: cards, now: now, timeZone: timeZone)
        var loaded: [Record] = []
        if let start = statements.map(\.statement.period.start).min(), let end = statements.map(\.statement.period.end).max() {
            loaded = try records(DateInterval(start: start, end: end))
        }
        var rows = statements.map { Row(card: $0.card, summary: CardStatementSummary(statement: $0.statement, records: loaded)) }
        if question.kind == .nextPayment {
            rows.sort { $0.summary.statement.paymentDate < $1.summary.statement.paymentDate }
        }
        self.kind = question.kind
        self.rows = rows
    }

    public init(kind: CardQuestion.Kind, rows: [Row]) {
        self.kind = kind
        self.rows = rows
    }
}
