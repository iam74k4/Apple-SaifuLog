import Foundation

/// 質問の文から、コードが読めたもの（期間・指標・カテゴリ）。
///
/// AI が使えないときは、これだけで質問を作る（`question`）。AI が使えるときは、AI のツールの選択（`QuestionChoice`）と
/// 合わせる（`resolved(with:)`）。どちらも、コードが文から読めたものを優先する。期間の言葉（「今月」「直近7日」）や
/// カテゴリの名前は辞書で確実に読めるので、モデルの選択で上書きしない（日付の計算をコードで決めるのと同じ考え方）。
public struct QuestionReading: Hashable, Sendable {
    /// 文に書かれた期間。書かれていなければ nil（今月として答える）。
    public var period: QuestionPeriod?
    /// 文に書かれた、はっきり指標を表す語（「残り」「収入」「何件」など）から読んだ指標。
    public var metric: QuestionMetric?
    /// 文に書かれたカテゴリ（キーワードか表示名）。
    public var category: EntryCategory?
    /// 「いくら」「合計」のような、金額を聞く語があるか（指標は決めない。AI が使えないときは支出の合計として答える）。
    public var asksAmount: Bool
    /// 答えられない書き方（対応していない期間・数字で名前を付けた月や年・日付、2 つ以上の期間、金額、1 日あたりに使った額）を
    /// 含むか。含むなら、AI にも答えさせない（「去年」を今年と読むような、聞かれていない期間の答えを出さないため）。
    public var hasUnsupportedPart: Bool

    public init(
        period: QuestionPeriod? = nil,
        metric: QuestionMetric? = nil,
        category: EntryCategory? = nil,
        asksAmount: Bool = false,
        hasUnsupportedPart: Bool = false
    ) {
        self.period = period
        self.metric = metric
        self.category = category
        self.asksAmount = asksAmount
        self.hasUnsupportedPart = hasUnsupportedPart
    }

    /// コードだけで作った質問（AI が使えないとき）。答えられない書き方を含むか、何も読めなければ nil（読めない質問）。
    ///
    /// 期間が無ければ今月、指標が無ければ（カテゴリがあればそのカテゴリの）支出の合計として答える。
    public var question: LedgerQuestion? {
        guard !hasUnsupportedPart, period != nil || metric != nil || category != nil || asksAmount else { return nil }
        return LedgerQuestion(period: period ?? .thisMonth, metric: metric ?? .expenseTotal, category: category)
    }

    /// AI のツールの選択と合わせた質問。答えられない書き方を含むなら nil。
    ///
    /// 期間・指標・カテゴリのどれも、文から読めたものを優先し、読めなかったものだけモデルの選択を使う（モデルが言い換えを
    /// 読めるのは、辞書に無い言い回しのとき）。直近 N 日の N は文から読むので、モデルが直近を選んでも文に日数が無ければ、
    /// 今月として答える（モデルには自由な数を選ばせない）。
    ///
    /// 文に指標の語が無く「いくら」「合計」のような金額を聞く語だけがあるとき、モデルが件数・いちばん多いカテゴリ・内訳を
    /// 選んでも、支出の合計（カテゴリがあればそのカテゴリの支出）にする。金額を聞かれたのに件数を答えたり、内訳を選んで
    /// 聞かれたカテゴリを落としたりしないため（「今月カフェいくら?」の答えを、AI の有無で変えない）。文にカテゴリがあれば、
    /// 予算・収入・収支の選択も同じくカテゴリの支出にする（どれもカテゴリを使わない指標で、文に書かれたカテゴリを落とすため）。
    /// カテゴリの無い文の予算・収入・収支の選択はそのまま使う（「いくら貯まった」「いくらもらった」のような、辞書に無い
    /// 言い回しをモデルが読めることがあるため）。
    public func resolved(with choice: QuestionChoice) -> LedgerQuestion? {
        guard !hasUnsupportedPart else { return nil }
        var modelMetric = choice.metric
        if asksAmount, category != nil || Self.nonAmountMetrics.contains(modelMetric) {
            // カテゴリがあれば、LedgerQuestion がそのカテゴリの支出にそろえる。
            if modelMetric != .categoryExpense { modelMetric = .expenseTotal }
        }
        return LedgerQuestion(
            period: period ?? choice.period.fixedPeriod ?? .thisMonth,
            metric: metric ?? modelMetric,
            category: category ?? choice.category
        )
    }

