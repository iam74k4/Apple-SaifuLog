import Foundation

/// 記録の返事の下に 1 行だけ出すヒント（docs/design.md §9 の「返事の下のヒント」）。
///
/// チャットで直せること（「それ日用品」「さっきのを900に直して」）と、左へスワイプするとカレンダーのページが出ることは、
/// 画面のどこにも書いていないと気づかれない（前は、直す文を読めなかったときの案内にしか例が出ず、カレンダーにはボタンも
/// ページの点も無い）。ボタンや案内の画面を増やさずに伝えるため、最初の数回の記録の返事にだけ、1 つずつ順に出す:
/// 1. 直し方: 記録した送信の返事に `limit` 回まで。チャットか直す画面（⑥）で一度でも直したら、もう出さない。
/// 2. カレンダー: 直し方を出し終えた後の返事に `limit` 回まで。一度でもカレンダーのページを開いたら、もう出さない。
///
/// 出した回数と、もう要らないことは UserDefaults に覚える（家計の中身ではないので、`AppSettings` に置く）。
struct ReplyHints {
    /// 返事の下に出すヒントの種類。
    enum Hint: Equatable, Sendable {
        /// チャットでの直し方。
        case correction
        /// 左へスワイプするとカレンダー。
        case calendar
    }

    /// それぞれのヒントを出す、記録の返事の回数の上限。
    static let limit = 3

    let defaults: UserDefaults

    /// 記録した送信の返事に出すヒントを決め、出した回数を数える。出すものが無ければ nil。
    mutating func nextHint() -> Hint? {
        if !defaults.bool(for: AppSettings.hasCorrectedEntry) {
            let shown = defaults.integer(for: AppSettings.correctionHintShownCount)
            if shown < Self.limit {
                defaults.set(shown + 1, for: AppSettings.correctionHintShownCount)
                return .correction
            }
        }
        if !defaults.bool(for: AppSettings.hasOpenedCalendar) {
            let shown = defaults.integer(for: AppSettings.calendarHintShownCount)
            if shown < Self.limit {
                defaults.set(shown + 1, for: AppSettings.calendarHintShownCount)
                return .calendar
            }
        }
        return nil
    }

    /// 記録を直した（直し方を知っている）。
    func markCorrected() {
        defaults.set(true, for: AppSettings.hasCorrectedEntry)
    }

    /// カレンダーのページを開いた（入口を知っている）。
    func markCalendarOpened() {
        defaults.set(true, for: AppSettings.hasOpenedCalendar)
    }
}
