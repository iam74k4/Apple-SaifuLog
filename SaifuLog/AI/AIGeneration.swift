#if canImport(FoundationModels)
import FoundationModels

/// 端末内 AI の生成の決め事（どの機能でも同じにする）。
enum AIGeneration {
    /// 毎回いちばん確かな答えにする（貪欲法）。
    ///
    /// このアプリが AI にさせるのは、文から値を抜き出すことと、選択肢から選ぶことだけで、言い回しの幅は要らない（画面に出す文は
    /// コードが書く）。既定の選び方（毎回少しずつ違う答えにする）では、同じ文でも送るたびに読み取りやカテゴリが揺れ、利用者には
    /// 理由の分からない違いに見えるため。`make test-ai` の結果も、動かすたびに変わりにくくなる。
    ///
    /// 引数名は `samplingMode`（iOS 27 の SDK で `sampling` から替わった。`sampling` のままだと非推奨の警告が出る）。新しい書き方も
    /// iOS 26 から使える（SDK が `@backDeployed` にしているので、iOS 26 の端末でも動く）。
    static let deterministic = GenerationOptions(samplingMode: .greedy)
}
#endif
