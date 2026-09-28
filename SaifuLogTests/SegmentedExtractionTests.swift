import Foundation
import SaifuLogCore
import Testing
@testable import SaifuLog

/// AI の経路で、区間ごとに 1 件ずつモデルに読ませ、入力全体とまとめて突き合わせること。
///
/// 以前は 1 回の生成で記録の配列を返させていたため、「コーヒー 400」1 回で同じ ¥400 が何件も保存されることがあった。
/// モデルの代わりに、読ませた区間の文字列を覚えて、区間ごとに決めた答えを返す偽物を使う。
struct SegmentedExtractionTests {
    /// モデルの代わり。読ませた区間の文字列を順に覚える。答えを決めていない区間を読ませたら throw する。
    actor FakeModel {
        private(set) var prompts: [String] = []
        private let answers: [String: ExtractedEntry]
        /// 最初の件を読んだところで、呼び出し元のタスクを取り消す（画面を閉じた、の代わり）。
        private let cancelsAfterFirst: Bool

        init(_ answers: [String: ExtractedEntry], cancelsAfterFirst: Bool = false) {
            self.answers = answers
            self.cancelsAfterFirst = cancelsAfterFirst
        }

        func extract(_ segment: InputSegment) throws -> ExtractedEntry {
            prompts.append(segment.text)
            if cancelsAfterFirst {
                withUnsafeCurrentTask { $0?.cancel() }
            }
            guard let answer = answers[segment.text] else { throw TestError() }
            return answer
        }
    }

    static func answer(
        _ item: String, _ amount: String, _ category: EntryCategory = .other,
        isIncome: Bool = false, date: String = ""
    ) -> ExtractedEntry {
        ExtractedEntry(
            item: item, amountText: amount, categoryName: category.displayName,
            isIncome: isIncome, splitCount: 1, dateText: date
        )
    }

    func parse(_ text: String, with model: FakeModel) async throws -> [ParsedEntry] {
        try await SegmentedExtraction.entries(from: text, now: TestSupport.now, calendar: TestSupport.calendar) {
            try await model.extract($0)
        }
    }

    /// 1 件の入力では、モデルに 1 回だけ読ませて 1 件だけ保存する。
    @Test func singleEntryIsGeneratedOnce() async throws {
        let model = FakeModel(["コーヒー 400": Self.answer("コーヒー", "400", .cafe)])

        let entries = try await parse("コーヒー 400", with: model)

        #expect(await model.prompts == ["コーヒー 400"])
        #expect(entries == [ParsedEntry(amount: 400, category: .cafe, memo: "コーヒー")])
    }

    /// 複数件は、コードで分けた区間ごとに 1 回ずつ読ませる。先頭の日付は後ろの件にもかかる。
    @Test func eachSegmentIsGeneratedSeparately() async throws {
        let model = FakeModel([
            "昨日 スーパー2480": Self.answer("スーパー", "2480", .food, date: "昨日"),
            "ドラッグ1200": Self.answer("ドラッグ", "1200", .daily),
        ])

        let entries = try await parse("昨日 スーパー2480とドラッグ1200", with: model)

        #expect(await model.prompts == ["昨日 スーパー2480", "ドラッグ1200"])
        #expect(entries == [
            ParsedEntry(amount: 2_480, category: .food, memo: "スーパー", daysAgo: 1),
            ParsedEntry(amount: 1_200, category: .daily, memo: "ドラッグ", daysAgo: 1),
        ])
    }

    /// 割り勘の人数はモデルに尋ねず、入力のその件にかかる人数で割る。
    @Test func splitComesFromInput() async throws {
        let model = FakeModel([
            "昨日 焼肉12000 4人で割り勘": Self.answer("焼肉", "12000", .food, date: "昨日"),
        ])

        let entries = try await parse("昨日 焼肉12000 4人で割り勘", with: model)

        #expect(entries == [ParsedEntry(
            amount: 3_000, category: .food, memo: "焼肉（4人で割り勘・総額 ¥12,000・立替 ¥9,000）",
            daysAgo: 1, splitCount: 4
        )])
    }

    /// 金額の無い入力では、モデルを呼ばずに空を返す（呼び出し側がルールベースで読み直す）。
    @Test func noAmountSkipsModel() async throws {
        let model = FakeModel([:])

        let entries = try await parse("ランチ", with: model)

        #expect(entries.isEmpty)
        #expect(await model.prompts.isEmpty)
    }

    /// どれか 1 件でも金額がその件の区間に無ければ throw する（同じ金額の繰り返し・計算した値）。
    /// 呼び出し側（FallbackEntryParser）が入力全体をルールベースで読み直す。
    @Test(arguments: ["2480", "3680"])
    func ungroundedSegmentThrows(secondAmount: String) async {
        let model = FakeModel([
            "スーパー2480": Self.answer("スーパー", "2480", .food),
            "ドラッグ1200": Self.answer("ドラッグ", secondAmount, .daily),
        ])

        await #expect(throws: ExtractedEntry.ResolveError.ungroundedAmount) {
            try await parse("スーパー2480とドラッグ1200", with: model)
        }
    }

    /// AI で読めなかったときは、FallbackEntryParser がルールベースで読み直し、記録そのものはできる。
    @Test func fallsBackToRulesWhenAIResultIsRejected() async throws {
        let model = FakeModel(["コーヒー 400": Self.answer("コーヒー", "4000", .cafe)])
        let parser = FallbackEntryParser(
            primary: StubParser { try await parse($0, with: model) },
            fallback: RuleBasedParser()
        )

        let entries = try await parser.parse("コーヒー 400")

        #expect(entries.map(\.amount) == [400])
    }

    /// 取り消された（画面を閉じたなど）あとは、残りの件をモデルに読ませない。
    @Test func cancellationStopsRemainingSegments() async {
        let model = FakeModel([
            "スーパー2480": Self.answer("スーパー", "2480", .food),
            "ドラッグ1200": Self.answer("ドラッグ", "1200", .daily),
        ], cancelsAfterFirst: true)

        let task = Task { try await parse("スーパー2480とドラッグ1200", with: model) }
        let result = await task.result

        #expect(throws: CancellationError.self) { try result.get() }
        #expect(await model.prompts == ["スーパー2480"])
    }
}

/// 読み方を差し替えられる解析器（FallbackEntryParser に AI の代わりとして渡す）。
private struct StubParser: EntryParsing {
    let body: @Sendable (String) async throws -> [ParsedEntry]

    init(_ body: @escaping @Sendable (String) async throws -> [ParsedEntry]) {
        self.body = body
    }

    func parse(_ text: String) async throws -> [ParsedEntry] {
        try await body(text)
    }
}