    /// 金額ではない答えになる指標（金額を聞く語だけの文では、モデルが選んでも使わない）。
    static let nonAmountMetrics: Set<QuestionMetric> = [.entryCount, .topCategory, .expenseByCategory]
}

/// AI のツールで選ばせる質問の形。期間の選択肢は日数を持たない（直近 N 日の N は文からコードが読む）。
public struct QuestionChoice: Hashable, Sendable {
    public enum Period: Hashable, Sendable, CaseIterable {
        case today, yesterday, thisWeek, lastWeek, thisMonth, lastMonth, thisYear
        /// 直近の何日か。日数はモデルに選ばせず、文から読む。
        case recentDays

        /// 日数の要らない期間。直近の何日かは nil。
        var fixedPeriod: QuestionPeriod? {
            switch self {
            case .today: .today
            case .yesterday: .yesterday
            case .thisWeek: .thisWeek
            case .lastWeek: .lastWeek
            case .thisMonth: .thisMonth
            case .lastMonth: .lastMonth
            case .thisYear: .thisYear
            case .recentDays: nil
            }
        }
    }

    public var period: Period
    public var metric: QuestionMetric
    public var category: EntryCategory?

    public init(period: Period, metric: QuestionMetric, category: EntryCategory? = nil) {
        self.period = period
        self.metric = metric
        self.category = category
    }
}

/// キーワード辞書で質問を読む（AI が使えない端末と、AI の生成が失敗したとき）。
///
/// 読める書き方:
/// - 期間: 今日・本日・昨日・今週・先週・今月・先月・今年、「年初から」「年明けから」「年の初めから」のような年の初めから（今年
///   として読む）、「直近7日」「過去30日間」「ここ1週間」「3日間」のような直近 N 日（N は 1〜366 日。週は 7 日として数える）。
///   書かれていなければ今月。
/// - 指標: 1日あたりに使える額（「何日で」「あと何日」、予算の語（「使える」「残り」「予算」「まで」など）と一緒の「1日あたり」
///   「1日で」「毎日」「日割り」。予算の語も使った額を聞く語も無い「1日あたり」「日割り」も）、予算の残り（「残り」「使える」「予算」）、
///   いちばん多いカテゴリ（「一番」「最も」）、カテゴリ別の内訳（「内訳」「カテゴリ別」「何に使った」）、件数（「何件」「何回」）、収支、
///   収入（「収入」「給料」）、支出の合計（「支出」「使った」、または「いくら」「合計」だけ）。
/// - カテゴリ: 記録の読み取りと同じキーワード（「カフェ」「コーヒー」「電車」）と表示名（「食費」「その他」）。
///
/// 読めないもの（読めない質問として、質問の例を出す）: 「去年」「来月」「明日」「一昨日」「週末」「金曜」「半年」「年度」のような
/// 対応していない期間（「年末」と、「から」「以降」の付かない「年始」「年初」「年明け」「年頭」「年の初め」も）、「3月」「2025年」
/// 「令和7年」のような数字で名前を付けた月や年、「9/26」「3日前」のような日付、「今月と先月」のような 2 つ以上の期間、金額を含む
/// 質問、1 日あたりに使った額（平均）を聞く質問（「1日あたりいくら使った」「毎日いくら使ってる」「先月は1日にいくら」）、
/// どの語にも当たらない質問。
public enum QuestionParser {
    /// 質問の例（読めない質問のときに出す）。日本語のまま見せる（解析が日本語の入力を前提にしているため、訳さない）。
    public static let examples = ["今月カフェいくら?", "先月の食費は?", "今月あと何日でいくら使える?", "今週いちばん使ったのは?"]

