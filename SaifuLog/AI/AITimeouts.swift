import Foundation

/// 端末内 AI を待つ上限（機能ごと）。値はここにだけ書く。
///
/// どれも、モデルが返らないまま止まったときに待ち続けないための安全の上限で、ふつうにかかる時間を詰めるためのものではない。
/// 上限を過ぎたら、AI が終わるのを待たずに、AI の使えない端末と同じ経路（キーワード辞書・定型文）に切り替え、時間切れとして
/// `AIFallbackLog` に残す（利用者には知らせない。docs/design.md §4-2）。
/// 値は実機で測る前の仮の値。実機でふつうにかかる時間（初めての生成のモデルの読み込みを含む）を測ってから見直す（docs/design.md §15）。
enum AITimeouts {
    /// ひとこと入力の読み取り（区間ごとの生成をすべて含む）。待つ間は次の文を送れず、保存先の開き直し（iCloud の切り替え）も
    /// 待たせるので、いちばん短くする。
    static let entry: Duration = .seconds(6)
    /// 家計への質問（ツール呼び出しと一言）。
    static let question: Duration = .seconds(8)
    /// ふりかえり（先週のふりかえり・月のまとめ）の一言。
    static let recapRemark: Duration = .seconds(8)
    /// レシートの品名とカテゴリの整え。品目の数だけ生成が長くなり、iOS 27 では画像も渡すので、ほかより長くする。
    static let receiptRefine: Duration = .seconds(15)
}
