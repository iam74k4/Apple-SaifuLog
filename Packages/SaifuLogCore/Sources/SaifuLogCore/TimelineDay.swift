import Foundation

/// タイムラインの日付の見出し（その日の最初の行の上に置く「今日」「昨日」「9月28日(月)」）の決め事。
///
/// 見出しの日は、行を並べる日時（送信は記録した日時、質問は送った日時、先週のふりかえりは出した日時）の暦の日で、
/// 使った日ではない（タイムラインは送った順に並べるので、翌朝に送った「昨日 焼肉…」は今日の見出しの下に並ぶ）。
/// 見出しに金額を添えないのはこのため（見出しの下に別の日の支出が並ぶことがあり、合計を出すと、その日に使った額と
/// 読み違えるため）。
///
/// 日の区切りは渡された暦のまま（時間帯も）。週の始まりは使わない。
public enum TimelineDay {
    /// 見出しの言い方。
    public enum Label: Hashable, Sendable {
        /// 今日。
        case today
        /// 昨日。
        case yesterday
        /// 日付（月日と曜日）。`includesYear` なら年も添える（今年でない日。年なしだと今年の日に見えるため）。
        case date(includesYear: Bool)
    }

    /// 並べた順の日時（古い順）から、日付の見出しを置く位置を返す。見出しは、返した添字の行の前に置く。
    ///
    /// 最初の行の前と、暦の日が前の行と変わる行の前に置く（最初の行の前にも置くのは、いちばん上の日の行が何日のものかが
    /// 分からなくならないように）。
    public static func headerIndices(for dates: [Date], calendar: Calendar) -> [Int] {
        dates.indices.filter { index in
            index == 0 || !calendar.isDate(dates[index], inSameDayAs: dates[index - 1])
        }
    }

    /// `day` の日の見出しの言い方（`now` の日から見て）。
    ///
    /// 昨日は暦の日で数える（夏時間の変わる日のように 1 日が 24 時間でない日も、前の暦の日を昨日とする）。
    public static func label(for day: Date, now: Date, calendar: Calendar) -> Label {
        if calendar.isDate(day, inSameDayAs: now) {
            return .today
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)),
           calendar.isDate(day, inSameDayAs: yesterday) {
            return .yesterday
        }
        return .date(includesYear: !calendar.isDate(day, equalTo: now, toGranularity: .year))
    }
}
