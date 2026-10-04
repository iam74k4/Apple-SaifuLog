import Foundation
import SaifuLogCore
import SwiftData
import Testing
@testable import SaifuLog

@MainActor
struct PaymentCategoryAutomationTests {
    typealias Fixture = HomeModelTests.Fixture

    struct Classifier: ItemCategoryClassifying {
        var answer = "日用品"
        var fails = false
        func categoryName(for item: String) async throws -> String {
            if fails { throw TestError() }
            return answer
        }
    }

    actor Gate: ItemCategoryClassifying {
        private var reply: CheckedContinuation<String, Never>?
        private var isWaiting: Bool { reply != nil }
        func categoryName(for item: String) async throws -> String {
            await withCheckedContinuation { continuation in
                reply = continuation
            }
        }
        func waitUntilAsked() async throws {
            try await withDeadline(.seconds(10)) {
                while !(await self.isWaiting) { try await Task.sleep(for: .milliseconds(10)) }
            }
        }
        func finish() { reply?.resume(returning: "日用品"); reply = nil }
    }

    @discardableResult
    private func pay(_ fixture: Fixture, merchant: String = "ユニクロ") throws -> Entry {
        try fixture.paymentInbox.append(amount: 3990, merchant: merchant, paidAt: TestSupport.now)
        return try #require(fixture.model.importCapturedPayments(calendar: TestSupport.calendar).first)
    }

    @Test func savesPaymentBeforeAIAndOnlyChangesCategory() async throws {
        let fixture = try Fixture()
        let gate = Gate()
        fixture.categoryRefiner = CategoryRefiner(classifier: gate, onFallback: nil)
        let entry = try pay(fixture)
        let id = entry.persistentModelID
        let key = entry.recurrenceKey
        #expect(entry.category == .other)
        #expect(fixture.paymentInbox.pending().isEmpty)
        #expect(fixture.pendingWrites.count == 1)
        #expect(fixture.model.classifyingPaymentIDs == [id])
        try await gate.waitUntilAsked()
        await gate.finish()
        await fixture.model.waitForPaymentClassification()
        #expect(entry.category == .daily)
        #expect(entry.amount == 3990 && entry.spentAt == TestSupport.now)
        #expect(entry.memo == "ユニクロ" && entry.recurrenceKey == key)
        #expect(fixture.model.categoryQuestionIDs.isEmpty)
        #expect(fixture.model.classifyingPaymentIDs.isEmpty)
        #expect(fixture.pendingWrites.count == 0)
        #expect(try LearnedCategoryStore(context: fixture.context).memory().rules.isEmpty)
    }

    @Test func learnedChoiceAndDictionarySkipAI() async throws {
        let fixture = try Fixture()
        fixture.categoryRefiner = CategoryRefiner(classifier: Classifier(answer: "交通"), onFallback: nil)
        let learned = LearnedCategoryStore(context: fixture.context)
        _ = try learned.remember(item: "ユニクロ", category: .entertainment)
        let chosen = try pay(fixture, merchant: "ユニクロ 新宿店")
        #expect(chosen.category == .entertainment)
        #expect(fixture.pendingWrites.count == 0)
        let known = try pay(fixture, merchant: "STARBUCKS")
        #expect(known.category == .cafe)
        #expect(fixture.pendingWrites.count == 0)
    }

    @Test(arguments: [Classifier(answer: "その他"), Classifier(answer: "invalid"), Classifier(fails: true)])
    func uncertainOrFailedAIKeepsQuestion(classifier: Classifier) async throws {
        let fixture = try Fixture()
        fixture.categoryRefiner = CategoryRefiner(classifier: classifier, onFallback: nil)
        let entry = try pay(fixture)
        await fixture.model.waitForPaymentClassification()
        #expect(entry.category == .other)
        #expect(fixture.model.categoryQuestionIDs == [entry.persistentModelID])
        #expect(try fixture.entries().count == 1)
    }

    @Test func userChoiceWinsWhileAIIsRunning() async throws {
        let fixture = try Fixture()
        let gate = Gate()
        fixture.categoryRefiner = CategoryRefiner(classifier: gate, onFallback: nil)
        let entry = try pay(fixture)
        try await gate.waitUntilAsked()
        fixture.model.chooseCategory(.entertainment, for: entry)
        await gate.finish()
        await fixture.model.waitForPaymentClassification()
        #expect(entry.category == .entertainment)
        #expect(try pay(fixture, merchant: "ユニクロ 渋谷店").category == .entertainment)
        #expect(fixture.model.classifyingPaymentIDs.isEmpty)
    }

    @Test func changedRecordIsNotOverwritten() async throws {
        let fixture = try Fixture()
        let gate = Gate()
        fixture.categoryRefiner = CategoryRefiner(classifier: gate, onFallback: nil)
        let entry = try pay(fixture)
        try await gate.waitUntilAsked()
        var edits = EntryEdits(entry)
        edits.memo = "贈り物"
        try EntryStore(context: fixture.context).update(entry, with: edits)
        await gate.finish()
        await fixture.model.waitForPaymentClassification()
        #expect(entry.memo == "贈り物" && entry.category == .other)
    }

    @Test func undoDuringAILeavesNoRecord() async throws {
        let fixture = try Fixture()
        let gate = Gate()
        fixture.categoryRefiner = CategoryRefiner(classifier: gate, onFallback: nil)
        try pay(fixture)
        try await gate.waitUntilAsked()
        fixture.model.undoLastRecord()
        await gate.finish()
        await fixture.model.waitForPaymentClassification()
        #expect(try fixture.entries().isEmpty)
        #expect(fixture.model.classifyingPaymentIDs.isEmpty)
    }

    @Test func cancellationKeepsSavedPaymentAndRejectsLateAnswer() async throws {
        let fixture = try Fixture()
        let gate = Gate()
        fixture.categoryRefiner = CategoryRefiner(classifier: gate, onFallback: nil)
        let entry = try pay(fixture)
        try await gate.waitUntilAsked()
        fixture.model.cancelPaymentClassification()
        await gate.finish()
        await fixture.model.waitForPaymentClassification()
        #expect(entry.category == .other)
        #expect(try fixture.entries().count == 1)
        #expect(fixture.pendingWrites.count == 0)
        #expect(fixture.model.categoryQuestionIDs == [entry.persistentModelID])
    }

    @Test func saveFailureKeepsPaymentAndQuestion() async throws {
        let fixture = try Fixture()
        let gate = Gate()
        fixture.categoryRefiner = CategoryRefiner(classifier: gate, onFallback: nil)
        let entry = try pay(fixture)
        let id = entry.persistentModelID
        try await gate.waitUntilAsked()
        fixture.failsSave = true
        await gate.finish()
        await fixture.model.waitForPaymentClassification()
        #expect(try fixture.entries().first?.category == .other)
        #expect(fixture.model.categoryQuestionIDs == [id])
        #expect(fixture.model.canUndo)
    }

    @Test func timeoutDoesNotHoldSavedPaymentOrStoreOpen() async throws {
        let fixture = try Fixture()
        let gate = Gate()
        fixture.categoryRefiner = CategoryRefiner(classifier: gate, timeout: .milliseconds(50), onFallback: nil)
        let entry = try pay(fixture)
        await fixture.model.waitForPaymentClassification()
        #expect(entry.category == .other)
        #expect(fixture.pendingWrites.count == 0)
        await gate.finish()
    }
}
