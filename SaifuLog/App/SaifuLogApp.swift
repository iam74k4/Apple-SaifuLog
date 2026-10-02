import SwiftData
import SwiftUI

@main
struct SaifuLogApp: App {
    /// 記録の保存先。ここでは作るだけで、開くのは最初の画面が出るとき（`StoreHost.start()`）。
    /// App の生成の時点で開くと、iOS が起動を前倒しで済ませておく prewarm の間（ロック中のことがある）に
    /// 開くことになり、NSFileProtectionComplete の保存先を読めないため。
    /// iCloud と同期するかは、設定の「iCloud で同期」（既定はオフ）を開く直前に読んで決める。
    @State private var storeHost: StoreHost
    /// プレミアムの購入と状態。アプリで 1 つ。
    @State private var purchases: PurchaseManager
    /// 家計の共有（家族・パートナー）。アプリで 1 つ。機能フラグが false のビルドでは何もしない（`HouseholdSharing`）。
    /// 家計の保存先は、自分の記録の保存先を開けた後に開く（`AppRootView` が `start()` を呼ぶ）。
    @State private var household = HouseholdHost()
    /// アプリのロック（設定の「Face ID でロック」）。アプリで 1 つ。保存先を開く前（再試行の画面を含む）から効かせる。
    @State private var appLock: AppLock
    #if DEBUG || INTERNAL_DIAGNOSTICS
    /// 家計の共有の招待を受け取るための委任先（場面の委任先を足す）。家計の共有を隠している間は、App Store へ出すビルドの
    /// 起動の仕組みを変えないよう、機能フラグと同じ条件のビルドにだけ入れる。
    @UIApplicationDelegateAdaptor(HouseholdAppDelegate.self) private var appDelegate
    #endif

    init() {
        #if DEBUG
        if let demo = ScreenshotDemo.current {
            // 撮影用のデモ（DEBUG のビルドだけ）。保存先はメモリの上の架空の記録、購入の状態は決めたもの、家族との共有は出さない。
            // App Store の購入の記録（Transaction.updates）も読まない。
            _storeHost = State(initialValue: demo.makeStoreHost())
            _purchases = State(initialValue: demo.makePurchases())
            _household = State(initialValue: HouseholdHost(isEnabled: false))
            // ロックの設定もデモの領域から読む（利用者の設定に触れない。デモの領域は毎回空なので、ロックはオフ）。
            _appLock = State(initialValue: AppLock(settings: demo.launchSettings))
            return
        }
        #endif
        // ロックと iCloud 同期の設定は UserDefaults ではなく専用のファイルから読む（`LaunchSettingsStore`）。ここ（App を作る
        // 時点）はロック中に裏で起こされたときにも通り、そのとき UserDefaults を読むと空の内容を覚えてしまうため、ここでは
        // UserDefaults を読まない。
        let settings = LaunchSettingsStore()
        _storeHost = State(initialValue: StoreHost(settings: settings))
        _appLock = State(initialValue: AppLock(settings: settings))
        let purchases = PurchaseManager()
        // 起動したらすぐ Transaction.updates の購読を始める（返金・失効・承認待ちの承認を取りこぼさないため）。
        // 購入の記録は保存先（SwiftData）ではなく StoreKit が持つので、保存先を開く最初の画面を待たない。
        purchases.start()
        _purchases = State(initialValue: purchases)
    }

    var body: some Scene {
        WindowGroup {
            StoreRootView(host: storeHost) { container in
                // 初回だけ案内（ようこそ → 予算を決める）を出し、それ以外はホーム。
                AppRootView(container: container, storeHost: storeHost, purchases: purchases, household: household)
            }
            // 設定の「Face ID でロック」の行が読み書きする。
            .environment(appLock)
            // ロック中と前面を離れている間は、ロックの画面をすべての画面より上に出す。
            .appLock(appLock)
            #if DEBUG
            // 撮影用のデモでは、画面の設定（@AppStorage）もデモの領域から読む（利用者の設定に触れない）。
            .defaultAppStorage(ScreenshotDemo.current?.defaults ?? .standard)
            #endif
        }
    }
}
