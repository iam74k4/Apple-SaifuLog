import Foundation
import Testing
@testable import SaifuLogCore

/// キーワード辞書で質問を読む（QuestionParser）。AI が使えない端末と、AI が失敗したときの経路。
@Suite("キーワード辞書で質問を読む")
struct QuestionParserTests {
    static func question(_ text: String) -> LedgerQuestion? {
        QuestionParser.question(from: text, now: Fixture.now, calendar: Fixture.calendar)
    }

    static func reading(_ text: String) -> QuestionReading {
        QuestionParser.read(text, now: Fixture.now, calendar: Fixture.calendar)
    }

    @Test("質問の例を読める")
    func examples() {
        #expect(Self.question("今月カフェいくら?") == LedgerQuestion(period: .thisMonth, metric: .categoryExpense, category: .cafe))
        #expect(Self.question("先月の食費は?") == LedgerQuestion(period: .lastMonth, metric: .categoryExpense, category: .food))
        #expect(Self.question("今月あと何日でいくら使える?") == LedgerQuestion(period: .thisMonth, metric: .dailyAllowance))
        #expect(Self.question("今週いちばん使ったのは?") == LedgerQuestion(period: .thisWeek, metric: .topCategory))
        for example in QuestionParser.examples {
            #expect(Self.question(example) != nil, "\(example)")
        }
    }

    @Test("期間の語", arguments: [
        ("今日の支出", QuestionPeriod.today),
        ("本日いくら使った", .today),
        ("昨日の支出", .yesterday),
        ("きのういくら", .yesterday),
        ("今週の支出", .thisWeek),
        ("先週の支出", .lastWeek),
        ("今月の支出", .thisMonth),
        ("先月の支出", .lastMonth),
        ("今年の支出", .thisYear),
        ("ことしの支出", .thisYear),
    ])
    func periods(text: String, expected: QuestionPeriod) {
        #expect(Self.question(text)?.period == expected, "\(text)")
    }

    @Test("直近 N 日（週は 7 日）", arguments: [
        ("直近7日の支出", 7),
        ("過去30日間の合計", 30),
        ("最近3日の出費", 3),
        ("ここ1週間の支出", 7),
        ("この2週間いくら使った", 14),
        ("3日間の支出", 3),
        ("一週間の支出", 7),
        ("直近 10 日の支出", 10),
        ("直近１４日の支出", 14),
        ("直近366日の支出", 366),
    ])
    func recentDays(text: String, days: Int) {
        #expect(Self.question(text)?.period == .recentDays(days), "\(text)")
    }

    @Test("期間が書かれていなければ今月")
    func defaultsToThisMonth() {
        #expect(Self.question("カフェいくら?")?.period == .thisMonth)
        #expect(Self.question("いくら使った?") == LedgerQuestion(period: .thisMonth, metric: .expenseTotal))
    }

    @Test("指標の語", arguments: [
        ("今月の支出は?", QuestionMetric.expenseTotal),
        ("今月いくら使った?", .expenseTotal),
        ("今月の合計", .expenseTotal),
        ("今月の収入は?", .incomeTotal),
        ("今月の給料いくら?", .incomeTotal),
        ("今月の収支は?", .balance),
        ("今月の内訳", .expenseByCategory),
        ("今月何に使った?", .expenseByCategory),
        ("今月の記録は何件?", .entryCount),
        ("今月の予算の残りは?", .remainingBudget),
        ("今月あといくら使える?", .remainingBudget),
        ("1日あたりいくら使える?", .dailyAllowance),
        ("1日あたりいくら?", .dailyAllowance),
        ("日割りでいくら?", .dailyAllowance),
        ("今月毎日いくらまで?", .dailyAllowance),
        ("今日1日でいくら使える?", .dailyAllowance),
        ("今月あと何日?", .dailyAllowance),
        ("今月いくら残ってる?", .remainingBudget),
        ("今月何に一番使った?", .topCategory),
        ("今年最も使ったのは?", .topCategory),
    ])
    func metrics(text: String, expected: QuestionMetric) {
        #expect(Self.question(text)?.metric == expected, "\(text)")
    }

