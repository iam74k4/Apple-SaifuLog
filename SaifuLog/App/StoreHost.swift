import Observation
import SwiftData
import UIKit

/// 記録の保存先を開き、開けたかどうかを画面（`StoreRootView`）に伝える。
///
/// 以前は App の static let で開き、開けなければ fatalError で止めていた。保存先は NSFileProtectionComplete
/// （SaifuLog.entitlements）なので、端末のロック中（保護されたデータが読めない間）に開こうとすると失敗し、
/// アプリが落ちてしまう。ここでは落とさずに待ち、ロックが解けたら開き直す。ロック中でないのに開けない
/// （空き容量が無いなど）ときは、再試行できる画面を出す。黙って空の保存先で続けると、記録が消えたように見えるため。
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
    /// ロックが解けるのを待っているか。解けたら（`protectedDataMayBeAvailable()`）開き直す。
    @ObservationIgnored private(set) var isWaitingForProtectedData = false
    @ObservationIgnored private var hasStarted = false
    /// 開き直しの間、前の保存先を持っておく。画面のツリーを畳んだ後も、書き込み中の処理が前の保存先の
    /// ModelContext を使うため（保存先を手放した後の ModelContext は使えない）。書き込みが終わったら手放す。
    @ObservationIgnored private var retiringContainer: ModelContainer?
    @ObservationIgnored private var isFinishingReopening = false
    @ObservationIgnored private let openContainer: @MainActor (ModelContainerFactory.CloudKitDatabase) throws -> ModelContainer
    @ObservationIgnored private let isProtectedDataAvailable: @MainActor () -> Bool
    @ObservationIgnored private let announce: @MainActor (String) -> Void

    /// - Parameters:
    ///   - openContainer: 保存先を開く処理。テストでメモリの上の保存先や、失敗する処理に差し替える。
    ///   - isProtectedDataAvailable: 保護されたデータが読めるか（ロック中でないか）。テストで差し替える。
    ///   - announce: VoiceOver に読み上げさせる。テストで読み上げる文を集める。
    init(
        cloudKitDatabase: ModelContainerFactory.CloudKitDatabase = .none,
        openContainer: @escaping @MainActor (ModelContainerFactory.CloudKitDatabase) throws -> ModelContainer = {
            try ModelContainerFactory.makeContainer(cloudKitDatabase: $0)
        },
        isProtectedDataAvailable: @escaping @MainActor () -> Bool = { UIApplication.shared.isProtectedDataAvailable },
        announce: @escaping @MainActor (String) -> Void = { VoiceOver.announce($0) }
    ) {
        self.cloudKitDatabase = cloudKitDatabase
        self.openContainer = openContainer
        self.isProtectedDataAvailable = isProtectedDataAvailable
        self.announce = announce
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

    /// iCloud の扱いを変えて保存先を開き直す（iCloud の切り替えで使う予定。いまの呼び出し元はテストだけ）。
    ///
    /// 同じファイルを 2 つの保存先で同時に開かないよう、先に `.reopening` にして、前の保存先を使う画面のツリー
    /// （その中の @Query や ModelContext）を畳む。畳み終えたら `StoreRootView` が `finishReopening()` を呼び、
    /// 書き込み中の処理（`pendingWrites`）が終わるのを待って、前の保存先を手放してから新しい保存先を開く。
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

    /// `.reopening` の画面が出た（前の画面のツリーが畳まれた）あとに呼ぶ。書き込み中の処理が終わるまで待つ。
    func finishReopening() async {
        guard case .reopening = state, !isFinishingReopening else { return }
        isFinishingReopening = true
        defer { isFinishingReopening = false }
        await pendingWrites.waitUntilIdle()
        retiringContainer = nil
        guard case .reopening = state else { return }
        open()
    }

    private func open() {
        guard isProtectedDataAvailable() else {
            // 開こうとしても読めない。ロックが解けるまで待つ（画面はいまの状態のまま）。
            isWaitingForProtectedData = true
            return
        }
        do {
            let container = try openContainer(cloudKitDatabase)
            isWaitingForProtectedData = false
            failedRetryCount = 0
            state = .ready(container)
        } catch {
            if isProtectedDataAvailable() {
                isWaitingForProtectedData = false
                state = .unavailable(error)
            } else {
                // 開いている途中でロックされた。ロックが解けたら開き直す。
                isWaitingForProtectedData = true
            }
        }
    }
}