    /// 質問の文を読む。
    /// - Parameters:
    ///   - now: 日付の言い回し（「9/26」など、答えられない書き方）を見分ける基準の日時。
    ///   - calendar: 同じく日付を見分ける暦。
    ///   - catalog: カテゴリの一覧。作ったカテゴリの名前（「衣服」）も読む（組み込みの語より先に見る。利用者が決めた名前のため）。
    public static func read(
        _ text: String, now: Date, calendar: Calendar, catalog: CategoryCatalog = .builtIn
    ) -> QuestionReading {
        let normalized = TextNormalizer.normalize(text)
        var chars = Array(normalized)
        var reading = QuestionReading()
        var periods: Set<QuestionPeriod> = []

        // 「3月」「2025年」のような、数字で名前を付けた月や年。日付の読み取り（`EntryScan`）は日の無い「3月」を日付と
        // みなさないので、ここで見ないと期間の書かれていない質問として今月の数字を答えてしまう。
        if namesMonthOrYear(chars) { reading.hasUnsupportedPart = true }

        // 直近 N 日。読んだところは空白で埋め、後で日付や金額として読まないようにする。
        for match in recentDayPhrases(in: chars) {
            if QuestionPeriod.recentDaysRange.contains(match.days) {
                periods.insert(.recentDays(match.days))
            } else {
                reading.hasUnsupportedPart = true
            }
            blank(&chars, match.range)
        }
        // 「1日あたり」の「1日」を、日付（その月の 1 日）として読まないように先に読む。
        // 「1日で」「毎日」は使った額を聞く文（「今日1日でいくら使った」）にも書くので、予算の語が無ければ 1 日あたりに
        // 使える額にしない（聞かれていない予算の数字を、別の期間で答えないため）。
        let asksAllowance = allowanceWords.contains { normalized.contains($0) }
        let asksSpending = spendingWords.contains { normalized.contains($0) }
        for range in ranges(of: dailyAllowancePhrases, in: chars) {
            let phrase = String(chars[range])
            if asksAllowance || allowanceOnlyPhrases.contains(phrase) {
                reading.metric = .dailyAllowance
            } else if oneDayPhrases.contains(phrase) {
                // 「今日1日で」「昨日1日で」は、その日まるごとのこと（期間はその日のまま）。それ以外は「今月1日に」の日付か、
                // 「1日にいくら使ってた」の平均で、どちらも答えられない。
                if !follows(singleDayPeriodWords, before: range.lowerBound, in: chars) {
                    reading.hasUnsupportedPart = true
                }
            } else if everyDayPhrases.contains(phrase) || asksSpending {
                // 「毎日いくら使ってる」「1日あたりいくら使った」は 1 日あたりに使った額（平均）で、答えられない。
                // 予算の語も使った額を聞く語も無い「毎日」も、言い添え（「毎日カフェ行ってるけど」）か平均か決められないので答えない。
                reading.hasUnsupportedPart = true
            } else {
                // 予算の語も使った額を聞く語も無い「1日あたりいくら?」「日割りでいくら?」は、1 日あたりに使える額として読む。
                reading.metric = .dailyAllowance
            }
            blank(&chars, range)
        }
        // 「年初から」「年明けから」は、年の初めから今日まで。今年として読む（AI の経路もこの読みを優先するので、辞書と AI で
        // 答える期間がそろう）。「年始」「年明け」だけ（「年末年始」「年明けの旅行」）は対応していない期間なので、その語を
        // 読む前に、年の初めからの言い回しだけを取り除いておく。
        for range in sinceYearStartRanges(in: chars) {
            periods.insert(.thisYear)
            blank(&chars, range)
        }
        let unsupported = ranges(of: unsupportedPeriodWords, in: chars)
        if !unsupported.isEmpty { reading.hasUnsupportedPart = true }
        for range in unsupported { blank(&chars, range) }
        for (word, period) in periodWords {
            let found = ranges(of: [word], in: chars)
            if !found.isEmpty { periods.insert(period) }
            for range in found { blank(&chars, range) }
        }
        if periods.count > 1 { reading.hasUnsupportedPart = true }
        reading.period = periods.count == 1 ? periods.first : nil

        let rest = String(chars)
        // 残りに日付（「9/26」「3日前」「26日」）や金額があれば、答えられない書き方。
        let scan = EntryScan(rest, now: now, calendar: calendar)
        if !scan.dates.isEmpty || !scan.amounts.isEmpty {
            reading.hasUnsupportedPart = true
        }

        if reading.metric == nil {
            reading.metric = metricWords.first { entry in
                entry.words.contains { rest.contains($0) }
            }?.metric
        }
        reading.asksAmount = amountWords.contains { rest.contains($0) }
        reading.category = catalog.customCategory(namedIn: rest) ?? EntryCategory.matched(in: rest)
        return reading
    }

