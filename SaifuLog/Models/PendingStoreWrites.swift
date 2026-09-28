/// 画面から始めて、あとで保存先に書き込む処理（解析を待ってから記録するなど）の数。
///
/// 保存先を開き直すとき（`StoreHost.reopen(cloudKitDatabase:)`）は、画面のツリーを畳んでも、送信の解析を
/// 待っている Task は前の保存先の ModelContext を持ったまま動き続ける。そのまま新しい保存先を開くと、
/// 前の保存先への書き込みが新しい保存先を開いた後に走り、同じファイルを 2 つの保存先で同時に開くことになる。
/// そこで、そうした処理を始めるときに `begin()`、終えたら `end()` を呼んでもらい、開き直しは
/// `waitUntilIdle()` で全部が終わるのを待ってから新しい保存先を開く。
///
/// 同期的に書き込む処理（取り消し・削除）は、開き直しと入れ替わりに走ることがないので数えない。
@MainActor
final class PendingStoreWrites {
    /// 終わっていない処理の数。
    private(set) var count = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// 処理を始める。Task を作る前に（同じ同期の呼び出しの中で）呼ぶ。Task の中で呼ぶと、Task が走り出す前に
    /// 開き直しが始まったとき、待たずに開いてしまうため。
    func begin() {
        count += 1
    }

    /// 処理を終えた（成功・失敗のどちらでも）。`begin()` と必ず対にする（defer で呼ぶ）。
    func end() {
        // 対になっていないのは作りの誤り。利用者の手元では落とさず、数を負にしないだけにする。
        guard count > 0 else {
            assertionFailure("begin() と対になっていない end()")
            return
        }
        count -= 1
        guard count == 0 else { return }
        let resumed = waiters
        waiters = []
        for waiter in resumed {
            waiter.resume()
        }
    }

    /// 終わっていない処理が無くなるまで待つ。無ければすぐに戻る。
    func waitUntilIdle() async {
        guard count > 0 else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}
