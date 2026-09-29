import SaifuLogCore
import SwiftData
import SwiftUI

/// 保存先を開けたあとの最初の画面。初回だけ案内（① ようこそ → ② 予算を決める）を出し、終えたらホーム（③）にする。
///
/// 案内はホームに重ねる全画面のカバー（fullScreenCover）ではなく、根元の画面の切り替えにしている。カバーは出す動きを
/// 消せないので、初回の起動でホームが一瞬見えてから案内が下から上がってくるため。切り替えなら、案内の間はホーム
/// （タイムラインの @Query や入力欄）を作らずに済む。
///
/// 保存先を開き直すと（`StoreHost.reopen`）、ここから作り直されて、出すかどうかも決め直す（そのときは案内を終えている）。
/// iCloud 同期を切り替えて開き直したときは、切り替えた設定の画面を開いた状態のホームから始める。
struct AppRootView: View {
    let container: ModelContainer
    /// 保存先を開いたもの。あとで保存先に書き込む処理を数える先（`pendingWrites`）と、設定の「iCloud で同期」の
    /// 切り替え先として、ホームのモデルに渡す。
    let storeHost: StoreHost
    /// プレミアムの購入と状態（アプリで 1 つ）。ホームのモデルに渡す。
    let purchases: PurchaseManager
    /// 家計の共有（アプリで 1 つ）。ここで始め（自分の記録の保存先を開けた後）、ホームのモデルに渡す。
    let household: HouseholdHost

    /// 初回の案内。出さないと決めたら nil のまま。終えても持ち続ける（終えたかどうかでホームへの切り替えを描くため）。
    @State private var onboarding: OnboardingModel?
    /// ホームの状態と操作。案内を出すかどうかを決めたときに 1 回だけ作る（決めるまでは nil で、地の色だけを出す。
    /// ホームを一瞬出してから案内に替えないように）。
    ///
    /// ホームの画面（HomeView）に作らせずにここで持つのは、描き直しのたびに捨てるモデルを作らないため。設定の画面を
    /// 開いた状態から始めるとき（iCloud 同期の切り替えの後）に、捨てるモデルが「設定に戻す」の知らせを先に読んでしまうと、
    /// 実際に使うモデルでは設定が開かないため。
    @State private var home: HomeModel?
    /// 設定の「週の始まり」。画面の暦に当てはめて、ここから下の画面に渡す。
    @AppStorage(AppSettings.weekStart) private var weekStart: WeekStart
    /// 端末の暦（地域と iOS の設定のもの）。
    @Environment(\.calendar) private var systemCalendar

    var body: some View {
        ZStack {
            if let onboarding, !onboarding.isCompleted {
                OnboardingView(model: onboarding)
                    .transition(.opacity)
            } else if let home {
                HomeView(model: home)
                    .transition(.opacity)
            } else {
                Theme.background
                    .ignoresSafeArea()
            }
        }
        // 案内からホームへの切り替えの動きは、案内を終える操作の側（`OnboardingView.finish`）で付ける。動きが済んだ
        // ところで VoiceOver に画面が替わったことを知らせるため（ここで付けると、済んだときが分からない）。
        .onAppear(perform: decide)
        #if DEBUG
        // 撮影用のデモ（DEBUG のビルドだけ）: ホームが出た後に、撮る画面（質問・月のまとめ・シートなど）を開く。
        // ホームが画面に出きるのを待ってから開く（出る前にシートや横に進む画面を開くと、出ないことがあるため）。
        .task {
            guard let demo = ScreenshotDemo.current else { return }
            try? await Task.sleep(for: .milliseconds(800))
            guard let home else { return }
            await demo.stage(on: home, calendar: weekStart.applied(to: systemCalendar))
        }
        #endif
        // 週の始まりを、画面の暦（ホーム・まとめ・直すシートの日付の選択が使う環境の calendar）に当てはめる。ホームは
        // この暦を解析や期間の区切り（`ReportPeriod`）に渡すので、今週・先週の区切りも設定に従う。暦を 1 か所で
        // 置き換えるのは、画面ごとに当てはめると、当てはめ忘れた画面だけ別の週になるため。
        .environment(\.calendar, weekStart.applied(to: systemCalendar))
    }

    /// 案内を出すかを決める。最初に出るときに一度だけ（記録があれば、ここで案内を終えたことにする）。
    ///
    /// init ではなくここで決めるのは、View の init は描き直しのたびに呼ばれ、そのたびに保存先を読むことになるため。
    private func decide() {
        // 家計の保存先も保護クラスが Complete なので、自分の記録の保存先を開けた（ロックが解けている）ここで開く。
        // 2 回目からは何もしない（iCloud 同期の切り替えで自分の記録の保存先を開き直しても、家計の保存先は開き直さない）。
        household.start()
        guard home == nil else { return }
        #if DEBUG
        if let demo = ScreenshotDemo.current {
            // 撮影用のデモ（DEBUG のビルドだけ）: 初回の案内を出さず、デモの設定・時計・AI の代わりでホームを作る。
            let home = demo.makeHomeModel(
                context: container.mainContext, pendingWrites: storeHost.pendingWrites, purchases: purchases, storeHost: storeHost,
                household: household
            )
            let calendar = weekStart.applied(to: systemCalendar)
            Task {
                await demo.prepare(home, calendar: calendar)
                self.home = home
            }
            return
        }
        #endif
        if OnboardingModel.needsOnboarding(context: container.mainContext) {
            onboarding = OnboardingModel(budgetStore: BudgetStore(context: container.mainContext))
        }
        let home = HomeModel(
            context: container.mainContext, pendingWrites: storeHost.pendingWrites, purchases: purchases, storeHost: storeHost,
            household: household
        )
        // iCloud 同期を切り替えて開き直したときは、切り替えた設定の画面を開いた状態から始める（どうなったかをその画面で見せる）。
        home.restoreSettingsAfterStoreSwitch()
        self.home = home
    }
}
