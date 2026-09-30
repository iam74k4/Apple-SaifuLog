import Foundation
import SaifuLogCore
import SwiftData
import Testing
@testable import SaifuLog

/// ホームのくり返しの記録（開いたときに記録して知らせる・取り消す・「毎月くり返す」・二重の記録の片づけ）。
@MainActor
struct HomeModelRecurringTests {
    typealias Fixture = HomeModelTests.Fixture

    private func store(_ fixture: Fixture) -> RecurringEntryStore {
        RecurringEntryStore(context: fixture.context, now: { TestSupport.now })
    }

    /// 家賃（毎月 25 日）を 9 月から記録する決まり。
    @discardableResult
    private func addRent(_ fixture: Fixture) throws -> RecurringEntry {
        try store(fixture).create(
            RecurringDraft(amount: 80_000, memo: "家賃", isIncome: false, category: .other, dayOfMonth: 25),
            startMonth: RecurringMonth(year: 2026, month: 9)
        )
    }

    /// 記録する日を過ぎた分を記録し、直前の送信として「取り消す」の対象にして読み上げる（使った日が今日でなければ日付も）。
    @Test func recordsDueEntriesAndAnnounces() throws {
        let fixture = try Fixture()
        try addRent(fixture)
        fixture.now = TestSupport.date(2026, 10, 25, hour: 9)

        fixture.model.recordDueRecurringEntries(calendar: TestSupport.calendar)

        let entries = try fixture.entries()
        #expect(entries.map(\.recurrenceKey).count == 2)
        #expect(entries.allSatisfy { $0.source == .recurring })
        #expect(fixture.model.justRecorded.count == 2)
        #expect(fixture.model.canUndo)
        #expect(fixture.announcements.count == 1)
        let announcement = try #require(fixture.announcements.last)
        #expect(announcement.contains("¥80,000"))
        // 今日でない 9 月の分には日付を添える。
        #expect(announcement.contains(TestSupport.date(2026, 9, 25, hour: 12).formatted(.dateTime.month().day())))

        // もう一度開いても記録しない。
        fixture.model.recordDueRecurringEntries(calendar: TestSupport.calendar)
        #expect(try fixture.entries().count == 2)
    }

    /// 取り消すと記録を消し、入力欄には何も戻さない（打った文が無い）。取り消した月の分はもう記録しない。
    @Test func undoDoesNotRestoreDraftOrRerecord() throws {
        let fixture = try Fixture()
        try addRent(fixture)
        fixture.now = TestSupport.date(2026, 9, 26)
        fixture.model.recordDueRecurringEntries(calendar: TestSupport.calendar)
        fixture.model.draft = "打ちかけ"

        fixture.model.undoLastRecord()

        #expect(try fixture.entries().isEmpty)
        #expect(fixture.model.draft == "打ちかけ")
        fixture.model.recordDueRecurringEntries(calendar: TestSupport.calendar)
        #expect(try fixture.entries().isEmpty)
    }

    /// 記録する日の前には何も記録せず、直前の送信の「取り消す」も変えない。
    @Test func nothingDueKeepsLastSend() async throws {
        let fixture = try Fixture()
        try addRent(fixture)
        fixture.now = TestSupport.date(2026, 9, 24)
        await fixture.send("ランチ 850")

        fixture.model.recordDueRecurringEntries(calendar: TestSupport.calendar)

        #expect(fixture.model.justRecorded.map(\.memo) == ["ランチ"])
    }

    /// 長押しの「毎月くり返す」は、その記録の中身を入れて作るシートを出し、その記録の月の分は記録しない（次の月から）。
    /// くり返しの記録から記録したものには出さない。
    @Test func makeRecurringFromEntry() async throws {
        let fixture = try Fixture()
        await fixture.send("家賃 80000")
        let entry = try #require(try fixture.entries().first)

        fixture.model.presentRecurringCreation(from: entry, calendar: TestSupport.calendar)

        let editor = try #require(fixture.model.recurringEditor)
        #expect(editor.amountText == "80,000")
        #expect(editor.memo == "家賃")
        #expect(editor.dayOfMonth == 28)
        #expect(!editor.showsThisMonthChoice)
        #expect(editor.save())
        #expect(try store(fixture).rules().first?.startMonthKey == 202610)
        // 保存したら、記録する日を過ぎた分を記録しに行く（ここでは無い）。
        #expect(try fixture.entries().count == 1)

        fixture.model.recurringEditor = nil
        fixture.now = TestSupport.date(2026, 10, 28, hour: 9)
        fixture.model.recordDueRecurringEntries(calendar: TestSupport.calendar)
        let recurring = try #require(try fixture.entries().last)
        #expect(recurring.source == .recurring)
        fixture.model.presentRecurringCreation(from: recurring, calendar: TestSupport.calendar)
        #expect(fixture.model.recurringEditor == nil)
    }

    /// ほかの端末が同じ月の分を記録していたら片づけ、消えた記録を「取り消す」の対象から外す。
    @Test func removesDuplicatesAndForgetsThem() throws {
        let fixture = try Fixture()
        try addRent(fixture)
        fixture.now = TestSupport.date(2026, 9, 25, hour: 9)
        fixture.model.recordDueRecurringEntries(calendar: TestSupport.calendar)
        let mine = try #require(fixture.model.justRecorded.first)
        let earlier = TestSupport.entry(amount: 80_000, memo: "家賃", createdAt: TestSupport.date(2026, 9, 25, hour: 8))
        earlier.recurrenceKey = mine.recurrenceKey
        fixture.context.insert(earlier)
        try fixture.context.save()

        fixture.model.removeDuplicateRecurringEntries()

        #expect(try fixture.entries().map(\.createdAt) == [TestSupport.date(2026, 9, 25, hour: 8)])
        #expect(fixture.model.justRecorded.isEmpty)
        #expect(!fixture.model.canUndo)
    }

    /// くり返しの記録は、よく使うひとことの候補に出さない（アプリが毎月記録するので、打つ候補ではない）。
    @Test func quickPhrasesSkipRecurringEntries() throws {
        let fixture = try Fixture()
        try addRent(fixture)
        fixture.now = TestSupport.date(2026, 11, 26)
        fixture.model.recordDueRecurringEntries(calendar: TestSupport.calendar)
        #expect(try fixture.entries().count == 3)

        fixture.model.refreshQuickPhrases()

        #expect(fixture.model.quickPhrases.isEmpty)
    }

    /// 設定から足したくり返しの記録も、記録する日を過ぎた分をすぐ記録する（ホームに戻ると返事のカードが出ている）。
    @Test func addingFromSettingsRecordsImmediately() throws {
        let fixture = try Fixture()
        fixture.model.recordDueRecurringEntries(calendar: TestSupport.calendar)
        fixture.model.presentSettings()
        let list = try #require(fixture.model.settings?.recurringList)

        list.presentCreation()
        let editor = try #require(list.editor)
        editor.amountText = "990"
        editor.memo = "動画"
        editor.dayOfMonth = 1
        editor.includesThisMonth = true
        #expect(editor.save())

        #expect(try fixture.entries().map(\.memo) == ["動画"])
        #expect(fixture.model.justRecorded.map(\.memo) == ["動画"])
    }
}