    @Test("カテゴリはキーワードと表示名で読む", arguments: [
        ("今月カフェいくら?", EntryCategory.cafe),
        ("今月コーヒーにいくら?", .cafe),
        ("先月のスタバは?", .cafe),
        ("今月の食費は?", .food),
        ("今週の電車代", .transport),
        ("今月の交通費いくら", .transport),
        ("今月の光熱費は?", .utilities),
        ("先月の医療費", .medical),
        ("今月その他にいくら?", .other),
    ])
    func categories(text: String, expected: EntryCategory) {
        let question = Self.question(text)
        #expect(question?.category == expected, "\(text)")
        #expect(question?.metric == .categoryExpense, "\(text)")
    }

    @Test("カテゴリの件数")
    func categoryCount() {
        #expect(Self.question("今月カフェ何回行った?") == LedgerQuestion(period: .thisMonth, metric: .entryCount, category: .cafe))
        #expect(Self.question("今月の記録は何件?") == LedgerQuestion(period: .thisMonth, metric: .entryCount))
    }

    @Test("収入・収支・予算・内訳ではカテゴリを使わない")
    func categoryIsDroppedWhenUnused() {
        #expect(Self.question("今月カフェの予算の残りは?") == LedgerQuestion(period: .thisMonth, metric: .remainingBudget))
        #expect(Self.question("先月の食費の内訳") == LedgerQuestion(period: .lastMonth, metric: .expenseByCategory))
    }

    @Test("答えられない書き方は読めない質問にする（聞かれていない期間の答えを出さない）", arguments: [
        "去年の食費は?",
        "昨年の支出",
        "来月の予算",
        "明日いくら使える?",
        "一昨日いくら使った?",
        "おとといの支出",
        "週末の支出は?",
        "金曜日いくら使った?",
        "9/26の支出は?",
        "3日前の支出",
        "26日の支出は?",
        "今月と先月の食費",
        "今日と昨日の支出",
        "3か月の支出",
        "ランチ850円って高い?",
        "3000円以上使った日は?",
        "直近400日の支出",
        "2週間前の支出",
        "直近0日の支出",
        // 数字で名前を付けた月や年（日の無い「3月」は日付として読まれないので、見落とすと今月の数字になる）。
        "3月の食費は?",
        "10月の食費は?",
        "9月のカフェいくら?",
        "8月の支出",
        "10月のカフェ",
        "3月いくら使った?",
        "12月の収入は?",
        "十二月の支出",
        "2025年の食費は?",
        "2025年の支出",
        "2026年の支出",
        "令和7年の食費",
        "この一年の支出",
        "1年間の支出",
        "半年の支出",
        "今年度の支出",
    ])
    func unsupported(text: String) {
        #expect(Self.question(text) == nil, "\(text)")
        #expect(Self.reading(text).hasUnsupportedPart, "\(text)")
    }

    @Test("使った額を聞く「1日で」「毎日」は、1 日あたりに使える額にしない（平均と日付は読めない質問）", arguments: [
        // 1 日あたりに使った額（平均）は答えられない。
        "先月は1日にいくら使ってた?",
        "1日あたりいくら使った?",
        "毎日いくら使ってる?",
        // 「今月1日に」は日付（その月の 1 日）。
        "今月1日にカフェいくら?",
        // 予算の語の無い「毎日」は、言い添えか平均か決められない。
        "毎日カフェ行ってるけど今月いくら?",
    ])
    func perDaySpendingIsUnsupported(text: String) {
        #expect(Self.question(text) == nil, "\(text)")
        #expect(Self.reading(text).hasUnsupportedPart, "\(text)")
    }

    @Test("「今日1日で」はその日まるごと。期間はその日のまま、使った額を答える")
    func wholeDayKeepsPeriod() {
        #expect(Self.question("今日1日でいくら使った?") == LedgerQuestion(period: .today, metric: .expenseTotal))
        #expect(Self.question("昨日は1日でいくら使った?") == LedgerQuestion(period: .yesterday, metric: .expenseTotal))
        #expect(Self.question("今日一日でカフェいくら?") == LedgerQuestion(period: .today, metric: .categoryExpense, category: .cafe))
    }

    @Test("どの語にも当たらなければ読めない", arguments: ["こんにちは?", "教えて", "どう?", "?"])
    func unreadable(text: String) {
        #expect(Self.question(text) == nil, "\(text)")
    }

