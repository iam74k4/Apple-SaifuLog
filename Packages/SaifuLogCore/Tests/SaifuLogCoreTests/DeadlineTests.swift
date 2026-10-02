import Foundation
import Testing
@testable import SaifuLogCore

/// 返らないまま止まった処理（端末内 AI の生成）の代わり。取り消されても `seconds` 秒たつまで返らない。
func sleepIgnoringCancellation(seconds: Double) async {
    await withCheckedContinuation { continuation in
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { continuation.resume() }
    }
}

@Suite("上限の時間まで待つ（withDeadline）")
struct DeadlineTests {
    struct StubError: Error {}

    /// 処理が始まったか・処理に取り消しが伝わったかの印。取り消しの知らせは別のスレッドから届くので錠で守る
    /// （コアの下限の macOS 14 では Synchronization の Mutex が使えないので NSLock）。
    final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false

        func set() {
            lock.withLock { value = true }
        }

        var isSet: Bool {
            lock.withLock { value }
        }
    }

    static let clock = ContinuousClock()

    /// 時間切れ・取り消しで抜けるまでの時間の上限。止まった処理（10 秒）を待っていないことが分かればよいので、テストを動かす
    /// 端末の混み具合で揺れないよう、上限の時間（0.2 秒）より十分に長く取る。
    static let promptly: Duration = .seconds(5)

    @Test("上限までに終われば、その値を返す")
    func returnsValueBeforeDeadline() async throws {
        let value = try await withDeadline(.seconds(10)) { 42 }

        #expect(value == 42)
    }

    @Test("処理が投げたエラーは、そのまま投げる")
    func rethrowsOperationError() async {
        await #expect(throws: StubError.self) {
            try await withDeadline(.seconds(10)) { () throws -> Int in throw StubError() }
        }
    }

    /// モデルが取り消しに応じずに止まっていても、上限で抜ける（終わるのを待たない）。
    @Test("上限を過ぎたら、処理が終わるのを待たずに時間切れを投げ、処理に取り消しを伝える")
    func timesOutWithoutWaitingForOperation() async {
        let cancelled = Flag()
        let start = Self.clock.now

        await #expect(throws: DeadlineExceeded(timeout: .milliseconds(200))) {
            try await withDeadline(.milliseconds(200)) {
                await withTaskCancellationHandler {
                    await sleepIgnoringCancellation(seconds: 10)
                } onCancel: {
                    cancelled.set()
                }
                return 1
            }
        }

        #expect(start.duration(to: Self.clock.now) < Self.promptly)
        #expect(cancelled.isSet)
    }

    /// 取り消しを時間切れと取り違えると、呼び出し側がルールベースで読み直して記録してしまう。
    @Test("呼び出した Task が取り消されたら、処理が終わるのを待たずに取り消しを投げ（時間切れにしない）、処理に取り消しを伝える")
    func outerCancellationThrowsCancellationError() async {
        let cancelled = Flag()
        let (started, startedContinuation) = AsyncStream.makeStream(of: Void.self)
        let task = Task {
            try await withDeadline(.seconds(30)) {
                await withTaskCancellationHandler {
                    startedContinuation.yield()
                    await sleepIgnoringCancellation(seconds: 10)
                } onCancel: {
                    cancelled.set()
                }
                return 1
            }
        }
        for await _ in started { break }
        let start = Self.clock.now

        task.cancel()
        let result = await task.result

        #expect(start.duration(to: Self.clock.now) < Self.promptly)
        #expect(throws: CancellationError.self) { try result.get() }
        #expect(cancelled.isSet)
    }

    @Test("取り消し済みの Task からは、処理を始めずに取り消しを投げる")
    func doesNotStartWhenAlreadyCancelled() async {
        let started = Flag()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await withDeadline(.seconds(10)) {
                started.set()
                return 1
            }
        }

        let result = await task.result

        #expect(throws: CancellationError.self) { try result.get() }
        #expect(!started.isSet)
    }
}
