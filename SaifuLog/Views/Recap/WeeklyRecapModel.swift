import Foundation
import Observation
import SaifuLogCore
import SwiftData

/// 先週のふりかえりの状態と操作。ホームのタイムラインのカードと、カードから横に進む内訳の画面が同じものを使う。
///
/// 数字はコア（`WeeklyRecap`・`BudgetSuggestion`）が計算し、ここでは保存先からの読み込みと、内訳から開くカテゴリの記録の一覧・
/// 「直す」（⑥）のシート、AI の一言（`RecapRemarkModel`）の受け渡しだけを受け持つ。画面（`WeeklyRecapCard`・`WeeklyRecapView`）から
/// 切り離し、保存先・時計・プレミアムの状態・AI を差し替えて SaifuLogTests で確かめられるようにしている。
///
/// 「先週」は、カードを出した日時（`shownAt`）を含む週の前の週。開いたまま週が替わったら、ホームが新しいカードに替える
/// （`HomeModel.showWeeklyRecapIfDue`）。読み直すのは、保存先に書き込まれたとき（画面が `ModelContext.didSave` を受けて
/// `reload()` を呼ぶ）・ここから直したり消したりしたとき・週の始まりを変えたとき（`update(calendar:)`）。
@MainActor
@Observable
final class WeeklyRecapModel: Identifiable {
    /// 予算についての案内（カードの下の段）。
    enum BudgetPrompt: Equatable {
        /// 予算が無い人に「予算を決める」を出す（目安を出せれば添える）。
        case setBudget(BudgetSuggestion?)
        /// 予算がある人に、目安といまの予算の差が大きいときだけ「予算を変更」を出す。
        case changeBudget(BudgetSuggestion, current: Int)
    }

    let id = UUID()
    /// カードを出した日時。「先週」の基準で、タイムラインではこの日時の位置に並べる。
    let shownAt: Date
    /// 週と日と月の区切り、日付の書き方の暦（ホームの画面の暦。週の始まりは設定のとおり）。
    private(set) var calendar: Calendar
    /// 先週の数字。読み込めなかったときは nil。
    private(set) var recap: WeeklyRecap?
    /// いまの月の全体の予算。決めていなければ nil。
    private(set) var budget: Int?
    /// 月の予算の目安。記録が 1 か月分に満たないなどで出せなければ nil。
    private(set) var suggestion: BudgetSuggestion?
    /// 保存先を読めなかった（内訳の画面は再試行のボタンを出し、カードは出さない）。
    private(set) var loadFailed = false
    /// 先週の記録（支出と収入）。内訳から開くカテゴリの記録の一覧に使う。
    private(set) var weekEntries: [Entry] = []
    /// 今日。日付に年を添えるかの基準。
    private(set) var today: Date
    /// 記録の一覧を出しているカテゴリ（横に進む）。一覧を閉じると画面が nil に戻す。
    var selectedCategory: EntryCategory?
    /// 「直す」のシートで直している記録。シートを閉じると画面が nil に戻す。
    var editing: EditEntryModel?
    /// AI の一言（プレミアムと体験中で、AI が使える端末だけ）。
    let remark: RecapRemarkModel

    @ObservationIgnored private let store: EntryStore
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let announce: @MainActor (String) -> Void
    @ObservationIgnored private let didSave: @MainActor (Entry) -> Void
    @ObservationIgnored private let didDelete: @MainActor (PersistentIdentifier) -> Void

    /// - Parameters:
    ///   - calendar: 週の区切りの暦（ホームの画面の暦）。
    ///   - shownAt: カードを出した日時。先週はこの日時を含む週の前の週。
    ///   - remark: AI の一言の状態と書かせ方。
    ///   - now: 今日の基準。テストで固定の日時にする。
    ///   - didSave: 内訳から開いた「直す」で保存できたあとに呼ぶ（ホームが「取り消す」を片づける）。
    ///   - didDelete: 内訳から開いた「直す」で削除できたあとに、消した記録の ID を渡して呼ぶ。
    init(
        store: EntryStore,
        calendar: Calendar,
        shownAt: Date,
        remark: RecapRemarkModel,
        now: @escaping () -> Date = { .now },
        announce: @escaping @MainActor (String) -> Void = { VoiceOver.announce($0) },
        didSave: @escaping @MainActor (Entry) -> Void = { _ in },
        didDelete: @escaping @MainActor (PersistentIdentifier) -> Void = { _ in }
    ) {
        self.store = store
        self.calendar = calendar
        self.shownAt = shownAt
        self.remark = remark
        self.now = now
        self.announce = announce
        self.didSave = didSave
        self.didDelete = didDelete
        self.today = now()
        reload()
    }

    // MARK: - 読み込み

