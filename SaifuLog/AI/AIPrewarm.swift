import Foundation

/// 端末内 AI のモデルを前もって読み込む（入力欄にフォーカスが入ったとき・前面に戻ったとき）。
///
/// 端末内のモデルは、使っていない間にメモリから外される。外れたまま送ると、読み込みを待つ間に読み取りが上限の時間（`AITimeouts`）に
/// 届き、キーワード辞書に戻りやすい。打ち始める前に読み込んでおく。フォーカスの出入りのたびに読み込み直さないよう、間を空ける。
/// AI が使えない端末では何もしない。
@MainActor
enum AIPrewarm {
    /// 読み込み直すまでに空ける間。
    static let minimumInterval: Duration = .seconds(60)

    private static var lastPrewarmedAt: ContinuousClock.Instant?

    static func prewarmIfAvailable() {
        #if canImport(FoundationModels)
        let now = ContinuousClock.now
        if let last = lastPrewarmedAt, last.duration(to: now) < minimumInterval { return }
        guard FoundationModelsEntryParser.isAvailable else { return }
        lastPrewarmedAt = now
        FoundationModelsEntryParser.prewarm()
        #endif
    }
}
