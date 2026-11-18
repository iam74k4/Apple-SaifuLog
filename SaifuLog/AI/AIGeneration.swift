#if canImport(FoundationModels)
import FoundationModels

/// 端末内 AI の生成の決め事（どの機能でも同じにする）。
enum AIGeneration {
    /// 毎回いちばん確かな答えにする（貪欲法）。
    ///
    /// このアプリが AI にさせるのは、文から値を抜き出すことと、選択肢から選ぶことだけで、言い回しの幅は要らない（画面に出す文は
    /// コードが書く）。既定の選び方（毎回少しずつ違う答えにする）では、同じ文でも送るたびに読み取りやカテゴリが揺れ、利用者には
    /// 理由の分からない違いに見えるため。`make test-ai` の結果も、動かすたびに変わりにくくなる。
    static let deterministic = GenerationOptions(sampling: .greedy)
}
#endif
