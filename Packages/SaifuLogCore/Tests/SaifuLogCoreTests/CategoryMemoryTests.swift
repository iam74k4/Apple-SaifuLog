import Foundation
import Testing
@testable import SaifuLogCore

/// 修正の記憶（`CategoryMemory`）。覚えた言葉のそろえ方・当て方・読み取った記録への当て方・聞き返すかの決め方・
/// iCloud で重なった行の選び方を確かめる。
@Suite("修正の記憶")
struct CategoryMemoryTests {
    /// 保存された覚えの行。
    struct Row: LearnedCategoryRecord {
        var phrase: String
        var categoryRawValue: String
        var updatedAt: Date

        init(_ phrase: String, _ category: EntryCategory, at updatedAt: Date = CategoryMemoryTests.earlier) {
            self.phrase = phrase
            self.categoryRawValue = category.rawValue
            self.updatedAt = updatedAt
        }

        init(_ phrase: String, rawCategory: String, at updatedAt: Date = CategoryMemoryTests.earlier) {
            self.phrase = phrase
            self.categoryRawValue = rawCategory
            self.updatedAt = updatedAt
        }
    }

    static let earlier = Fixture.date(2026, 9, 1, hour: 9)
    static let later = Fixture.date(2026, 9, 20, hour: 21)

    // MARK: - 言葉のそろえ方

    @Test("表記ゆれ（ひらがなとカタカナ・全角と半角・英字の大小・空白）をそろえる", arguments: [
        ("ランチ", "ランチ"),
        ("らんち", "ランチ"),
        ("UNIQLO", "uniqlo"),
        ("ＵＮＩＱＬＯ", "uniqlo"),
        ("  ユニクロ\u{3000}\u{3000}靴下 ", "ユニクロ 靴下"),
        ("セブン11", "セブン11"),
    ])
    func keyFolding(item: String, expected: String) {
        #expect(CategoryMemory.key(for: item) == expected)
    }

    @Test("空の品目と長すぎる品目は覚えない")
    func keyRejectsEmptyAndLong() {
        #expect(CategoryMemory.key(for: "") == nil)
        #expect(CategoryMemory.key(for: "  \u{3000} ") == nil)
        #expect(CategoryMemory.key(for: String(repeating: "あ", count: CategoryMemory.maximumKeyLength)) != nil)
        #expect(CategoryMemory.key(for: String(repeating: "あ", count: CategoryMemory.maximumKeyLength + 1)) == nil)
    }

    @Test("メモから、解析が書き足した説明を除いた品目を取り出す")
    func itemOfMemo() {
        let split = ParsedEntry.assemble(total: 12_000, category: .food, isIncome: false, item: "焼肉", daysAgo: 0, splitCount: 4)
        #expect(CategoryMemory.item(ofMemo: split.memo, amount: split.amount, isIncome: false) == "焼肉")
        // 金額を直して書いた形と合わなくなっても、全角の括弧の前までを品目にする。
        #expect(CategoryMemory.item(ofMemo: split.memo, amount: 2_500, isIncome: false) == "焼肉")
        let perPerson = ParsedEntry.assemble(
            total: 3_000, category: .food, isIncome: false, item: "焼肉", daysAgo: 0, splitCount: 4, isPerPerson: true
        )
        #expect(CategoryMemory.item(ofMemo: perPerson.memo, amount: perPerson.amount, isIncome: false) == "焼肉")
        #expect(CategoryMemory.item(ofMemo: "ユニクロ", amount: 3_990, isIncome: false) == "ユニクロ")
        // 利用者が書いた半角の括弧は品目のまま。
        #expect(CategoryMemory.item(ofMemo: "ランチ(社食)", amount: 500, isIncome: false) == "ランチ(社食)")
    }

    // MARK: - 当て方

