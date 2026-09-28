import Foundation
import Observation
import SaifuLogCore
import SwiftData

/// 「月のまとめ」（⑦）の状態と操作。表示する月と月送り、その月の数字（`MonthlyReport`）、カテゴリごとの記録の一覧、
/// 一覧から開く「直す」（⑥）のシート。
///
/// 画面（`MonthlyReportView`）から切り離し、保存先・時計・読み上げを差し替えて SaifuLogTests で確かめられるようにしている。
/// 数字の計算はコア（`MonthlyReport`）に任せ、ここでは読み込みと月の行き来だけを受け持つ。
///
/// 保存先はここで読む（画面の @Query にしない）。月送りの端（記録のある最初の月）や数字を、記録を足したり消したり
/// したあとの値でテストで確かめるため。読み直すのは、月を替えたとき・今日が変わったとき・ここから直したり消したり
/// したとき・保存先に書き込まれたとき（画面が `ModelContext.didSave` を受けて `reload()` を呼ぶ）。
@MainActor
@Observable
final class MonthlyReportModel {
    /// 表示している月（終わりの時刻は含まない）。月は `ReportPeriod`（ホームの今月と同じ、利用者が選んだ暦の月）で区切る。
    private(set) var month: DateInterval
    /// 今日。今月より先へ進めないことと、今月かどうか（平均の日数・日割りの目安）の基準。
    private(set) var today: Date
    /// 表示している月の数字。読み込めなかったときは nil。
    private(set) var report: MonthlyReport?
    /// 保存先を読めなかった（再試行のボタンを出す）。
    private(set) var loadFailed = false
    /// 使った日時のいちばん古い記録の日時。記録が 1 件も無ければ nil。これより前の月へは戻れない。
    private(set) var earliestSpentAt: Date?
    /// 表示している月の記録（支出と収入）。
    private(set) var monthEntries: [Entry] = []
    /// 記録の一覧を出しているカテゴリ（横に進む）。一覧を閉じると画面が nil に戻す。
    var selectedCategory: EntryCategory?
    /// 「直す」のシートで直している記録の状態と操作。シートを閉じると画面が nil に戻す。
    var editing: EditEntryModel?

    /// 月の区切りと日付の書き方の暦（ホームの画面の暦）。
    let calendar: Calendar

    @ObservationIgnored private let store: EntryStore
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let announce: @MainActor (String) -> Void
    @ObservationIgnored private let didSave: @MainActor (Entry) -> Void
    @ObservationIgnored private let didDelete: @MainActor (PersistentIdentifier) -> Void

    /// - Parameters:
    ///   - calendar: 月の区切りの暦。ホームと同じ暦を渡す（ホームの今月の合計と同じ月でまとめるため）。
    ///   - now: 今日の基準。テストで固定の日時にする。
    ///   - announce: VoiceOver に読み上げさせる。テストで読み上げる文を集める。
    ///   - didSave: ここから開いた「直す」で保存できたあとに呼ぶ（ホームが「取り消す」を片づける）。
    ///   - didDelete: ここから開いた「直す」で削除できたあとに、消した記録の ID を渡して呼ぶ（ホームが「取り消す」の対象から外す）。
    init(
        store: EntryStore,
        calendar: Calendar,
        now: @escaping () -> Date = { .now },
        announce: @escaping @MainActor (String) -> Void = { VoiceOver.announce($0) },
        didSave: @escaping @MainActor (Entry) -> Void = { _ in },
        didDelete: @escaping @MainActor (PersistentIdentifier) -> Void = { _ in }
    ) {
        let today = now()
        self.store = store
        self.calendar = calendar
        self.now = now
        self.announce = announce
        self.didSave = didSave
        self.didDelete = didDelete
        self.today = today
        // 暦で月を区切れないことは実際には無いが、そのときは数字を出さない（report が nil のまま）。
        self.month = ReportPeriod.thisMonth.interval(now: today, calendar: calendar) ?? DateInterval(start: today, duration: 0)
        reload()
    }

    // MARK: - 月送り

    /// 前の月へ戻れるか。記録のある最初の月より前には戻れない（何も無い月をさかのぼり続けないように）。
    var canShowPreviousMonth: Bool {
        earliestSpentAt.map { $0 < month.start } ?? false
    }

