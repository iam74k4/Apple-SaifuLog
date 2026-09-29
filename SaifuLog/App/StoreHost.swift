import Observation
import SwiftData
import UIKit

/// 記録の保存先を開き、開けたかどうかを画面（`StoreRootView`）に伝える。
///
/// 以前は App の static let で開き、開けなければ fatalError で止めていた。保存先は NSFileProtectionComplete
/// （SaifuLog.entitlements）なので、端末のロック中（保護されたデータが読めない間）に開こうとすると失敗し、
/// アプリが落ちてしまう。ここでは落とさずに待ち、ロックが解けたら開き直す。ロック中でないのに開けない
/// （空き容量が無いなど）ときは、再試行できる画面を出す。黙って空の保存先で続けると、記録が消えたように見えるため。
///
/// iCloud 同期（設定の「iCloud で同期」。既定はオフ）の切り替えもここが受け持つ（`setICloudSyncEnabled(_:)`）。
/// iCloud と同期する保存先を開けず、同じファイルを端末の中だけの保存先としてなら開けたときは、そちらに戻して理由を
/// `iCloudFallback` に残す（`fallBackToLocalStore(after:)`）。
@MainActor
@Observable
final class StoreHost {
    enum State {
        /// 開く前・開いている途中・ロックが解けるのを待っている間。
        case loading
        /// 開けた。この保存先で画面を組み立てる。
        case ready(ModelContainer)
        /// ロック中でないのに開けなかった。再試行の画面を出す。
        case unavailable(any Error)
        /// 開き直すために、前の保存先を使う画面のツリーを畳み、書き込み中の処理が終わるのを待っている間
        /// （iCloud の切り替えで使う）。
        case reopening
    }

    private(set) var state: State = .loading
    /// 再試行のボタンで開き直しても、また開けなかった回数（開けたら 0 に戻す）。
    ///
    /// 開けない原因が続いていると、再試行してもすぐに同じ画面に戻り、見た目が何も変わらない。回数を画面に出して、
    /// 押したことが伝わるようにする。
    private(set) var failedRetryCount = 0
    /// 画面から始めて、あとで保存先に書き込む処理。開き直すときは、これが終わるのを待ってから新しい保存先を開く。
    /// 保存先を使う画面のモデル（`HomeModel` など）に渡す。
    @ObservationIgnored let pendingWrites = PendingStoreWrites()
    /// 開いている（これから開く）保存先の iCloud の扱い。
    @ObservationIgnored private(set) var cloudKitDatabase: ModelContainerFactory.CloudKitDatabase
    /// iCloud と同期する保存先を開けず、端末の中だけに戻したときの理由。画面が知らせ（アラート）を出し、閉じたら
    /// `acknowledgeICloudFallback()` で消す。
    private(set) var iCloudFallback: ICloudSyncFailure?
    /// iCloud 同期を切り替えて開き直したあと、設定の画面に戻すか。切り替えは設定の画面から始まるが、開き直すと画面の
    /// ツリーを畳むのでホームに戻ってしまう。どうなったか（オンかオフか、戻したならその理由）を切り替えた画面で見せるため、
    /// ホームを組み立てるときに `consumeSettingsRestoration()` で読む（`HomeModel.restoreSettingsAfterStoreSwitch`）。
    @ObservationIgnored private var restoresSettings = false
    /// 開き直せたら VoiceOver に読み上げる文（iCloud 同期を切り替えたとき）。
    @ObservationIgnored private var pendingAnnouncement: String?
    /// ロックが解けるのを待っているか。解けたら（`protectedDataMayBeAvailable()`）開き直す。
    @ObservationIgnored private(set) var isWaitingForProtectedData = false
    @ObservationIgnored private var hasStarted = false
    /// 開き直しの間、前の保存先を持っておく。画面のツリーを畳んだ後も、書き込み中の処理が前の保存先の
    /// ModelContext を使うため（保存先を手放した後の ModelContext は使えない）。書き込みが終わったら手放す。
    @ObservationIgnored private var retiringContainer: ModelContainer?
    @ObservationIgnored private var isFinishingReopening = false
    /// 開けた保存先で組み立てた画面（`StoreRootView` の content）が、いま画面のツリーにいくつあるか。
    @ObservationIgnored private var mountedContentCount = 0
    /// 前の保存先の画面が消えるのを待っている開き直し。
    @ObservationIgnored private var contentRemovalWaiters: [CheckedContinuation<Void, Never>] = []
    /// 前の保存先の画面が消えるのを待つ上限。消えた知らせ（onDisappear）が来ないまま読み込み中の画面で止まり続けないように。
    @ObservationIgnored private let contentRemovalTimeout: Duration
    @ObservationIgnored private let openContainer: @MainActor (ModelContainerFactory.CloudKitDatabase) throws -> ModelContainer
    @ObservationIgnored private let isProtectedDataAvailable: @MainActor () -> Bool
    @ObservationIgnored private let announce: @MainActor (String) -> Void
    @ObservationIgnored private let defaults: UserDefaults

