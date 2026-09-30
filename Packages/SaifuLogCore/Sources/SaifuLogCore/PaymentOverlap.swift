import Foundation

/// Apple Pay の支払いの記録と、同じ買い物を打った・声で入れた・レシートで記録したものとの重なりの見つけ方
/// （docs/design.md §9 の Apple Pay の支払いの決め事）。
///
/// Apple Pay の支払いは払うだけで記録される（`PaymentCapture`）ので、同じ買い物を一行で打ったり、レシートを読み取って内訳で
/// 記録したりすると、支出を 2 回数える。使った日と金額が同じものを重なりの候補にし、返事で聞く。消すのは利用者が選んだとき
/// だけにする（同じ日に同じ額を別々に払うこともあるため）。
///
/// 比べる額は送信（1 回の送信で記録したもの）ごとに作る（`sendAmounts`）。打った文と声は、支出の 1 件ずつの額と、同じ日の支出が
/// 2 件以上ならその日の合計（別々に払ったときにも、まとめて払ったときにも当たるように）。レシートは合計だけ（品目の額は、
/// 別に払ったほかの支払いと偶然そろいやすいため）。収入は比べない（呼び出し側が除いて渡す）。
public enum PaymentOverlap {
    /// 比べる額の 1 つ。
    public struct Amount<ID: Hashable>: Hashable {
        /// どの記録（か、額のまとまり）のものか。
        public var id: ID
        /// 金額（円）。
        public var amount: Int
        /// 使った日時。日の区切りで比べ、同じ日に候補がいくつもあれば時刻の近いものにする。
        public var spentAt: Date

        public init(id: ID, amount: Int, spentAt: Date) {
            self.id = id
            self.amount = amount
            self.spentAt = spentAt
        }
    }

    /// 1 回の送信の中で比べる額。
    public struct SendAmounts<ID: Hashable>: Hashable {
        /// 支出の 1 件ずつの額（打った文・声）。レシートは空。
        public var items: [Amount<ID>]
        /// 使った日ごとの支出の合計（打った文・声は支出が 2 件以上の日だけ、レシートはいつも）。id はその日のいちばん後の記録。
        public var totals: [Amount<ID>]

        public init(items: [Amount<ID>], totals: [Amount<ID>]) {
            self.items = items
            self.totals = totals
        }
    }

    /// 重なりの組（比べた額と、それに当たった候補）。
    public struct Pair<Query: Hashable, Candidate: Hashable>: Hashable {
        public var query: Query
        public var candidate: Candidate

        public init(query: Query, candidate: Candidate) {
            self.query = query
            self.candidate = candidate
        }
    }

    /// 送信で記録した支出から、比べる額を作る。
    ///
    /// - Parameters:
    ///   - expenses: 送信で記録した支出（書いた順。収入は除いて渡す）。
    ///   - isReceipt: レシートから記録した送信か（合計だけで比べる）。
    public static func sendAmounts<ID>(_ expenses: [Amount<ID>], isReceipt: Bool, calendar: Calendar) -> SendAmounts<ID> {
        // 使った日ごとにまとめる（書いた順のまま）。「昨日 ランチ 1200 今日 コーヒー 300」のように日をまたぐ送信は、日ごとに合計する。
        var days: [(day: Date, expenses: [Amount<ID>])] = []
        for expense in expenses {
            let day = calendar.startOfDay(for: expense.spentAt)
            if let index = days.firstIndex(where: { $0.day == day }) {
                days[index].expenses.append(expense)
            } else {
                days.append((day, [expense]))
            }
        }
        let totals = days.compactMap { group -> Amount<ID>? in
            guard let last = group.expenses.last, isReceipt || group.expenses.count >= 2 else { return nil }
            return Amount(id: last.id, amount: group.expenses.reduce(0) { $0 + $1.amount }, spentAt: last.spentAt)
        }
        return SendAmounts(items: isReceipt ? [] : expenses, totals: totals)
    }

    /// 額ごとに（並んだ順に）、同じ額で使った日が同じ候補のうち、時刻のいちばん近いものを当てる。当たらない額は組にしない。
    ///
    /// 1 つの候補は 1 つの額にだけ当てる（同じ支払いを、2 つの記録の重なりとして聞かないため）。
    public static func pairs<Query, Candidate>(
        _ queries: [Amount<Query>], among candidates: [Amount<Candidate>], calendar: Calendar
    ) -> [Pair<Query, Candidate>] {
        var used = Set<Candidate>()
        var result: [Pair<Query, Candidate>] = []
        for query in queries {
            let match = candidates
                .filter {
                    !used.contains($0.id) && $0.amount == query.amount
                        && calendar.isDate($0.spentAt, inSameDayAs: query.spentAt)
                }
                .min { abs($0.spentAt.timeIntervalSince(query.spentAt)) < abs($1.spentAt.timeIntervalSince(query.spentAt)) }
            guard let match else { continue }
            used.insert(match.id)
            result.append(Pair(query: query.id, candidate: match.id))
        }
        return result
    }

    /// 送信に重なる支払い（`paymentPairs`）。
    public struct SendMatches<Query: Hashable, Payment: Hashable>: Hashable {
        /// 当たった組。
        public var pairs: [Pair<Query, Payment>]
        /// 合計で当たったか（1 件ずつの額では 1 つも当たらなかった）。聞き返しに合計の額を添えるのに使う。
        public var byTotal: Bool

        public init(pairs: [Pair<Query, Payment>], byTotal: Bool) {
            self.pairs = pairs
            self.byTotal = byTotal
        }
    }

    /// 新しく記録した送信（打った文・声・レシート）に重なる、前に記録した Apple Pay の支払いを探す。
    ///
    /// 1 件ずつの額で探し、1 つも当たらなければ合計で探す（1 回の送信の中の買い物は、別々に払ったか、まとめて払ったかの
    /// どちらかとみなす。両方で探すと、別々に払った 1 件と、偶然同じ額の合計とを重ねて聞いてしまうため）。
    public static func paymentPairs<Query, Payment>(
        for send: SendAmounts<Query>, among payments: [Amount<Payment>], calendar: Calendar
    ) -> SendMatches<Query, Payment> {
        let items = pairs(send.items, among: payments, calendar: calendar)
        guard items.isEmpty else { return SendMatches(pairs: items, byTotal: false) }
        let totals = pairs(send.totals, among: payments, calendar: calendar)
        return SendMatches(pairs: totals, byTotal: !totals.isEmpty)
    }
}