    /// 先週の数字と予算の目安を読み直す。数字の文が変わったら、AI の一言も書き直す。
    func reload() {
        today = now()
        let context = store.context
        do {
            guard let range = Self.readingRange(shownAt: shownAt, calendar: calendar) else {
                throw ReadingRangeError()
            }
            let records = try context.fetch(Entry.descriptor(spentIn: range))
            let budgets = try context.fetch(FetchDescriptor<Budget>())
            let earliest = try context.fetch(Entry.earliestDescriptor).first?.spentAt
            let plan = BudgetPlan.resolve(budgets)
            let recap = WeeklyRecap(
                records: records, now: shownAt, budget: plan.total,
                budgetDecidedAt: BudgetPlan.decidedAt(.total, in: budgets), calendar: calendar
            )
            self.recap = recap
            budget = plan.total
            suggestion = BudgetSuggestion(records: records, recordingStartedAt: earliest, now: shownAt, calendar: calendar)
            if let week = recap?.week {
                weekEntries = records.filter { $0.spentAt >= week.start && $0.spentAt < week.end }
            } else {
                weekEntries = []
            }
            loadFailed = false
            // AI に渡す文にも作ったカテゴリの名前を書く（読めなければ組み込みの名前だけ）。
            let catalog = (try? CustomCategoryStore(context: context).catalog()) ?? .builtIn
            remark.update(facts: recap.flatMap { RecapFacts.text(for: $0, calendar: calendar, catalog: catalog) })
        } catch {
            recap = nil
            suggestion = nil
            weekEntries = []
            loadFailed = true
            remark.update(facts: nil)
        }
    }

    /// 週の始まり（画面の暦）が変わったら、変えた後の週で数え直す。
    func update(calendar: Calendar) {
        guard calendar != self.calendar else { return }
        self.calendar = calendar
        selectedCategory = nil
        reload()
    }

    /// 読む範囲: 前の週の始まり（前の週との差のため）か、予算の目安に使う 3 か月前の月の始まりの早いほうから、先週の終わりか
    /// 今月の始まりの遅いほうまで。
    static func readingRange(shownAt: Date, calendar: Calendar) -> DateInterval? {
        guard let week = ReportPeriod.lastWeek.interval(now: shownAt, calendar: calendar),
              let previousWeek = ReportPeriod.lastWeek.interval(now: week.start, calendar: calendar),
              let thisMonth = ReportPeriod.thisMonth.interval(now: shownAt, calendar: calendar)
        else { return nil }
        var monthStart = thisMonth.start
        for _ in 0..<BudgetSuggestion.monthsToLookBack {
            guard let previous = ReportPeriod.lastMonth.interval(now: monthStart, calendar: calendar) else { return nil }
            monthStart = previous.start
        }
        return DateInterval(start: min(previousWeek.start, monthStart), end: max(week.end, thisMonth.start))
    }

    private struct ReadingRangeError: Error {}

    // MARK: - カードの中身

    /// 予算についての案内。予算が無ければ「予算を決める」（目安を出せれば添える）、予算があれば目安との差が大きいときだけ
    /// 「予算を変更」。どちらでもなければ nil（何も出さない）。表示するだけで、予算は変えない。
    var budgetPrompt: BudgetPrompt? {
        guard let budget else { return .setBudget(suggestion) }
        guard let suggestion, suggestion.differsNotably(from: budget) else { return nil }
        return .changeBudget(suggestion, current: budget)
    }

    /// 先週の期間の見出し（「9月21日～27日」）。週を区切ったのと同じ暦・時間帯で書く。
    var periodTitle: String {
        guard let week = recap?.week else { return "" }
        return QuestionTexts.dateRange(week, calendar: calendar)
    }

    // MARK: - カテゴリの記録

    /// 記録の一覧へ進む（内訳の行から）。
    func showEntries(in category: EntryCategory) {
        selectedCategory = category
    }
}

/// カテゴリの記録の一覧（`CategoryEntriesView`）に、先週の記録を出す。
extension WeeklyRecapModel: CategoryEntriesSource {
    var emptyEntriesText: LocalizedStringResource {
        "この週の記録はありません"
    }

    /// 先週の、そのカテゴリの支出の記録。使った日時の新しい順（同じ日時なら記録した順の新しいほうから。⑦ の一覧と同じ）。
    func entries(in category: EntryCategory) -> [Entry] {
        weekEntries
            .filter { !$0.isIncome && $0.category == category }
            .sorted { a, b in a.spentAt != b.spentAt ? a.spentAt > b.spentAt : a.createdAt > b.createdAt }
    }

    func breakdownItem(for category: EntryCategory) -> CategoryBreakdown.Item? {
        recap?.breakdown.item(for: category)
    }

    /// 一覧の記録から「直す」のシートを出す。直したり消したりしたら読み直す（カードと内訳の数字をすぐ合わせるため）。
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
extension WeeklyRecapModel: Hashable {
    nonisolated static func == (lhs: WeeklyRecapModel, rhs: WeeklyRecapModel) -> Bool {
        lhs === rhs
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}