    /// 読めた質問。読めなければ nil。
    public static func question(
        from text: String, now: Date, calendar: Calendar, catalog: CategoryCatalog = .builtIn
    ) -> LedgerQuestion? {
        read(text, now: now, calendar: calendar, catalog: catalog).question
    }

    // MARK: - 辞書

    /// 期間の語。
    static let periodWords: [(String, QuestionPeriod)] = [
        ("今日", .today), ("本日", .today), ("昨日", .yesterday), ("きのう", .yesterday),
        ("今週", .thisWeek), ("先週", .lastWeek), ("今月", .thisMonth), ("先月", .lastMonth),
        ("今年", .thisYear), ("ことし", .thisYear),
    ]

    /// 年の初めから今日までを表す言い回し。今年として読む。
    ///
    /// 今年（1 月 1 日から 12 月 31 日）と違うのは、先の日付で書いた記録（払う予定の家賃など）も数えることだけで、回答カードには
    /// 今年の日付の範囲を出す。「年初」「年始」「年明け」「年頭」「年の初め」だけは読めない語（`unsupportedPeriodWords`）なので、
    /// 「年初めから」「年明けてから」のような言い回しもここに並べる（並べないと、「今年初めから」まで読めない質問になる）。
    static let sinceYearStartPhrases = [
        "年初から", "年初めから", "年始から", "年始めから", "年明けから", "年頭から", "年の初めから", "年の始めから",
        "年初以降", "年初め以降", "年始以降", "年始め以降", "年明け以降", "年頭以降", "年の初め以降", "年の始め以降",
        "年明けてから", "年が明けてから",
    ]

    /// 対応していない期間の語。含むときは読めない質問にする（黙って今月として答えると、聞かれていない期間の数字になるため）。
    /// 「一昨日」は「昨日」を含むので、ここで先に読んで昨日と数えないようにしている。
    /// 「年度」は「今年度」を今年（暦の年）と読まないため。元号は「令和7年」の年を、数字の年と同じく読めないものにするため。
    /// 「年初」「年始」「年明け」「年が明け」「年頭」「年の初め」だけ（「年末年始」「年明けの旅行」「今年の初めの外食」）は年の
    /// 初めの数日のことで、今年とは読めない（「から」「以降」が付けば、年の初めからの言い回しとして先に読んである）。
    static let unsupportedPeriodWords = [
        "一昨年", "おととし", "一昨日", "おととい", "おとつい", "去年", "昨年", "来年", "来月", "来週", "先々月", "先々週",
        "明日", "あした", "明後日", "あさって", "今朝", "今夜", "今晩", "昨夜", "週末", "年末", "年始", "年初", "年明け", "年が明け",
        "年頭", "年の初め", "年の始め", "上旬", "中旬", "下旬", "上半期", "下半期", "曜日", "月曜", "火曜", "水曜", "木曜", "金曜",
        "土曜", "日曜", "か月", "ヶ月", "カ月", "ケ月", "半年", "年度", "令和", "平成", "昭和",
    ]

    /// 予算の語が無くても、1 日あたりに使える額を聞いているとみなす言い回し（予算の残りの日数を前提にした言い方）。
    static let allowanceOnlyPhrases = ["何日で", "あと何日"]
    /// 「1日で」「1日に」。予算の語があれば 1 日あたりに使える額、「今日1日で」ならその日の期間、ほかは読めない。
    static let oneDayPhrases = ["1日に", "一日に", "1日で", "一日で"]
    /// 「毎日」。予算の語があれば 1 日あたりに使える額、ほかは読めない。
    static let everyDayPhrases = ["毎日"]
    /// 「1日あたり」「日割り」。予算の語か、どちらの語も無ければ 1 日あたりに使える額、使った額を聞く語があれば読めない。
    static let perDayPhrases = ["1日あたり", "1日当たり", "一日あたり", "一日当たり", "1日いくら", "一日いくら", "日割り"]

