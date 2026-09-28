import Foundation

/// キーワード辞書による解析。Apple Intelligence が使えない端末や、AI の生成が失敗したときに使う。
///
/// AI が無くても記録できるアプリにするための下支え。自然な文章の理解は AI に任せ、
/// ここでは「ランチ 850」の形を確実に読むことを優先する。
///
/// - 金額: 区間の中の最後の数字（全角数字・桁区切り・「円」「¥」・「25万」「1万2千500」「5百」・「500×3」に対応）。
///   「-500」のようにマイナスを付けた額は返金として収入にする（正の金額の後ろに置いた値引き「850(-100引き)」は除く）
/// - 日付: 「今日」「昨日」「一昨日」「3日前」「9/26」「9-26」「9月26日」「26日」「2026/9/26」「2025年9月26日」。
///   年を省いた月日は、60 日先までは未来の日付として読む（`DateExpression`）
/// - 割り勘: 「割り勘」の語と「N人」の両方があれば 1 人分に割る（割った内容はメモに残す）。
///   「1人あたり3000」のように 1 人分として書いた額は割らない（メモに「1人分」と書き足す）
/// - 収入: 「給料」「ボーナス」などの語があれば収入（「給料日なので」「収入印紙」「年金保険」のような支出の言い回しは除く）
/// - 複数件: 金額の後ろの「と」「、」などで区切られ、それぞれに金額があれば分けて記録する。
///   日付と割り勘は件ごとに割り当てる（`EntryScan.segments()`）
public struct RuleBasedParser: EntryParsing {
    public var calendar: Calendar
    private let now: @Sendable () -> Date

    /// - Parameter now: 「昨日」「9/26」を解釈する基準の日時。テストで日付を固定するために差し替えられる。
    public init(calendar: Calendar = .current, now: @escaping @Sendable () -> Date = { Date() }) {
        self.calendar = calendar
        self.now = now
    }

    public func parse(_ text: String) async throws -> [ParsedEntry] {
        entries(from: text)
    }

    /// 同期版。解析は端末内の文字列処理だけで終わるので、待つ必要はない。
    public func entries(from text: String) -> [ParsedEntry] {
        EntryInput(text, now: now(), calendar: calendar).ruleBasedEntries
    }

    /// 収入とみなす語。「お小遣い」「仕送り」は払う側でも使うので、単独では入れない（`IncomeRule.giftWords`）。
    public static let incomeKeywords = [
        "給料", "給与", "月給", "賞与", "ボーナス", "収入", "入金", "報酬", "売上", "副業", "年金", "配当",
        "利息", "還付", "バイト代", "アルバイト代", "時給", "日給", "手取り",
    ]

    /// 収入の語を含むが、支出の言い回しになる語。ここに当たった部分は収入の判定から外し、
    /// 支出としてカテゴリを推定する（「給料日なので焼肉 5000」は食費の支出）。
    /// 収入の語は部分一致で見るので、長い語で打ち消さないと、よく使う言い回しの支出が
    /// 収入（+¥）になって今月の収入に足されてしまうため（`EntryCategory.other` と同じ考え方）。
    ///
    /// 「ボーナスで」は、後ろに「た」「ました」が続く「ボーナスでた」では打ち消さない。「給料日」は、後ろに
    /// 「入った」などの受け取った語が続くときと、ほかに語が無いとき（「給料日 25万」）は打ち消さない（`IncomeRule`）。
    public static let incomeExclusions = [
        "給料日", "ボーナスで", "ボーナス払い", "収入印紙", "国民年金", "年金保険料",
    ]
}

/// 収入かどうかの判定。ルールベースの解析と、AI が返した「収入」の検査（`ExtractedEntry`）の両方で使う。
enum IncomeRule {
    /// 文が収入の記録か。
    ///
    /// 収入の語があっても、その後ろに支出を表す語が続けば収入にしない（「入金手数料」「収入保障保険」
    /// 「個人年金保険」「副業の経費」「給料から天引き」）。誤って収入にすると、残高が金額の 2 倍ずれるため。
    /// 前にある支出の語は見ない（「所得税の還付」「保険金の入金」は収入）。
    static func isIncome(_ text: String) -> Bool {
        let haystack = masked(text)
        for keyword in RuleBasedParser.incomeKeywords.map(KeywordMatcher.fold) {
            var searchStart = haystack.startIndex
            while let range = haystack.range(of: keyword, range: searchStart..<haystack.endIndex) {
                let rest = haystack[range.upperBound...]
                if !expenseWords.contains(where: { rest.contains($0) }) { return true }
                searchStart = range.upperBound
            }
        }
        // 「お年玉もらった」「お小遣いもらった」。もらう・あげるの両方に使う語は、もらった語と組のときだけ収入。
        return giftWords.contains { haystack.contains($0) } && receiptWords.contains { haystack.contains($0) }
    }

