import Foundation
import Testing
@testable import SaifuLogCore

@Suite("予算の決め方")
struct BudgetPlanTests {
    /// 予算のテストで使う保存された予算の行。
    struct Row: BudgetRecord {
        var scopeRawValue: String
        var amount: Int
        var updatedAt: Date

        init(_ scope: BudgetScope, _ amount: Int, at updatedAt: Date) {
            self.scopeRawValue = scope.rawValue
            self.amount = amount
            self.updatedAt = updatedAt
        }

        init(rawScope: String, _ amount: Int, at updatedAt: Date) {
            self.scopeRawValue = rawScope
            self.amount = amount
            self.updatedAt = updatedAt
        }
    }

    static let earlier = Fixture.date(2026, 9, 1, hour: 9)
    static let later = Fixture.date(2026, 9, 20, hour: 21)

    // MARK: - 対象

    /// rawValue は保存に使うので変えない。全体は "total"、カテゴリはカテゴリの rawValue のまま。
    @Test("対象の rawValue は保存に使う値のまま、行き来できる")
    func scopeRawValues() {
        #expect(BudgetScope.total.rawValue == "total")
        #expect(BudgetScope(rawValue: "total") == .total)
        for category in EntryCategory.allCases {
            #expect(BudgetScope.category(category).rawValue == category.rawValue)
            #expect(BudgetScope(rawValue: category.rawValue) == .category(category))
        }
    }

    /// カテゴリの rawValue が "total" と重なると、そのカテゴリの予算が全体の予算として読まれてしまう。
    @Test("全体の rawValue はどのカテゴリの rawValue とも重ならない")
    func totalDoesNotCollideWithCategories() {
        #expect(!EntryCategory.allCases.map(\.rawValue).contains(BudgetScope.totalRawValue))
    }

    @Test("知らない対象は読まない", arguments: ["", "Total", "rent", "食費"])
    func unknownScope(rawValue: String) {
        #expect(BudgetScope(rawValue: rawValue) == nil)
    }

    // MARK: - 決め方

    @Test("記録が無ければ、予算は決まっていない")
    func empty() {
        let plan = BudgetPlan.resolve([Row]())

        #expect(plan.total == nil)
        #expect(plan.byCategory.isEmpty)
        #expect(plan == BudgetPlan())
    }

    @Test("全体とカテゴリ別の予算を読む")
    func readsTotalAndCategories() {
        let plan = BudgetPlan.resolve([
            Row(.total, 150_000, at: Self.earlier),
            Row(.category(.food), 40_000, at: Self.earlier),
            Row(.category(.cafe), 5_000, at: Self.later),
        ])

        #expect(plan.total == 150_000)
        #expect(plan.byCategory == [.food: 40_000, .cafe: 5_000])
        #expect(plan.amount(for: .total) == 150_000)
        #expect(plan.amount(for: .category(.food)) == 40_000)
        #expect(plan.amount(for: .category(.transport)) == nil)
    }

    /// iCloud で別々の端末の行が届くと、同じ対象の行が重なる。最後に書いたほうを採る。
    @Test("同じ対象の行が重なったら、最後に書いた行を採る（読み込む順番によらない）")
    func latestWins() {
        let rows = [
            Row(.total, 200_000, at: Self.later),
            Row(.total, 150_000, at: Self.earlier),
            Row(.category(.food), 30_000, at: Self.earlier),
            Row(.category(.food), 45_000, at: Self.later),
        ]

        let plan = BudgetPlan.resolve(rows)
        #expect(plan.total == 200_000)
        #expect(plan.byCategory == [.food: 45_000])
        #expect(BudgetPlan.resolve(rows.reversed()) == plan)
    }

    /// 予算を消すときは行を消さずに 0 を書く。あとから書いた 0 が、前の額に負けない。
    @Test("最後に書いた行が 0 なら、その対象は設定なし")
    func zeroMeansUnset() {
        let plan = BudgetPlan.resolve([
            Row(.total, 150_000, at: Self.earlier),
            Row(.total, 0, at: Self.later),
            Row(.category(.food), 40_000, at: Self.later),
            Row(.category(.food), 0, at: Self.earlier),
        ])

        #expect(plan.total == nil)
        #expect(plan.byCategory == [.food: 40_000])
    }

    /// 日時まで同じなら額の大きいほう。順番で決めると、端末ごとに違う予算が出る。
    @Test("日時が同じ行は、額の大きいほうを採る（読み込む順番によらない）")
    func tieBreaksByAmount() {
        let rows = [
            Row(.total, 0, at: Self.later),
            Row(.total, 150_000, at: Self.later),
            Row(.total, 120_000, at: Self.later),
        ]

        #expect(BudgetPlan.resolve(rows).total == 150_000)
        #expect(BudgetPlan.resolve(rows.reversed()).total == 150_000)
        #expect(BudgetPlan.preferred(rows)?.amount == 150_000)
    }

    /// 新しい版で足したカテゴリの行が iCloud で届いても、ほかの予算の読み方を変えない。
    @Test("知らない対象の行は読み飛ばす")
    func skipsUnknownScopes() {
        let plan = BudgetPlan.resolve([
            Row(rawScope: "pets", 9_000, at: Self.later),
            Row(.total, 150_000, at: Self.earlier),
        ])

        #expect(plan == BudgetPlan(total: 150_000))
    }

    @Test("0 以下の額は設定なしとして持たない")
    func initDropsNonPositiveAmounts() {
        let plan = BudgetPlan(total: 0, byCategory: [.food: 30_000, .cafe: 0, .daily: -1])

        #expect(plan.total == nil)
        #expect(plan.byCategory == [.food: 30_000])
        #expect(BudgetPlan(total: -500).total == nil)
    }

    @Test("行が無ければ、有効な行も無い")
    func preferredOfEmpty() {
        #expect(BudgetPlan.preferred([Row]()) == nil)
    }

    // MARK: - 決めた日時

    /// 月のまとめが、どの月から予算の進みを出すかに使う（有効な行の書き込んだ日時）。
    @Test("いま有効な予算を決めた日時は、有効とみなす行の日時")
    func decidedAtIsPreferredRowsDate() {
        let rows = [
            Row(.total, 150_000, at: Self.earlier),
            Row(.total, 200_000, at: Self.later),
            Row(.category(.food), 40_000, at: Self.earlier),
        ]

        #expect(BudgetPlan.decidedAt(.total, in: rows) == Self.later)
        #expect(BudgetPlan.decidedAt(.total, in: rows.reversed()) == Self.later)
        #expect(BudgetPlan.decidedAt(.category(.food), in: rows) == Self.earlier)
    }

    @Test("決めていない（行が無い・最後に書いた行が 0）なら、決めた日時も無い")
    func decidedAtWithoutBudget() {
        #expect(BudgetPlan.decidedAt(.total, in: [Row]()) == nil)
        #expect(BudgetPlan.decidedAt(.total, in: [
            Row(.total, 150_000, at: Self.earlier),
            Row(.total, 0, at: Self.later),
        ]) == nil)
        #expect(BudgetPlan.decidedAt(.category(.cafe), in: [Row(.total, 150_000, at: Self.earlier)]) == nil)
        #expect(BudgetPlan.decidedAt(.total, in: [Row(rawScope: "pets", 9_000, at: Self.later)]) == nil)
    }
}
