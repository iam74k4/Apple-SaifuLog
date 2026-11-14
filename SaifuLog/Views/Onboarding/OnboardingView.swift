import SwiftUI

/// 初回の案内（① ようこそ）。「はじめる」でホームへ進む。
///
/// 予算を決める画面は案内に入れない。記録を始める前に決めることを求めず、ホームの空の画面の例（「今月の予算を5万にして」）・
/// 設定・質問の答えから、いつでも決められるようにするため。終えたら（`OnboardingModel.isCompleted`）、呼び出し側
/// （`AppRootView`）がホームに切り替える。
struct OnboardingView: View {
    let model: OnboardingModel

    var body: some View {
        // 関数をそのまま渡さず閉包で包む（画面の関数は MainActor に属し、そのまま `() -> Void` に渡すと Swift 6 で弾かれうるため）。
        WelcomeView(aiStatus: model.aiStatus, start: { finish() })
    }

    /// 案内を終えて、ホームに切り替える（`AppRootView` が ① を消してホームを出す）。
    ///
    /// 根元の画面の切り替えは、横に進む・シートを出すのと違って、画面が替わったことを VoiceOver に伝えない。フォーカス
    /// していた「はじめる」が消えて行き先が決まらず、何も読まれないままホームになってしまう。そこで切り替えの動きが
    /// 済んでから、画面が替わったことを知らせる（ホームの最初の要素にフォーカスが移る）。済む前に知らせると、消えかけの
    /// ① の要素にフォーカスが移りうるため。
    private func finish() {
        withAnimation(.default, completionCriteria: .removed) {
            model.start()
        } completion: {
            VoiceOver.screenChanged()
        }
    }
}

#Preview {
    OnboardingView(model: OnboardingModel())
}
