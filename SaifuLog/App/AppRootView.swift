import SwiftData
import SwiftUI

/// 保存先を開けたあとの最初の画面。初回だけ案内（① ようこそ → ② 予算を決める）を出し、終えたらホーム（③）にする。
///
/// 案内はホームに重ねる全画面のカバー（fullScreenCover）ではなく、根元の画面の切り替えにしている。カバーは出す動きを
/// 消せないので、初回の起動でホームが一瞬見えてから案内が下から上がってくるため。切り替えなら、案内の間はホーム
/// （タイムラインの @Query や入力欄）を作らずに済む。
///
/// 保存先を開き直すと（`StoreHost.reopen`）、ここから作り直されて、出すかどうかも決め直す（そのときは案内を終えている）。
struct AppRootView: View {
    let container: ModelContainer
    /// あとで保存先に書き込む処理を数える先（`StoreHost.pendingWrites`）。ホームのモデルに渡す。
    let pendingWrites: PendingStoreWrites

    /// 初回の案内。出さないと決めたら nil のまま。終えても持ち続ける（終えたかどうかでホームへの切り替えを描くため）。
    @State private var onboarding: OnboardingModel?
    /// 案内を出すかどうかを決めたか。決めるまでは地の色だけを出す（ホームを一瞬出してから案内に替えないように）。
    @State private var hasDecided = false

    var body: some View {
        ZStack {
            if let onboarding, !onboarding.isCompleted {
                OnboardingView(model: onboarding)
                    .transition(.opacity)
            } else if hasDecided {
                HomeView(model: HomeModel(context: container.mainContext, pendingWrites: pendingWrites))
                    .transition(.opacity)
            } else {
                Theme.background
                    .ignoresSafeArea()
            }
        }
        // 案内からホームへの切り替えの動きは、案内を終える操作の側（`OnboardingView.finish`）で付ける。動きが済んだ
        // ところで VoiceOver に画面が替わったことを知らせるため（ここで付けると、済んだときが分からない）。
        .onAppear(perform: decide)
    }

    /// 案内を出すかを決める。最初に出るときに一度だけ（記録があれば、ここで案内を終えたことにする）。
    ///
    /// init ではなくここで決めるのは、View の init は描き直しのたびに呼ばれ、そのたびに保存先を読むことになるため。
    private func decide() {
        guard !hasDecided else { return }
        hasDecided = true
        if OnboardingModel.needsOnboarding(context: container.mainContext) {
            onboarding = OnboardingModel(budgetStore: BudgetStore(context: container.mainContext))
        }
    }
}
