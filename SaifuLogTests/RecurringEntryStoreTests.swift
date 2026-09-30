import Foundation
import SaifuLogCore
import SwiftData
import Testing
@testable import SaifuLog

/// くり返しの記録の読み書き（`RecurringEntryStore`）。作る・直す・やめると、記録する日を過ぎた月の分の記録・二重の記録の片づけ。
@MainActor
struct RecurringEntryStoreTests {
    static let timeZone = TestSupport.calendar.timeZone
    static let rent = RecurringDraft(amount: 80_000, memo: "家賃", isIncome: false, category: .other, dayOfMonth: 25)

    /// 保存先と、決めた ID・固定の日時で作る読み書き。
    @MainActor
    final class Fixture {
        let context: ModelContext
        var failsSave = false
        private var nextID = 0
        private(set) var store: RecurringEntryStore!

        init() throws {
            context = try TestSupport.makeContext()
            var store = RecurringEntryStore(context: context, now: { TestSupport.now })
            store.makeID = { [unowned self] in
                nextID += 1
                return "rule-\(nextID)"
            }
            store.save = { [unowned self] context in
                if failsSave { throw TestError() }
                try context.save()
            }
            self.store = store
        }

        func entries() throws -> [Entry] {
            try context.fetch(FetchDescriptor<Entry>(sortBy: [SortDescriptor(\.createdAt)]))
        }

        func record(at now: Date) throws -> [Entry] {
            try store.recordDue(now: now, timeZone: RecurringEntryStoreTests.timeZone)
        }
    }

    // MARK: - 作る・直す・やめる

    @Test func createUpdateDelete() throws {
        let fixture = try Fixture()
        try fixture.store.create(Self.rent, startMonth: RecurringMonth(year: 2026, month: 10))
        var subscription = Self.rent
        subscription.memo = "動画"
        subscription.amount = 990
        subscription.dayOfMonth = 5
        try fixture.store.create(subscription, startMonth: RecurringMonth(year: 2026, month: 10))

        // 毎月の日の順。
        #expect(try fixture.store.rules().map(\.memo) == ["動画", "家賃"])

        var changed = Self.rent
        changed.amount = 82_000
        try fixture.store.update("rule-1", with: changed)
        #expect(try fixture.store.rules().first { $0.recurrenceID == "rule-1" }?.amount == 82_000)

        try fixture.store.delete("rule-2")
        #expect(try fixture.store.rules().map(\.recurrenceID) == ["rule-1"])
        #expect(throws: RecurringEntryError.notFound) { try fixture.store.update("rule-2", with: changed) }
    }

    /// 収入はカテゴリを持たない（「その他」で保存する）。日は 1〜31 に収める。
    @Test func draftIsNormalized() throws {
        let fixture = try Fixture()
        let salary = try fixture.store.create(
            RecurringDraft(amount: 250_000, memo: "給料", isIncome: true, category: .food, dayOfMonth: 40),
            startMonth: RecurringMonth(year: 2026, month: 10)
        )
        #expect(salary.category == .other)
        #expect(salary.dayOfMonth == 31)
    }

    // MARK: - 記録する

    /// 記録する日を過ぎた月の分を、くり返しの記録として（打った文は空・印つき）記録し、記録した月を覚える。同じ月はもう記録しない。
    @Test func recordsDueMonthOnce() throws {
        let fixture = try Fixture()
        try fixture.store.create(Self.rent, startMonth: RecurringMonth(year: 2026, month: 10))

        #expect(try fixture.record(at: TestSupport.date(2026, 10, 24, hour: 23)).isEmpty)
        let recorded = try fixture.record(at: TestSupport.date(2026, 10, 25, hour: 8))

        let entry = try #require(recorded.first)
        #expect(recorded.count == 1)
        #expect(entry.amount == 80_000)
        #expect(entry.memo == "家賃")
        #expect(entry.source == .recurring)
        #expect(entry.originalText.isEmpty)
        #expect(entry.recurrenceKey == "rule-1/202610")
        #expect(entry.spentAt == TestSupport.date(2026, 10, 25, hour: 12))
        #expect(entry.createdAt == TestSupport.date(2026, 10, 25, hour: 8))
        #expect(try fixture.store.rules().first?.lastRecordedMonthKey == 202610)

        #expect(try fixture.record(at: TestSupport.date(2026, 10, 31)).isEmpty)
        #expect(try fixture.entries().count == 1)
    }

