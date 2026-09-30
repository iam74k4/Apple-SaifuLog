import Foundation
import Observation
import SaifuLogCore

/// くり返しの記録を作る・直すシート（下から出す）の状態と操作。金額・品目・支出か収入か・カテゴリ・毎月の日を決めて保存する。
///
/// 設定の「くり返しの記録」（作る・直す）と、ホームの返事の行の長押しの「毎月くり返す」（その記録の中身を入れて作る）から開く。
/// 画面（`RecurringEditorSheet`）から切り離し、保存先・時計・読み上げを差し替えて SaifuLogTests で確かめられるようにしている。
@MainActor
@Observable
final class RecurringEditorModel: Identifiable {
    /// 作るか、どの決まりを直すか。
    enum Mode: Equatable {
        case create
        case edit(String)
    }

    let mode: Mode
    /// 金額の入力欄（「80,000」の形）。
    var amountText: String
    var memo: String
    var isIncome: Bool
    var category: EntryCategory
    /// 毎月の何日か（1〜31。31 は月末）。
    var dayOfMonth: Int
    /// 今月の記録する日を過ぎているとき、今月の分も記録するか（作るときだけ）。
    var includesThisMonth = false
    /// 保存・やめるに失敗した（アラートを出す）。
    var failure: Failure?
    /// 「やめる」の確認を出しているか。
    var showsDeleteConfirmation = false

    @ObservationIgnored private let store: RecurringEntryStore
    @ObservationIgnored private let original: RecurringDraft?
    /// 今月の分をもう記録してある（記録から作った）なら、その次の月。この月より前からは記録しない。
    @ObservationIgnored private let notBefore: RecurringMonth?
    /// 直すときの、最初の月と記録を済ませた月（次に記録する日を出すため）。
    @ObservationIgnored private let schedule: (start: RecurringMonth, last: RecurringMonth?)?
    @ObservationIgnored private let timeZone: TimeZone
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let announce: @MainActor (String) -> Void
    @ObservationIgnored private let didChange: @MainActor () -> Void

    /// 作る。
    ///
    /// - Parameters:
    ///   - prefill: 入れておく中身（「毎月くり返す」で、その記録の金額・品目・カテゴリ・使った日）。無ければ空。
    ///   - notBefore: 今月の分をもう記録してある（記録から作った）なら、その次の月（今月の分をもう一度記録しないように）。
    ///   - didChange: 保存・やめたあとに呼ぶ（ホームが、記録する日を過ぎた分をすぐ記録する）。
    init(
        creating prefill: RecurringDraft? = nil,
        notBefore: RecurringMonth? = nil,
        store: RecurringEntryStore,
        timeZone: TimeZone,
        now: @escaping () -> Date = { .now },
        announce: @escaping @MainActor (String) -> Void = { VoiceOver.announce($0) },
        didChange: @escaping @MainActor () -> Void = {}
    ) {
        mode = .create
        let draft = prefill ?? RecurringDraft(amount: 0, memo: "", isIncome: false, category: .other, dayOfMonth: 25)
        amountText = EntryAmountInput.text(for: draft.amount)
        memo = draft.memo
        isIncome = draft.isIncome
        category = draft.category
        dayOfMonth = draft.dayOfMonth
        original = nil
        self.notBefore = notBefore
        schedule = nil
        self.store = store
        self.timeZone = timeZone
        self.now = now
        self.announce = announce
        self.didChange = didChange
    }

    /// 直す。
    init(
        editing row: RecurringEntry,
        store: RecurringEntryStore,
        timeZone: TimeZone,
        now: @escaping () -> Date = { .now },
        announce: @escaping @MainActor (String) -> Void = { VoiceOver.announce($0) },
        didChange: @escaping @MainActor () -> Void = {}
    ) {
        mode = .edit(row.recurrenceID)
        let draft = row.draft
        amountText = EntryAmountInput.text(for: draft.amount)
        memo = draft.memo
        isIncome = draft.isIncome
        category = draft.category
        dayOfMonth = draft.dayOfMonth
        original = draft
        notBefore = nil
        schedule = row.rule.map { ($0.startMonth, $0.lastRecordedMonth) }
        self.store = store
        self.timeZone = timeZone
        self.now = now
        self.announce = announce
        self.didChange = didChange
    }

