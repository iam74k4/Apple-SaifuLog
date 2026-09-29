import Foundation
import Network

/// いまの回線が、大きなダウンロードを気にしたほうがよい回線かを調べる（Network の NWPathMonitor）。
///
/// 書き起こしのモデルは端末に入れる大きなファイルで、Apple のサーバーからダウンロードする。モバイル回線（インターネット共有を
/// 含む）か低データモードなら、ダウンロードの前の確認で Wi‑Fi をすすめる。調べるのは回線の種類だけで、どこにも送らない。
struct SystemNetworkCost: NetworkCostChecking {
    func isExpensive() async -> Bool {
        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "SaifuLog.NetworkCost")
        let path = await withCheckedContinuation { (continuation: CheckedContinuation<NWPath, Never>) in
            // 最初の知らせ（いまの回線）だけを受け取る。
            let once = OnceFlag()
            monitor.pathUpdateHandler = { path in
                guard once.claim() else { return }
                continuation.resume(returning: path)
            }
            monitor.start(queue: queue)
        }
        monitor.cancel()
        return path.isExpensive || path.isConstrained
    }
}

/// 1 回だけ通す印（知らせが続けて来ても、続きを 1 回だけ再開するため）。
private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.withLock {
            defer { claimed = true }
            return !claimed
        }
    }
}