    /// 文に、収入ではないとはっきり分かる手がかりがあるか。AI が「収入」と返したときの検査に使う。
    ///
    /// ルールベースで収入と読めないうえに、打ち消しの語（「収入印紙」）か、支出の語が後ろに続く収入の語
    /// （「入金手数料」）があるときだけ真。収入の語が無いだけでは偽にする。AI が読めていた
    /// 「お小遣いもらった」のような収入まで捨てないため。
    static func contradictsIncome(_ text: String) -> Bool {
        guard !isIncome(text) else { return false }
        let folded = KeywordMatcher.fold(text)
        let haystack = masked(text)
        if haystack != folded { return true }
        return RuleBasedParser.incomeKeywords.map(KeywordMatcher.fold).contains { haystack.contains($0) }
    }

    /// 打ち消しの語を、使われない文字で埋めた文（ひらがなはカタカナ、英字は小文字にそろえる）。
    private static func masked(_ text: String) -> String {
        var chars = Array(KeywordMatcher.fold(text))
        for exclusion in RuleBasedParser.incomeExclusions {
            let phrase = Array(KeywordMatcher.fold(exclusion))
            let exceptions = (exclusionExceptions[exclusion] ?? []).map { Array(KeywordMatcher.fold($0)) }
            var i = 0
            while i + phrase.count <= chars.count {
                guard Array(chars[i..<(i + phrase.count)]) == phrase else {
                    i += 1
                    continue
                }
                let rest = chars[(i + phrase.count)...]
                if exceptions.contains(where: { rest.starts(with: $0) }) || means(income: exclusion, in: chars, at: i) {
                    i += phrase.count
                    continue
                }
                // 空白ではなく使われない文字で埋める。前後がつながって新しい語ができないようにするため。
                for j in i..<(i + phrase.count) { chars[j] = "\u{0}" }
                i += phrase.count
            }
        }
        return String(chars)
    }

    /// 打ち消しの語の後ろにこれが続けば、打ち消さない（「ボーナスでた」「ボーナスでました」は収入）。
    private static let exclusionExceptions: [String: [String]] = [
        "ボーナスで": ["た", "ました"],
    ]

    /// `chars[start...]` の打ち消しの語 `exclusion` が、この文では収入の記録を指しているか。
    ///
    /// 「給料日」は、「給料日なので焼肉」のような支出の言い回しにも、給料日に受け取った給料の記録にも使う。
    /// 後ろに受け取った語が続く（「給料日 入った 25万」）か、ほかに語が無い（「給料日 25万」）ときは、給料の記録とみなす。
    /// 打ち消したままだと、ルールベースでは支出になり、AI が収入と読んでも `contradictsIncome` で支出に戻されて、
    /// どちらの経路でも給料を収入として記録できないため。
    private static func means(income exclusion: String, in chars: [Character], at start: Int) -> Bool {
        guard let receipts = standaloneIncomeExclusions[exclusion] else { return false }
        let end = start + KeywordMatcher.fold(exclusion).count
        let rest = String(chars[end...])
        if receipts.map(KeywordMatcher.fold).contains(where: { rest.contains($0) }) { return true }
        // 金額の表記（数字・位・円・記号）と空白しか残らなければ、ほかに語が無い。
        return (chars[..<start] + chars[end...]).allSatisfy { $0.isASCIIDigit || $0.isWhitespace || amountNotation.contains($0) }
    }

    /// 支出の言い回しにも収入の記録にも使う打ち消しの語と、収入の記録とみなす手がかり（後ろに続く、受け取った語）。
    private static let standaloneIncomeExclusions: [String: [String]] = [
        "給料日": ["入った", "入りました", "入金", "振込", "振り込", "出た", "でた", "もらった"],
    ]
    /// 金額の表記に使う、数字以外の文字。
    private static let amountNotation: Set<Character> = [
        "円", "¥", "\\", ",", ".", "十", "百", "千", "万", "億", "-", "+", "、", "。", "!",
    ]

    /// 収入の語の後ろにあれば、その収入の語は支出の言い回しの一部とみなす語。
    /// 「税」だけにしないのは、「配当 税引後」のような収入の書き方に当たるため。
    private static let expenseWords = [
        "手数料", "保険", "経費", "天引", "払い", "払った", "支払", "返済", "再投資", "引き落とし", "引落",
        "住民税", "所得税", "税金",
    ].map(KeywordMatcher.fold)

    /// もらう・あげるの両方に使う語。
    private static let giftWords = ["お年玉", "お小遣い", "おこづかい", "小遣い", "仕送り", "お祝い"]
        .map(KeywordMatcher.fold)
    private static let receiptWords = ["もらった", "もらい", "もらう", "貰", "いただいた", "頂いた", "受け取"]
        .map(KeywordMatcher.fold)
}
