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
        let clothes = try create("衣服", in: fixture)

        await fixture.send("衣服 3000")

        let entry = try #require(try fixture.entries().first)
        #expect(entry.category == clothes)
        #expect(fixture.model.categoryQuestionIDs.isEmpty)
        #expect(entry.kindText(in: fixture.model.categories.catalog) == "衣服")
    }

    /// 聞き返しの「カテゴリを作る」で作ると、聞き返した記録をそのカテゴリにし、品目を覚えて次から使う。
    @Test func creatingCategoryFromQuestionAssignsAndRemembers() async throws {
        let fixture = try Fixture()
        await fixture.send("ユニクロ 3990")
        let entry = try #require(try fixture.entries().first)

        fixture.model.presentCategoryCreation(for: entry)
        let editor = try #require(fixture.model.categoryEditor)
        editor.name = "衣服"
        #expect(editor.save())

        let clothes = try #require(fixture.model.categories.catalog.customs.first?.category)
        #expect(entry.category == clothes)
        #expect(fixture.model.categoryQuestionIDs.isEmpty)
        #expect(try LearnedCategoryStore(context: fixture.context).memory().rules == ["ユニクロ": clothes])
        #expect(fixture.announcements.last?.contains("次から「ユニクロ」は衣服にします") == true)

        await fixture.send("ユニクロ 1990")
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
        try LearnedCategoryStore(context: fixture.context, now: { TestSupport.now }).remember(item: "ユニクロ", category: .custom("gone"))

        await fixture.send("ユニクロ 3990")

        let entry = try #require(try fixture.entries().first)
        #expect(entry.category == .other)
        #expect(fixture.model.categoryQuestionIDs == [entry.persistentModelID])
    }

    /// 作ったカテゴリの名前で聞かれたら、そのカテゴリの支出で答える（記録と取り違えない）。
    @Test func answersQuestionAboutCustomCategory() async throws {
        let fixture = try Fixture()
        let clothes = try create("衣服", in: fixture)
        try fixture.insert(
            TestSupport.entry(amount: 3000, category: clothes, memo: "シャツ"),
            TestSupport.entry(amount: 850, category: .food)
        )

        await fixture.send("今月の衣服いくら?")

        guard case .answered(let answer, _, _) = fixture.lastQuestionState else {
            Issue.record("答えのカードが出なかった")
            return
        }
        #expect(answer.question.category == clothes)
        #expect(answer.value == .amount(3000))
        #expect(try fixture.entries().count == 2)
    }
}

/// 家族の家計には作ったカテゴリを持ち込まない（家族の端末には無いカテゴリなので「その他」にする）。
@MainActor
struct HomeModelCustomCategoryHouseholdTests {
    @Test func householdEntriesUseOtherForCustomCategory() async throws {
        let fixture = try HomeModelHouseholdTests.Fixture()
        try fixture.household.insertHousehold(role: .owner)
        _ = try CustomCategoryStore(context: fixture.context, now: { TestSupport.now })
            .create(name: "衣服", symbolName: "tshirt", colorIndex: 0)
        fixture.model.categories.reload()
        fixture.model.ledgerScope = .household

        await fixture.send("衣服 3000")

        #expect(try fixture.household.entries().map(\.category) == [.other])
    }
}
