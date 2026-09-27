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

    static let aiEntry = ParsedEntry(amount: 3_000, category: .food, memo: "AI")
    static let ruleEntry = ParsedEntry(amount: 12_000, category: .food, memo: "ルール")

    func parser(primary: Result<[ParsedEntry], any Error>) -> FallbackEntryParser {
        FallbackEntryParser(
            primary: StubParser(result: primary),
            fallback: StubParser(result: .success([Self.ruleEntry]))
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
}
