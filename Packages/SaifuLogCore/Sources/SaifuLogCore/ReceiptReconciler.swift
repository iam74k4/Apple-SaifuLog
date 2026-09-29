import Foundation

/// レシートの品目から記録の下書きを作り、品目の合計とレシートの合計（税込み）を照合する。
///
/// 決め事（docs/design.md §3-3）:
/// - 記録する額は、品目の額から品目に付いた値引きを引いた額（`ReceiptItem.netAmount`）
/// - **外税のレシートは、税を品目に按分せず、「税・その他」の 1 行にする。** 品目の額をレシートに印字された額のまま
///   見せ、利用者が 1 行ずつレシートと見比べて直せるようにするため（按分すると印字と違う額が並び、どこが読み違いか
///   分からなくなる）。「税・その他」の行のカテゴリは、品目の額がいちばん多いカテゴリにする（カテゴリ別の合計のずれを、
///   税の分だけにとどめるため）
/// - 小計の後の値引きのように品目に付かない値引きは、外税と差し引いて、残りが正なら「税・その他」の行に、負なら
///   品目の額に按分して引く（記録の金額は正の数だけなので、負の行は作れないため）
/// - 品目が無く合計だけが読めたレシート（飲食店の「御会計」だけなど）は、合計で 1 行にする
/// - 照合はコードの足し算で、合わなければ差を出す。黙って記録しない（画面が確かめる）
public enum ReceiptReconciler {
    /// レシートから、記録の下書きの行を作る。
    public static func draftLines(for scan: ReceiptScan) -> [ReceiptDraftLine] {
        var lines = scan.items.enumerated().map { index, item in
            ReceiptDraftLine(
                kind: .item, name: item.name, amount: item.netAmount, category: item.category,
                quantity: item.quantity, unitPrice: item.unitPrice, discount: item.discount,
                isReducedTaxRate: item.isReducedTaxRate, itemIndex: index
            )
        }.filter { $0.amount > 0 }
        guard !lines.isEmpty else {
            guard let total = scan.total, total > 0 else { return [] }
            return [ReceiptDraftLine(
                kind: .wholeReceipt, name: ReceiptSummary.storeLabel(scan.storeName) ?? "", amount: total,
                category: scan.storeCategory ?? .other
            )]
        }
        let adjustment = scan.exclusiveTax - scan.receiptDiscount
        if adjustment > 0 {
            let category = dominantCategory(of: lines.map { ($0.amount, $0.category) }) ?? scan.storeCategory ?? .other
            lines.append(ReceiptDraftLine(kind: .taxAndOther, name: "", amount: adjustment, category: category))
        } else if adjustment < 0, let reduced = deducting(-adjustment, from: lines.map(\.amount)) {
            for index in lines.indices {
                lines[index].discount += lines[index].amount - reduced[index]
                lines[index].amount = reduced[index]
            }
        }
        return lines
    }

    /// 記録する行の合計とレシートの合計を照合する。
    public static func reconcile(linesTotal: Int, receiptTotal: Int?) -> ReceiptReconciliation {
        guard let receiptTotal else {
            return ReceiptReconciliation(linesTotal: linesTotal, receiptTotal: nil, status: .totalMissing)
        }
        let difference = receiptTotal - linesTotal
        return ReceiptReconciliation(
            linesTotal: linesTotal, receiptTotal: receiptTotal,
            status: difference == 0 ? .matched : .mismatched(difference: difference)
        )
    }

    /// 額がいちばん多いカテゴリ（同じ額なら先に出てきたもの）。行が無ければ nil。
    public static func dominantCategory(of lines: [(amount: Int, category: EntryCategory)]) -> EntryCategory? {
        var totals: [(category: EntryCategory, amount: Int)] = []
        for line in lines {
            if let index = totals.firstIndex(where: { $0.category == line.category }) {
                totals[index].amount += line.amount
            } else {
                totals.append((line.category, line.amount))
            }
        }
        var best: (category: EntryCategory, amount: Int)?
        for total in totals where total.amount > (best?.amount ?? Int.min) {
            best = total
        }
        return best?.category
    }

