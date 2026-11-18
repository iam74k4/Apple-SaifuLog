#if canImport(FoundationModels)
import FoundationModels
import Testing
@testable import SaifuLog

/// 端末内 AI の生成の決め事（`AIGeneration`）。
struct AIGenerationTests {
    /// どの機能も「いちばん確かな答え」で生成する。揺れると、同じ文でも送るたびに読み取りやカテゴリが変わる。
    ///
    /// 引数名を `sampling` から `samplingMode` に替えたもの（iOS 27 の SDK で替わった）は、iOS 26 の端末ではアプリの中に入った実装で
    /// 動く（SDK の `@backDeployed`）。iOS 26 のシミュレータでも通ることで、その道が生きていることを確かめる（`make test-app-ios26`）。
    @Test("生成の選び方は貪欲法で、温度や長さの上限は決めない")
    func deterministicIsGreedy() {
        let options = AIGeneration.deterministic

        #expect(options.samplingMode == .greedy)
        #expect(options.temperature == nil)
        #expect(options.maximumResponseTokens == nil)
    }
}
#endif
