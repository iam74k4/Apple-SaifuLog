import Foundation
import SaifuLogCore
import SwiftData
import Testing
@testable import SaifuLog

/// くり返しの記録を作る・直すシート（`RecurringEditorModel`）と、設定の一覧（`RecurringListModel`）。
@MainActor
struct RecurringEditorModelTests {
    static let timeZone = TestSupport.calendar.timeZone

    /// 保存先と、読み上げ・変わったことの知らせを集める。いまは 2026-10-10 12:00。
    @MainActor
    final class Fixture {
        let context: ModelContext
        var now = TestSupport.date(2026, 10, 10, hour: 12)
        var failsSave = false
        private(set) var announcements: [String] = []
        private(set) var changes = 0
        private(set) var store: RecurringEntryStore!

        init() throws {
            context = try TestSupport.makeContext()
            var store = RecurringEntryStore(context: context)
            store.now = { [unowned self] in now }
            store.save = { [unowned self] context in
                if failsSave { throw TestError() }
                try context.save()
            }
            self.store = store
        }

        func creating(_ prefill: RecurringDraft? = nil, notBefore: RecurringMonth? = nil) -> RecurringEditorModel {
            RecurringEditorModel(
                creating: prefill, notBefore: notBefore, store: store, timeZone: RecurringEditorModelTests.timeZone,
                now: { [unowned self] in now }, announce: { [unowned self] in announcements.append($0) },
                didChange: { [unowned self] in changes += 1 }
            )
        }

        func editing(_ row: RecurringEntry) -> RecurringEditorModel {
            RecurringEditorModel(
                editing: row, store: store, timeZone: RecurringEditorModelTests.timeZone, now: { [unowned self] in now },
                announce: { [unowned self] in announcements.append($0) }, didChange: { [unowned self] in changes += 1 }
            )
        }

        func list() -> RecurringListModel {
            RecurringListModel(
                store: store, timeZone: RecurringEditorModelTests.timeZone, now: { [unowned self] in now },
                announce: { [unowned self] in announcements.append($0) }, didChange: { [unowned self] in changes += 1 }
            )
        }
    }

    // MARK: - 作る

    /// 金額を入れるまで保存できない。今月の日がまだなら今月から記録し、次に記録する日を出す。
    @Test func createStartsThisMonthWhenDayIsAhead() throws {
        let fixture = try Fixture()
        let editor = fixture.creating()
        #expect(!editor.canSave)
        #expect(editor.dayOfMonth == 25)

        editor.amountText = "80000"
        editor.normalizeAmountText()
        editor.memo = " 家賃 "
        #expect(editor.amountText == "80,000")
        #expect(editor.canSave)
        #expect(!editor.showsThisMonthChoice)
        #expect(editor.recordsImmediately == nil)
        #expect(editor.nextDate == TestSupport.date(2026, 10, 25, hour: 12))
        #expect(editor.save())

        let row = try #require(try fixture.store.rules().first)
        #expect(row.memo == "家賃")
        #expect(row.amount == 80_000)
        #expect(row.startMonthKey == 202610)
        #expect(fixture.announcements == ["くり返しの記録を足しました"])
        #expect(fixture.changes == 1)
    }

    /// 今月の日を過ぎていれば来月から。「今月の分も記録する」を選べば今月からで、保存するとすぐ記録する日を出す。
    @Test func createAfterDayAsksAboutThisMonth() throws {
        let fixture = try Fixture()
        let editor = fixture.creating()
        editor.amountText = "990"
        editor.dayOfMonth = 5

        #expect(editor.showsThisMonthChoice)
        #expect(editor.recordsImmediately == nil)
        #expect(editor.nextDate == TestSupport.date(2026, 11, 5, hour: 12))

        editor.includesThisMonth = true
        #expect(editor.recordsImmediately == TestSupport.date(2026, 10, 5, hour: 12))
        #expect(editor.save())
        #expect(try fixture.store.rules().first?.startMonthKey == 202610)
    }

