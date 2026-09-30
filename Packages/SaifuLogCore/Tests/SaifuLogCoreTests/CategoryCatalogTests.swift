import Foundation
import Testing
@testable import SaifuLogCore

/// 利用者が作ったカテゴリ（`EntryCategory.custom` と `CategoryCatalog`）。保存する値・並び・名前の引き方・文の中の名前・名前の確かめと、
/// 作ったカテゴリを使う計算（修正の記憶・内訳・質問・CSV・AI に渡す文）を確かめる。
@Suite("作ったカテゴリ")
struct CategoryCatalogTests {
    static let clothes = CustomCategoryInfo(id: "c1", name: "衣服", symbolName: "tshirt", colorIndex: 0)
    static let beauty = CustomCategoryInfo(id: "c2", name: "美容", symbolName: "scissors", colorIndex: 1)
    static let gym = CustomCategoryInfo(id: "c3", name: "ジム代", symbolName: "dumbbell", colorIndex: 2)
    static let catalog = CategoryCatalog(customs: [clothes, beauty, gym])

    // MARK: - 保存する値

    /// 組み込みのカテゴリの rawValue は、列挙型の rawValue で保存していたときと同じ（変えると保存済みの記録が「その他」に落ちる）。
    @Test("組み込みの rawValue は保存していた値のまま")
    func builtInRawValuesAreStable() {
        #expect(EntryCategory.builtIns.map(\.rawValue) == [
            "food", "daily", "transport", "cafe", "entertainment", "utilities", "medical", "other",
        ])
        for category in EntryCategory.builtIns {
            #expect(EntryCategory(rawValue: category.rawValue) == category)
            #expect(!category.isCustom)
        }
    }

    @Test("作ったカテゴリは「custom:」と ID で保存し、行き来できる")
    func customRawValueRoundTrips() throws {
        let category = EntryCategory.custom("5f0c")
        #expect(category.rawValue == "custom:5f0c")
        #expect(EntryCategory(rawValue: "custom:5f0c") == category)
        #expect(category.isCustom)
        #expect(category.customID == "5f0c")
        // 空の ID と知らない値は読まない。
        #expect(EntryCategory(rawValue: "custom:") == nil)
        #expect(EntryCategory(rawValue: "clothes") == nil)
        #expect(EntryCategory(rawValue: "") == nil)

        let data = try JSONEncoder().encode([EntryCategory.food, category])
        #expect(String(data: data, encoding: .utf8) == #"["food","custom:5f0c"]"#)
        #expect(try JSONDecoder().decode([EntryCategory].self, from: data) == [.food, category])
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(EntryCategory.self, from: Data(#""nope""#.utf8)) }
    }

    /// 作ったカテゴリの表示名・記号・キーワードは、一覧が無くても落ちないよう「その他」と同じにする（名前は一覧から引く）。
    @Test("作ったカテゴリだけの情報は「その他」と同じ")
    func customFallsBackToOther() {
        let category = EntryCategory.custom("x")
        #expect(category.displayName == EntryCategory.other.displayName)
        #expect(category.symbolName == EntryCategory.other.symbolName)
        #expect(category.keywords.isEmpty)
        // 表示名から引けるのは組み込みだけ（AI の出力を戻すため）。
        #expect(EntryCategory(displayName: "衣服") == nil)
    }

    @Test("並びの基準は、組み込みの順・作ったカテゴリ（ID の順）・その他")
    func standardOrder() {
        let shuffled: [EntryCategory] = [.other, .custom("b"), .medical, .food, .custom("a"), .cafe]
        #expect(shuffled.sorted(by: EntryCategory.areInStandardOrder) == [
            .food, .cafe, .medical, .custom("a"), .custom("b"), .other,
        ])
    }

    // MARK: - 一覧

    @Test("画面の並びは、組み込み（その他以外）・作った順・その他")
    func catalogOrder() {
        #expect(Self.catalog.all == [
            .food, .daily, .transport, .cafe, .entertainment, .utilities, .medical,
            .custom("c1"), .custom("c2"), .custom("c3"), .other,
        ])
        #expect(CategoryCatalog.builtIn.all == EntryCategory.builtIns)
    }

    @Test("名前を引く。一覧に無い作ったカテゴリは「その他」")
    func names() {
        #expect(Self.catalog.name(of: .food) == "食費")
        #expect(Self.catalog.name(of: .custom("c1")) == "衣服")
        #expect(Self.catalog.name(of: .custom("gone")) == "その他")
        #expect(Self.catalog.contains(.custom("c2")))
        #expect(!Self.catalog.contains(.custom("gone")))
        #expect(Self.catalog.contains(.medical))
        #expect(Self.catalog.info(for: .food) == nil)
    }

    @Test("文の中の作ったカテゴリの名前を探す（表記ゆれも同じ。長い名前が勝つ）")
    func namedInText() {
        #expect(Self.catalog.customCategory(namedIn: "衣服 3000") == .custom("c1"))
        #expect(Self.catalog.customCategory(namedIn: "美容院で美容") == .custom("c2"))
        #expect(Self.catalog.customCategory(namedIn: "じむ代") == .custom("c3"))
        #expect(Self.catalog.customCategory(namedIn: "ランチ") == nil)
        let overlapping = CategoryCatalog(customs: [
            CustomCategoryInfo(id: "a", name: "服", symbolName: "tshirt", colorIndex: 0),
            CustomCategoryInfo(id: "b", name: "子ども服", symbolName: "tshirt", colorIndex: 0),
        ])
        #expect(overlapping.customCategory(namedIn: "子ども服 2000") == .custom("b"))
        #expect(overlapping.customCategory(namedIn: "服 2000") == .custom("a"))
    }

    @Test("作る名前を確かめる（空・長すぎる・ほかのカテゴリと同じ名前は使えない）")
    func validateName() {
        #expect(Self.catalog.validateName("  ペット  ") == .success("ペット"))
        #expect(Self.catalog.validateName("  ") == .failure(.empty))
        #expect(Self.catalog.validateName(String(repeating: "あ", count: CategoryCatalog.maximumNameLength + 1)) == .failure(.tooLong))
        #expect(Self.catalog.validateName("食費") == .failure(.duplicate))
        #expect(Self.catalog.validateName("光熱") == .failure(.duplicate))
        #expect(Self.catalog.validateName("いふく") == .success("いふく"))
        #expect(Self.catalog.validateName("じむ代") == .failure(.duplicate))
        // 自分の今の名前とは重なってよい（名前を変えずに記号だけ変えるとき）。
        #expect(Self.catalog.validateName("衣服", editing: "c1") == .success("衣服"))
        #expect(Self.catalog.validateName("衣服", editing: "c2") == .failure(.duplicate))
    }

    // MARK: - 作ったカテゴリを使う計算

    @Test("文に作ったカテゴリの名前があれば、そのカテゴリにする（覚えより先）")
    func applyingCustomNames() {
        let memory = CategoryMemory(rules: ["衣服 ユニクロ": .daily, "ユニクロ": .custom("c1"), "スタバ": .custom("gone")])
        let entries = [
            ParsedEntry(amount: 3_000, category: .other, memo: "衣服 ユニクロ"),
            ParsedEntry(amount: 1_990, category: .daily, memo: "ユニクロ"),
            ParsedEntry(amount: 500, category: .cafe, memo: "スタバ"),
        ]

        let applied = memory.applying(to: entries, catalog: Self.catalog)

        #expect(applied.map(\.category) == [.custom("c1"), .custom("c1"), .cafe])
    }

    @Test("作ったカテゴリの名前が書かれた品目は聞き返さない")
    func doesNotAskForCustomNames() {
        let memory = CategoryMemory()
        #expect(memory.asksCategory(memo: "ジム代", amount: 8_000, category: .other, isIncome: false))
        #expect(!memory.asksCategory(memo: "ジム代", amount: 8_000, category: .other, isIncome: false, catalog: Self.catalog))
    }

    @Test("一覧に無い作ったカテゴリを指す覚えは、無いものとして聞き返す（一覧にあれば聞き返さない）")
    func asksWhenLearnedCategoryIsMissing() {
        let memory = CategoryMemory(rules: ["ユニクロ": .custom("c1"), "ユザワヤ": .custom("gone"), "家賃": .other])
        #expect(!memory.asksCategory(memo: "ユニクロ", amount: 3_990, category: .other, isIncome: false, catalog: Self.catalog))
        #expect(memory.asksCategory(memo: "ユザワヤ", amount: 500, category: .other, isIncome: false, catalog: Self.catalog))
        // 「その他のまま」を選んだ覚えは、組み込みのカテゴリなのでいつもある。
        #expect(!memory.asksCategory(memo: "家賃", amount: 80_000, category: .other, isIncome: false, catalog: Self.catalog))
        // 一覧を渡さなければ、作ったカテゴリを指す覚えはどれも無いものとみなす。
        #expect(memory.asksCategory(memo: "ユニクロ", amount: 3_990, category: .other, isIncome: false))
    }

    @Test("内訳の同じ額の行は、組み込み・作ったカテゴリ・その他の順")
    func breakdownOrderWithCustoms() {
        let breakdown = CategoryBreakdown(expenseByCategory: [
            .other: 1_000, .custom("c2"): 1_000, .food: 1_000, .custom("c1"): 3_000,
        ])
        #expect(breakdown.items.map(\.category) == [.custom("c1"), .food, .custom("c2"), .other])
    }

    @Test("CSV には作ったカテゴリの名前を書く（英語でも利用者の名前のまま）")
    func csvNames() {
        #expect(LedgerCSVWriter.categoryName(.custom("c1"), language: .japanese, catalog: Self.catalog) == "衣服")
        #expect(LedgerCSVWriter.categoryName(.custom("c1"), language: .english, catalog: Self.catalog) == "衣服")
        #expect(LedgerCSVWriter.categoryName(.custom("gone"), language: .english, catalog: Self.catalog) == "Other")
        #expect(LedgerCSVWriter.categoryName(.food, language: .english, catalog: Self.catalog) == "Food")
    }

    @Test("質問の作ったカテゴリの名前を読む（組み込みの語より先）")
    func questionsReadCustomNames() throws {
        let question = try #require(QuestionParser.question(
            from: "今月の衣服いくら?", now: Fixture.now, calendar: Fixture.calendar, catalog: Self.catalog
        ))
        #expect(question.category == .custom("c1"))
        #expect(question.metric == .categoryExpense)
        // 一覧を渡さなければ、作ったカテゴリの名前は読まない。
        #expect(QuestionParser.read("今月の衣服いくら?", now: Fixture.now, calendar: Fixture.calendar).category == nil)
    }

    @Test("期間の語に作ったカテゴリの名前が続く文は、金額が無ければ質問")
    func classifierUsesCustomNames() {
        #expect(InputIntentClassifier.classify("先月の衣服", now: Fixture.now, calendar: Fixture.calendar) == .record)
        #expect(
            InputIntentClassifier.classify("先月の衣服", now: Fixture.now, calendar: Fixture.calendar, catalog: Self.catalog)
                == .question
        )
    }

    @Test("AI に渡す文にも作ったカテゴリの名前を書く")
    func factsUseCustomNames() {
        let question = LedgerQuestion(period: .thisMonth, metric: .categoryExpense, category: .custom("c1"))
        #expect(LedgerAnswerFacts.metricName(question, catalog: Self.catalog) == "衣服の支出の合計")
        let breakdown = CategoryBreakdown(expenseByCategory: [.custom("c2"): 4_000, .food: 1_000])
        #expect(RecapFacts.categories(breakdown.items, catalog: Self.catalog) == "美容 ¥4,000（80%）、食費 ¥1,000（20%）")
    }
}