    /// 開かなかった月の分もまとめて記録する（使った日時の順に、記録した日時を 1 ミリ秒ずつずらして 1 つの返事にまとめる）。
    /// 取り消した（消した）月の分は、もう記録しない。
    @Test func catchesUpAndDoesNotRecreateDeleted() throws {
        let fixture = try Fixture()
        try fixture.store.create(Self.rent, startMonth: RecurringMonth(year: 2026, month: 8))
        var subscription = Self.rent
        subscription.memo = "動画"
        subscription.dayOfMonth = 1
        try fixture.store.create(subscription, startMonth: RecurringMonth(year: 2026, month: 10))

        let recorded = try fixture.record(at: TestSupport.date(2026, 10, 26))

        #expect(recorded.map(\.recurrenceKey) == ["rule-1/202608", "rule-1/202609", "rule-2/202610", "rule-1/202610"])
        let sends = TimelineSend.groupRanges(of: recorded.map {
            TimelineSend.Record(id: $0.recurrenceKey, originalText: $0.originalText, source: $0.source, createdAt: $0.createdAt)
        })
        #expect(sends == [0..<4])

        for entry in recorded { fixture.context.delete(entry) }
        try fixture.context.save()
        #expect(try fixture.record(at: TestSupport.date(2026, 10, 27)).isEmpty)
    }

    /// ほかの端末が記録して届いた月の分（同じ印の記録がある）は記録せず、記録した月だけ覚える。
    @Test func skipsOccurrenceRecordedElsewhere() throws {
        let fixture = try Fixture()
        try fixture.store.create(Self.rent, startMonth: RecurringMonth(year: 2026, month: 10))
        let fromOtherDevice = TestSupport.entry(amount: 80_000, category: .other, memo: "家賃")
        fromOtherDevice.recurrenceKey = "rule-1/202610"
        fixture.context.insert(fromOtherDevice)
        try fixture.context.save()

        #expect(try fixture.record(at: TestSupport.date(2026, 10, 26)).isEmpty)
        #expect(try fixture.entries().count == 1)
        #expect(try fixture.store.rules().first?.lastRecordedMonthKey == 202610)
    }

    /// 書き込めなければ巻き戻す（記録も、記録した月も残らない。次に開いたときにもう一度記録する）。
    @Test func recordFailureRollsBack() throws {
        let fixture = try Fixture()
        try fixture.store.create(Self.rent, startMonth: RecurringMonth(year: 2026, month: 10))
        fixture.failsSave = true

        #expect(throws: TestError.self) { try fixture.record(at: TestSupport.date(2026, 10, 26)) }

        fixture.failsSave = false
        #expect(try fixture.entries().isEmpty)
        #expect(try fixture.store.rules().first?.lastRecordedMonthKey == 0)
        #expect(try fixture.record(at: TestSupport.date(2026, 10, 26)).count == 1)
    }

    // MARK: - 二重の記録

    /// 2 台が同じ月の分を記録していたら、記録した日時のいちばん古い 1 件を残す。
    @Test func removesDuplicateOccurrences() throws {
        let fixture = try Fixture()
        let first = TestSupport.entry(amount: 80_000, memo: "家賃", createdAt: TestSupport.date(2026, 10, 25, hour: 8))
        let second = TestSupport.entry(amount: 80_000, memo: "家賃", createdAt: TestSupport.date(2026, 10, 25, hour: 9))
        let typed = TestSupport.entry(amount: 850, memo: "ランチ")
        first.recurrenceKey = "rule-1/202610"
        second.recurrenceKey = "rule-1/202610"
        [first, second, typed].forEach(fixture.context.insert)
        try fixture.context.save()
        let secondID = second.persistentModelID

        let removed = try fixture.store.removeDuplicateOccurrences()

        #expect(removed == [secondID])
        #expect(try fixture.entries().map(\.amount) == [850, 80_000])
        #expect(try fixture.store.removeDuplicateOccurrences().isEmpty)
    }

    // MARK: - 作ったカテゴリを消したとき

    /// くり返しの記録のカテゴリにしていた作ったカテゴリを消すと、くり返しの記録は「その他」になる。
    @Test func deletingCustomCategoryMovesRuleToOther() throws {
        let fixture = try Fixture()
        let categories = CustomCategoryStore(context: fixture.context, now: { TestSupport.now })
        let housing = try categories.create(name: "住居", symbolName: "house", colorIndex: 0)
        var draft = Self.rent
        draft.category = housing
        try fixture.store.create(draft, startMonth: RecurringMonth(year: 2026, month: 10))

        try categories.delete(housing)

        #expect(try fixture.store.rules().first?.category == .other)
    }
}
