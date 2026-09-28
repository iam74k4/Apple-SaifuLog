import SwiftUI

/// 初回の案内。① ようこそ → ② 予算を決める（「あとで」で飛ばせる）。
///
/// 終えたら（`OnboardingModel.isCompleted`）、呼び出し側（`AppRootView`）がホームに切り替える。② は予算を決める画面
/// （`BudgetSetupView`）をそのまま使い、ここでは進み方（① から横に進む・「あとで」）だけを足す。
struct OnboardingView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        NavigationStack {
            WelcomeView(model: model)
                // ① はナビゲーションバーの無い全画面にする（戻る先も見出しも無いため）。
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(isPresented: $model.showsBudgetSetup) {
                    BudgetSetupView(model: model.budgetSetup, onFinish: { finish { model.finishBudgetSetup() } })
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("あとで") { finish { model.skipBudgetSetup() } }
                                    .accessibilityHint("予算を決めずにホームへ進みます。予算はホームからいつでも決められます。")
                            }
                        }
                }
        }
    }

    /// 案内を終えて、ホームに切り替える（`AppRootView` が ① ② を消してホームを出す）。
    ///
    /// 根元の画面の切り替えは、横に進む・シートを出すのと違って、画面が替わったことを VoiceOver に伝えない。フォーカス
    /// していた「あとで」や保存のボタンが消えて行き先が決まらず、「あとで」では何も読まれないままホームになってしまう。
    /// そこで切り替えの動きが済んでから、画面が替わったことを知らせる（ホームの最初の要素にフォーカスが移る）。済む前に
    /// 知らせると、消えかけの ① ② の要素にフォーカスが移りうるため。② の保存では、先に「予算を ¥… にしました」を
    /// 優先して読ませてあるので、それより後に知らせる順になる（読み上げが途中で切れないかは実機で確かめる）。
    private func finish(_ complete: () -> Void) {
        withAnimation(.default, completionCriteria: .removed) {
            complete()
        } completion: {
            VoiceOver.screenChanged()
        }
    }
}

#Preview {
    if let container = try? ModelContainerFactory.makeInMemoryContainer() {
        OnboardingView(model: OnboardingModel(budgetStore: BudgetStore(context: container.mainContext)))
    }
}
