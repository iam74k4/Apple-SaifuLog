import SwiftData
import SwiftUI

@main
struct SaifuLogApp: App {
    /// 記録の保存先。ここでは作るだけで、開くのは最初の画面が出るとき（`StoreHost.start()`）。
    /// App の生成の時点で開くと、iOS が起動を前倒しで済ませておく prewarm の間（ロック中のことがある）に
    /// 開くことになり、NSFileProtectionComplete の保存先を読めないため。
    /// iCloud と同期するかは、設定の「iCloud で同期」（既定はオフ）で決める。
    @State private var storeHost = StoreHost(
        cloudKitDatabase: .init(syncEnabled: UserDefaults.standard.bool(for: AppSettings.iCloudSyncEnabled))
    )
    /// プレミアムの購入と状態。アプリで 1 つ。
    @State private var purchases: PurchaseManager
    /// 家計の共有（家族・パートナー）。アプリで 1 つ。機能フラグが false のビルドでは何もしない（`HouseholdSharing`）。
    /// 家計の保存先は、自分の記録の保存先を開けた後に開く（`AppRootView` が `start()` を呼ぶ）。
    @State private var household = HouseholdHost()
    #if DEBUG || INTERNAL_DIAGNOSTICS
    /// 家計の共有の招待を受け取るための委任先（場面の委任先を足す）。家計の共有を隠している間は、App Store へ出すビルドの
    /// 起動の仕組みを変えないよう、機能フラグと同じ条件のビルドにだけ入れる。
    @UIApplicationDelegateAdaptor(HouseholdAppDelegate.self) private var appDelegate
    #endif

    init() {
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
        }
    }
}
