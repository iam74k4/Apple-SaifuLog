import Foundation
import Testing
@testable import SaifuLogCore

@Suite("カテゴリ別の内訳")
struct CategoryBreakdownTests {
    static func breakdown(_ amounts: [EntryCategory: Int]) -> CategoryBreakdown {
        CategoryBreakdown(expenseByCategory: amounts)
    }

    static func percents(_ breakdown: CategoryBreakdown) -> [Int] {
        breakdown.items.map(\.percent)
    }

    @Test("金額の多い順に並べ、割合を添える")
    func sortsByAmount() {
        let breakdown = Self.breakdown([.cafe: 2_000, .food: 6_000, .transport: 1_000, .daily: 1_000])

        #expect(breakdown.items.map(\.category) == [.food, .cafe, .daily, .transport])
        #expect(breakdown.items.map(\.amount) == [6_000, 2_000, 1_000, 1_000])
        #expect(Self.percents(breakdown) == [60, 20, 10, 10])
        #expect(breakdown.total == 10_000)
    }

    /// 1 つずつ四捨五入すると 99%（33.3% × 3）や 102%（16.7% × 6）になる組み合わせ。
    @Test("割合を足すとちょうど 100% になる", arguments: [
        [EntryCategory.food: 1, .cafe: 1, .other: 1],
        [.food: 1, .daily: 1, .transport: 1, .cafe: 1, .entertainment: 1, .utilities: 1],
        [.food: 1, .daily: 1, .transport: 1, .cafe: 1, .entertainment: 1, .utilities: 1, .medical: 1],
        [.food: 12_300, .cafe: 4_560, .transport: 7_890, .other: 1],
        [.food: 999, .daily: 1],
        [.food: 1, .daily: 1, .transport: 1, .cafe: 1, .entertainment: 1, .utilities: 1, .medical: 1, .other: 1],
    ])
    func sumsTo100(amounts: [EntryCategory: Int]) {
        let breakdown = Self.breakdown(amounts)

        #expect(Self.percents(breakdown).reduce(0, +) == 100)
        #expect(breakdown.items.count == amounts.count)
    }

    /// 3 等分は 33.3...% ずつ。余った 1% は、端数が同じなので上の行（カテゴリの定義順で先の食費）に足す。
    @Test("3 等分は 34・33・33（余りは並びの上の行へ）")
    func threeWaySplit() {
        let breakdown = Self.breakdown([.other: 500, .cafe: 500, .food: 500])

        #expect(breakdown.items.map(\.category) == [.food, .cafe, .other])
        #expect(Self.percents(breakdown) == [34, 33, 33])
    }

    /// 6 等分は 16.66...% ずつ。4% 余るので、上の 4 行が 17%。
    @Test("6 等分は 17・17・17・17・16・16")
    func sixWaySplit() {
        let breakdown = Self.breakdown([
            .food: 100, .daily: 100, .transport: 100, .cafe: 100, .entertainment: 100, .utilities: 100,
        ])

        #expect(Self.percents(breakdown) == [17, 17, 17, 17, 16, 16])
    }

    /// 4/7 = 57.14%、2/7 = 28.57%、1/7 = 14.29%。切り捨てると 99% で、端数がいちばん大きいのは 2 行目。
    @Test("余った % は、並びの順ではなく端数の大きい行に足す")
    func leftoverGoesToLargestRemainder() {
        let breakdown = Self.breakdown([.food: 4, .cafe: 2, .other: 1])

        #expect(breakdown.items.map(\.category) == [.food, .cafe, .other])
        #expect(Self.percents(breakdown) == [57, 29, 14])
    }

    @Test("支出が無ければ行も無い")
    func empty() {
        let breakdown = Self.breakdown([:])

        #expect(breakdown.isEmpty)
        #expect(breakdown.items.isEmpty)
        #expect(breakdown.total == 0)
        #expect(breakdown.item(for: .food) == nil)
    }

