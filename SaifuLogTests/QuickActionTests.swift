import AppIntents
import Foundation
import SaifuLogCore
import SwiftData
import Testing
@testable import SaifuLog

/// Siri・ショートカットからの頼み（`SaifuLogIntents`・`QuickActionInbox`・`HomeModel.performPendingQuickAction`）。
@MainActor
@Suite(.serialized)
struct QuickActionTests {
    typealias Fixture = HomeModelTests.Fixture

    // MARK: - 受け箱と操作

    /// 操作は頼みを受け箱に置くだけ（アプリを開いてから、ホームが行う）。受け取ると空になる。
    @Test func intentsPostToInbox() async throws {
        _ = QuickActionInbox.shared.take()
        var record = RecordEntryIntent()
        record.text = "ランチ 850"
        _ = try await record.perform()
        #expect(QuickActionInbox.shared.take() == .record("ランチ 850"))
        #expect(QuickActionInbox.shared.take() == nil)

        var ask = AskQuestionIntent()
        ask.question = "今月いくら?"
        _ = try await ask.perform()
        #expect(QuickActionInbox.shared.pending == .ask("今月いくら?"))

        // 続けて頼まれたら、新しいほうを持つ。
        _ = try await ScanReceiptIntent().perform()
        #expect(QuickActionInbox.shared.take() == .receipt)
        _ = try await ComposeEntryIntent().perform()
        #expect(QuickActionInbox.shared.take() == .compose)
        _ = try await VoiceEntryIntent().perform()
        #expect(QuickActionInbox.shared.take() == .voice)
        #expect(RecordEntryIntent.openAppWhenRun)
    }

    // MARK: - ホーム

    /// 「ひとことで記録」は、入力欄の文に触れずに送り、ふつうの送信と同じく記録して「取り消す」を出す。
    @Test func recordsWithoutTouchingDraft() async throws {
        let fixture = try Fixture()
        fixture.model.draft = "打ちかけ"
        fixture.model.receive(.record("ランチ 850"))

        await fixture.model.performPendingQuickAction(calendar: TestSupport.calendar)?.value

        #expect(try fixture.entries().map(\.amount) == [850])
        #expect(fixture.model.draft == "打ちかけ")
        #expect(fixture.model.canUndo)
        #expect(fixture.model.pendingQuickAction == nil)
    }

    /// 「家計に質問」は、記録か見分けずに質問として答える（金額の入った文も記録しない）。
    @Test func asksAsQuestion() async throws {
        let fixture = try Fixture()
        fixture.model.receive(.ask("今月の支出は?"))
        await fixture.model.performPendingQuickAction(calendar: TestSupport.calendar)?.value
        guard case .answered(let answer, _, _) = fixture.lastQuestionState else {
            Issue.record("答えのカードが出なかった")
            return
        }
        #expect(answer.question.metric == .expenseTotal)

        fixture.model.receive(.ask("ランチ 850"))
        await fixture.model.performPendingQuickAction(calendar: TestSupport.calendar)?.value
        #expect(try fixture.entries().isEmpty)
        #expect(fixture.lastQuestionState == .unreadable)
    }

    /// 読み取りの間は待ち、終わってから行う。
    @Test func waitsWhileParsing() async throws {
        let fixture = try Fixture()
        let gate = AsyncGate()
        fixture.parser = StubParser { text in
            await gate.wait()
            return [ParsedEntry(amount: 400, category: .cafe, memo: text)]
        }
        fixture.model.draft = "コーヒー 400"
        let sending = fixture.model.send(calendar: TestSupport.calendar)
        fixture.model.receive(.record("ランチ 850"))

        #expect(fixture.model.performPendingQuickAction(calendar: TestSupport.calendar) == nil)
        #expect(fixture.model.pendingQuickAction == .record("ランチ 850"))

        await gate.open()
        await sending?.value
        fixture.parser = RuleBasedParser(calendar: TestSupport.calendar, now: { TestSupport.now })
        await fixture.model.performPendingQuickAction(calendar: TestSupport.calendar)?.value

        #expect(try fixture.entries().map(\.amount).sorted() == [400, 850])
    }

    /// 入力欄を開く頼みと、文の空の記録の頼みは、入力欄にキーボードを出す。ほかの画面を出している間は待つ。
    @Test func composeWaitsForOtherScreens() async throws {
        let fixture = try Fixture()
        fixture.model.presentSettings()
        fixture.model.receive(.compose)

        #expect(fixture.model.performPendingQuickAction(calendar: TestSupport.calendar) == nil)
        #expect(fixture.model.inputFocusRequest == 0)

        fixture.model.settings = nil
        await fixture.model.performPendingQuickAction(calendar: TestSupport.calendar)?.value
        #expect(fixture.model.inputFocusRequest == 1)

        fixture.model.receive(.record("  "))
        await fixture.model.performPendingQuickAction(calendar: TestSupport.calendar)?.value
        #expect(fixture.model.inputFocusRequest == 2)
        #expect(try fixture.entries().isEmpty)
    }

    /// 「レシートを読み取る」は、カメラのボタンを押したときと同じく「撮る」「写真から選ぶ」を出す。
    @Test func receiptShowsSourceChoice() async throws {
        let fixture = try Fixture()
        fixture.model.receive(.receipt)

        await fixture.model.performPendingQuickAction(calendar: TestSupport.calendar)?.value

        #expect(fixture.model.showsReceiptSourceChoice)
    }
}

/// テストで解析を止めておく門（開くまで待たせる）。
actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}
