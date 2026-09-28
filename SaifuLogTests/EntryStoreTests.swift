import Foundation
import SwiftData
import Testing
@testable import SaifuLog

/// 保存・削除の失敗を捨てずに知らせ、画面と保存先を食い違わせないこと。
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