    /// 記録する行から、保存する記録を作る。
    ///
    /// - 品目ごと: 1 行を 1 件にする（品名が空なら店名、それも無ければ空）
    /// - まとめて 1 件: 行の額の合計を 1 件にする。品目は店名（無ければ空）、カテゴリは `singleCategory`
    public static func records(
        _ lines: [ReceiptRecordLine], mode: ReceiptRecordMode, storeName: String?, singleCategory: EntryCategory
    ) -> [ReceiptRecord] {
        let lines = lines.filter { $0.amount > 0 }
        guard !lines.isEmpty else { return [] }
        let store = ReceiptSummary.storeLabel(storeName) ?? ""
        switch mode {
        case .perItem:
            return lines.map { line in
                let name = line.name.trimmingCharacters(in: .whitespacesAndNewlines)
                return ReceiptRecord(memo: name.isEmpty ? store : name, amount: line.amount, category: line.category)
            }
        case .single:
            return [ReceiptRecord(memo: store, amount: lines.reduce(0) { $0 + $1.amount }, category: singleCategory)]
        }
    }

    /// `amount` を、額の比で各行から引いた額（最大剰余法で、引いた額の合計をちょうど `amount` にする）。
    /// どの行も 1 円以上残せなければ nil。
    static func deducting(_ amount: Int, from values: [Int]) -> [Int]? {
        let total = values.reduce(0, +)
        guard amount > 0, total - amount >= values.count else { return amount == 0 ? values : nil }
        var shares = values.map { $0 * amount / total }
        let remainders = values.enumerated().map { (index: $0.offset, remainder: $0.element * amount % total) }
        var rest = amount - shares.reduce(0, +)
        // 端数の大きい行から 1 円ずつ足す（同じなら上の行から）。
        for entry in remainders.sorted(by: { $0.remainder > $1.remainder || ($0.remainder == $1.remainder && $0.index < $1.index) })
        where rest > 0 {
            shares[entry.index] += 1
            rest -= 1
        }
        let result = zip(values, shares).map { $0 - $1 }
        return result.allSatisfy { $0 >= 1 } ? result : nil
    }
}

/// 記録の下書きの 1 行（読み取り結果の画面で、外したり直したりする）。
public struct ReceiptDraftLine: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        /// レシートの品目。
        case item
        /// 外税など、品目に足す額（「税・その他」）。
        case taxAndOther
        /// 品目が読めず、合計だけで作った 1 行。
        case wholeReceipt
    }

    public var kind: Kind
    /// 品名（「税・その他」の行は空。画面が名前を付ける）。
    public var name: String
    /// 記録する額（値引きを引いた額）。
    public var amount: Int
    public var category: EntryCategory
    public var quantity: Int?
    public var unitPrice: Int?
    /// 引いた値引き（品目に付いた値引きと、按分したレシート全体の値引き）。
    public var discount: Int
    public var isReducedTaxRate: Bool
    /// 元の品目の位置（`ReceiptScan.items` の添字）。品目でない行は nil。
    public var itemIndex: Int?

    public init(
        kind: Kind, name: String, amount: Int, category: EntryCategory, quantity: Int? = nil, unitPrice: Int? = nil,
        discount: Int = 0, isReducedTaxRate: Bool = false, itemIndex: Int? = nil
    ) {
        self.kind = kind
        self.name = name
        self.amount = amount
        self.category = category
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.discount = discount
        self.isReducedTaxRate = isReducedTaxRate
        self.itemIndex = itemIndex
    }
}

/// 照合の結果。
public struct ReceiptReconciliation: Sendable, Hashable {
    public enum Status: Sendable, Hashable {
        /// 行の合計がレシートの合計と同じ。
        case matched
        /// 合わない。`difference` はレシートの合計 − 行の合計（正なら行が足りない）。
        case mismatched(difference: Int)
        /// レシートの合計が読めなかった（行の合計で記録する）。
        case totalMissing
    }

    /// 記録する行の合計。
    public let linesTotal: Int
    /// レシートの合計。読めなければ nil。
    public let receiptTotal: Int?
    public let status: Status
}

/// 記録する 1 行（利用者が外さずに残した行）。
public struct ReceiptRecordLine: Sendable, Hashable {
    public var name: String
    public var amount: Int
    public var category: EntryCategory

    public init(name: String, amount: Int, category: EntryCategory) {
        self.name = name
        self.amount = amount
        self.category = category
    }
}

/// まとめて 1 件か、品目ごとか。
public enum ReceiptRecordMode: Sendable, Hashable, CaseIterable {
    case perItem
    case single
}

/// 保存する 1 件（日時と元の文は、画面が決めて付ける）。
public struct ReceiptRecord: Sendable, Hashable {
    public var memo: String
    public var amount: Int
    public var category: EntryCategory

    public init(memo: String, amount: Int, category: EntryCategory) {
        self.memo = memo
        self.amount = amount
        self.category = category
    }
}