    /// 1 日あたりの額を聞く言い回しのすべて。記録か質問かの見分け（`InputIntentClassifier`）も、この「1日」を金額として数えない。
    static let dailyAllowancePhrases = perDayPhrases + oneDayPhrases + everyDayPhrases + allowanceOnlyPhrases

    /// 1 日あたりの言い回しを、使える額（予算）の意味に決める語。
    static let allowanceWords = [
        "使える", "つかえる", "使っていい", "使ってもいい", "使っても良い", "使って良い", "予算", "残り", "のこり", "残って",
        "あと", "まで",
    ]

    /// 1 日あたりの言い回しと一緒なら、使った額（平均）を聞いているとみなす語。
    static let spendingWords = ["使っ", "つかっ", "使い", "使う", "支出", "出費", "払っ"]

    /// 「今日1日で」の「今日」のような、1 日だけの期間の語。
    static let singleDayPeriodWords = ["今日", "本日", "昨日", "きのう"]

    /// はっきり指標を表す語。上から順に見て、最初に当たったものを採る（「あと何日でいくら使える」は 1 日あたり、
    /// 「何に一番使った」はいちばん多いカテゴリ）。
    static let metricWords: [(metric: QuestionMetric, words: [String])] = [
        (.remainingBudget, ["残り", "のこり", "残って", "のこって", "あといくら", "使える", "つかえる", "予算"]),
        (.topCategory, ["一番", "いちばん", "最も", "もっとも"]),
        (.expenseByCategory, ["内訳", "カテゴリ別", "カテゴリごと", "カテゴリー別", "カテゴリーごと", "何に使", "なにに使", "何に", "なにに"]),
        (.entryCount, ["何件", "なんけん", "件数", "何回", "なんかい", "回数", "何度"]),
        (.balance, ["収支", "差し引き", "黒字", "赤字"]),
        (.incomeTotal, ["収入", "給料", "給与", "入金", "稼い", "かせい", "ボーナス", "賞与", "もらった"]),
        (.expenseTotal, ["支出", "出費", "使った", "つかった", "使いすぎ", "払った"]),
    ]

    /// 金額を聞く語（指標は決めない）。
    static let amountWords = [
        "いくら", "幾ら", "合計", "総額", "トータル", "どれくらい", "どれぐらい", "どのくらい", "どのぐらい", "何円", "なんえん", "なんぼ",
    ]

    // MARK: - 読み取りの部品

    /// 「直近7日」「過去30日間」「ここ1週間」「この2週間」「3日間」「一週間」。
    ///
    /// 後ろに「前」「後」が続くもの（「2週間前」「3日後」）は、直近の日数ではなく、ある日を指す言い回しなので、日数を 0
    /// （範囲の外。読めない質問）として返す。
    static func recentDayPhrases(in chars: [Character]) -> [(days: Int, range: Range<Int>)] {
        var result: [(days: Int, range: Range<Int>)] = []
        var i = 0
        while i < chars.count {
            if let match = recentDayPhrase(in: chars, at: i) {
                result.append(match)
                i = match.range.upperBound
            } else {
                i += 1
            }
        }
        return result
    }

