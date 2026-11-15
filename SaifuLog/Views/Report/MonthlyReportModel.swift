import Foundation
import Observation
import SaifuLogCore
import SwiftData

/// 「月のまとめ」（⑦。月の画面）の状態と操作。表示する月と月送り、「内訳」と「カレンダー」の切り替え、その月の数字
/// （`MonthlyReport`）、カテゴリごとの記録の一覧、日ごとのカレンダー（`LedgerCalendarModel`）、記録から開く「直す」（⑥）のシート。
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
    /// 今日。今月より先へ進めないことと、今月かどうか（予算の残りの日数）の基準。
    private(set) var today: Date
    /// 表示している月の数字。読み込めなかったときは nil。
    private(set) var report: MonthlyReport?
    /// 保存先を読めなかった（再試行のボタンを出す）。
    private(set) var loadFailed = false
    /// 使った日時のいちばん古い記録の日時。記録が 1 件も無ければ nil。これより前の月へは戻れない。
    private(set) var earliestSpentAt: Date?
    /// 表示している月の記録（支出と収入）。
    private(set) var monthEntries: [Entry] = []
    /// 表示している月の支出を、払ったカードごとに分けた合計（カードを登録していれば出す）。
    private(set) var paymentBreakdown: PaymentBreakdown?
    /// 出している見方（内訳かカレンダー）。月を替えてもそのまま。替えたらホームに知らせ、次に開くときもその見方で開く。
    var tab: Tab = .breakdown {
        didSet { if tab != oldValue { tabDidChange(tab) } }
    }
    @ObservationIgnored private let tabDidChange: @MainActor (Tab) -> Void
    /// 「カレンダー」の日ごとの集計と選んだ日の記録。月はこの画面の月に合わせる。
    let days: LedgerCalendarModel
    /// 記録の一覧を出している絞り方（カテゴリか払い方。横に進む）。一覧を閉じると画面が nil に戻す。
    var selectedFilter: ReportEntryFilter?
    /// 「直す」のシートで直している記録の状態と操作。シートを閉じると画面が nil に戻す。
    var editing: EditEntryModel?
    /// 記録の一覧の長押しで消そうとしている記録（確認を出している間）。
    var pendingDeletion: HomeModel.PendingDeletion?
    /// 消せなかった（保存に失敗した）ことを知らせているか。
    var showsDeleteFailure = false
    #if DEBUG
    /// まとめを下の端（カテゴリ別のグラフと金額の行）まで送るか。撮影用のデモ（`ScreenshotDemo`）が、月のまとめの
    /// スクリーンショットを撮るときだけ使う（DEBUG のビルドだけ）。
    var screenshotScrollsToBottom = false
    #endif

    /// 月の区切りと日付の書き方の暦（ホームの画面の暦）。
    let calendar: Calendar

    @ObservationIgnored private let store: EntryStore
    /// いまのカードの一覧（支払い方法の内訳に使う）。無ければ内訳を出さない。
    @ObservationIgnored private let cards: CardCatalogModel?
    /// カレンダーの記録の長押しの「毎月くり返す」（ホームがくり返しの記録を作るシートを出す）。nil なら出さない。
    @ObservationIgnored let makeRecurring: (@MainActor (Entry) -> Void)?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let announce: @MainActor (String) -> Void
    @ObservationIgnored private let didSave: @MainActor (Entry) -> Void
    @ObservationIgnored private let didDelete: @MainActor (PersistentIdentifier) -> Void

    /// - Parameters:
    ///   - calendar: 月の区切りの暦。ホームと同じ暦を渡す（ホームの今月の合計と同じ月でまとめるため）。
    ///   - month: 開く月に入る日時（質問の回答カードから先月を開くときなど）。nil なら今月。今月より先の月は今月にする
    ///     （月送りで今月より先へ進めないのと同じ）。
    ///   - now: 今日の基準。テストで固定の日時にする。
    ///   - announce: VoiceOver に読み上げさせる。テストで読み上げる文を集める。
    ///   - didSave: ここから開いた「直す」で保存できたあとに呼ぶ（ホームが「取り消す」を片づける）。
    ///   - didDelete: ここから開いた「直す」で削除できたあとに、消した記録の ID を渡して呼ぶ（ホームが「取り消す」の対象から外す）。
    ///   - makeRecurring: カレンダーの記録の長押しの「毎月くり返す」で、その記録を渡して呼ぶ。nil なら出さない。
    ///   - tab: 開くときの見方（ホームが前に選んだ見方を覚えて渡す。前は毎回「内訳」から開き、カレンダーを選び直していた）。
    ///   - tabDidChange: 見方を替えたときに呼ぶ（ホームが覚える）。
    init(
        store: EntryStore,
        cards: CardCatalogModel? = nil,
        calendar: Calendar,
        month anchor: Date? = nil,
        now: @escaping () -> Date = { .now },
        announce: @escaping @MainActor (String) -> Void = { VoiceOver.announce($0) },
        didSave: @escaping @MainActor (Entry) -> Void = { _ in },
        didDelete: @escaping @MainActor (PersistentIdentifier) -> Void = { _ in },
        makeRecurring: (@MainActor (Entry) -> Void)? = nil,
        tab: Tab = .breakdown,
        tabDidChange: @escaping @MainActor (Tab) -> Void = { _ in }
    ) {
        let today = now()
        self.tab = tab
        self.tabDidChange = tabDidChange
        self.makeRecurring = makeRecurring
        self.store = store
        self.cards = cards
        self.calendar = calendar
        self.now = now
        self.announce = announce
        self.didSave = didSave
        self.didDelete = didDelete
        self.today = today
        // 暦で月を区切れないことは実際には無いが、そのときは数字を出さない（report が nil のまま）。
        let month = ReportPeriod.thisMonth.interval(now: min(anchor ?? today, today), calendar: calendar)
            ?? DateInterval(start: today, duration: 0)
        self.month = month
        days = LedgerCalendarModel(store: store, now: now)
        days.follow(monthContaining: month.start, calendar: calendar)
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

    /// 今月を見ているか（下のバーの「今月」を出さない）。
    var isCurrentMonth: Bool {
        month.start <= today && today < month.end
    }

    /// 今月へ戻る（下のバーの「今月」）。
    func showThisMonth() {
        guard !isCurrentMonth, let current = ReportPeriod.thisMonth.interval(now: today, calendar: calendar) else { return }
        show(current)
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
        selectedFilter = nil
        days.follow(monthContaining: newMonth.start, calendar: calendar)
        reload()
        announce(monthTitle)
    }

    // MARK: - 読み込み

    /// 表示している月の数字とカレンダーを読み直す。
    func reload() {
        days.reload()
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
            // カードを登録していて、この月にカードの記録があるときだけ、支払い方法の内訳を出す（カードを使わない人に出さないため）。
            let breakdown = cards.map { PaymentBreakdown(records: monthEntries, interval: month, cards: $0.cards) }
            paymentBreakdown = breakdown?.hasCardRecords == true ? breakdown : nil
            loadFailed = false
        } catch {
            report = nil
            monthEntries = []
            paymentBreakdown = nil
            loadFailed = true
        }
    }

    /// 「今日」を読み直す。前面に戻ったときと、日付が変わったときに呼ぶ（今月かどうかと予算の残りの日数が変わるため）。
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
        selectedFilter = .category(category)
    }

    /// 表示している月の、その払い方の支出の記録（並びはカテゴリの一覧と同じ）。`cardID` が空なら現金・その他（一覧に無いカードの
    /// 記録も含む。支払い方法の内訳と同じ数え方）。
    func entries(paidWith cardID: String) -> [Entry] {
        let known = Set(cards?.cards.map(\.id) ?? [])
        return monthEntries
            .filter { entry in
                guard !entry.isIncome else { return false }
                let paidCard = known.contains(entry.cardID) ? entry.cardID : ""
                return paidCard == cardID
            }
            .sorted { a, b in a.spentAt != b.spentAt ? a.spentAt > b.spentAt : a.createdAt > b.createdAt }
    }

    /// その払い方の記録の一覧へ進む（支払い方法の内訳の行）。`cardID` が空なら現金・その他。
    func showEntries(paidWith cardID: String) {
        selectedFilter = .payment(cardID: cardID)
    }

    /// 絞り方に合う記録。
    func entries(for filter: ReportEntryFilter) -> [Entry] {
        switch filter {
        case .category(let category): entries(in: category)
        case .payment(let cardID): entries(paidWith: cardID)
        }
    }

    /// 払い方の名前（カードの名前。現金・その他や一覧に無いカードなら nil）。
    func cardName(for cardID: String) -> String? {
        cards?.card(id: cardID)?.name
    }

    /// 一覧の記録から「直す」のシートを出す。直したり消したりしたら読み直す（数字と一覧をすぐ合わせるため）。
    ///
    /// ほかの端末（iCloud）で消された記録なら開かずに読み直す（シートは開いた時点の記録の値を読むので、消えた記録の値を
    /// 読むとアプリが落ちうるため。カレンダーの一覧と同じ）。削除の確認と読み上げに作ったカテゴリの名前を使うよう、
    /// カテゴリの一覧を渡す（渡さないと、作ったカテゴリが「その他」と読まれる）。
    func presentEdit(_ entry: Entry) {
        guard store.exists(entry.persistentModelID) else {
            reload()
            return
        }
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
            },
            catalog: (try? CustomCategoryStore(context: store.context).catalog()) ?? .builtIn
        )
    }
}

