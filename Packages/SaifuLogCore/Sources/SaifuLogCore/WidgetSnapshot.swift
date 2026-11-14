import Foundation

/// ウィジェット（ホーム画面・ロック画面）に出す今月の数字。アプリが書き、ウィジェットの拡張が読む。
///
/// 保存先（SwiftData）は NSFileProtectionComplete でロック中は読めず、ウィジェットは別のプロセスで動くので、アプリがホームの帯と
/// 同じ数字だけをここに書いて渡す（App Group の共有の領域のファイル。アプリの `WidgetSnapshotFile`）。渡すのは月・使った額・予算だけで、
/// 記録の品目・メモ・カテゴリは渡さない（保存先より弱い保護の場所に置くので、家計の中身を置かない。`docs/design.md` §9）。
///
/// アプリのロック（Face ID でロック）をオンにしている間は数字を渡さない（`hidden`）。ロックで家計を隠しているのに、ホーム画面に
/// 金額が出ていては意味がないため。
public struct WidgetSnapshot: Codable, Sendable, Equatable {
    /// 書き方の版。形を変えたら上げる（古い形のファイルを読み違えないように。読めなければウィジェットは「開くと出ます」にする）。
    public static let currentVersion = 1

    public let version: Int
    /// 数字を出さない（アプリのロック中）。そのとき数字の項目は空。
    public let hidesFigures: Bool
    /// 数えた月（`ReportPeriod.thisMonth`。終わりの時刻は含まない）。
    public let monthStart: Date?
    public let monthEnd: Date?
    /// その月に使った額（支出の合計。ホームの帯の「今月使った額」と同じ）。
    public let spent: Int
    /// 月の全体の予算。決めていなければ nil。
    public let budget: Int?

    /// 数字を出さない（アプリのロック中）。
    public static let hidden = WidgetSnapshot(
        version: currentVersion, hidesFigures: true, monthStart: nil, monthEnd: nil, spent: 0, budget: nil
    )

    /// その月の数字。予算が 0 以下なら決めていないとみなす（`BudgetStatus` と同じ）。
    public static func figures(spent: Int, budget: Int?, month: DateInterval) -> WidgetSnapshot {
        WidgetSnapshot(
            version: currentVersion, hidesFigures: false, monthStart: month.start, monthEnd: month.end,
            spent: spent, budget: budget.flatMap { $0 > 0 ? $0 : nil }
        )
    }

    init(version: Int, hidesFigures: Bool, monthStart: Date?, monthEnd: Date?, spent: Int, budget: Int?) {
        self.version = version
        self.hidesFigures = hidesFigures
        self.monthStart = monthStart
        self.monthEnd = monthEnd
        self.spent = spent
        self.budget = budget
    }

    /// ファイルの中身から読む。形が違う・版が違うときは nil（ウィジェットは「開くと出ます」にする）。
    public static func decode(_ data: Data) -> WidgetSnapshot? {
        guard let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data),
              snapshot.version == currentVersion
        else { return nil }
        return snapshot
    }

    /// ファイルに書く中身。
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    /// `now` の時点で出す数字。
    ///
    /// 数えた月が終わっていれば（月が替わってからアプリを開いていない）、今月はまだ何も使っていないとして 0 にし、予算は同じ全体の
    /// 予算で数える（予算は月ごとではなく全体の 1 つで、次の月にもそのまま使うため。`BudgetPlan`）。次にアプリを開くと、くり返しの
    /// 記録やほかの端末の記録も入った数字に替わる。
    public func display(now: Date, calendar: Calendar) -> WidgetDisplay {
        guard !hidesFigures else { return .hidden }
        let isPastMonth = monthEnd.map { now >= $0 } ?? true
        let spent = isPastMonth ? 0 : spent
        let status = ReportPeriod.thisMonth.interval(now: now, calendar: calendar).flatMap {
            BudgetStatus(budget: budget, spent: spent, now: now, month: $0, calendar: calendar)
        }
        return .figures(spent: spent, budget: status)
    }

    /// 次に数字を描き直す時刻（`now` の次の月の始まり。月が替わると使った額が 0 に戻るため）。
    public static func nextRefresh(after now: Date, calendar: Calendar) -> Date? {
        ReportPeriod.thisMonth.interval(now: now, calendar: calendar)?.end
    }
}

/// ウィジェットに出すもの。
public enum WidgetDisplay: Sendable, Equatable {
    /// 数字を出さない（アプリのロック中）。
    case hidden
    /// 今月使った額と、予算を決めていれば予算の進み（残り・超えた額・バーの割合）。
    case figures(spent: Int, budget: BudgetStatus?)
}
