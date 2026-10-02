import Foundation
import Testing
@testable import SaifuLogCore

@Suite("AI からルールベースへの切り替え")
struct FallbackEntryParserTests {
    struct StubError: Error {}

    struct StubParser: EntryParsing {
        let result: Result<[ParsedEntry], any Error>

        func parse(_ text: String) async throws -> [ParsedEntry] {
            try result.get()
        }
    }

    /// `onFallback` に渡された理由を集める。呼ばれるのは `parse` の Task の上だが、`@Sendable` の決まりに合わせて錠で守る
    /// （コアの下限の macOS 14 では Synchronization の Mutex が使えないので NSLock）。
    final class FallbackRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [AIFallbackReason] = []

        func record(_ reason: AIFallbackReason) {
            lock.withLock { recorded.append(reason) }
        }

        var reasons: [AIFallbackReason] {
            lock.withLock { recorded }
        }
    }

    static let aiEntry = ParsedEntry(amount: 3_000, category: .food, memo: "AI")
    static let ruleEntry = ParsedEntry(amount: 12_000, category: .food, memo: "ルール")

    func parser(
        primary: Result<[ParsedEntry], any Error>, fallback: [ParsedEntry] = [FallbackEntryParserTests.ruleEntry], recorder: FallbackRecorder? = nil
    ) -> FallbackEntryParser {
        FallbackEntryParser(
            primary: StubParser(result: primary),
            fallback: StubParser(result: .success(fallback)),
            onFallback: { recorder?.record($0) }
        )
    }

    @Test("AI が読めたらその結果を使う")
    func usesPrimary() async throws {
        let entries = try await parser(primary: .success([Self.aiEntry])).parse("焼肉")
        #expect(entries == [Self.aiEntry])
    }

    @Test("AI が失敗したらルールベースで読み直す")
    func fallsBackOnError() async throws {
        let entries = try await parser(primary: .failure(StubError())).parse("焼肉")
        #expect(entries == [Self.ruleEntry])
    }

    @Test("AI が何も読めなかったらルールベースで読み直す")
    func fallsBackOnEmpty() async throws {
        let entries = try await parser(primary: .success([])).parse("焼肉")
        #expect(entries == [Self.ruleEntry])
    }

    @Test("取り消しは読み直さずにそのまま伝える")
    func propagatesCancellation() async {
        await #expect(throws: CancellationError.self) {
            try await parser(primary: .failure(CancellationError())).parse("焼肉")
        }
    }

    // MARK: - 読み直しの知らせ

    @Test("AI が失敗したら、そのエラーを知らせてからルールベースの結果を返す")
    func reportsPrimaryError() async throws {
        let recorder = FallbackRecorder()

        let entries = try await parser(primary: .failure(StubError()), recorder: recorder).parse("焼肉")

        #expect(entries == [Self.ruleEntry])
        #expect(recorder.reasons.count == 1)
        guard case .failed(let error) = try #require(recorder.reasons.first) else {
            Issue.record("失敗として知らせていない: \(recorder.reasons)")
            return
        }
        #expect(error is StubError)
    }

    @Test("AI が何も読めなかったら、結果が無かったと知らせる")
    func reportsEmptyResult() async throws {
        let recorder = FallbackRecorder()

        let entries = try await parser(primary: .success([]), recorder: recorder).parse("焼肉")

        #expect(entries == [Self.ruleEntry])
        #expect(recorder.reasons.count == 1)
        guard case .noResult = try #require(recorder.reasons.first) else {
            Issue.record("結果が無かったと知らせていない: \(recorder.reasons)")
            return
        }
    }

    /// 金額の無い文など。AI の経路はモデルに渡さずに 0 件を返すので、AI が読み落としたことにしない。
    @Test("AI もルールベースも読めなければ知らせない")
    func doesNotReportWhenNeitherReads() async throws {
        let recorder = FallbackRecorder()

        let entries = try await parser(primary: .success([]), fallback: [], recorder: recorder).parse("ランチ")

        #expect(entries.isEmpty)
        #expect(recorder.reasons.isEmpty)
    }

    @Test("AI が失敗したら、ルールベースも読めなくても知らせる")
    func reportsErrorEvenWhenFallbackReadsNothing() async throws {
        let recorder = FallbackRecorder()

        let entries = try await parser(primary: .failure(StubError()), fallback: [], recorder: recorder).parse("ランチ")

        #expect(entries.isEmpty)
        #expect(recorder.reasons.count == 1)
    }

    @Test("AI が読めたときと取り消しは知らせない")
    func doesNotReportSuccessOrCancellation() async throws {
        let recorder = FallbackRecorder()

        _ = try await parser(primary: .success([Self.aiEntry]), recorder: recorder).parse("焼肉")
        await #expect(throws: CancellationError.self) {
            try await parser(primary: .failure(CancellationError()), recorder: recorder).parse("焼肉")
        }

        #expect(recorder.reasons.isEmpty)
    }

    // MARK: - 上限の時間

    /// 返らないまま止まった AI の代わり。取り消しに応じず、10 秒たつまで返らない。始めたことを `started` に知らせる。
    struct HangingParser: EntryParsing {
        var started: AsyncStream<Void>.Continuation?

        func parse(_ text: String) async throws -> [ParsedEntry] {
            started?.yield()
            await sleepIgnoringCancellation(seconds: 10)
            return [FallbackEntryParserTests.aiEntry]
        }
    }

    /// 読み取りが終わらないと、次の文を送れず、保存先の開き直しも待ち続ける。
    @Test("AI が上限の時間までに返らなければ、終わるのを待たずにルールベースで読み、時間切れを知らせる")
    func fallsBackOnTimeout() async throws {
        let recorder = FallbackRecorder()
        let parser = FallbackEntryParser(
            primary: HangingParser(), fallback: StubParser(result: .success([Self.ruleEntry])),
            timeout: .milliseconds(200), onFallback: { recorder.record($0) }
        )
        let clock = ContinuousClock()
        let start = clock.now

        let entries = try await parser.parse("焼肉")

        // 止まった AI（10 秒）を待っていないことが分かればよいので、テストを動かす端末の混み具合で揺れないよう大きく取る。
        #expect(start.duration(to: clock.now) < .seconds(5))
        #expect(entries == [Self.ruleEntry])
        #expect(recorder.reasons.count == 1)
        guard case .timedOut(let timeout) = try #require(recorder.reasons.first) else {
            Issue.record("時間切れとして知らせていない: \(recorder.reasons)")
            return
        }
        #expect(timeout == .milliseconds(200))
    }

    @Test("上限があっても、AI が上限までに読めたらその結果を使い、何も知らせない")
    func usesPrimaryWithinTimeout() async throws {
        let recorder = FallbackRecorder()
        let parser = FallbackEntryParser(
            primary: StubParser(result: .success([Self.aiEntry])), fallback: StubParser(result: .success([Self.ruleEntry])),
            timeout: .seconds(10), onFallback: { recorder.record($0) }
        )

        let entries = try await parser.parse("焼肉")

        #expect(entries == [Self.aiEntry])
        #expect(recorder.reasons.isEmpty)
    }

    @Test("上限があっても、上限までに AI が失敗したら、時間切れではなく失敗として知らせる")
    func reportsFailureWithinTimeout() async throws {
        let recorder = FallbackRecorder()
        let parser = FallbackEntryParser(
            primary: StubParser(result: .failure(StubError())), fallback: StubParser(result: .success([Self.ruleEntry])),
            timeout: .seconds(10), onFallback: { recorder.record($0) }
        )

        let entries = try await parser.parse("焼肉")

        #expect(entries == [Self.ruleEntry])
        guard case .failed(let error) = try #require(recorder.reasons.first) else {
            Issue.record("失敗として知らせていない: \(recorder.reasons)")
            return
        }
        #expect(error is StubError)
    }

    /// 取り消しを時間切れや失敗と取り違えると、取り消した送信をルールベースで読み直して記録してしまう。
    @Test("AI を待つ間に取り消されたら、時間切れにも読み直しにもせず、取り消しを伝える")
    func cancellationWhileWaitingIsNotTimeout() async {
        let recorder = FallbackRecorder()
        let (started, startedContinuation) = AsyncStream.makeStream(of: Void.self)
        let parser = FallbackEntryParser(
            primary: HangingParser(started: startedContinuation), fallback: StubParser(result: .success([Self.ruleEntry])),
            timeout: .seconds(30), onFallback: { recorder.record($0) }
        )
        let task = Task { try await parser.parse("焼肉") }
        for await _ in started { break }

        task.cancel()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(recorder.reasons.isEmpty)
    }
}