    @Test("0 円（以下）のカテゴリは出さない")
    func dropsNonPositiveAmounts() {
        let breakdown = Self.breakdown([.food: 0, .cafe: 500, .daily: -100])

        #expect(breakdown.items == [CategoryBreakdown.Item(category: .cafe, amount: 500, percent: 100)])
        #expect(breakdown.total == 500)

        #expect(Self.breakdown([.food: 0]).isEmpty)
    }

    @Test("1 カテゴリだけなら 100%")
    func singleCategory() {
        let breakdown = Self.breakdown([.transport: 1_280])

        #expect(breakdown.items == [CategoryBreakdown.Item(category: .transport, amount: 1_280, percent: 100)])
    }

    /// 辞書の並びは開くたびに変わりうるので、同じ額の行の順はカテゴリの定義順で決める。
    @Test("同じ額なら、カテゴリの定義順")
    func tiesInDefinitionOrder() {
        let breakdown = Self.breakdown([.other: 500, .medical: 500, .food: 500, .transport: 500, .cafe: 900])

        #expect(breakdown.items.map(\.category) == [.cafe, .food, .transport, .medical, .other])
    }

    /// 0 円のカテゴリは行にしないので、0% の行は「1% 未満」の意味になる。
    @Test("ごく小さい額は 0% になり、合計は 100% のまま")
    func tinyAmountRoundsToZero() {
        let breakdown = Self.breakdown([.food: 999_999, .cafe: 1])

        #expect(Self.percents(breakdown) == [100, 0])
        #expect(breakdown.item(for: .cafe)?.amount == 1)
    }

    @Test("大きな額でも桁あふれしない")
    func largeAmounts() {
        let breakdown = Self.breakdown([.food: Int.max / 2, .cafe: Int.max / 4])

        #expect(Self.percents(breakdown) == [67, 33])
    }

    /// どの組み合わせでも、合計は 100 で、1 行ずつの割合は本当の割合との差が 1 未満。
    @Test("いろいろな額の組み合わせでも、合計は 100 で、本当の割合との差は 1% 未満")
    func manyCombinations() {
        var seed: UInt64 = 20_260_928
        func next() -> Int {
            // 実行のたびに同じ並びになる簡単な乱数（線形合同法）。
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int(seed >> 40) % 50_000 + 1
        }
        for round in 0..<500 {
            let count = round % EntryCategory.builtIns.count + 1
            let amounts = Dictionary(uniqueKeysWithValues: EntryCategory.builtIns.prefix(count).map { ($0, next()) })
            let breakdown = Self.breakdown(amounts)
            let total = Double(amounts.values.reduce(0, +))

            #expect(Self.percents(breakdown).reduce(0, +) == 100, "\(amounts)")
            for item in breakdown.items {
                let exact = Double(item.amount) * 100 / total
                #expect(abs(Double(item.percent) - exact) < 1, "\(amounts)")
            }
            // 金額の多い順（同じ額はカテゴリの定義順）。
            #expect(breakdown.items.map(\.amount) == breakdown.items.map(\.amount).sorted(by: >))
        }
    }

    @Test("期間の集計から作ると、支出だけを数える（収入は入れない）")
    func fromLedgerSummary() {
        let records = [
            TestRecord(amount: 3_000, category: .food, spentAt: Fixture.date(2026, 9, 3)),
            TestRecord(amount: 1_000, category: .cafe, spentAt: Fixture.date(2026, 9, 4)),
            TestRecord(amount: 250_000, isIncome: true, category: .other, spentAt: Fixture.date(2026, 9, 25)),
        ]
        let summary = LedgerSummary(
            records: records, interval: DateInterval(start: Fixture.date(2026, 9, 1), end: Fixture.date(2026, 10, 1)),
            calendar: Fixture.calendar
        )

        let breakdown = CategoryBreakdown(summary)

        #expect(breakdown.items.map(\.category) == [.food, .cafe])
        #expect(Self.percents(breakdown) == [75, 25])
        #expect(breakdown.total == summary.expense)
        #expect(breakdown.item(for: .cafe)?.amount == 1_000)
        #expect(breakdown.item(for: .other) == nil)
    }
}
