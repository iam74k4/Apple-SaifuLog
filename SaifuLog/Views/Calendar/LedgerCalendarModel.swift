import Foundation
import Observation
import SaifuLogCore
import SwiftData

/// 月の画面（⑦ 月のまとめ）の「カレンダー」の状態と操作。見せる月は月の画面（`MonthlyReportModel`）が決める。
///
/// 見せる月の記録だけを読み（全期間を読まない。記録が増えても重くならないように）、日ごとの集計（`LedgerCalendarMonth`）を出す。
/// 「いくら使ったか」が分かることだけに絞る（見通し・予算の印・くり返しの予定は出さない。月のまとめと会話の質問にある）。
/// 数字はコアで数え、ここでは数え直さない。
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
        /// 払ったカードの ID（空は現金・その他）。
        let cardID: String
        /// くり返しの記録から記録したものか（行の長押しに「毎月くり返す」を出さない）。
        let isRecurring: Bool

        init(_ entry: Entry) {
            id = entry.persistentModelID
            amount = entry.amount
            isIncome = entry.isIncome
            category = entry.category
            memo = entry.memo
            spentAt = entry.spentAt
            createdAt = entry.createdAt
            cardID = entry.cardID
            isRecurring = entry.source == .recurring
        }
    }

    /// 見せている月。
    private(set) var month: DateInterval?
    /// 見せている月の日ごとの集計。
    private(set) var days: LedgerCalendarMonth?
    /// 選んでいる日の始まり。
    private(set) var selectedDay: Date?
    /// 選んでいる日の記録（使った日時の順）。
    private(set) var selectedRecords: [DayRecord] = []
    /// 記録を読めなかったか（画面に知らせを出す）。
    private(set) var loadFailed = false

    @ObservationIgnored private let store: EntryStore
    @ObservationIgnored private let now: () -> Date
    /// 日を区切る暦（月の画面の暦。週の始まりは端末の設定のとおり）。`follow(monthContaining:calendar:)` で受け取る。
    @ObservationIgnored private(set) var calendar = Calendar.current
    /// 見せている月の記録（日を選び直すたびに読み直さないよう持っておく）。
    @ObservationIgnored private var monthRecords: [DayRecord] = []

    /// - Parameter now: 今日の基準。テストで固定の日時にする。
    init(store: EntryStore, now: @escaping () -> Date) {
        self.store = store
        self.now = now
    }

    // MARK: - 見せる月

    /// 月の画面が見せている月に合わせる（開いたとき・月を替えたとき）。選んでいた日は外す。読み込みは `reload()` で
    /// （月の画面が自分の数字といっしょに読み直す）。
    func follow(monthContaining date: Date, calendar: Calendar) {
        self.calendar = calendar
        month = ReportPeriod.thisMonth.interval(now: date, calendar: calendar)
        selectedDay = nil
    }

    /// 今月を見せているか。
    private var isCurrentMonth: Bool {
        guard let month else { return false }
        let today = now()
        return month.start <= today && today < month.end
    }

    // MARK: - 読み込み

    /// 記録を読み直す（月を替えたとき・保存したとき・ほかの端末の変更が届いたとき・前面に戻ったとき）。
    func reload() {
        guard let month else { return }
        let today = now()
        do {
            monthRecords = try store.context.fetch(Entry.descriptor(spentIn: month)).map(DayRecord.init)
            loadFailed = false
        } catch {
            monthRecords = []
            loadFailed = true
        }
        days = LedgerCalendarMonth(records: monthRecords, month: month, calendar: calendar)
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