    // MARK: - AI の選択と合わせる

    @Test("文から読めた期間・カテゴリ・指標は、モデルの選択より優先する")
    func readingWinsOverModel() {
        let reading = Self.reading("先月のカフェの件数は?")
        let choice = QuestionChoice(period: .thisYear, metric: .expenseTotal, category: .food)

        #expect(reading.resolved(with: choice) == LedgerQuestion(period: .lastMonth, metric: .entryCount, category: .cafe))
    }

    @Test("文から読めなかったものだけ、モデルの選択を使う")
    func modelFillsGaps() {
        // 「年初から」「外で食べた」は辞書に無い言い回し。
        let reading = Self.reading("年初から外で食べたのは?")
        let choice = QuestionChoice(period: .thisYear, metric: .categoryExpense, category: .food)

        #expect(reading.question == nil)
        #expect(reading.resolved(with: choice) == LedgerQuestion(period: .thisYear, metric: .categoryExpense, category: .food))
    }

    @Test("金額を聞く語だけの文では、モデルが件数・いちばん多いカテゴリ・内訳を選んでも金額で答える", arguments: [
        QuestionMetric.entryCount, .topCategory, .expenseByCategory,
    ])
    func amountQuestionKeepsAmount(modelMetric: QuestionMetric) {
        let choice = QuestionChoice(period: .thisMonth, metric: modelMetric, category: .cafe)

        #expect(Self.reading("今月カフェいくら?").resolved(with: choice)
            == LedgerQuestion(period: .thisMonth, metric: .categoryExpense, category: .cafe))
        #expect(Self.reading("今月いくら?").resolved(with: QuestionChoice(period: .thisMonth, metric: modelMetric))
            == LedgerQuestion(period: .thisMonth, metric: .expenseTotal))
    }

    @Test("金額を聞く語とカテゴリの文では、モデルがカテゴリを使わない指標を選んでも、そのカテゴリの支出で答える", arguments: [
        QuestionMetric.remainingBudget, .dailyAllowance, .incomeTotal, .balance, .expenseTotal, .categoryExpense,
    ])
    func amountQuestionWithCategoryKeepsCategory(modelMetric: QuestionMetric) {
        let choice = QuestionChoice(period: .thisMonth, metric: modelMetric)

        #expect(Self.reading("今月カフェいくら?").resolved(with: choice)
            == LedgerQuestion(period: .thisMonth, metric: .categoryExpense, category: .cafe))
    }

    @Test("金額を聞く語だけの文でも、予算・収入・収支の選択はモデルのまま使う（辞書に無い言い回しを読めることがあるため）", arguments: [
        QuestionMetric.remainingBudget, .dailyAllowance, .incomeTotal, .balance,
    ])
    func amountQuestionKeepsModelAmountMetric(modelMetric: QuestionMetric) {
        let choice = QuestionChoice(period: .thisMonth, metric: modelMetric)

        #expect(Self.reading("今月はいくら?").resolved(with: choice) == LedgerQuestion(period: .thisMonth, metric: modelMetric))
    }

    @Test("金額を聞く語が無ければ、モデルの件数の選択を使う")
    func modelCountWithoutAmountWord() {
        let choice = QuestionChoice(period: .thisMonth, metric: .entryCount, category: .cafe)

        #expect(Self.reading("今月カフェ行った?").resolved(with: choice)
            == LedgerQuestion(period: .thisMonth, metric: .entryCount, category: .cafe))
    }

    @Test("直近 N 日の N は文から読む。モデルが直近を選んでも、文に日数が無ければ今月")
    func recentDaysNeedCountFromText() {
        let choice = QuestionChoice(period: .recentDays, metric: .expenseTotal)

        #expect(Self.reading("最近いくら使った?").resolved(with: choice)?.period == .thisMonth)
        #expect(Self.reading("直近10日いくら使った?").resolved(with: choice)?.period == .recentDays(10))
    }

    @Test("答えられない書き方を含むなら、モデルの選択があっても答えない")
    func unsupportedBlocksModel() {
        let choice = QuestionChoice(period: .thisYear, metric: .categoryExpense, category: .food)

        #expect(Self.reading("去年の食費は?").resolved(with: choice) == nil)
    }
}
