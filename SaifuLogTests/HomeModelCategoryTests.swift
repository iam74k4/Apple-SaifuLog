import Foundation
import SaifuLogCore
import SwiftData
import Testing
@testable import SaifuLog

/// ホームのカテゴリの聞き返しと修正の記憶（`HomeModel.chooseCategory`・`categoryQuestionIDs`、直すで覚えること）。
/// メモリの上の保存先と、固定の日時のキーワード辞書で確かめる。
@MainActor
struct HomeModelCategoryTests {
    typealias Fixture = HomeModelTests.Fixture

    private func learned(_ fixture: Fixture) -> LearnedCategoryStore {
        LearnedCategoryStore(context: fixture.context, now: { TestSupport.now })
    }

    // MARK: - 聞き返し

    /// 辞書に当たらない品目は「その他」で記録し、返事で聞き返す（記録は止めない）。VoiceOver にも選べることを読み上げる。
    @Test func asksCategoryForUnknownItem() async throws {
        let fixture = try Fixture()

        await fixture.send("ユニクロ 3990")

        let entry = try #require(try fixture.entries().first)
        #expect(entry.category == .other)
        #expect(fixture.model.categoryQuestionIDs == [entry.persistentModelID])
        #expect(fixture.announcements.last?.contains("カテゴリを選べます") == true)
    }

    // MARK: - AI への聞き直し

    /// 決めた答えを返す AI の代わり。聞かれた品目を残す。
    private final class StubClassifier: ItemCategoryClassifying, @unchecked Sendable {
        let answers: [String: String]
        let fails: Bool
        private let lock = NSLock()
        private var asked: [String] = []

        init(answers: [String: String] = [:], fails: Bool = false) {
            self.answers = answers
            self.fails = fails
        }

        var askedItems: [String] { lock.withLock { asked } }

        func categoryName(for item: String) async throws -> String {
            lock.withLock { asked.append(item) }
            if fails { throw TestError() }
            return answers[item] ?? "その他"
        }
    }

    /// 辞書で決まらない品目は、返事で聞き返す前に AI に聞き直し、AI が選んだカテゴリで記録する（聞き返さない）。
    /// AI の答えは覚えない（覚えるのは利用者が選んだカテゴリだけ）。
    @Test func refinesUnknownItemWithAI() async throws {
        let fixture = try Fixture()
        let classifier = StubClassifier(answers: ["ユニクロ": "日用品"])
        fixture.categoryRefiner = CategoryRefiner(classifier: classifier, onFallback: nil)

        await fixture.send("ユニクロ 3990")

        let entry = try #require(try fixture.entries().first)
        #expect(entry.category == .daily)
        #expect(fixture.model.categoryQuestionIDs.isEmpty)
        #expect(fixture.announcements.last?.contains("カテゴリを選べます") == false)
        #expect(classifier.askedItems == ["ユニクロ"])
        #expect(try learned(fixture).memory().rules.isEmpty)
    }

    /// 辞書で決まった品目・覚えた品目・収入は AI に聞かない（AI を待たずに記録する）。
    @Test func doesNotAskAIWhenCategoryIsKnown() async throws {
        let fixture = try Fixture()
        let classifier = StubClassifier(answers: ["ランチ": "娯楽"])
        fixture.categoryRefiner = CategoryRefiner(classifier: classifier, onFallback: nil)
        _ = try learned(fixture).remember(item: "ジム", category: .entertainment)

        await fixture.send("ランチ 850")
        await fixture.send("ジム 8000")
        await fixture.send("給料 25万")

        #expect(classifier.askedItems.isEmpty)
        #expect(try fixture.entries().map(\.category) == [.food, .entertainment, .other])
    }

