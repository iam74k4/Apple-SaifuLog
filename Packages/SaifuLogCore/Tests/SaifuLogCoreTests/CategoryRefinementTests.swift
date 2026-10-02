import Foundation
import Testing
@testable import SaifuLogCore

@Suite("カテゴリの聞き直し（端末内 AI）")
struct CategoryRefinementTests {
    /// 聞かれた品目と、AI の結果を使わなかった理由を残す（別の Task から呼ばれるので錠で守る）。
    final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var askedItems: [String] = []
        private var reasonNames: [String] = []

        var items: [String] { lock.withLock { askedItems } }
        var reasons: [String] { lock.withLock { reasonNames } }

        func ask(_ item: String) {
            lock.withLock { askedItems.append(item) }
        }

        func report(_ reason: AIFallbackReason) {
            let name = switch reason {
            case .failed: "failed"
            case .timedOut: "timedOut"
            case .noResult: "noResult"
            }
            lock.withLock { reasonNames.append(name) }
        }
    }

    struct Failure: Error {}

    /// 決めた答えを返す AI の代わり。品目ごとに答え・遅れ・失敗を決める。
    struct StubClassifier: ItemCategoryClassifying {
        var answers: [String: String] = [:]
        var delays: [String: Duration] = [:]
        var failing: Set<String> = []
        let log: Log

        func categoryName(for item: String) async throws -> String {
            log.ask(item)
            if let delay = delays[item] { try await Task.sleep(for: delay) }
            if failing.contains(item) { throw Failure() }
            return answers[item] ?? "その他"
        }
    }

    private static func expense(_ memo: String, _ amount: Int = 500, _ category: EntryCategory = .other) -> ParsedEntry {
        ParsedEntry(amount: amount, category: category, memo: memo)
    }

    // MARK: - 聞き直す記録

    @Test("聞き直すのは、返事で聞き返す記録と同じ（その他の支出で、辞書にも覚えにも当たらず、品目があるもの）")
    func requestsMatchCategoryQuestions() {
        // 「その他のまま」を選んで覚えた言葉。
        let memory = CategoryMemory.resolve([CategoryMemoryTests.Row("家賃", .other)])
        let entries = [
            Self.expense("ジンギスカン"),
            Self.expense("ランチ", 850, .food),
            ParsedEntry(amount: 3_000, category: .other, isIncome: true, memo: "臨時収入"),
            Self.expense("家賃", 80_000),
            Self.expense("洋服", 4_000),
            Self.expense(""),
            // 割り勘の説明は渡さず、品目だけを渡す。
            Self.expense("ジンギスカン（4人で割り勘・総額 ¥12,000・立替 ¥9,000）", 3_000),
        ]

        let requests = CategoryRefinement.requests(for: entries, memory: memory)

        #expect(requests == [
            .init(index: 0, item: "ジンギスカン"),
            .init(index: 6, item: "ジンギスカン"),
        ])
    }

    @Test("作ったカテゴリの名前が書かれた品目は聞き直さない")
    func skipsCustomCategoryNames() {
        let catalog = CategoryCatalog(customs: [CustomCategoryInfo(id: "clothes", name: "衣服", symbolName: "tshirt", colorIndex: 0)])

        let requests = CategoryRefinement.requests(for: [Self.expense("衣服 セール")], memory: CategoryMemory(), catalog: catalog)

        #expect(requests.isEmpty)
    }

    // MARK: - 答えの当て方

    @Test("組み込みのカテゴリの表示名で、その他でない答えだけを当てる")
    func appliesOnlyUsefulAnswers() {
        let entries = [Self.expense("a"), Self.expense("b"), Self.expense("c"), Self.expense("d")]

        let applied = CategoryRefinement.applying([0: "食費", 1: "その他", 2: "家賃", 9: "交通"], to: entries)

        #expect(applied.map(\.category) == [.food, .other, .other, .other])
    }

    // MARK: - 聞き方

    @Test("AI が選んだカテゴリで記録し、その他を選んだ品目はそのまま（返事で聞き返す）")
    func refinesWithClassifier() async throws {
        let log = Log()
        let classifier = StubClassifier(answers: ["ジンギスカン": "食費", "なぞの品": "その他"], log: log)
        let entries = [Self.expense("ジンギスカン"), Self.expense("なぞの品"), Self.expense("ランチ", 850, .food)]

        let refined = try await CategoryRefinement.refine(
            entries, memory: CategoryMemory(), classifier: classifier, timeout: .seconds(5), onFallback: log.report
        )

        #expect(refined.map(\.category) == [.food, .other, .food])
        // 辞書で決まった品目は聞かない。AI がその他を選んだのは、AI の結果を使わなかったことにしない（答えはあった）。
        #expect(log.items == ["ジンギスカン", "なぞの品"])
        #expect(log.reasons.isEmpty)
    }

    @Test("聞き直す記録が無ければ、AI を呼ばない")
    func doesNotCallClassifierWithoutRequests() async throws {
        let log = Log()
        let entries = [Self.expense("ランチ", 850, .food), ParsedEntry(amount: 250_000, category: .other, isIncome: true, memo: "給料")]

        let refined = try await CategoryRefinement.refine(
            entries, memory: CategoryMemory(), classifier: StubClassifier(log: log), timeout: .seconds(5)
        )

        #expect(refined == entries)
        #expect(log.items.isEmpty)
    }

    @Test("聞けなかった品目はその他のまま、ほかの品目は聞く。失敗を知らせる")
    func failureLeavesOtherItems() async throws {
        let log = Log()
        let classifier = StubClassifier(answers: ["b": "交通"], failing: ["a"], log: log)

        let refined = try await CategoryRefinement.refine(
            [Self.expense("a"), Self.expense("b")], memory: CategoryMemory(), classifier: classifier, timeout: .seconds(5),
            onFallback: log.report
        )

        #expect(refined.map(\.category) == [.other, .transport])
        #expect(log.reasons == ["failed"])
    }

    // 上限は、すぐ返る 1 件目が並んで動くほかのテストに押されても間に合う長さにする（CI で 0.3 秒にしたら、1 件目まで
    // 間に合わずに落ちた）。止まる 2 件目は上限よりずっと長く止め、待たずに戻ることを確かめる。
    @Test("全体の上限を過ぎたら待たずに、間に合った答えだけを使う。時間切れを知らせる")
    func timeoutKeepsAnswersInTime() async throws {
        let log = Log()
        let classifier = StubClassifier(answers: ["a": "カフェ", "b": "交通"], delays: ["b": .seconds(120)], log: log)
        let clock = ContinuousClock()
        let start = clock.now

        let refined = try await CategoryRefinement.refine(
            [Self.expense("a"), Self.expense("b"), Self.expense("c")], memory: CategoryMemory(), classifier: classifier,
            timeout: .seconds(3), onFallback: log.report
        )

        #expect(refined.map(\.category) == [.cafe, .other, .other])
        // 止まった品目の後ろは聞かない。止まった AI が終わるのも待たない。
        #expect(log.items == ["a", "b"])
        #expect(log.reasons == ["timedOut"])
        #expect(start.duration(to: clock.now) < .seconds(60))
    }

    @Test("呼び出した Task が取り消されたら、取り消しとして投げる（記録しない）")
    func cancellationThrows() async {
        let log = Log()
        let classifier = StubClassifier(delays: ["a": .seconds(30)], log: log)
        let task = Task {
            try await CategoryRefinement.refine(
                [Self.expense("a")], memory: CategoryMemory(), classifier: classifier, timeout: .seconds(20), onFallback: log.report
            )
        }
        try? await Task.sleep(for: .milliseconds(100))
        task.cancel()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(log.reasons.isEmpty)
    }
}