    /// - Parameters:
    ///   - cloudKitDatabase: 最初に開く保存先の iCloud の扱い。アプリは設定の「iCloud で同期」から決める
    ///     （`CloudKitDatabase(syncEnabled:)`）。
    ///   - defaults: 設定の置き場所。iCloud 同期を切り替えたときと、開けずに端末の中だけへ戻したときに書く。
    ///     アプリは `UserDefaults.standard`（`AppSettings` の決まり）、テストは使い捨ての領域。
    ///   - openContainer: 保存先を開く処理。テストでメモリの上の保存先や、失敗する処理に差し替える。
    ///   - isProtectedDataAvailable: 保護されたデータが読めるか（ロック中でないか）。テストで差し替える。
    ///   - announce: VoiceOver に読み上げさせる。テストで読み上げる文を集める。
    ///   - contentRemovalTimeout: 開き直すときに、前の保存先の画面が消えるのを待つ上限。テストで短くする。
    init(
        cloudKitDatabase: ModelContainerFactory.CloudKitDatabase = .none,
        defaults: UserDefaults = .standard,
        openContainer: @escaping @MainActor (ModelContainerFactory.CloudKitDatabase) throws -> ModelContainer = {
            try ModelContainerFactory.makeContainer(cloudKitDatabase: $0)
        },
        isProtectedDataAvailable: @escaping @MainActor () -> Bool = { UIApplication.shared.isProtectedDataAvailable },
        announce: @escaping @MainActor (String) -> Void = { VoiceOver.announce($0) },
        contentRemovalTimeout: Duration = .seconds(3)
    ) {
        self.cloudKitDatabase = cloudKitDatabase
        self.defaults = defaults
        self.openContainer = openContainer
        self.isProtectedDataAvailable = isProtectedDataAvailable
        self.announce = announce
        self.contentRemovalTimeout = contentRemovalTimeout
    }

