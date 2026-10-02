import Foundation

/// レシートの 1 行から日付と時刻を読む。
///
/// ひとこと入力の日付の読み取り（`EntryScan`）は「昨日」「26日」のような話し言葉を相手にするが、レシートの日付は
/// 年から書いた決まった形（「2026年09月27日(日) 18:32」「2026/09/27」「R8.9.27」「26-09-27」）なので、ここで形を決めて読む。
/// 日付として成り立つかと何日前かは `DateExpression` で確かめる（暦はグレゴリオ暦。和暦の設定でも「2026」は西暦）。
enum ReceiptDateReader {
    /// 行の中の日付。先の日付（読み違い）や、成り立たない日付は読まない。
    ///
    /// - Parameter text: 表記ゆれをそろえた行（半角の数字）。
    static func date(in text: String, now: Date, calendar: Calendar) -> ReceiptDate? {
        guard let daysAgo = daysAgo(in: text, now: now, calendar: calendar) else { return nil }
        let time = self.time(in: text)
        return ReceiptDate(daysAgo: daysAgo, hour: time?.hour, minute: time?.minute)
    }

    /// 行の中の時刻（「18:32」「18:32:05」「18時32分」）。
    static func time(in text: String) -> (hour: Int, minute: Int)? {
        for pattern in timePatterns {
            guard let match = pattern.firstMatch(in: text),
                  let hour = match["hour"].flatMap({ Int($0) }),
                  let minute = match["minute"].flatMap({ Int($0) }),
                  (0...23).contains(hour), (0...59).contains(minute)
            else { continue }
            return (hour, minute)
        }
        return nil
    }

    private static func daysAgo(in text: String, now: Date, calendar: Calendar) -> Int? {
        // 和暦（「令和8年9月27日」「R8.9.27」「令和元年」）。
        if let match = eraPattern.firstMatch(in: text) {
            let eraName = match["era"] ?? ""
            let yearText = match["year"] ?? ""
            if let base = eraBases.first(where: { eraName.hasPrefix($0.name) })?.base,
               let year = yearText == "元" ? 1 : Int(yearText),
               let days = validDaysAgo(year: base + year, match: match, now: now, calendar: calendar) {
                return days
            }
        }
        // 西暦 4 桁（「2026年9月27日」「2026/09/27」「2026-09-27」「2026.9.27」）。
        if let match = westernPattern.firstMatch(in: text), let year = match["year"].flatMap({ Int($0) }),
           let days = validDaysAgo(year: year, match: match, now: now, calendar: calendar) {
            return days
        }
        // 西暦の下 2 桁（「26/09/27」「26.09.27」「26-09-27」）。電話番号（「03-1234-5678」）は月日の桁が合わないので当たらない。
        // 「-」でつないだものは、時刻か曜日のある行か、ほかに文字の無い行のときだけ読む。住所の番地（「芝浦12-3-4」）も同じ形で、
        // 2012 年 3 月 4 日と読むと、その下にある買った日時の行より先に採ってしまうため。
        if let match = shortYearPattern.firstMatch(in: text), let year = match["year"].flatMap({ Int($0) }),
           match["separator"] != "-" || hasTimeOrWeekday(text) || isOnlyDate(text, match: match),
           let days = validDaysAgo(year: 2000 + year, match: match, now: now, calendar: calendar) {
            return days
        }
        // 年の無い月日（「9月27日」）。年はひとこと入力と同じ決め方で補う。
        if let match = monthDayPattern.firstMatch(in: text),
           let month = match["month"].flatMap({ Int($0) }),
           let day = match["day"].flatMap({ Int($0) }),
           let days = DateExpression.daysAgo(month: month, day: day, now: now, calendar: calendar), days >= 0 {
            return days
        }
        return nil
    }

    /// 年月日が成り立ち、今日か過去なら何日前か。先の日付は、レシートでは読み違いとみなして読まない。
    private static func validDaysAgo(
        year: Int, match: TextMatch, now: Date, calendar: Calendar
    ) -> Int? {
        guard let month = match["month"].flatMap({ Int($0) }),
              let day = match["day"].flatMap({ Int($0) }),
              let days = DateExpression.daysAgo(year: year, month: month, day: day, now: now, calendar: calendar),
              days >= 0
        else { return nil }
        return days
    }

    /// 行に時刻か曜日（「(日)」「（土）」「(Sat)」）があるか。買った日時の行の手がかり。
    private static func hasTimeOrWeekday(_ text: String) -> Bool {
        time(in: text) != nil || weekdayPattern.matches(text)
    }

    /// 行が日付だけか（日付の外に、かな・漢字・英字が無い）。
    private static func isOnlyDate(_ text: String, match: TextMatch) -> Bool {
        !(text[..<match.range.lowerBound] + text[match.range.upperBound...]).contains(where: \.isLetter)
    }

    /// 元号と、その 0 年にあたる西暦。
    private static let eraBases: [(name: String, base: Int)] = [
        ("令和", 2018), ("R", 2018), ("r", 2018), ("平成", 1988), ("H", 1988), ("h", 1988),
    ]

    // 数字の途中から読み始めない・読み終えないよう、前後に数字が続かないことを確かめる。
    private static let eraPattern = TextPattern(
        #"(?<era>令和|平成|[RrHh])\s*(?<year>元|\d{1,2})\s*[年./\-]\s*(?<month>\d{1,2})\s*[月./\-]\s*(?<day>\d{1,2})(?!\d)"#
    )
    private static let westernPattern = TextPattern(
        #"(?<!\d)(?<year>\d{4})\s*[年./\-]\s*(?<month>\d{1,2})\s*[月./\-]\s*(?<day>\d{1,2})(?!\d)"#
    )
    private static let shortYearPattern = TextPattern(
        #"(?<![\d\-])(?<year>\d{2})(?<separator>[./\-])(?<month>\d{1,2})[./\-](?<day>\d{1,2})(?![\d\-])"#
    )
    private static let weekdayPattern = TextPattern(
        #"[(（](?:[日月火水木金土](?:曜日?)?|SUN|MON|TUE|WED|THU|FRI|SAT|Sun|Mon|Tue|Wed|Thu|Fri|Sat)\.?[)）]"#
    )
    private static let monthDayPattern = TextPattern(#"(?<!\d)(?<month>\d{1,2})\s*月\s*(?<day>\d{1,2})\s*日"#)
    private static let timePatterns = [
        TextPattern(#"(?<!\d)(?<hour>\d{1,2}):(?<minute>\d{2})(?::\d{2})?(?!\d)"#),
        TextPattern(#"(?<!\d)(?<hour>\d{1,2})\s*時\s*(?<minute>\d{1,2})\s*分"#),
    ]
}
