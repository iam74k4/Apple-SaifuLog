import Foundation
import Testing
@testable import SaifuLogCore

@Suite("ひとこと入力のカテゴリの振り分け")
struct CategoryResolverTests {
    static let clothes = CustomCategoryInfo(id: "clothes", name: "衣服", symbolName: "tshirt", colorIndex: 0)
    static let catalog = CategoryCatalog(customs: [clothes])

    private static func expense(_ memo: String, _ category: EntryCategory = .other) -> ParsedEntry {
        ParsedEntry(amount: 500, category: category, memo: memo)
    }

    private static func history(_ item: String, _ category: EntryCategory) -> CategoryHistory {
        CategoryHistory(records: [CategoryHistory.Record(item: item, category: category), CategoryHistory.Record(item: item, category: category)])
    }

    @Test("作ったカテゴリの名前がいちばん強い")
    func customNameWins() {
        let memory = CategoryMemory.resolve([CategoryMemoryTests.Row("衣服 セール", .daily)])

        let resolved = CategoryResolver.resolve([Self.expense("衣服 セール")], memory: memory, catalog: Self.catalog)

        #expect(resolved.map(\.entry.category) == [Self.clothes.category])
        #expect(resolved.map(\.source) == [.named])
    }

    @Test("覚えたカテゴリは、過去の記録と読み取ったカテゴリより強い")
    func learnedBeatsHistoryAndParsed() {
        let memory = CategoryMemory.resolve([CategoryMemoryTests.Row("スタバ", .food)])

        let resolved = CategoryResolver.resolve(
            [Self.expense("スタバ", .cafe)], memory: memory, history: Self.history("スタバ", .entertainment)
        )

        #expect(resolved.map(\.entry.category) == [.food])
        #expect(resolved.map(\.source) == [.learned])
    }

    @Test("過去の記録のいつものカテゴリは、読み取ったカテゴリより強い")
    func historyBeatsParsed() {
        let resolved = CategoryResolver.resolve(
            [Self.expense("スタバ", .food)], memory: CategoryMemory(), history: Self.history("スタバ", .cafe)
        )

        #expect(resolved.map(\.entry.category) == [.cafe])
        #expect(resolved.map(\.source) == [.history])
    }

    @Test("組み込みのカテゴリの名前が書かれた品目は、読み取ったカテゴリのまま")
    func builtInNameKeepsParsed() {
        let resolved = CategoryResolver.resolve(
            [Self.expense("日用品 まとめ買い", .daily)], memory: CategoryMemory(), history: Self.history("日用品 まとめ買い", .food)
        )

        #expect(resolved.map(\.entry.category) == [.daily])
        #expect(resolved.map(\.source) == [.named])
    }

    @Test("品目と同じ言葉の覚えは、組み込みのカテゴリの名前が書かれた品目にも当てる")
    func exactLearnedBeatsBuiltInName() {
        let memory = CategoryMemory.resolve([CategoryMemoryTests.Row("日用品 まとめ買い", .food)])

        let resolved = CategoryResolver.resolve([Self.expense("日用品 まとめ買い", .daily)], memory: memory)

        #expect(resolved.map(\.entry.category) == [.food])
        #expect(resolved.map(\.source) == [.learned])
    }

    /// 打った品目は店の名前とは限らない。店の種類の語やほかの意味にもなる名前で、黙って食費などにしない。
    @Test("店の名前の辞書は、打った品目にはチェーンの名前だけを当てる")
    func storeDictionaryUsesChainNamesOnly() {
        let resolved = CategoryResolver.resolve(
            [Self.expense("ライフカード 年会費"), Self.expense("スーパー"), Self.expense("DAISOで買い物")], memory: CategoryMemory()
        )

        #expect(resolved.map(\.entry.category) == [.other, .other, .daily])
        #expect(resolved.map(\.source) == [.unresolved, .unresolved, .store])
    }

    @Test("読み取りで「その他」になった品目は、店の名前の辞書で振り分ける")
    func storeDictionaryForOther() {
        let resolved = CategoryResolver.resolve(
            [Self.expense("マツキヨ"), Self.expense("ローソン"), Self.expense("ジンギスカン")], memory: CategoryMemory()
        )

        #expect(resolved.map(\.entry.category) == [.daily, .food, .other])
        #expect(resolved.map(\.source) == [.store, .store, .unresolved])
        #expect(resolved.map(\.asksCategory) == [false, false, true])
    }

    @Test("一覧に無い作ったカテゴリを指す覚えと過去の記録は当てない")
    func skipsMissingCustomCategories() {
        let gone = EntryCategory.custom("gone")
        let memory = CategoryMemory.resolve([CategoryMemoryTests.Row("ほげ", gone)])

        let resolved = CategoryResolver.resolve(
            [Self.expense("ほげ"), Self.expense("ふが")], memory: memory, history: Self.history("ふが", gone)
        )

        #expect(resolved.map(\.entry.category) == [.other, .other])
        #expect(resolved.map(\.asksCategory) == [true, true])
    }

    @Test("聞き返すのは、決まらずに「その他」のままで、辞書の「その他」の語にも当たらない支出")
    func asksOnlyUnresolvedUnknownItems() {
        let memory = CategoryMemory.resolve([CategoryMemoryTests.Row("家賃", .other)])
        let entries = [
            Self.expense("洋服"),
            Self.expense("家賃"),
            Self.expense(""),
            ParsedEntry(amount: 3_000, category: .other, isIncome: true, memo: "臨時収入"),
        ]

        let resolved = CategoryResolver.resolve(entries, memory: memory)

        #expect(resolved.map(\.asksCategory) == [false, false, true, false])
        #expect(resolved.map(\.source) == [.unresolved, .learned, .unresolved, .income])
    }
}