    /// AI がその他を選んだとき・失敗したときは、これまでどおり返事で聞き返す（記録は止めない）。
    @Test(arguments: [false, true])
    func fallsBackToCategoryQuestion(fails: Bool) async throws {
        let fixture = try Fixture()
        fixture.categoryRefiner = CategoryRefiner(classifier: StubClassifier(fails: fails), onFallback: nil)

        await fixture.send("ユニクロ 3990")

        let entry = try #require(try fixture.entries().first)
        #expect(entry.category == .other)
        #expect(fixture.model.categoryQuestionIDs == [entry.persistentModelID])
    }

    /// 辞書に当たった品目と、辞書の「その他」の語（洋服など）と、収入は聞き返さない。
    @Test func doesNotAskWhenCategoryIsKnown() async throws {
        let fixture = try Fixture()

        await fixture.send("ランチ 850")
        #expect(fixture.model.categoryQuestionIDs.isEmpty)
        await fixture.send("洋服 4000")
        #expect(fixture.model.categoryQuestionIDs.isEmpty)
        await fixture.send("給料 25万")
        #expect(fixture.model.categoryQuestionIDs.isEmpty)
        #expect(fixture.announcements.allSatisfy { !$0.contains("カテゴリを選べます") })
    }

    /// 1 回の送信で複数件を記録したら、分からない件だけを聞き返す。
    @Test func asksOnlyUnknownEntriesOfSend() async throws {
        let fixture = try Fixture()

        await fixture.send("スーパー2480、ユニクロ3990")

        let entries = try fixture.entries()
        #expect(entries.map(\.category) == [.food, .other])
        #expect(fixture.model.categoryQuestionIDs == [entries[1].persistentModelID])
    }

    /// 選んだカテゴリに記録を直し、品目とカテゴリの組を覚えて、次の同じ品目の記録に使う（聞き返さない）。
    @Test func choosingCategoryUpdatesEntryAndIsRememberedNextTime() async throws {
        let fixture = try Fixture()
        await fixture.send("ジム 8000")
        let entry = try #require(try fixture.entries().first)

        fixture.model.chooseCategory(.entertainment, for: entry)

        #expect(entry.category == .entertainment)
        #expect(fixture.model.categoryQuestionIDs.isEmpty)
        #expect(try learned(fixture).memory().rules == ["ジム": .entertainment])
        #expect(fixture.announcements.last?.contains("次から「ジム」は娯楽にします") == true)
        // 「取り消す」は残す（取り消して送り直しても、覚えたカテゴリで記録されるので食い違わない）。
        #expect(fixture.model.canUndo)

        await fixture.send("ジム 8000")

        let latest = try #require(try fixture.entries().last)
        #expect(latest.category == .entertainment)
        #expect(fixture.model.categoryQuestionIDs.isEmpty)
    }

    /// 「その他のまま」も覚え、同じ品目でもう聞き返さない（記録は書き換えない）。
    @Test func keepingOtherIsRememberedAndStopsAsking() async throws {
        let fixture = try Fixture()
        await fixture.send("家賃 80000")
        let entry = try #require(try fixture.entries().first)

        fixture.model.chooseCategory(.other, for: entry)

        #expect(entry.category == .other)
        #expect(try learned(fixture).memory().rules == ["家賃": .other])
        await fixture.send("家賃 80000")
        #expect(fixture.model.categoryQuestionIDs.isEmpty)
    }

    /// 次の文を送ったら、前の返事の聞き返しは引っ込める（取り消すと同じ）。
    @Test func sendingNextClearsQuestion() async throws {
        let fixture = try Fixture()
        await fixture.send("ユニクロ 3990")
        let entry = try #require(try fixture.entries().first)

        await fixture.send("ランチ 850")

        #expect(fixture.model.categoryQuestionIDs.isEmpty)
        // 引っ込めた後は選べない（前の記録は、返事の行から直す）。
        fixture.model.chooseCategory(.daily, for: entry)
        #expect(entry.category == .other)
        #expect(try learned(fixture).memory().rules.isEmpty)
    }

