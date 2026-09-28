import Foundation

/// 予算の対象。月の全体の予算か、あるカテゴリの予算（プレミアム）か。
///
/// rawValue は保存に使う（アプリの予算のモデルの `scopeRawValue`）ので変えないこと。全体は "total"、
/// カテゴリはカテゴリの rawValue をそのまま使う（"total" と重なるカテゴリが無いことはテストで確かめる）。
public enum BudgetScope: RawRepresentable, Hashable, Sendable {
    case total
    case category(EntryCategory)

    public static let totalRawValue = "total"

    /// 知らない値（新しい版で足したカテゴリが iCloud で届いたときなど）は nil。
    public init?(rawValue: String) {
        if rawValue == Self.totalRawValue {
            self = .total
        } else if let category = EntryCategory(rawValue: rawValue) {
            self = .category(category)
        } else {
            return nil
        }
    }

    public var rawValue: String {
        switch self {
        case .total: Self.totalRawValue
        case .category(let category): category.rawValue
        }
    }
}

/// 保存された予算の 1 件の最小の形。
///
/// 保存用のモデル（SwiftData）をコアに持ち込まずに予算を読むための境目。アプリ側のモデルがこれに準拠する。
public protocol BudgetRecord {
    /// 対象（`BudgetScope.rawValue`）。
    var scopeRawValue: String { get }
    /// 月の予算（円）。0 以下は「設定なし」。
    var amount: Int { get }
    /// 最後に書いた日時。
    var updatedAt: Date { get }
}

/// いま有効な予算（全体と、カテゴリ別）。
///
/// 予算は月ごとに持たず、毎月同じ額を使う（決め直すと、その月から新しい額で数える）。
public struct BudgetPlan: Sendable, Hashable {
    /// 予算に使える最大の額（円）。入力欄の桁数（8 桁）と同じ。
    public static let maximumAmount = 99_999_999

    /// 月の全体の予算。決めていなければ nil。
    public let total: Int?
    /// カテゴリ別の予算。決めていないカテゴリは入れない。
    public let byCategory: [EntryCategory: Int]

    /// 0 以下の額は「設定なし」として持たない。
    public init(total: Int? = nil, byCategory: [EntryCategory: Int] = [:]) {
        self.total = total.flatMap { $0 > 0 ? $0 : nil }
        self.byCategory = byCategory.filter { $0.value > 0 }
    }

    /// 保存された予算の行から、いま有効な予算を決める。
    ///
    /// 同じ対象の行が複数あれば、`preferred(_:)` の 1 行を採る。iCloud で同期すると、別々の端末で書いた
    /// 行がそれぞれ届き、同じ対象の行が重なることがある（一意制約は CloudKit と両立しないので付けられない）。
    /// 採った行の額が 0 以下なら、その対象は「設定なし」。予算を消すときに行を消さず 0 を書くのは、
    /// 削除が他の端末に伝わるのが遅れても、あとから書いた「設定なし」が古い額に負けないようにするため。
    /// 知らない対象の行は読み飛ばす。
    public static func resolve<Records: Sequence>(_ records: Records) -> BudgetPlan
    where Records.Element: BudgetRecord {
        var groups: [BudgetScope: [Records.Element]] = [:]
        for record in records {
            guard let scope = BudgetScope(rawValue: record.scopeRawValue) else { continue }
            groups[scope, default: []].append(record)
        }
        var total: Int?
        var byCategory: [EntryCategory: Int] = [:]
        for (scope, rows) in groups {
            guard let amount = preferred(rows)?.amount else { continue }
            switch scope {
            case .total: total = amount
            case .category(let category): byCategory[category] = amount
            }
        }
        return BudgetPlan(total: total, byCategory: byCategory)
    }

    /// 同じ対象の行のうち、有効とみなす 1 行。最後に書いた（`updatedAt` の新しい）行を採る。
    ///
    /// 日時まで同じなら額の大きい行を採る。読み込む順番は端末ごとに違うので、順番で決めると端末によって
    /// 違う予算が出るため。額で決めるのは、同時に書いた「設定なし」（0）で決めた予算が黙って消えないようにするため。
    /// 予算を書き込むとき（アプリの `BudgetStore`）も、残す行をこれで選ぶ。
    public static func preferred<Records: Sequence>(_ records: Records) -> Records.Element?
    where Records.Element: BudgetRecord {
        records.max { a, b in
            a.updatedAt != b.updatedAt ? a.updatedAt < b.updatedAt : a.amount < b.amount
        }
    }

    /// その対象の予算。決めていなければ nil。
    public func amount(for scope: BudgetScope) -> Int? {
        switch scope {
        case .total: total
        case .category(let category): byCategory[category]
        }
    }
}
