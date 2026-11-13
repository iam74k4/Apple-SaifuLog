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

    final class ChoicesLog: @unchecked Sendable {
        private let lock = NSLock()
        private var all: [[String]] = []
        var choices: [[String]] { lock.withLock { all } }
        func record(_ choices: [String]) { lock.withLock { all.append(choices) } }
    }

    static let clothes = CustomCategoryInfo(id: "clothes", name: "衣服", symbolName: "tshirt", colorIndex: 0)
    static let customCatalog = CategoryCatalog(customs: [clothes])

    /// 振り分けてから（`CategoryResolver`）聞き直す。
    private static func resolved(
        _ entries: [ParsedEntry], memory: CategoryMemory = CategoryMemory(), catalog: CategoryCatalog = .builtIn
    ) -> [CategoryResolver.Resolution] {
        CategoryResolver.resolve(entries, memory: memory, catalog: catalog)
    }

    /// 決めた答えを返す AI の代わり。品目ごとに答え・遅れ・失敗を決める。渡された選択肢を残す。
    struct StubClassifier: ItemCategoryClassifying {
        var answers: [String: String] = [:]
        var delays: [String: Duration] = [:]
        var failing: Set<String> = []
        let log: Log
        var choicesLog: ChoicesLog?

        func categoryName(for item: String, choices: [String]) async throws -> String {
            log.ask(item)
            choicesLog?.record(choices)
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

        let requests = CategoryRefinement.requests(for: Self.resolved(entries, memory: memory))

        #expect(requests == [
            .init(index: 0, item: "ジンギスカン"),
            .init(index: 6, item: "ジンギスカン"),
        ])
    }

    @Test("作ったカテゴリの名前が書かれた品目は聞き直さない")
    func skipsCustomCategoryNames() {
        let catalog = CategoryCatalog(customs: [CustomCategoryInfo(id: "clothes", name: "衣服", symbolName: "tshirt", colorIndex: 0)])

        let requests = CategoryRefinement.requests(for: Self.resolved([Self.expense("衣服 セール")], catalog: catalog), catalog: catalog)

        #expect(requests.isEmpty)
    }

    @Test("作ったカテゴリがあれば、読み取ったカテゴリで決まった記録も、作ったカテゴリの答えだけを使う聞き直しにする")
    func requestsCustomOnlyForParsedEntries() {
        let memory = CategoryMemory.resolve([CategoryMemoryTests.Row("靴", .daily)])
        let entries = [
            Self.expense("Tシャツ", 2_000, .daily),
            Self.expense("ジンギスカン"),
            Self.expense("靴", 5_000),
            Self.expense("洋服", 4_000),
            ParsedEntry(amount: 3_000, category: .other, isIncome: true, memo: "臨時収入"),
        ]

        let requests = CategoryRefinement.requests(for: Self.resolved(entries, memory: memory, catalog: Self.customCatalog), catalog: Self.customCatalog)

        #expect(requests == [
            .init(index: 0, item: "Tシャツ", acceptsBuiltIn: false),
            .init(index: 1, item: "ジンギスカン"),
            // 辞書の「その他」の語で「その他」にした品目は聞き返さないが、作ったカテゴリに当たるかは聞く。
            .init(index: 3, item: "洋服", acceptsBuiltIn: false),
        ])
    }

    @Test("作ったカテゴリが無ければ、読み取ったカテゴリで決まった記録は聞き直さない")
    func noCustomOnlyRequestsWithoutCustoms() {
        let requests = CategoryRefinement.requests(for: Self.resolved([Self.expense("Tシャツ", 2_000, .daily)]))

        #expect(requests.isEmpty)
    }

    // MARK: - 答えの当て方

    @Test("一覧のカテゴリの名前で、その他でない答えだけを当てる")
    func appliesOnlyUsefulAnswers() {
        let resolutions = Self.resolved([Self.expense("a"), Self.expense("b"), Self.expense("c"), Self.expense("d")])
        let requests = CategoryRefinement.requests(for: resolutions)

        let applied = CategoryRefinement.applying([0: "食費", 1: "その他", 2: "家賃", 9: "交通"], to: resolutions, requests: requests)

        #expect(applied.map(\.category) == [.food, .other, .other, .other])
    }

    @Test("作ったカテゴリの答えだけを使う聞き直しには、組み込みのカテゴリの答えを当てない")
    func customOnlyRequestIgnoresBuiltInAnswers() {
        let resolutions = Self.resolved([Self.expense("Tシャツ", 2_000, .daily), Self.expense("靴下", 500, .daily)], catalog: Self.customCatalog)
        let requests = CategoryRefinement.requests(for: resolutions, catalog: Self.customCatalog)

        let applied = CategoryRefinement.applying([0: "衣服", 1: "食費"], to: resolutions, requests: requests, catalog: Self.customCatalog)

        #expect(applied.map(\.category) == [Self.clothes.category, .daily])
    }

    @Test("選択肢は組み込みの表示名と作ったカテゴリの名前（その他が最後）")
    func choicesIncludeCustomCategories() {
        #expect(CategoryRefinement.choices(in: Self.customCatalog) == ["食費", "日用品", "交通", "カフェ", "娯楽", "光熱・通信", "医療", "衣服", "その他"])
    }

    // MARK: - 聞き方

    @Test("AI が選んだカテゴリで記録し、その他を選んだ品目はそのまま（返事で聞き返す）")
    func refinesWithClassifier() async throws {
        let log = Log()
        let classifier = StubClassifier(answers: ["ジンギスカン": "食費", "なぞの品": "その他"], log: log)
        let entries = [Self.expense("ジンギスカン"), Self.expense("なぞの品"), Self.expense("ランチ", 850, .food)]

        let refined = try await CategoryRefinement.refine(
            Self.resolved(entries), classifier: classifier, timeout: .seconds(5), onFallback: log.report
        )

        #expect(refined.map(\.category) == [.food, .other, .food])
        // 辞書で決まった品目は聞かない。AI がその他を選んだのは、AI の結果を使わなかったことにしない（答えはあった）。
        #expect(log.items == ["ジンギスカン", "なぞの品"])
        #expect(log.reasons.isEmpty)
    }

    @Test("その他のままの記録を先に聞き、作ったカテゴリを選択肢に渡す")
    func asksUnresolvedFirstWithCustomChoices() async throws {
        let log = Log()
        let choices = ChoicesLog()
        let classifier = StubClassifier(answers: ["Tシャツ": "衣服", "ジンギスカン": "食費"], log: log, choicesLog: choices)

        let refined = try await CategoryRefinement.refine(
            Self.resolved([Self.expense("Tシャツ", 2_000, .daily), Self.expense("ジンギスカン")], catalog: Self.customCatalog),
            catalog: Self.customCatalog, classifier: classifier, timeout: .seconds(5)
        )

        #expect(refined.map(\.category) == [Self.clothes.category, .food])
        #expect(log.items == ["ジンギスカン", "Tシャツ"])
        #expect(choices.choices.allSatisfy { $0.contains("衣服") && $0.last == "その他" })
    }

    @Test("聞き直す記録が無ければ、AI を呼ばない")
    func doesNotCallClassifierWithoutRequests() async throws {
        let log = Log()
        let entries = [Self.expense("ランチ", 850, .food), ParsedEntry(amount: 250_000, category: .other, isIncome: true, memo: "給料")]

        let refined = try await CategoryRefinement.refine(
            Self.resolved(entries), classifier: StubClassifier(log: log), timeout: .seconds(5)
        )

        #expect(refined == entries)
        #expect(log.items.isEmpty)
    }

    @Test("聞けなかった品目はその他のまま、ほかの品目は聞く。失敗を知らせる")
    func failureLeavesOtherItems() async throws {
        let log = Log()
        let classifier = StubClassifier(answers: ["b": "交通"], failing: ["a"], log: log)

        let refined = try await CategoryRefinement.refine(
            Self.resolved([Self.expense("a"), Self.expense("b")]), classifier: classifier, timeout: .seconds(5),
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
            Self.resolved([Self.expense("a"), Self.expense("b"), Self.expense("c")]), classifier: classifier,
            timeout: .seconds(3), onFallback: log.report
        )

        #expect(refined.map(\.category) == [.cafe, .other, .other])
        // 1件目の答えを受け取ってから次のループへ戻る間に期限を過ぎた場合、2件目は呼ばないのが正しい。
        // CIの負荷によるスケジューラの遅れを、アプリの不具合と扱わない。3件目はどちらの場合も聞かない。
        #expect(log.items == ["a"] || log.items == ["a", "b"])
        #expect(log.reasons == ["timedOut"])
        #expect(start.duration(to: clock.now) < .seconds(60))
    }

    @Test("呼び出した Task が取り消されたら、取り消しとして投げる（記録しない）")
    func cancellationThrows() async {
        let log = Log()
        let classifier = StubClassifier(delays: ["a": .seconds(30)], log: log)
        let task = Task {
            try await CategoryRefinement.refine(
                Self.resolved([Self.expense("a")]), classifier: classifier, timeout: .seconds(20), onFallback: log.report
            )
        }
        try? await Task.sleep(for: .milliseconds(100))
        task.cancel()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(log.reasons.isEmpty)
    }
}
