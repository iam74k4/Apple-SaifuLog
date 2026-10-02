import Foundation

/// `withDeadline` の処理が、上限の時間までに終わらなかった。
public struct DeadlineExceeded: Error, Equatable, Sendable {
    /// 待った上限。
    public let timeout: Duration

    public init(timeout: Duration) {
        self.timeout = timeout
    }
}

/// `operation` の結果を、上限の時間（`timeout`）まで待つ。
///
/// - 上限までに終われば、その値を返す（`operation` が投げたエラーはそのまま投げる）。
/// - 上限を過ぎたら、`operation` に取り消しを伝え、終わるのを待たずに `DeadlineExceeded` を投げる。
/// - 呼び出した Task が取り消されたら、`operation` に取り消しを伝え、終わるのを待たずに `CancellationError` を投げる。
///   時間切れや `operation` の失敗と入れ違いに取り消されたときも、取り消しにする。呼び出し側が取り消しを時間切れや AI の失敗と
///   取り違えて、ルールベースで読み直して記録したりしないように。取り消し済みの Task からは `operation` を始めない。
///
/// 端末内 AI の生成が返らないまま止まったときに、画面（読み取り中は送信できない）と保存先の開き直し（書き込み中の処理を待つ）が
/// 待ち続けないための上限に使う（docs/design.md §4-2）。
///
/// `operation` は呼び出した Task の子にせず、別の Task で動かす。子にすると（`withTaskGroup` など）、取り消しを伝えても、
/// 取り消しに応じずに止まっている子が終わるまで抜けられないため。そのため `operation` は呼び出し側の actor の外で動き、
/// 時間切れや取り消しの後も、取り消しに応じるまで動き続けることがある（その結果は捨てる）。
public func withDeadline<T: Sendable>(
    _ timeout: Duration,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    let race = DeadlineRace<T>()
    let outcome = await withTaskCancellationHandler {
        await withCheckedContinuation { continuation in
            race.start(continuation, timeout: timeout, operation: operation)
        }
    } onCancel: {
        race.finish(.failure(CancellationError()))
    }
    switch outcome {
    case .success(let value):
        return value
    case .failure(let error):
        // 時間切れか `operation` の失敗が、呼び出した Task の取り消しと入れ違いに先に届いたときも、取り消しとして伝える。
        try Task.checkCancellation()
        throw error
    }
}

/// `withDeadline` の、処理の終わり・時間切れ・取り消しのうち最初に届いたもので、待っている呼び出し側を 1 回だけ再開する。
///
/// 3 つは別々のスレッドから同時に届きうるので、状態は錠の中でだけ読み書きする。コアの下限の macOS 14 では
/// Synchronization の Mutex が使えないので NSLock にし、状態をすべて錠で守ることで Sendable とする（@unchecked）。
private final class DeadlineRace<T: Sendable>: @unchecked Sendable {
    typealias Waiter = CheckedContinuation<Result<T, any Error>, Never>

    private let lock = NSLock()
    /// 待っている呼び出し側。再開したら nil にする。
    private var waiter: Waiter?
    /// 最初に届いた結果。決まった後に届いたもの（時間切れの後に終わった処理など）は捨てる。
    private var outcome: Result<T, any Error>?
    /// 処理と時計。結果が決まったら取り消す（処理には取り消しを伝え、時計は止める）。
    private var tasks: [Task<Void, Never>] = []

    /// 処理と時計を始める。呼び出し側が待ち始めたとき（`withCheckedContinuation` の中）に呼ぶ。
    func start(_ waiter: Waiter, timeout: Duration, operation: @escaping @Sendable () async throws -> T) {
        let early = lock.withLock { () -> Result<T, any Error>? in
            if outcome == nil { self.waiter = waiter }
            return outcome
        }
        // 待ち始める前に取り消されていた（`withTaskCancellationHandler` は、取り消し済みの Task では本体より先に onCancel を
        // 呼ぶ）。処理は始めない。
        if let early {
            waiter.resume(returning: early)
            return
        }
        let work = Task {
            let result: Result<T, any Error>
            do {
                result = .success(try await operation())
            } catch {
                result = .failure(error)
            }
            self.finish(result)
        }
        let timer = Task {
            do {
                try await Task.sleep(for: timeout)
            } catch {
                // 先に結果が決まって止められた。時間切れにしない。
                return
            }
            self.finish(.failure(DeadlineExceeded(timeout: timeout)))
        }
        let isDecided = lock.withLock { () -> Bool in
            if outcome == nil { tasks = [work, timer] }
            return outcome != nil
        }
        // 覚える前に結果が決まっていた（処理がすぐ終わった・その間に取り消された）。止められなかったほうを、ここで止める。
        if isDecided {
            work.cancel()
            timer.cancel()
        }
    }

    /// 結果を決める。最初の 1 回だけが効く。
    func finish(_ result: Result<T, any Error>) {
        let decided = lock.withLock { () -> (waiter: Waiter?, tasks: [Task<Void, Never>])? in
            guard outcome == nil else { return nil }
            outcome = result
            defer {
                waiter = nil
                tasks = []
            }
            return (waiter, tasks)
        }
        guard let decided else { return }
        for task in decided.tasks {
            task.cancel()
        }
        decided.waiter?.resume(returning: result)
    }
}