    /// 次の月へ進めるか。今月より先には進めない（先の日付の記録があっても）。
    var canShowNextMonth: Bool {
        today >= month.end
    }

    /// 表示している月の見出し（「2026年9月」「September 2026」）。月を区切ったのと同じ暦・時間帯で書く。
    var monthTitle: String {
        var style = Date.FormatStyle.dateTime.year().month(.wide)
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return month.start.formatted(style)
    }

    func showPreviousMonth() {
        guard canShowPreviousMonth,
              let previous = ReportPeriod.lastMonth.interval(now: month.start, calendar: calendar)
        else { return }
        show(previous)
    }

    func showNextMonth() {
        // 今の月の終わり（次の月の始まり）を含む月が、次の月。
        guard canShowNextMonth, let next = ReportPeriod.thisMonth.interval(now: month.end, calendar: calendar) else { return }
        show(next)
    }

    /// 月を替え、見出しを VoiceOver に読み上げる。
    ///
    /// 「前の月」「次の月」のボタンを押しても、フォーカスはボタンに残り、どの月になったかが読まれないため。
    private func show(_ newMonth: DateInterval) {
        month = newMonth
        selectedCategory = nil
        reload()
        announce(monthTitle)
    }

    // MARK: - 読み込み

    /// 表示している月の数字を読み直す。
    func reload() {
        let context = store.context
        do {
            // 前の月との差を出すので、前の月の記録もいっしょに読む。
            let previousStart = ReportPeriod.lastMonth.interval(now: month.start, calendar: calendar)?.start ?? month.start
            let records = try context.fetch(Entry.descriptor(spentIn: DateInterval(start: previousStart, end: month.end)))
            let budgets = try context.fetch(FetchDescriptor<Budget>())
            earliestSpentAt = try context.fetch(Entry.earliestDescriptor).first?.spentAt
            report = MonthlyReport(
                records: records,
                month: month.start,
                now: today,
                budget: BudgetPlan.resolve(budgets).total,
                budgetDecidedAt: BudgetPlan.decidedAt(.total, in: budgets),
                calendar: calendar
            )
            let month = month
            monthEntries = records.filter { $0.spentAt >= month.start && $0.spentAt < month.end }
            loadFailed = false
        } catch {
            report = nil
            monthEntries = []
            loadFailed = true
        }
    }

    /// 「今日」を読み直す。前面に戻ったときと、日付が変わったときに呼ぶ（今月かどうかと平均の日数が変わるため）。
    /// 表示している月はそのまま（見ている月が黙って替わらないように）。
    func refreshToday() {
        today = now()
        reload()
    }

    // MARK: - カテゴリの記録

    /// 表示している月の、そのカテゴリの支出の記録。使った日時の新しい順（同じ日時なら記録した順の新しいほうから）。
    ///
    /// 内訳（支出だけ）の行から開くので、収入は入れない。
    func entries(in category: EntryCategory) -> [Entry] {
        monthEntries
            .filter { !$0.isIncome && $0.category == category }
            .sorted { a, b in a.spentAt != b.spentAt ? a.spentAt > b.spentAt : a.createdAt > b.createdAt }
    }

    /// そのカテゴリの記録の一覧へ進む。
    func showEntries(in category: EntryCategory) {
        selectedCategory = category
    }

    /// 一覧の記録から「直す」のシートを出す。直したり消したりしたら読み直す（数字と一覧をすぐ合わせるため）。
    func presentEdit(_ entry: Entry) {
        editing = EditEntryModel(
            entry: entry,
            store: store,
            calendar: calendar,
            now: now,
            announce: announce,
            didSave: { [weak self] entry in
                self?.reload()
                self?.didSave(entry)
            },
            didDelete: { [weak self] id in
                self?.reload()
                self?.didDelete(id)
            }
        )
    }
}

/// ホームから横に進む先（`navigationDestination(item:)`）として渡すため、同じインスタンスかどうかで比べる。
extension MonthlyReportModel: Hashable {
    nonisolated static func == (lhs: MonthlyReportModel, rhs: MonthlyReportModel) -> Bool {
        lhs === rhs
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}
