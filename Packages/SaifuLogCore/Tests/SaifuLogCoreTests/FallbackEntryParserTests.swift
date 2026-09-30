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

    func parser(primary: Result<[ParsedEntry], any Error>, recorder: FallbackRecorder? = nil) -> FallbackEntryParser {
        FallbackEntryParser(
            primary: StubParser(result: primary),
            fallback: StubParser(result: .success([Self.ruleEntry])),
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

    @Test("AI が読めたときと取り消しは知らせない")
    func doesNotReportSuccessOrCancellation() async throws {
        let recorder = FallbackRecorder()

        _ = try await parser(primary: .success([Self.aiEntry]), recorder: recorder).parse("焼肉")
        await #expect(throws: CancellationError.self) {
            try await parser(primary: .failure(CancellationError()), recorder: recorder).parse("焼肉")
        }

        #expect(recorder.reasons.isEmpty)
    }
}