    /// 記録から作ったとき（「毎月くり返す」）は、その記録の月の分をもう記録してあるので、次の月から（今月の分を選ばせない）。
    @Test func createFromEntryStartsNextMonth() throws {
        let fixture = try Fixture()
        let editor = fixture.creating(
            RecurringDraft(amount: 80_000, memo: "家賃", isIncome: false, category: .other, dayOfMonth: 25),
            notBefore: RecurringMonth(year: 2026, month: 11)
        )

        #expect(editor.amountText == "80,000")
        #expect(editor.canSave)
        #expect(!editor.showsThisMonthChoice)
        #expect(editor.nextDate == TestSupport.date(2026, 11, 25, hour: 12))
        #expect(editor.save())
        #expect(try fixture.store.rules().first?.startMonthKey == 202611)
    }

    /// 書き込めなければ知らせ、閉じない。
    @Test func createFailureShowsAlert() throws {
        let fixture = try Fixture()
        let editor = fixture.creating()
        editor.amountText = "990"
        fixture.failsSave = true

        #expect(!editor.save())
        #expect(editor.failure == .save)
        #expect(fixture.changes == 0)
    }

    /// 保存できない金額は理由を出す（空欄のうちは出さない）。
    @Test func amountIssue() throws {
        let fixture = try Fixture()
        let editor = fixture.creating()
        #expect(editor.amountIssue == nil)
        editor.amountText = "0"
        #expect(editor.amountIssue == .notPositive)
        #expect(!editor.canSave)
    }

    // MARK: - 直す・やめる

    /// 直すときは今の中身を入れて開き、変えるまで保存できない。記録済みの月は変えない。やめると決まりが消える。
    @Test func editAndDelete() throws {
        let fixture = try Fixture()
        let row = try fixture.store.create(
            RecurringDraft(amount: 80_000, memo: "家賃", isIncome: false, category: .other, dayOfMonth: 25),
            startMonth: RecurringMonth(year: 2026, month: 9)
        )
        row.lastRecordedMonthKey = 202609
        let editor = fixture.editing(row)

        #expect(editor.amountText == "80,000")
        #expect(!editor.canSave)
        #expect(editor.nextDate == TestSupport.date(2026, 10, 25, hour: 12))

        // 日を今日より前にすると、今月の分を保存してすぐ記録することを出す。
        editor.dayOfMonth = 5
        #expect(editor.canSave)
        #expect(editor.recordsImmediately == TestSupport.date(2026, 10, 5, hour: 12))
        #expect(editor.save())
        #expect(row.dayOfMonth == 5)
        #expect(row.lastRecordedMonthKey == 202609)
        #expect(fixture.announcements.last == "くり返しの記録を直しました")

        let again = fixture.editing(row)
        #expect(again.delete())
        #expect(try fixture.store.rules().isEmpty)
        #expect(fixture.announcements.last == "くり返しの記録をやめました")
        #expect(fixture.changes == 2)
    }

    // MARK: - 設定の一覧

    /// 一覧には次に記録する日を出し、足す・やめるで読み直す。
    @Test func listShowsNextDatesAndDeletes() throws {
        let fixture = try Fixture()
        try fixture.store.create(
            RecurringDraft(amount: 80_000, memo: "家賃", isIncome: false, category: .other, dayOfMonth: 25),
            startMonth: RecurringMonth(year: 2026, month: 10)
        )
        let list = fixture.list()
        #expect(list.rows.map(\.memo) == ["家賃"])
        #expect(list.rows.first?.nextDate == TestSupport.date(2026, 10, 25, hour: 12))

        list.presentCreation()
        let editor = try #require(list.editor)
        editor.amountText = "990"
        editor.memo = "動画"
        editor.dayOfMonth = 1
        #expect(editor.save())
        #expect(list.rows.map(\.memo) == ["動画", "家賃"])
        #expect(list.rows.first?.nextDate == TestSupport.date(2026, 11, 1, hour: 12))

        let rent = try #require(list.rows.last)
        list.requestDeletion(rent)
        #expect(list.pendingDeletion == rent)
        list.confirmDeletion(rent)
        #expect(list.rows.map(\.memo) == ["動画"])
        #expect(fixture.changes == 2)
    }
}