    /// 最初の画面が出るときに呼ぶ（2 回目からは何もしない）。
    ///
    /// App を作る時点では開かない。iOS が起動を前倒しで済ませておく prewarm はロック中にも走ることがあり、
    /// その間に開こうとしても読めないため。
    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        open()
    }

    /// 保護されたデータが読めるようになった（ロックが解けた）、またはアプリが前面に来たときに呼ぶ。
    /// ロックが解けるのを待っていたときだけ開き直す。
    func protectedDataMayBeAvailable() {
        guard isWaitingForProtectedData else { return }
        open()
    }

    /// 再試行の画面のボタン。
    func retry() {
        guard case .unavailable = state else { return }
        state = .loading
        open()
        // また開けなければ、同じ呼び出しの中で .unavailable に戻る。SwiftUI は 2 回の変更をまとめて描くので、
        // 読み込み中の画面は一瞬も出ず、見た目も VoiceOver も何も変わらない。試したことを回数と読み上げで伝える。
        if case .unavailable = state {
            failedRetryCount += 1
            announce(String(localized: "もう一度試しましたが、記録を開けませんでした"))
        }
    }

    /// 設定の「iCloud で同期」を切り替える。設定に書いてから、iCloud の扱いを変えて保存先を開き直す（`reopen`）。
    ///
    /// 同期のオンとオフで同じファイルを開くので、オンにするとこの端末の記録が iCloud に上がり、オフに戻してもこの端末の
    /// 記録は残る（`ModelContainerFactory.makeContainer`）。開き直したら設定の画面に戻す（`consumeSettingsRestoration`）。
    /// iCloud と同期する保存先を開けず、端末の中だけの保存先としてなら開けたときは、そちらに戻して設定もオフに戻す
    /// （`iCloudFallback`）。いまと同じ値なら何もしない。
    func setICloudSyncEnabled(_ enabled: Bool) {
        let target = ModelContainerFactory.CloudKitDatabase(syncEnabled: enabled)
        guard target != cloudKitDatabase else { return }
        // 開き直せない状態（開く前・開き直しの途中）では受け付けない（設定を書いたのに開き直さない、を避ける）。
        switch state {
        case .ready, .unavailable: break
        case .loading, .reopening: return
        }
        defaults.set(enabled, for: AppSettings.iCloudSyncEnabled)
        iCloudFallback = nil
        restoresSettings = true
        pendingAnnouncement = enabled
            ? String(localized: "iCloud での同期をオンにしました")
            : String(localized: "iCloud での同期をオフにしました。記録はこの iPhone に残っています")
        reopen(cloudKitDatabase: target)
    }

    /// iCloud 同期を切り替えて開き直したあと、設定の画面に戻すか（一度だけ true を返す）。
    func consumeSettingsRestoration() -> Bool {
        defer { restoresSettings = false }
        return restoresSettings
    }

    /// 端末の中だけに戻したことの知らせを閉じた。
    func acknowledgeICloudFallback() {
        iCloudFallback = nil
    }

    /// iCloud の扱いを変えて保存先を開き直す（`setICloudSyncEnabled(_:)` から呼ぶ）。
    ///
    /// 同じファイルを 2 つの保存先で同時に開かないよう、先に `.reopening` にして、前の保存先を使う画面のツリー
    /// （その中の @Query や ModelContext）を畳む。`.reopening` の画面が出たら `StoreRootView` が `finishReopening()` を呼び、
    /// 前の保存先の画面が消え（`contentDidDisappear()`）、書き込み中の処理（`pendingWrites`）が終わるのを待って、前の保存先を
    /// 手放してから新しい保存先を開く。
    /// ほかに前の保存先を持ち続けているもの（画面のモデルを抱えたままの処理など）があれば、それが手放すまで
    /// 前の保存先は閉じない。保存先を使う処理は、あとで書き込むなら必ず `pendingWrites` に数えること。
    func reopen(cloudKitDatabase: ModelContainerFactory.CloudKitDatabase) {
        switch state {
        case .ready(let container): retiringContainer = container
        case .unavailable: break
        case .loading, .reopening: return
        }
        self.cloudKitDatabase = cloudKitDatabase
        failedRetryCount = 0
        state = .reopening
    }

    /// 開けた保存先で組み立てた画面が、画面のツリーに入った（`StoreRootView` が呼ぶ）。
    func contentDidAppear() {
        mountedContentCount += 1
    }

    /// 開けた保存先で組み立てた画面が、画面のツリーから消えた（`StoreRootView` が呼ぶ）。
    func contentDidDisappear() {
        mountedContentCount = max(0, mountedContentCount - 1)
        if mountedContentCount == 0 { resumeContentRemovalWaiters() }
    }

    /// `.reopening` の画面が出たあとに呼ぶ。前の保存先の画面が消え、書き込み中の処理が終わるまで待ってから開く。
    ///
    /// `.reopening` の画面が出ても、前の画面がまだ消えていないことがある（シートやアラートを閉じる動きの途中で切り替えた
    /// ときなど。シミュレータの iOS 26.4 で、設定のアラートから切り替えたときに見た）。待たずに開くと、前の画面のモデルが
    /// 前の保存先を使い続けたまま、同じファイルを新しい保存先でも開くことになる。
    func finishReopening() async {
        guard case .reopening = state, !isFinishingReopening else { return }
        isFinishingReopening = true
        defer { isFinishingReopening = false }
        await waitUntilContentRemoved()
        await pendingWrites.waitUntilIdle()
        retiringContainer = nil
        guard case .reopening = state else { return }
        open()
    }

    /// 開けた保存先の画面がツリーに残っていれば、消えるまで待つ（上限つき）。
    private func waitUntilContentRemoved() async {
        guard mountedContentCount > 0 else { return }
        let timeout = contentRemovalTimeout
        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.resumeContentRemovalWaiters()
        }
        await withCheckedContinuation { continuation in
            contentRemovalWaiters.append(continuation)
        }
        timeoutTask.cancel()
    }

    private func resumeContentRemovalWaiters() {
        let waiters = contentRemovalWaiters
        contentRemovalWaiters = []
        for waiter in waiters { waiter.resume() }
    }

    private func open() {
        guard isProtectedDataAvailable() else {
            // 開こうとしても読めない。ロックが解けるまで待つ（画面はいまの状態のまま）。
            isWaitingForProtectedData = true
            return
        }
        do {
            didOpen(try openContainer(cloudKitDatabase))
        } catch {
            guard isProtectedDataAvailable() else {
                // 開いている途中でロックされた。ロックが解けたら開き直す（iCloud の扱いは変えない。ロックのせいで
                // 開けなかっただけで、iCloud のせいではないため）。
                isWaitingForProtectedData = true
                return
            }
            isWaitingForProtectedData = false
            if cloudKitDatabase.isSyncEnabled {
                fallBackToLocalStore(after: error)
            } else {
                state = .unavailable(error)
            }
        }
    }

    private func didOpen(_ container: ModelContainer) {
        isWaitingForProtectedData = false
        failedRetryCount = 0
        state = .ready(container)
        if let pendingAnnouncement {
            self.pendingAnnouncement = nil
            announce(pendingAnnouncement)
        }
    }

    /// iCloud と同期する保存先を開けなかった。同じファイルを端末の中だけの保存先として開いてみて、開けたときだけ
    /// そちらに戻し、設定もオフに戻して、理由を残す。
    ///
    /// 黙って再試行の画面を出すと、iCloud をやめれば開けるのに記録を使えなくなる。設定をオンのままにすると、起動の
    /// たびに同じ失敗を繰り返す。
    ///
    /// iCloud のせいかどうかを、エラーの種類では決めない。CloudKit の制約に合わないモデルで開けないとき、SwiftData は
    /// 中身の分からない `SwiftDataError.loadIssueModelContainer` を投げ、空き容量が無い・保存先が壊れた・移行できない
    /// ときと見分けられないため（`ICloudSyncFailure`）。代わりに、iCloud の扱いだけを替えて同じファイルを開いてみる。
    /// 開ければ、違いは iCloud の扱いだけなので iCloud のせいとみなす。
    /// 端末の中だけでも開けなければ iCloud のせいではないので、設定も iCloud の扱いも変えず、戻したという知らせも出さずに
    /// ふだんと同じ再試行の画面にする（保存先を開けていないのに「この iPhone の中だけに保存しています」と知らせない。
    /// 空き容量を空けた後の再試行では、また iCloud と同期する保存先から開く）。
    private func fallBackToLocalStore(after iCloudError: any Error) {
        let container: ModelContainer
        do {
            container = try openContainer(.none)
        } catch {
            if isProtectedDataAvailable() {
                state = .unavailable(error)
            } else {
                // 開いている途中でロックされた。ロックが解けたら、iCloud と同期する保存先から開き直す。
                isWaitingForProtectedData = true
            }
            return
        }
        cloudKitDatabase = .none
        defaults.set(false, for: AppSettings.iCloudSyncEnabled)
        iCloudFallback = ICloudSyncFailure(error: iCloudError)
        // 「オンにしました」とは読み上げない（戻したことは知らせのアラートで伝える）。
        pendingAnnouncement = nil
        didOpen(container)
    }
}
