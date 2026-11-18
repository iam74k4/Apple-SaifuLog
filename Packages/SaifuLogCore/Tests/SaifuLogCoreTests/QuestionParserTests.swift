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

    @Test("年の初めからの言い回しは今年として読む", arguments: [
        "年初から外食いくら?",
        "年始からの食費は?",
        "年明けから外食いくら?",
        "年頭からの支出",
        "年初め以降の支出",
        "年明け以降カフェいくら?",
        "年明けてから外食いくら?",
        "年が明けてからいくら使った?",
        "今年初めからカフェいくら?",
        "今年頭から外食いくら?",
        "今年の年初から外食いくら?",
        "年の初めから外食いくら?",
        "今年の初めからカフェいくら?",
        "年の始め以降の支出",
    ])
    func sinceYearStart(text: String) {
        #expect(Self.question(text)?.period == .thisYear, "\(text)")
    }

    /// 聞かれたのは年の初めからなので、黙って今月として答えない（辞書に無い語として期間を読み落とすと、今月の数字になる）。
    @Test("「年初から外食いくら?」は今年の食費で答える")
    func sinceYearStartQuestion() {
        #expect(Self.question("年初から外食いくら?") == LedgerQuestion(period: .thisYear, metric: .categoryExpense, category: .food))
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
        // 年末と、「から」の付かない年の初めの語は、年の初めの数日のこと（今年とは読めない）。
        "年末の支出",
        "年末から外食いくら?",
        "年始の食費は?",
        "年初の外食いくら?",
        "年明けの支出",
        "今年初めの外食いくら?",
        "年の初めの支出",
        "今年の初めの外食いくら?",
        "年が明けたら外食いくら?",
        "年末年始から外食いくら?",
        // 「年」の前に漢字が付いた言い回しは、別の年のこと。
        "去年初めから外食いくら?",
        "昨年頭からの支出",
        "毎年初めからの支出",
        "毎年の初めからの支出",
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
        // 「年が変わってから」「外で食べた」は辞書に無い言い回し。
        let reading = Self.reading("年が変わってから外で食べたのは?")
        let choice = QuestionChoice(period: .thisYear, metric: .categoryExpense, category: .food)

        #expect(reading.question == nil)
        #expect(reading.resolved(with: choice) == LedgerQuestion(period: .thisYear, metric: .categoryExpense, category: .food))
    }

    /// 辞書で読める期間なので、AI が使えるかどうかで答える期間を変えない（辞書の経路は今年、AI の経路はモデルの選択、とならない）。
    @Test("「年初から」は文から今年と読み、モデルがほかの期間を選んでも辞書の経路と同じ質問にする", arguments: QuestionChoice.Period.allCases)
    func sinceYearStartWinsOverModel(modelPeriod: QuestionChoice.Period) {
        let reading = Self.reading("年初から外食いくら?")
        let choice = QuestionChoice(period: modelPeriod, metric: .categoryExpense, category: .food)

        #expect(reading.period == .thisYear)
        #expect(!reading.hasUnsupportedPart)
        #expect(reading.resolved(with: choice) == reading.question)
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

    /// 2026-11-15 に本物のモデルで試したとき、「今月いくら使った?」に食費を選び、支出の合計ではなく食費の額を答えた。
    @Test("辞書で読んだ語のほかに語が残らない文では、モデルの選んだカテゴリと期間を使わない", arguments: QuestionChoice.Period.allCases)
    func modelCannotAddCategoryOrPeriodToReadText(modelPeriod: QuestionChoice.Period) {
        let choice = QuestionChoice(period: modelPeriod, metric: .categoryExpense, category: .food)

        #expect(Self.reading("今月いくら使った?").resolved(with: choice) == LedgerQuestion(period: .thisMonth, metric: .expenseTotal))
        #expect(Self.reading("いくら使った?").resolved(with: choice) == LedgerQuestion(period: .thisMonth, metric: .expenseTotal))
        #expect(Self.reading("今月の記録は何件?").resolved(with: QuestionChoice(period: modelPeriod, metric: .entryCount, category: .food))
            == LedgerQuestion(period: .thisMonth, metric: .entryCount))
        // カテゴリの語は読んだ語として数える（ひらがなで書いても）。期間はモデルの選択を使わず今月。
        #expect(Self.reading("らんちいくら?").resolved(with: QuestionChoice(period: modelPeriod, metric: .expenseTotal))
            == LedgerQuestion(period: .thisMonth, metric: .categoryExpense, category: .food))
    }

    @Test("辞書で読んだ語・質問の決まり文句のほかに漢字・カタカナ・英字が残るかを見る", arguments: [
        ("今月いくら使った?", false), ("先月いちばん使ったカテゴリは?", false), ("今月の記録は何件?", false),
        ("予算あとどれくらい残ってる?", false), ("先月の食費は?", false), ("今月カフェいくら?", false), ("らんちいくら?", false),
        ("年が変わってから外で食べたのは?", true), ("今月ミモザ堂でいくら使った?", true), ("最近いくら使った?", true),
        ("今月 mimoza いくら?", true),
        // 辞書で読めるカテゴリの語（店やサービスの名前も）は、読んだ語として数える。
        ("今月ユニクロでいくら使った?", false),
    ])
    func unreadWords(text: String, hasUnreadWords: Bool) {
        #expect(Self.reading(text).hasUnreadWords == hasUnreadWords, "\(text)")
    }

    @Test("辞書に無い語が残る文では、モデルの選んだカテゴリを使う")
    func modelReadsUnknownWords() {
        let choice = QuestionChoice(period: .thisMonth, metric: .categoryExpense, category: .clothing)

        #expect(Self.reading("今月ミモザ堂でいくら使った?").resolved(with: choice)
            == LedgerQuestion(period: .thisMonth, metric: .categoryExpense, category: .clothing))
    }

    /// 2026-11-15 に本物のモデルで試したとき、「先月の食費は?」「今週の交通費は?」に内訳を選び、聞かれたカテゴリを落とした。
    @Test("文にカテゴリがあれば、モデルがカテゴリを使わない指標を選んでも、そのカテゴリの支出で答える", arguments: [
        QuestionMetric.expenseByCategory, .topCategory, .remainingBudget, .dailyAllowance, .incomeTotal, .balance, .expenseTotal,
        .categoryExpense,
    ])
    func categoryInTextKeepsCategory(modelMetric: QuestionMetric) {
        #expect(Self.reading("先月の食費は?").resolved(with: QuestionChoice(period: .lastMonth, metric: modelMetric))
            == LedgerQuestion(period: .lastMonth, metric: .categoryExpense, category: .food))
        #expect(Self.reading("今週の交通費は?").resolved(with: QuestionChoice(period: .thisWeek, metric: modelMetric))
            == LedgerQuestion(period: .thisWeek, metric: .categoryExpense, category: .transport))
    }

    /// 2026-11-15 に本物のモデルで試したとき、「月末まで毎日いくらまで使える?」に今年を選んだ。
    @Test("予算の指標は、文に期間が無ければ、モデルがほかの期間を選んでも今月", arguments: QuestionChoice.Period.allCases)
    func budgetMetricUsesThisMonth(modelPeriod: QuestionChoice.Period) {
        #expect(Self.reading("月末まで毎日いくらまで使える?").resolved(with: QuestionChoice(period: modelPeriod, metric: .dailyAllowance))
            == LedgerQuestion(period: .thisMonth, metric: .dailyAllowance))
        #expect(Self.reading("予算あとどれくらい残ってる?").resolved(with: QuestionChoice(period: modelPeriod, metric: .remainingBudget))
            == LedgerQuestion(period: .thisMonth, metric: .remainingBudget))
    }

    @Test("答えられない書き方を含むなら、モデルの選択があっても答えない")
    func unsupportedBlocksModel() {
        let choice = QuestionChoice(period: .thisYear, metric: .categoryExpense, category: .food)

        #expect(Self.reading("去年の食費は?").resolved(with: choice) == nil)
        #expect(Self.reading("年明けの外食いくら?").resolved(with: choice) == nil)
    }

    // MARK: - 品目や店の名前

    /// 品目（メモ）にだけ名前を持つ記録の写し。
    static func ledger(_ memos: [String]) -> QuestionLedger {
        QuestionLedger(records: memos.map { LedgerRecordValue(amount: 100, spentAt: Fixture.now, searchText: $0) })
    }

    @Test("カテゴリを品目や店の名前で読んだら、その名前（書かれたとおり）も読む。カテゴリの名前なら読まない", arguments: [
        ("今月スタバに何回行った?", "スタバ"), ("先月のすたばは?", "すたば"), ("今週の電車代", "電車"), ("今月ランチいくら?", "ランチ"),
        ("今月ユニクロでいくら使った?", "ユニクロ"), ("今月 Starbucks いくら?", "Starbucks"),
        ("今月カフェいくら?", nil), ("先月の食費は?", nil), ("今週の交通費は?", nil), ("今月の光熱費は?", nil), ("今月の美容は?", nil),
        ("今月その他いくら?", nil), ("今月いくら使った?", nil),
    ] as [(String, String?)])
    func itemWord(text: String, itemWord: String?) {
        #expect(Self.reading(text).itemWord == itemWord, "\(text)")
    }

    @Test("品目の名前の記録があれば、その名前の記録だけを数える質問にする。名前の記録が無ければカテゴリのまま")
    func itemWordNarrowsWhenRecorded() {
        let reading = Self.reading("今月スタバに何回行った?")

        #expect(reading.question(in: Self.ledger(["スタバ ラテ"]))
            == LedgerQuestion(period: .thisMonth, metric: .entryCount, keyword: "スタバ"))
        #expect(reading.question(in: Self.ledger(["ドトール"])) == LedgerQuestion(period: .thisMonth, metric: .entryCount, category: .cafe))
        // ひらがなで書いても、カタカナの品目に当たる。
        #expect(Self.reading("今月すたばいくら?").question(in: Self.ledger(["スタバ"]))
            == LedgerQuestion(period: .thisMonth, metric: .expenseTotal, keyword: "すたば"))
        // カテゴリの名前で聞かれたら、名前の記録があってもカテゴリで答える。
        #expect(Self.reading("今月カフェいくら?").question(in: Self.ledger(["カフェ"]))
            == LedgerQuestion(period: .thisMonth, metric: .categoryExpense, category: .cafe))
        // AI の経路でも、文から読んだ名前をモデルの名前より優先する。
        #expect(reading.resolved(with: QuestionChoice(period: .thisMonth, metric: .entryCount, keyword: "行った"), in: Self.ledger(["スタバ"]))
            == LedgerQuestion(period: .thisMonth, metric: .entryCount, keyword: "スタバ"))
    }

    @Test("辞書に無い名前は、モデルが抜き出した名前を、残りの文に書かれ、その名前の記録があるときだけ使う")
    func modelKeyword() {
        let reading = Self.reading("今月メルカリでいくら使った?")
        let ledger = Self.ledger(["メルカリ 古着"])
        func resolved(_ keyword: String?) -> LedgerQuestion? {
            reading.resolved(with: QuestionChoice(period: .thisMonth, metric: .expenseTotal, category: .other, keyword: keyword), in: ledger)
        }
        let narrowed = LedgerQuestion(period: .thisMonth, metric: .expenseTotal, keyword: "メルカリ")
        let byModelCategory = LedgerQuestion(period: .thisMonth, metric: .categoryExpense, category: .other)

        #expect(resolved("メルカリ") == narrowed)
        // 文に書かれたとおりの字にそろえ、後ろの助詞と前後の記号を除く。
        #expect(resolved("めるかり") == narrowed)
        #expect(resolved("メルカリで") == narrowed)
        #expect(resolved(" メルカリ。") == narrowed)
        // 文に無い名前・読んだ語を含む名前・短すぎる名前は使わない（モデルのカテゴリのまま）。
        #expect(resolved("Amazon") == byModelCategory)
        #expect(resolved("今月のメルカリ") == byModelCategory)
        #expect(resolved("メ") == byModelCategory)
        #expect(resolved(nil) == byModelCategory)
        // 名前の記録が無ければ使わない。
        #expect(reading.resolved(with: QuestionChoice(period: .thisMonth, metric: .expenseTotal, keyword: "メルカリ"), in: Self.ledger(["Amazon"]))
            == LedgerQuestion(period: .thisMonth, metric: .expenseTotal))
    }

    @Test("文がすべて辞書で読めるか、カテゴリの名前があれば、モデルの抜き出した名前を使わない")
    func modelKeywordNeedsUnreadWords() {
        let ledger = Self.ledger(["いくら丼", "食費"])

        #expect(Self.reading("今月いくら使った?").resolved(with: QuestionChoice(period: .thisMonth, metric: .expenseTotal, keyword: "いくら"), in: ledger)
            == LedgerQuestion(period: .thisMonth, metric: .expenseTotal))
        #expect(Self.reading("先月の食費は?").resolved(with: QuestionChoice(period: .lastMonth, metric: .expenseTotal, keyword: "食費"), in: ledger)
            == LedgerQuestion(period: .lastMonth, metric: .categoryExpense, category: .food))
    }

    @Test("AI の名前の受け付け: 後ろの「代」「費」を除き、ひらがなの名前の「と」は残し、数字と長すぎる名前は使わない")
    func acceptedKeyword() {
        #expect(Self.reading("今月ジム代いくら?").acceptedKeyword("ジム代") == "ジム")
        #expect(Self.reading("今年のふるさと納税はいくら?").acceptedKeyword("ふるさと納税") == "ふるさと納税")
        #expect(Self.reading("今年のふるさと納税はいくら?").acceptedKeyword("ふるさと納税は") == "ふるさと納税")
        #expect(Self.reading("今月 Amazon でいくら?").acceptedKeyword("amazon") == "Amazon")
        #expect(Self.reading("今月メルカリでいくら使った?").acceptedKeyword("メルカリ2") == nil)
        #expect(Self.reading("今月\(String(repeating: "ア", count: 21))いくら?").acceptedKeyword(String(repeating: "ア", count: 21)) == nil)
    }
}