    // MARK: - 入力の確かめ

    /// 金額を保存できない理由。空欄のうちは出さない（打ち始める前から注意を出さない）。
    var amountIssue: EntryAmountIssue? {
        guard !amountText.isEmpty, case .failure(let issue) = EntryAmountInput.validate(amountText) else { return nil }
        return issue
    }

    var canSave: Bool {
        guard let draft else { return false }
        return draft != original
    }

    /// 入力欄の中身（保存できる金額のときだけ）。
    private var draft: RecurringDraft? {
        guard case .success(let amount) = EntryAmountInput.validate(amountText) else { return nil }
        return RecurringDraft(
            amount: amount, memo: memo.trimmingCharacters(in: .whitespacesAndNewlines), isIncome: isIncome,
            category: isIncome ? .other : category, dayOfMonth: dayOfMonth
        )
    }

    /// 金額の入力欄を見せる形にそろえる（3 桁ごとのカンマ）。
    func normalizeAmountText() {
        let formatted = EntryAmountInput.formatted(amountText)
        if formatted != amountText { amountText = formatted }
    }

    // MARK: - 日付

    /// 「今月の分も記録する」を出すか（作るときで、今月の記録する日を過ぎていて、今月の分をまだ記録していないとき）。
    var showsThisMonthChoice: Bool {
        mode == .create && notBefore == nil
            && RecurringSchedule.hasPassedThisMonth(dayOfMonth: dayOfMonth, now: now(), timeZone: timeZone)
    }

    /// 保存したときの決まり（最初の月と記録を済ませた月を、いまの入力で決めたもの）。
    private var previewRule: RecurringRule {
        let start: RecurringMonth
        let last: RecurringMonth?
        if let schedule {
            (start, last) = (schedule.start, schedule.last)
        } else {
            start = RecurringSchedule.startMonth(
                dayOfMonth: dayOfMonth, now: now(), timeZone: timeZone, includesThisMonth: showsThisMonthChoice && includesThisMonth,
                notBefore: notBefore
            )
            last = nil
        }
        return RecurringRule(
            id: "", memo: memo, amount: 0, isIncome: isIncome, category: category, dayOfMonth: dayOfMonth, startMonth: start,
            lastRecordedMonth: last
        )
    }

    /// 保存したらすぐ記録する日（記録する日を過ぎた、まだ記録していない月の分。いちばん新しい月）。無ければ nil。
    var recordsImmediately: Date? {
        let rule = previewRule
        return RecurringSchedule.dueMonths(for: rule, now: now(), timeZone: timeZone).last
            .flatMap { RecurringSchedule.date(in: $0, dayOfMonth: rule.dayOfMonth, timeZone: timeZone) }
    }

    /// 次に記録する日（すぐ記録する分を除く）。
    var nextDate: Date? {
        RecurringSchedule.nextDate(for: previewRule, now: now(), timeZone: timeZone)
    }

    // MARK: - 保存・やめる

    /// 保存する。保存できたら true（呼び出し側がシートを閉じる）。
    @discardableResult
    func save() -> Bool {
        guard let draft, canSave else { return false }
        do {
            switch mode {
            case .create:
                try store.create(draft, startMonth: previewRule.startMonth)
            case .edit(let id):
                try store.update(id, with: draft)
            }
        } catch {
            failure = .save
            return false
        }
        switch mode {
        case .create: announce(String(localized: "くり返しの記録を足しました"))
        case .edit: announce(String(localized: "くり返しの記録を直しました"))
        }
        didChange()
        return true
    }

    /// やめる（決まりを消す。記録したものは残す）。できたら true。
    @discardableResult
    func delete() -> Bool {
        guard case .edit(let id) = mode else { return false }
        do {
            try store.delete(id)
        } catch {
            failure = .delete
            return false
        }
        announce(String(localized: "くり返しの記録をやめました"))
        didChange()
        return true
    }

    /// 保存・やめるの失敗。
    enum Failure: Equatable {
        case save
        case delete
    }
}