    @Test("同じ言葉を覚えていれば、そのカテゴリ（表記ゆれも同じ言葉）")
    func exactMatch() {
        let memory = CategoryMemory.resolve([Row("ユニクロ", .other), Row("家賃", .utilities)])

        #expect(memory.category(forItem: "ユニクロ") == .other)
        #expect(memory.category(forItem: "ゆにくろ") == .other)
        #expect(memory.category(forItem: "家賃") == .utilities)
        #expect(memory.category(forItem: "ランチ") == nil)
        #expect(memory.category(forItem: "") == nil)
    }

    @Test("品目に含まれる覚えた言葉のうち、最も長いものを当てる")
    func containedMatchPrefersLongest() {
        let memory = CategoryMemory.resolve([
            Row("コーヒー", .food),
            Row("コーヒー豆", .daily),
            Row("ユニクロ", .other),
        ])

        #expect(memory.category(forItem: "ユニクロ 靴下") == .other)
        #expect(memory.category(forItem: "ユニクロで靴下") == .other)
        #expect(memory.category(forItem: "コーヒー豆 200g") == .daily)
        #expect(memory.category(forItem: "缶コーヒー") == .food)
    }

    @Test("同じ長さの言葉が 2 つ含まれるときは、文字の順で先の言葉を当てる（読むたびに変わらない）")
    func containedMatchTieIsDeterministic() {
        let memory = CategoryMemory.resolve([Row("アイウ", .daily), Row("エオカ", .transport)])

        #expect(memory.category(forItem: "エオカとアイウ") == .daily)
        #expect(memory.category(forItem: "アイウとエオカ") == .daily)
    }

    /// 1 文字の言葉を部分一致に使うと、「薬」を覚えたときに「薬局」「目薬」まで同じカテゴリになる。
    @Test("1 文字の言葉は、同じ言葉のときだけ当てる")
    func singleCharacterKeyOnlyMatchesExactly() {
        let memory = CategoryMemory.resolve([Row("薬", .daily)])

        #expect(memory.category(forItem: "薬") == .daily)
        #expect(memory.category(forItem: "薬局") == nil)
        #expect(memory.category(forItem: "目薬") == nil)
    }

    @Test("読み取った記録のカテゴリを覚えで置き換える（AI と辞書のどちらで読んだものにも）")
    func applyingReplacesCategory() async throws {
        let memory = CategoryMemory.resolve([Row("家賃", .other), Row("ドラッグ", .daily), Row("ユニクロ", .other)])
        let parsed = try await Fixture.parser.parse("家賃 80000")
        let aiLike = [ParsedEntry(amount: 1_200, category: .entertainment, memo: "ドラッグ")]

        #expect(memory.applying(to: parsed).map(\.category) == [.other])
        #expect(memory.applying(to: aiLike).map(\.category) == [.daily])
        #expect(memory.applying(to: [ParsedEntry(amount: 3_990, category: .daily, memo: "ユニクロ 靴下")]).map(\.category) == [.other])
    }

    @Test("割り勘の記録は、説明を除いた品目で当てる")
    func applyingUsesItemOfSplitMemo() {
        let memory = CategoryMemory.resolve([Row("焼肉", .entertainment)])
        let split = ParsedEntry.assemble(total: 12_000, category: .food, isIncome: false, item: "焼肉", daysAgo: 1, splitCount: 4)

        let applied = memory.applying(to: [split])

        #expect(applied.map(\.category) == [.entertainment])
        // カテゴリのほか（金額・メモ・日付・人数）は変えない。
        #expect(applied.first?.amount == split.amount)
        #expect(applied.first?.memo == split.memo)
        #expect(applied.first?.daysAgo == 1)
        #expect(applied.first?.splitCount == 4)
    }

    @Test("収入と、品目にカテゴリの名前が書かれた記録は置き換えない")
    func applyingSkipsIncomeAndExplicitCategory() {
        let memory = CategoryMemory.resolve([Row("給料", .food), Row("ユニクロ", .other)])

        let income = ParsedEntry(amount: 250_000, category: .other, isIncome: true, memo: "給料")
        #expect(memory.applying(to: [income]) == [income])
        let explicit = ParsedEntry(amount: 500, category: .daily, memo: "日用品 ユニクロ")
        #expect(memory.applying(to: [explicit]) == [explicit])
    }

