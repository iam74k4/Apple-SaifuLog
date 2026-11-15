import Foundation

/// 記録の返事の下に 1 行だけ出すヒント（docs/design.md §9 の「返事の下のヒント」）。
///
/// チャットで直せること（「それ日用品」「さっきのを900に直して」）は、画面のどこにも書いていないと気づかれない（前は、
/// 直す文を読めなかったときの案内にしか例が出なかった）。ボタンや案内の画面を増やさずに伝えるため、最初の数回の記録の返事
/// にだけ出す: 記録した送信の返事に `limit` 回まで。チャットか直す画面（⑥）で一度でも直したら、もう出さない。
/// （カレンダーのヒントはやめた。カレンダーを、帯から開く月の画面の切り替えにして、見える入口ができたため。）
///
/// 出した回数と、もう要らないことは UserDefaults に覚える（家計の中身ではないので、`AppSettings` に置く）。
struct ReplyHints {
    /// 返事の下に出すヒントの種類。
    enum Hint: Equatable, Sendable {
        /// チャットでの直し方。
        case correction
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
        return nil
    }

    /// 記録を直した（直し方を知っている）。
    func markCorrected() {
        defaults.set(true, for: AppSettings.hasCorrectedEntry)
    }
}
