import Foundation
import SaifuLogCore
import Testing

/// ウィジェットに出す文と数字（`MonthSpendPresentation`）を、大きさ × 状態ごとに確かめる。帯と同じ数字だけを出し、予算を超えたら
/// 語でも伝え、ロック中と数字の無いときは金額を出さないこと。
struct MonthSpendPresentationTests {
    typealias Fixture = WidgetFixture

    static func presentation(
        _ display: WidgetDisplay?, _ layout: MonthSpendLayout, language: String = "ja"
    ) -> MonthSpendPresentation {
        MonthSpendPresentation(
            display: display, layout: layout, bundle: Fixture.strings(language),
            locale: language == "ja" ? Fixture.japanese : Fixture.english
        )
    }

    static let withinBudget = WidgetDisplay.figures(spent: 32_480, budget: Fixture.budget(50_000, spent: 32_480))
    static let overBudget = WidgetDisplay.figures(spent: 53_000, budget: Fixture.budget(50_000, spent: 53_000))
    static let withoutBudget = WidgetDisplay.figures(spent: 42_380, budget: nil)

    // MARK: - ホーム画面の小

    @Test("小: 見出し・使った額・「あと ¥…」とバー")
    func smallWithinBudget() {
        let shown = Self.presentation(Self.withinBudget, .small)

        #expect(shown.kind == .figures)
        #expect(shown.title == "今月使った額")
        #expect(shown.primary == "¥32,480")
        #expect(shown.budgetLine == "あと ¥17,520")
        #expect(!shown.isOver)
        #expect(shown.fraction == 32_480.0 / 50_000.0)
        for part in ["今月使った額", "¥32,480", "あと ¥17,520"] {
            #expect(shown.accessibilityLabel.contains(part))
        }
    }

    @Test("小: 予算を超えたら「¥… オーバー」（語でも伝える）とバーはいっぱい")
    func smallOverBudget() {
        let shown = Self.presentation(Self.overBudget, .small)

        #expect(shown.primary == "¥53,000")
        #expect(shown.budgetLine == "¥3,000 オーバー")
        #expect(shown.isOver)
        #expect(shown.fraction == 1)
        #expect(shown.accessibilityLabel.contains("¥3,000 オーバー"))
    }

    @Test("小: 予算を決めていなければ、使った額だけ（バーも予算の行も出さない）")
    func smallWithoutBudget() {
        let shown = Self.presentation(Self.withoutBudget, .small)

        #expect(shown.primary == "¥42,380")
        #expect(shown.budgetLine == nil)
        #expect(shown.fraction == nil)
        #expect(!shown.isOver)
    }

    // MARK: - ロック画面

    @Test("長方形: 「今月 ¥…」とバーと予算の行")
    func rectangular() {
        let shown = Self.presentation(Self.withinBudget, .rectangular)

        #expect(shown.primary == "今月 ¥32,480")
        #expect(shown.budgetLine == "あと ¥17,520")
        #expect(shown.fraction != nil)
        #expect(Self.presentation(Self.overBudget, .rectangular).budgetLine == "¥3,000 オーバー")
    }

    @Test("1 行: 予算の残りか超えた額まで 1 つの文にする（予算が無ければ使った額だけ）", arguments: [
        (MonthSpendPresentationTests.withinBudget, "今月 ¥32,480・あと ¥17,520"),
        (MonthSpendPresentationTests.overBudget, "今月 ¥53,000・¥3,000 オーバー"),
        (MonthSpendPresentationTests.withoutBudget, "今月 ¥42,380"),
    ])
    func inline(display: WidgetDisplay, expected: String) {
        let shown = Self.presentation(display, .inline)

        #expect(shown.primary == expected)
        #expect(shown.budgetLine == nil)
        #expect(shown.fraction == nil)
    }

    @Test("丸: 予算があれば使った割合のゲージ、超えたら割合の代わりに注意の印、無ければ使った額")
    func circular() {
        let within = Self.presentation(Self.withinBudget, .circular)
        #expect(within.primary == "65%")
        #expect(within.fraction == 32_480.0 / 50_000.0)
        #expect(within.symbol == "yensign")
        #expect(within.accessibilityLabel.contains("¥32,480"))

        let over = Self.presentation(Self.overBudget, .circular)
        #expect(over.isOver)
        #expect(over.primary.isEmpty)
        #expect(over.fraction == 1)
        #expect(over.accessibilityLabel.contains("¥3,000 オーバー"))

        let without = Self.presentation(Self.withoutBudget, .circular)
        #expect(without.primary == "¥42,380")
        #expect(without.fraction == nil)
    }

    // MARK: - ロック中・数字が無いとき

    /// アプリのロック中は、どの大きさにも金額を出さない（読み上げにも）。
    @Test("アプリのロック中は「ロック中」とだけ出し、金額を出さない", arguments: MonthSpendLayout.allCases)
    func lockedShowsNoAmounts(layout: MonthSpendLayout) {
        let shown = Self.presentation(.hidden, layout)

        #expect(shown.kind == .locked)
        #expect(shown.title == "ロック中")
        #expect(shown.primary == "アプリのロック中は金額を出しません")
        #expect(shown.symbol == "lock.fill")
        #expect(shown.fraction == nil)
        #expect(shown.budgetLine == nil)
        for text in [shown.title, shown.primary, shown.accessibilityLabel] {
            #expect(!text.contains("¥"))
        }
    }

    @Test("まだ数字が無ければ「アプリを開くと出ます」", arguments: MonthSpendLayout.allCases)
    func emptyAsksToOpenApp(layout: MonthSpendLayout) {
        let shown = Self.presentation(nil, layout)

        #expect(shown.kind == .empty)
        #expect(shown.title == "今月使った額")
        #expect(shown.primary == "アプリを開くと出ます")
        #expect(shown.fraction == nil)
        #expect(!shown.accessibilityLabel.contains("¥"))
    }

    // MARK: - 英語

    @Test("英語の訳: 見出し・予算の行・1 行・ロック中")
    func english() {
        let small = Self.presentation(Self.withinBudget, .small, language: "en")
        #expect(small.title == "Spent This Month")
        #expect(small.budgetLine == "¥17,520 left")
        #expect(Self.presentation(Self.overBudget, .small, language: "en").budgetLine == "¥3,000 over")
        #expect(Self.presentation(Self.withinBudget, .rectangular, language: "en").primary == "¥32,480 this month")
        #expect(Self.presentation(Self.withinBudget, .inline, language: "en").primary == "¥32,480 this month · ¥17,520 left")
        #expect(Self.presentation(Self.overBudget, .inline, language: "en").primary == "¥53,000 this month · ¥3,000 over")

        let locked = Self.presentation(.hidden, .small, language: "en")
        #expect(locked.title == "Locked")
        #expect(locked.primary == "Amounts are hidden while the app is locked")
        #expect(Self.presentation(nil, .small, language: "en").primary == "Open the app to show this")
    }
}