    @Test("覚えが無ければ、読み取ったままにする")
    func applyingWithoutRules() {
        let entries = [ParsedEntry(amount: 850, category: .food, memo: "ランチ")]
        #expect(CategoryMemory().applying(to: entries) == entries)
    }

    // MARK: - 聞き返し

    @Test("その他になり、辞書にも覚えにも当たらない支出だけ聞き返す")
    func asksOnlyWhenUnknown() {
        let memory = CategoryMemory.resolve([Row("家賃", .other), Row("ジム", .entertainment)])

        #expect(memory.asksCategory(memo: "ユニクロ", amount: 3_990, category: .other, isIncome: false))
        // 金額だけの記録も、その記録のカテゴリは選べるので聞き返す。
        #expect(memory.asksCategory(memo: "", amount: 3_990, category: .other, isIncome: false))
        // その他以外に読めた記録・収入は聞き返さない。
        #expect(!memory.asksCategory(memo: "ユニクロ", amount: 3_990, category: .daily, isIncome: false))
        #expect(!memory.asksCategory(memo: "臨時収入", amount: 3_000, category: .other, isIncome: true))
        // 覚えた言葉（「その他のまま」を選んだ言葉も）は聞き返さない。
        #expect(!memory.asksCategory(memo: "家賃", amount: 80_000, category: .other, isIncome: false))
        // 辞書の「その他」の語とカテゴリの名前は、その他と読んだ理由があるので聞き返さない。
        #expect(!memory.asksCategory(memo: "洋服", amount: 4_000, category: .other, isIncome: false))
        #expect(!memory.asksCategory(memo: "その他", amount: 500, category: .other, isIncome: false))
        // 英語の品目も同じ。辞書の「その他」の語（"clothes"）は聞き返さず、どこにも当たらない語は聞き返す。
        #expect(!memory.asksCategory(memo: "clothes", amount: 4_000, category: .other, isIncome: false))
        #expect(memory.asksCategory(memo: "widget", amount: 4_000, category: .other, isIncome: false))
    }

    // MARK: - 重なった行

    @Test("同じ言葉の行が重なったら、書いた日時の新しい行を採る（表記ゆれの行も同じ言葉）")
    func resolvePrefersLatest() {
        let memory = CategoryMemory.resolve([
            Row("ユニクロ", .daily, at: Self.later),
            Row("ゆにくろ", .other, at: Self.earlier),
        ])

        #expect(memory.rules == ["ユニクロ": .daily])
    }

    @Test("同じ日時の行は、カテゴリの rawValue の順で先の行を採る（並び順によらない）")
    func resolveTieIsDeterministic() {
        let rows = [Row("ユニクロ", .other), Row("ユニクロ", .daily)]

        #expect(CategoryMemory.resolve(rows).rules == ["ユニクロ": .daily])
        #expect(CategoryMemory.resolve(rows.reversed()).rules == ["ユニクロ": .daily])
        #expect(CategoryMemory.preferred(rows)?.categoryRawValue == EntryCategory.daily.rawValue)
        #expect(CategoryMemory.preferred(Array(rows.reversed()))?.categoryRawValue == EntryCategory.daily.rawValue)
    }

    @Test("知らないカテゴリの行と空の言葉の行は読み飛ばし、残す行にも選ばない")
    func resolveSkipsUnknownRows() {
        let rows = [
            Row("ユニクロ", rawCategory: "clothing", at: Self.later),
            Row("ユニクロ", .other, at: Self.earlier),
            Row(" ", .food),
        ]

        #expect(CategoryMemory.resolve(rows).rules == ["ユニクロ": .other])
        #expect(CategoryMemory.preferred(Array(rows.prefix(2)))?.categoryRawValue == EntryCategory.other.rawValue)
        #expect(CategoryMemory.preferred([Row]()) == nil)
    }
}
