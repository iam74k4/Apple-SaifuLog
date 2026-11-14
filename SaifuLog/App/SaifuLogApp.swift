import SwiftData
import SwiftUI

@main
struct SaifuLogApp: App {
    /// 記録の保存先。ここでは作るだけで、開くのは最初の画面が出るとき（`StoreHost.start()`）。
    /// App の生成の時点で開くと、iOS が起動を前倒しで済ませておく prewarm の間（ロック中のことがある）に
    /// 開くことになり、NSFileProtectionComplete の保存先を読めないため。
    /// iCloud と同期するかは、設定の「iCloud で同期」（既定はオフ）を開く直前に読んで決める。
    @State private var storeHost: StoreHost
    /// アプリのロック（設定の「Face ID でロック」）。アプリで 1 つ。保存先を開く前（再試行の画面を含む）から効かせる。
    @State private var appLock: AppLock
    /// ホームの帯の数字をウィジェットに渡すもの。撮影用のデモと UI テストでは作らない（架空の記録の数字で、端末のウィジェットを
    /// 書き換えないため）。
    @State private var widgetPublisher: WidgetPublisher? = nil

    init() {
        #if DEBUG
        if let demo = ScreenshotDemo.current {
            // 撮影用のデモ（DEBUG のビルドだけ）。保存先はメモリの上の架空の記録。
            _storeHost = State(initialValue: demo.makeStoreHost())
            // ロックの設定もデモの領域から読む（利用者の設定に触れない。デモの領域は毎回空なので、ロックはオフ）。
            _appLock = State(initialValue: AppLock(settings: demo.launchSettings))
            return
        }
        if let uiTest = UITestMode.current {
            // UI テスト（DEBUG のビルドだけ）。保存先はメモリの上で、ロックと iCloud 同期はオフ（`UITestMode`）。
            _storeHost = State(initialValue: uiTest.makeStoreHost())
            _appLock = State(initialValue: AppLock(settings: uiTest.launchSettings))
            return
        }
        #endif
        // ロックと iCloud 同期の設定は UserDefaults ではなく専用のファイルから読む（`LaunchSettingsStore`）。ここ（App を作る
        // 時点）はロック中に裏で起こされたときにも通り、そのとき UserDefaults を読むと空の内容を覚えてしまうため、ここでは
        // UserDefaults を読まない。
        let settings = LaunchSettingsStore()
        _storeHost = State(initialValue: StoreHost(settings: settings))
        _appLock = State(initialValue: AppLock(settings: settings))
        _widgetPublisher = State(initialValue: WidgetPublisher())
    }

    var body: some Scene {
        WindowGroup {
            StoreRootView(host: storeHost) { container in
                // 初回だけ案内（ようこそ → 予算を決める）を出し、それ以外はホーム。
                AppRootView(container: container, storeHost: storeHost)
            }
            // 設定の「Face ID でロック」の行が読み書きする。
            .environment(appLock)
            // ホームの帯が、数字をウィジェットに渡す。
            .environment(\.widgetPublisher, widgetPublisher)
            // ウィジェットを押して開いたら、会話の入力欄を開く（`WidgetLink`）。
            .onOpenURL { url in
                if WidgetLink.isRecord(url) {
                    QuickActionInbox.shared.post(.record(""))
                }
            }
            // ロック中と前面を離れている間は、ロックの画面をすべての画面より上に出す。
            .appLock(appLock)
            #if DEBUG
            // 撮影用のデモと UI テストでは、画面の設定（@AppStorage）もそれぞれの領域から読む（利用者の設定に触れない）。
            .defaultAppStorage(ScreenshotDemo.current?.defaults ?? UITestMode.current?.defaults ?? .standard)
            #endif
        }
    }
}
