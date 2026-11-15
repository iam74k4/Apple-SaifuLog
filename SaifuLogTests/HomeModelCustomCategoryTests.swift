import Foundation
import SaifuLogCore
import SwiftData
import Testing
@testable import SaifuLog

/// ホームでの作ったカテゴリ（名前を書いた記録・聞き返しから作る・覚えたカテゴリ・質問・家族の家計）。
@MainActor
struct HomeModelCustomCategoryTests {
    typealias Fixture = HomeModelTests.Fixture

    /// 保存先にカテゴリを作り、ホームの一覧を読み直す（設定の画面で作ったときと同じ）。
    private func create(_ name: String, in fixture: Fixture) throws -> EntryCategory {
        let category = try CustomCategoryStore(context: fixture.context, now: { TestSupport.now })
            .create(name: name, symbolName: "tag", colorIndex: 0)
        fixture.model.categories.reload()
        return category
    }

    /// 文に作ったカテゴリの名前があれば、そのカテゴリで記録し、聞き返さない。返事と読み上げにも作ったカテゴリの名前を出す。
    @Test func recordsCustomCategoryNamedInText() async throws {
        let fixture = try Fixture()
        let clothes = try create("推し活", in: fixture)

        await fixture.send("推し活 3000")

        let entry = try #require(try fixture.entries().first)
        #expect(entry.category == clothes)
        #expect(fixture.model.categoryQuestionIDs.isEmpty)
        #expect(entry.kindText(in: fixture.model.categories.catalog) == "推し活")
    }

    /// 聞き返しの「カテゴリを作る」で作ると、聞き返した記録をそのカテゴリにし、品目を覚えて次から使う。
    @Test func creatingCategoryFromQuestionAssignsAndRemembers() async throws {
        let fixture = try Fixture()
        await fixture.send("メルカリ 3990")
        let entry = try #require(try fixture.entries().first)

        fixture.model.presentCategoryCreation(for: entry)
        let editor = try #require(fixture.model.categoryEditor)
        editor.name = "推し活"
        #expect(editor.save())

        let clothes = try #require(fixture.model.categories.catalog.customs.first?.category)
        #expect(entry.category == clothes)
        #expect(fixture.model.categoryQuestionIDs.isEmpty)
        #expect(try LearnedCategoryStore(context: fixture.context).memory().rules == ["メルカリ": clothes])
        #expect(fixture.announcements.last?.contains("次から「メルカリ」は推し活にします") == true)

        await fixture.send("メルカリ 1990")
        #expect(try fixture.entries().last?.category == clothes)
        #expect(fixture.model.categoryQuestionIDs.isEmpty)
    }

    /// 聞き返していない記録には、作るシートを出さない。
    @Test func creationNeedsQuestion() async throws {
        let fixture = try Fixture()
        await fixture.send("ランチ 850")
        let entry = try #require(try fixture.entries().first)

        fixture.model.presentCategoryCreation(for: entry)

        #expect(fixture.model.categoryEditor == nil)
    }

    /// 覚えたカテゴリが一覧に無い（ほかの端末で消した・まだ届いていない）ときは使わず、いつもどおり聞き返す。
    @Test func learnedMissingCustomCategoryIsIgnored() async throws {
        let fixture = try Fixture()
        try LearnedCategoryStore(context: fixture.context, now: { TestSupport.now }).remember(item: "メルカリ", category: .custom("gone"))

        await fixture.send("メルカリ 3990")

        let entry = try #require(try fixture.entries().first)
        #expect(entry.category == .other)
        #expect(fixture.model.categoryQuestionIDs == [entry.persistentModelID])
    }

    /// 作ったカテゴリの名前で聞かれたら、そのカテゴリの支出で答える（記録と取り違えない）。
    @Test func answersQuestionAboutCustomCategory() async throws {
        let fixture = try Fixture()
        let clothes = try create("推し活", in: fixture)
        try fixture.insert(
            TestSupport.entry(amount: 3000, category: clothes, memo: "シャツ"),
            TestSupport.entry(amount: 850, category: .food)
        )

        await fixture.send("今月の推し活いくら?")

        guard case .answered(let answer, _) = fixture.lastQuestionState else {
            Issue.record("答えのカードが出なかった")
            return
        }
        #expect(answer.question.category == clothes)
        #expect(answer.value == .amount(3000))
        #expect(try fixture.entries().count == 2)
    }

    /// AI が使える端末では、名前を書かなくても、作ったカテゴリに当たる品目をそのカテゴリにする。作ったカテゴリを選択肢に渡す。
    @Test func aiChoosesCustomCategory() async throws {
        let fixture = try Fixture()
        let clothes = try create("推し活", in: fixture)
        let classifier = ChoiceRecorder(answer: "推し活")
        fixture.categoryRefiner = CategoryRefiner(classifier: classifier, onFallback: nil)

        await fixture.send("アクスタ 2000")

        let entry = try #require(try fixture.entries().first)
        #expect(entry.category == clothes)
        #expect(fixture.model.categoryQuestionIDs.isEmpty)
        #expect(classifier.choices.first?.contains("推し活") == true)
    }

    /// 作ったカテゴリを選択肢に入れても、読み取ったカテゴリを組み込みのカテゴリの答えで変えない。
    @Test func aiBuiltInAnswerDoesNotOverrideParsedCategory() async throws {
        let fixture = try Fixture()
        _ = try create("推し活", in: fixture)
        fixture.categoryRefiner = CategoryRefiner(classifier: ChoiceRecorder(answer: "娯楽"), onFallback: nil)

        await fixture.send("ランチ 850")

        #expect(try fixture.entries().first?.category == .food)
    }

    /// チャットの文で、作ったカテゴリに直せる。
    @Test func recategorizesToCustomCategoryFromChat() async throws {
        let fixture = try Fixture()
        let clothes = try create("推し活", in: fixture)
        await fixture.send("メルカリ 3990")

        await fixture.send("それ推し活")

        #expect(try fixture.entries().map(\.category) == [clothes])
    }

    /// 決めた答えを返し、渡された選択肢を残す AI の代わり。
    private final class ChoiceRecorder: ItemCategoryClassifying, @unchecked Sendable {
        let answer: String
        private let lock = NSLock()
        private var recorded: [[String]] = []

        init(answer: String) {
            self.answer = answer
        }

        var choices: [[String]] { lock.withLock { recorded } }

        func categoryName(for item: String, choices: [String]) async throws -> String {
            lock.withLock { recorded.append(choices) }
            return answer
        }
    }

}
