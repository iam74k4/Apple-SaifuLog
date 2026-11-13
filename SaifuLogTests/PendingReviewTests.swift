import Foundation
import SaifuLogCore
import SwiftData
import Testing
@testable import SaifuLog

/// カテゴリの聞き返し（`Entry.needsCategoryReview` と `HomeModel.categoryQuestionIDs`）が、保存先を開き直した後も残ること。
@MainActor
@Suite(.serialized)
struct PendingReviewTests {
    /// カテゴリの聞き返しは保存先に残り、開き直した後も選べる。選ぶと聞き返しが終わる。
    @Test func categoryQuestionSurvivesClosingAndReopeningTheDatabase() async throws {
        let directory = URL.temporaryDirectory.appending(path: "PendingReview-\(UUID().uuidString)")
        let url = directory.appending(path: "review.store")
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            let container = try ModelContainerFactory.makeContainer(url: url, cloudKitDatabase: .none)
            let model = HomeModel(store: EntryStore(context: container.mainContext),
                                  makeParser: { _, _ in RuleBasedParser(calendar: TestSupport.calendar, now: { TestSupport.now }) },
                                  makeCategoryRefiner: { nil }, now: { TestSupport.now }, announce: { _ in })
            model.draft = "ぽんかん 450"
            await model.send(calendar: TestSupport.calendar)?.value
            #expect(model.categoryQuestionIDs.count == 1)
        }
        let container = try ModelContainerFactory.makeContainer(url: url, cloudKitDatabase: .none)
        let model = HomeModel(store: EntryStore(context: container.mainContext),
                              makeCategoryRefiner: { nil }, now: { TestSupport.now }, announce: { _ in })
        let entry = try #require(try container.mainContext.fetch(FetchDescriptor<Entry>()).first)
        #expect(model.categoryQuestionIDs == [entry.persistentModelID])

        model.chooseCategory(.food, for: entry)

        #expect(entry.category == .food)
        #expect(!entry.needsCategoryReview)
        #expect(model.categoryQuestionIDs.isEmpty)
    }
}
