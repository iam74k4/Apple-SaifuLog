import Foundation
import Observation
import SaifuLogCore
import SwiftData

/// カレンダーのページ（ホームを左へスワイプした 2 枚目。docs/design.md §9 の ⑩）の状態と操作。
///
/// 見せる月の記録だけを読み（全期間を読まない。記録が増えても重くならないように）、日ごとの集計（`LedgerCalendarMonth`）と、
/// 今月なら見通し（`SpendingOutlook`。今日あと・固定費を引いた今月あと・月末の見込み）を出す。数字はコアで数え、ここでは
/// 数え直さない。記録は「自分」の記録だけ（家族の家計は v1 では出さない）。
@MainActor
@Observable
final class LedgerCalendarModel {
    /// 記録の 1 件（画面に出す値の控え）。
    ///
    /// 記録そのものではなく値を控えて出す。ほかの端末（iCloud）で消された記録は、SwiftData が値を空にし、値を読むとアプリが
    /// 落ちうるため（`HomeModel.justRecordedIDs` と同じ考え方）。直す・消すときは、まだあるかを確かめてから記録を引く（`entry(for:)`）。
    struct DayRecord: Identifiable, Hashable, LedgerEntryDisplaying {
        let id: PersistentIdentifier
        let amount: Int
        let isIncome: Bool
        let category: EntryCategory
        let memo: String
        let spentAt: Date
        let createdAt: Date
        /// くり返しの記録から記録したものか（固定費として、月末の見込みのペースから外す）。
        let isRecurring: Bool

        init(_ entry: Entry) {
            id = entry.persistentModelID
            amount = entry.amount
            isIncome = entry.isIncome
            category = entry.category
            memo = entry.memo
            spentAt = entry.spentAt
            createdAt = entry.createdAt
            isRecurring = entry.source == .recurring
        }
    }

    /// 見せている月。
    private(set) var month: DateInterval?
    /// 見せている月の日ごとの集計。
    private(set) var days: LedgerCalendarMonth?
    /// 見せている月の、くり返しの記録の予定（まだ記録していないもの。収入も）。
    private(set) var planned: [PlannedOccurrence] = []
    /// 今月を見せているときの見通し。ほかの月では nil。
    private(set) var outlook: SpendingOutlook?
    /// 月の全体の予算（日の印の日割りに使う）。決めていなければ nil。
    private(set) var budget: Int?
    /// 選んでいる日の始まり。
    private(set) var selectedDay: Date?
    /// 選んでいる日の記録（使った日時の順）。
    private(set) var selectedRecords: [DayRecord] = []
    /// 記録を読めなかったか（画面に知らせを出す）。
    private(set) var loadFailed = false

    @ObservationIgnored private let store: EntryStore
    @ObservationIgnored private let budgetStore: BudgetStore
    @ObservationIgnored private let recurring: RecurringEntryStore
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let announce: @MainActor (String) -> Void
    /// 日を区切る暦（画面の暦。週の始まりは設定のとおり）。`configure(calendar:)` で受け取る。
    @ObservationIgnored private(set) var calendar = Calendar.current
    /// 見せている月の記録（日を選び直すたびに読み直さないよう持っておく）。
    @ObservationIgnored private var monthRecords: [DayRecord] = []
    /// 前に読んだときの今日の始まり（日付が変わったかを見る）。
    @ObservationIgnored private var lastToday: Date?

    /// - Parameters:
    ///   - now: 今日の基準。テストで固定の日時にする。
    ///   - announce: VoiceOver に読み上げさせる（月を替えたときに、替えた月を読む）。テストで読み上げる文を集める。
    init(
        store: EntryStore, budgetStore: BudgetStore, recurring: RecurringEntryStore, now: @escaping () -> Date,
        announce: @escaping @MainActor (String) -> Void = { VoiceOver.announce($0) }
    ) {
        self.store = store
        self.budgetStore = budgetStore
        self.recurring = recurring
        self.now = now
        self.announce = announce
    }

    // MARK: - 見せる月

    /// 画面の暦を受け取る（ホームが出たときと、週の始まりの設定が変わったとき）。まだ月を決めていなければ今月を見せる。
    func configure(calendar: Calendar) {
        let changed = calendar != self.calendar
        self.calendar = calendar
        if month == nil || changed {
            show(monthContaining: month?.start ?? now(), selecting: selectedDay)
        }
    }

    /// 今月を見せているか（見通しを出すか）。
    var isCurrentMonth: Bool {
        guard let month else { return false }
        let today = now()
        return month.start <= today && today < month.end
    }

    /// 今月より先の月を見ているか（月のまとめは今月より先を出さないので、入口を出さない）。
    var isFutureMonth: Bool {
        guard let month else { return false }
        return month.start > now()
    }

    /// 今月の今日を選んでいるか（「今日」のボタンを押せなくする）。
    var isShowingToday: Bool {
        guard isCurrentMonth, let selectedDay else { return false }
        return calendar.isDate(selectedDay, inSameDayAs: now())
    }

    /// 見せている月の題（「2026年10月」「October 2026」）。読み上げに使う。
    var monthTitle: String {
        monthTitle(.wide)
    }

    /// 帯に出す月の題（「2026年10月」「Oct 2026」）。英語の月の名前は長く、略さないと帯が 1 行に収まらないため、略した形にする。
    var shortMonthTitle: String {
        monthTitle(.abbreviated)
    }