extension MonthlyReportModel {
    /// 一覧の記録の長押しの「削除」。確認を出す（ホームとカレンダーの記録と同じく、長押しでいつでも消せるようにする。
    /// 前は ⑥ を開かないと消せなかった）。ほかの端末で消されていたら、確認を出さずに読み直す。
    func requestDelete(_ entry: Entry) {
        guard store.exists(entry.persistentModelID) else {
            reload()
            return
        }
        let catalog = (try? CustomCategoryStore(context: store.context).catalog()) ?? .builtIn
        pendingDeletion = HomeModel.PendingDeletion(
            entry: entry, id: entry.persistentModelID, summary: entry.summaryText(in: catalog)
        )
    }

    /// 確認のあとで記録を削除する。確認の間にほかの端末で消されていたら、消えたものとして扱う（記録の値には触れない）。
    func delete(_ pending: HomeModel.PendingDeletion) {
        pendingDeletion = nil
        if store.exists(pending.id) {
            do {
                try store.delete([pending.entry])
            } catch {
                showsDeleteFailure = true
                return
            }
        }
        reload()
        // ホームの「取り消す」の対象からも外す（⑥ から消したときと同じ）。
        didDelete(pending.id)
        announce(String(localized: "削除しました: \(pending.summary)"))
    }
}

extension MonthlyReportModel {
    /// 月の画面の見方。
    enum Tab: Hashable {
        /// 予算とカテゴリ別の内訳（支払い方法の内訳も）。
        case breakdown
        /// 日ごとに使った額のカレンダーと、選んだ日の記録。
        case calendar
    }
}

/// 月の画面から進む記録の一覧の絞り方。
enum ReportEntryFilter: Hashable {
    /// カテゴリ別の内訳の行から。
    case category(EntryCategory)
    /// 支払い方法の内訳の行から（空は現金・その他）。
    case payment(cardID: String)
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
