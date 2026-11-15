import Foundation
import SaifuLogCore
import SwiftData
import Testing
@testable import SaifuLog

/// 保存・直し・削除の失敗を捨てずに知らせ、画面と保存先を食い違わせないこと。
@MainActor
struct EntryStoreTests {
    @Test func insertSavesEntries() throws {
        let context = try TestSupport.makeContext()
        let store = EntryStore(context: context)

        try store.insert([TestSupport.entry(), TestSupport.entry(amount: 400, memo: "コーヒー")])

        #expect(try context.fetchCount(FetchDescriptor<Entry>()) == 2)
        #expect(!context.hasChanges)
    }

    /// 保存に失敗したら throw し、入れかけた記録を残さない（以前は try? で捨てて「記録しました」と読み上げていた）。
    @Test func insertRollsBackWhenSaveFails() throws {
        let context = try TestSupport.makeContext()
        var store = EntryStore(context: context)
        store.save = { _ in throw TestError() }

        #expect(throws: TestError.self) {
            try store.insert([TestSupport.entry()])
        }
        #expect(try context.fetchCount(FetchDescriptor<Entry>()) == 0)
        #expect(!context.hasChanges)
    }

    /// 直した値を書き込む（直すシートの保存）。
    @Test func updateSavesEdits() throws {
        let context = try TestSupport.makeContext()
        let store = EntryStore(context: context)
        let lunch = TestSupport.entry()
        try store.insert([lunch])
        let yesterday = TestSupport.date(2026, 9, 27, hour: 12)

        try store.update(lunch, with: EntryEdits(
            amount: 900, isIncome: false, category: .cafe, memo: "カフェランチ", spentAt: yesterday
        ))

        #expect(!context.hasChanges)
        let saved = try #require(try context.fetch(FetchDescriptor<Entry>()).first)
        #expect(saved.amount == 900)
        #expect(saved.category == .cafe)
        #expect(saved.memo == "カフェランチ")
        #expect(saved.spentAt == yesterday)
        // 元の入力文・記録した日時は直さない（読み違いの見直しと、タイムラインの並びのため）。
        #expect(saved.originalText == "ランチ 850")
        #expect(saved.createdAt == TestSupport.now)
    }

    /// 直した内容を書き込めなければ throw し、記録を直す前の値に戻す。
    /// 戻さないと、画面には直した値が出たまま、次の自動保存で黙って書き込まれたり、次の起動で戻ったりする。
    /// 保存先から読み直す前の、読み込み済みの記録の値（吹き出しが読むもの）も戻っていること
    /// （SwiftData の rollback だけでは戻らない）。
    @Test func updateRollsBackWhenSaveFails() throws {
        let context = try TestSupport.makeContext()
        var store = EntryStore(context: context)
        let lunch = TestSupport.entry()
        try store.insert([lunch])
        store.save = { _ in throw TestError() }

        #expect(throws: TestError.self) {
            try store.update(lunch, with: EntryEdits(
                amount: 900, isIncome: true, category: .other, memo: "給料",
                spentAt: TestSupport.date(2026, 8, 1)
            ))
        }

        #expect(!context.hasChanges)
        #expect(lunch.amount == 850)
        #expect(!lunch.isIncome)
        #expect(lunch.category == .food)
        #expect(lunch.memo == "ランチ")
        #expect(lunch.spentAt == TestSupport.now)
        let saved = try #require(try context.fetch(FetchDescriptor<Entry>()).first)
        #expect(saved.amount == 850)
    }

    /// 直していない項目は書き換えない。同じ値だけなら、変更として残さない。
    @Test func applyingSameValuesLeavesNoChanges() throws {
        let context = try TestSupport.makeContext()
        let store = EntryStore(context: context)
        let lunch = TestSupport.entry()
        try store.insert([lunch])

        EntryEdits(lunch).apply(to: lunch)

        #expect(!context.hasChanges)
    }

    /// 直した日付と金額は、ホームの今月の合計と予算の残り（帯の数字）にそのまま反映される。
    /// 前の月へ移した記録は今月の読み込みから外れ、合計からも抜ける。
    @Test func updateIsReflectedInMonthlyFigures() throws {
        let context = try TestSupport.makeContext()
        let store = EntryStore(context: context)
        let lunch = TestSupport.entry()
        let coffee = TestSupport.entry(amount: 400, category: .cafe, memo: "コーヒー")
        try store.insert([lunch, coffee])
        try BudgetStore(context: context).setAmount(100_000, for: .total)
        func figures() throws -> (summary: MonthlySummary, budget: BudgetStatus?) {
            let records = try context.fetch(Entry.monthDescriptor(containing: TestSupport.now, calendar: TestSupport.calendar))
            let budgets = try context.fetch(FetchDescriptor<Budget>())
            return MonthSummaryHeader.figures(records: records, budgets: budgets, today: TestSupport.now, calendar: TestSupport.calendar)
        }
        #expect(try figures().summary.expense == 1_250)

        var edits = EntryEdits(lunch)
        edits.amount = 1_850
        try store.update(lunch, with: edits)
        #expect(try figures().summary.expense == 2_250)
        #expect(try figures().budget?.remaining == 97_750)

        edits.spentAt = TestSupport.date(2026, 8, 31, hour: 12)
        try store.update(lunch, with: edits)
        #expect(try figures().summary.expense == 400)
        #expect(try figures().budget?.remaining == 99_600)

        // 支出を収入に直すと、支出の合計と予算の使った額から抜け、収入に数える。
        var coffeeEdits = EntryEdits(coffee)
        coffeeEdits.isIncome = true
        coffeeEdits.category = .other
        try store.update(coffee, with: coffeeEdits)
        #expect(try figures().summary.expense == 0)
        #expect(try figures().summary.income == 400)
        #expect(try figures().budget?.remaining == 100_000)
    }

    @Test func deleteRemovesEntries() throws {
        let context = try TestSupport.makeContext()
        let store = EntryStore(context: context)
        let lunch = TestSupport.entry()
        let coffee = TestSupport.entry(amount: 400, memo: "コーヒー")
        try store.insert([lunch, coffee])

        try store.delete([lunch])

        let remaining = try context.fetch(FetchDescriptor<Entry>())
        #expect(remaining.map(\.memo) == ["コーヒー"])
    }

    /// 削除（取り消しを含む）を書き込めなければ throw し、記録を元に戻す。
    /// 戻さないと画面からは消えたのに、次の起動で戻ってくる。
    @Test func deleteRollsBackWhenSaveFails() throws {
        let context = try TestSupport.makeContext()
        var store = EntryStore(context: context)
        let lunch = TestSupport.entry()
        try store.insert([lunch])
        store.save = { _ in throw TestError() }

        #expect(throws: TestError.self) {
            try store.delete([lunch])
        }
        let remaining = try context.fetch(FetchDescriptor<Entry>())
        #expect(remaining.map(\.memo) == ["ランチ"])
        #expect(!context.hasChanges)
    }
}