    private func monthTitle(_ width: Date.FormatStyle.Symbol.Month) -> String {
        guard let month else { return "" }
        var style = Date.FormatStyle.dateTime.year().month(width)
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return month.start.formatted(style)
    }

    /// 今月を見せて、今日を選ぶ（「今日」のボタン）。
    func showThisMonth() {
        let changesMonth = !isCurrentMonth
        show(monthContaining: now(), selecting: nil)
        if changesMonth { announce(monthTitle) }
    }

    /// 前の月・次の月を見せる。替えた月を読み上げる（月の題は画面の上にあり、VoiceOver のフォーカスは押したボタンに残るため）。
    func showMonth(offset: Int) {
        guard let month, let date = calendar.date(byAdding: .month, value: offset, to: month.start) else { return }
        show(monthContaining: date, selecting: nil)
        announce(monthTitle)
    }

    private func show(monthContaining date: Date, selecting day: Date?) {
        month = ReportPeriod.thisMonth.interval(now: date, calendar: calendar)
        selectedDay = day
        reload()
    }

    // MARK: - 読み込み

    /// 前面に戻ったときと、日付が変わったとき（0 時・時間帯の変更）に読み直す。今日を見ていたなら、日付が変わっても今日を見せる
    /// （開いたまま・裏に置いたまま日をまたいだとき、昨日の日や先月のままにしない）。ほかの日やほかの月を見ていたら、そのまま。
    func refreshToday() {
        guard month != nil else { return }
        if let lastToday, !calendar.isDate(lastToday, inSameDayAs: now()) {
            let wasShowingToday = selectedDay.map { calendar.isDate($0, inSameDayAs: lastToday) } ?? false
            let wasShowingThisMonth = month.map { $0.start <= lastToday && lastToday < $0.end } ?? false
            if wasShowingThisMonth, !isCurrentMonth {
                show(monthContaining: now(), selecting: nil)
                return
            }
            if wasShowingToday { selectedDay = nil }
        }
        reload()
    }

    /// 記録・予算・くり返しの記録を読み直す（保存したとき・ほかの端末の変更が届いたとき・前面に戻ったとき）。
    func reload() {
        guard let month else { return }
        let today = now()
        lastToday = calendar.startOfDay(for: today)
        do {
            monthRecords = try store.context.fetch(Entry.descriptor(spentIn: month)).map(DayRecord.init)
            loadFailed = false
        } catch {
            monthRecords = []
            loadFailed = true
        }
        // 予算と決まりを読めなくても、記録の集計は出す（予算の印と予定を出さないだけ）。
        budget = (try? budgetStore.plan())?.amount(for: .total)
        let rules = ((try? recurring.rules()) ?? []).compactMap(\.rule)
        days = LedgerCalendarMonth(records: monthRecords, month: month, calendar: calendar)
        planned = RecurringSchedule.plannedOccurrences(for: rules, in: month, now: today, timeZone: calendar.timeZone)
        outlook = SpendingOutlook(
            budget: budget,
            records: monthRecords.map {
                SpendingOutlook.Record(amount: $0.amount, isIncome: $0.isIncome, spentAt: $0.spentAt, isRecurring: $0.isRecurring)
            },
            rules: rules, now: today, month: month, calendar: calendar
        )
        // 選んだ日が見せている月の外なら外す。今月で選んでいなければ今日を選ぶ（ほかの月は、日を押すまで選ばない）。
        if let selectedDay, !(month.start <= selectedDay && selectedDay < month.end) {
            self.selectedDay = nil
        }
        if self.selectedDay == nil, isCurrentMonth {
            self.selectedDay = calendar.startOfDay(for: today)
        }
        updateSelectedRecords()
    }

    // MARK: - 日を選ぶ

    func select(_ day: LedgerCalendarMonth.Day) {
        selectedDay = day.start
        updateSelectedRecords()
    }

    /// 選んでいる日の集計。
    var selectedSummary: LedgerCalendarMonth.Day? {
        guard let selectedDay else { return nil }
        return days?.day(containing: selectedDay, calendar: calendar)
    }

    /// その日の予定（まだ記録していないくり返しの記録）。
    func planned(on day: Date) -> [PlannedOccurrence] {
        planned.filter { calendar.isDate($0.date, inSameDayAs: day) }
    }

    /// 予算の日割りより多く使った日か（日の印）。予算を決めていなければ false。
    func exceedsPace(_ day: LedgerCalendarMonth.Day) -> Bool {
        guard let pace = days?.dailyPace(budget: budget) else { return false }
        return day.expense > pace
    }

    /// 今日か。
    func isToday(_ day: LedgerCalendarMonth.Day) -> Bool {
        calendar.isDate(day.start, inSameDayAs: now())
    }

    /// 今日より後の日か（まだ来ていない日は薄く出す）。
    func isFuture(_ day: LedgerCalendarMonth.Day) -> Bool {
        day.start > now()
    }

    private func updateSelectedRecords() {
        guard let selectedDay else {
            selectedRecords = []
            return
        }
        selectedRecords = monthRecords
            .filter { calendar.isDate($0.spentAt, inSameDayAs: selectedDay) }
            .sorted { ($0.spentAt, $0.createdAt) < ($1.spentAt, $1.createdAt) }
    }

    // MARK: - 直す・消す

    /// 一覧の記録を引く（直す・消す）。ほかの端末で消されていたら nil を返し、読み直して一覧から外す。
    func entry(for record: DayRecord) -> Entry? {
        guard store.exists(record.id), let entry = store.context.model(for: record.id) as? Entry else {
            reload()
            return nil
        }
        return entry
    }
}