    private static func recentDayPhrase(in chars: [Character], at start: Int) -> (days: Int, range: Range<Int>)? {
        let prefixes = ["直近", "過去", "最近", "ここ", "この"]
        var cursor = start
        if let prefix = prefixes.first(where: { matches($0, in: chars, at: start) }) {
            cursor += prefix.count
            while cursor < chars.count, chars[cursor] == " " { cursor += 1 }
        } else if start > 0, chars[start - 1].isASCIIDigit {
            // ほかの数の途中（「12日」の「2日」）は読まない。
            return nil
        }
        let hasPrefix = cursor != start
        // 数（半角の数字か、「一」〜「十」の 1 文字）。
        var numberEnd = cursor
        while numberEnd < chars.count, chars[numberEnd].isASCIIDigit { numberEnd += 1 }
        let number: Int
        if numberEnd > cursor {
            guard numberEnd - cursor <= 4, let value = Int(String(chars[cursor..<numberEnd])) else { return nil }
            number = value
        } else if cursor < chars.count, let value = kanjiDigit(chars[cursor]) {
            number = value
            numberEnd = cursor + 1
        } else {
            return nil
        }
        var end = numberEnd
        while end < chars.count, chars[end] == " " { end += 1 }
        let days: Int
        if matches("週間", in: chars, at: end) {
            days = number * 7
            end += 2
        } else if matches("日", in: chars, at: end) {
            end += 1
            let hasSuffix = matches("間", in: chars, at: end)
            if hasSuffix { end += 1 }
            // 「3日」だけはその月の 3 日（日付）なので、前置きか「間」があるときだけ直近の日数として読む。
            guard hasPrefix || hasSuffix else { return nil }
            days = number
        } else {
            return nil
        }
        if matches("前", in: chars, at: end) || matches("後", in: chars, at: end) {
            return (0, start..<(end + 1))
        }
        return (days, start..<end)
    }

    private static func kanjiDigit(_ char: Character) -> Int? {
        ["一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9, "十": 10][char]
    }

    /// 数字（半角か漢数字）の直後（空白を挟んでもよい）に「月」か「年」がある（「3月」「十二月」「2025年」「この一年」）。
    ///
    /// 「か月」「ヶ月」は間に「か」「ヶ」が入るので当たらない（期間の長さで、別に読めないものにしている）。「今月」「毎年」の
    /// ような語は前が数字でないので当たらない。
    static func namesMonthOrYear(_ chars: [Character]) -> Bool {
        for (index, char) in chars.enumerated() where char == "月" || char == "年" {
            var previous = index - 1
            while previous >= 0, chars[previous] == " " { previous -= 1 }
            guard previous >= 0 else { continue }
            if chars[previous].isASCIIDigit || kanjiDigit(chars[previous]) != nil || chars[previous] == "〇" {
                return true
            }
        }
        return false
    }

    /// 年の初めからの言い回し（「年初から」「年明けから」）の位置。
    ///
    /// 「年」の前に漢字が付いたもの（「去年初めから」「昨年頭から」「毎年初めから」）は、別の年を指すか、ほかの語の一部なので
    /// 読まない（そのまま「去年」「昨年」「年初」として読めない質問になる）。前の漢字が「今」（「今年初めから」「今年頭から」）
    /// なら今年のことなので読む。
    static func sinceYearStartRanges(in chars: [Character]) -> [Range<Int>] {
        ranges(of: sinceYearStartPhrases, in: chars).filter { range in
            guard range.lowerBound > 0 else { return true }
            let previous = chars[range.lowerBound - 1]
            return previous == "今" || !isKanji(previous)
        }
    }

    private static func isKanji(_ char: Character) -> Bool {
        guard let scalar = char.unicodeScalars.first, char.unicodeScalars.count == 1 else { return false }
        return (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value)
    }

    /// `index` の前（空白と「は」「も」を挟んでもよい）が、`words` のどれかで終わるか。
    private static func follows(_ words: [String], before index: Int, in chars: [Character]) -> Bool {
        var end = index
        while end > 0, [" ", "は", "も"].contains(chars[end - 1]) { end -= 1 }
        return words.contains { matches($0, in: chars, at: end - $0.count) }
    }

    private static func matches(_ word: String, in chars: [Character], at index: Int) -> Bool {
        let needle = Array(word)
        guard index >= 0, index + needle.count <= chars.count else { return false }
        return Array(chars[index..<(index + needle.count)]) == needle
    }

    /// 語の現れる位置（重ならないように、左から）。
    static func ranges(of words: [String], in chars: [Character]) -> [Range<Int>] {
        var result: [Range<Int>] = []
        var i = 0
        while i < chars.count {
            if let word = words.first(where: { matches($0, in: chars, at: i) }) {
                result.append(i..<(i + word.count))
                i += word.count
            } else {
                i += 1
            }
        }
        return result
    }

    private static func blank(_ chars: inout [Character], _ range: Range<Int>) {
        for index in range { chars[index] = " " }
    }
}