    /// 取り消したら、聞き返しも消す（消えた記録を選ばないように）。
    @Test func undoClearsQuestion() async throws {
        let fixture = try Fixture()
        await fixture.send("ユニクロ 3990")

        fixture.model.undoLastRecord()

        #expect(fixture.model.categoryQuestionIDs.isEmpty)
        #expect(try fixture.entries().isEmpty)
    }

    /// 記録のカテゴリを書き込めなければ、聞き返しを残して知らせる（もう一度選べるように）。覚えもしない。
    @Test func choosingCategoryFailureKeepsQuestion() async throws {
        let fixture = try Fixture()
        await fixture.send("ユニクロ 3990")
        let entry = try #require(try fixture.entries().first)
        fixture.failsSave = true

        fixture.model.chooseCategory(.daily, for: entry)

        #expect(fixture.model.storeFailure == .categoryChoice)
        #expect(fixture.model.categoryQuestionIDs == [entry.persistentModelID])
        fixture.failsSave = false
        #expect(try fixture.entries().map(\.category) == [.other])
        #expect(try learned(fixture).memory().rules.isEmpty)
    }

    /// 直す（⑥）でカテゴリを選んだら、返事の聞き返しは引っ込める（直すで変えたカテゴリは、そこで覚える）。
    @Test func editingClearsQuestionAndRemembers() async throws {
        let fixture = try Fixture()
        await fixture.send("ユニクロ 3990")
        let entry = try #require(try fixture.entries().first)
        fixture.model.presentEdit(entry, calendar: TestSupport.calendar)
        let editing = try #require(fixture.model.editing)

        editing.category = .daily
        #expect(editing.learningItem == "ユニクロ")
        #expect(editing.save())

        #expect(fixture.model.categoryQuestionIDs.isEmpty)
        #expect(try learned(fixture).memory().rules == ["ユニクロ": .daily])
    }

    // MARK: - 修正の記憶

    /// 覚えたカテゴリは、辞書の読みより優先する（AI の読みも同じ。当てるのは読み取った後）。
    @Test func rememberedCategoryOverridesParsedCategory() async throws {
        let fixture = try Fixture()
        try learned(fixture).remember(item: "コーヒー豆", category: .food)
        fixture.parser = StubParser { _ in [ParsedEntry(amount: 1_200, category: .cafe, memo: "コーヒー豆")] }

        await fixture.send("コーヒー豆 1200")

        #expect(try fixture.entries().map(\.category) == [.food])
    }

    /// 知らないカテゴリの覚え（新しい版の端末から iCloud で届いた行）は読み飛ばし、いつもどおり記録する。
    @Test func unknownCategoryRowIsIgnored() async throws {
        let fixture = try Fixture()
        let broken = LearnedCategory(phrase: "ランチ", category: .other, updatedAt: TestSupport.now)
        broken.categoryRawValue = "unknown"
        fixture.context.insert(broken)
        try fixture.context.save()

        await fixture.send("ランチ 850")

        #expect(try fixture.entries().map(\.category) == [.food])
    }

    /// 直すの金額やメモだけの直しは覚えない。直すのシートは、カテゴリを変えたときだけ覚えることを知らせる。
    @Test func editWithoutCategoryChangeDoesNotLearn() async throws {
        let fixture = try Fixture()
        await fixture.send("ランチ 850")
        let entry = try #require(try fixture.entries().first)
        fixture.model.presentEdit(entry, calendar: TestSupport.calendar)
        let editing = try #require(fixture.model.editing)

        editing.amountText = "900"
        #expect(editing.learningItem == nil)
        editing.isIncome = true
        editing.category = .daily
        #expect(editing.learningItem == nil)
        editing.isIncome = false
        #expect(editing.learningItem == "ランチ")
        editing.category = .food
        #expect(editing.save())

        #expect(try learned(fixture).memory().rules.isEmpty)
    }
}
