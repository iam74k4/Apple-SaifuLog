import Foundation
import SaifuLogCore
import SwiftData
import Testing
@testable import SaifuLog

/// 記録の返事に添える端末内 AI の一言（`HomeModel.replyRemark`）。数字の文（`RecordFacts`）だけを渡し、照合に通った一言だけを、
/// 直前の送信の返事に出す。
@MainActor
struct HomeModelReplyRemarkTests {
    typealias Fixture = HomeModelTests.Fixture

    /// 照合に通る一言は、直前の送信の返事に出す。AI には数字の文を渡す（いま記録したもの・今月のカテゴリの合計と件数・今月の合計）。
    @Test func showsCheckedRemark() async throws {
        let fixture = try Fixture()
        let received = FactsBox()
        let writer = StubRemarkWriter { facts in
            received.set(facts)
            return "今月のカフェは2件目です。"
        }
        fixture.recordRemarkWriter = writer
        await fixture.send("コーヒー 400")
        // 1 件目の一言（「2件目」は数字の文に無いので出さない）を書き終えてから、2 件目を送る。
        await fixture.model.replyRemarkTask?.value
        #expect(fixture.model.replyRemark == nil)
        await fixture.send("カフェラテ 480")
        await fixture.model.replyRemarkTask?.value

        let latest = try #require(try fixture.entries().last)
        #expect(fixture.model.replyRemark?.text == "今月のカフェは2件目です。")
        #expect(fixture.model.replyRemark?.entryIDs == [latest.persistentModelID])
        let facts = try #require(received.value)
        #expect(facts.contains("いま記録した支出: カフェラテ ¥480（カフェ）"))
        #expect(facts.contains("今月のカフェ: ¥880（記録 2件）"))
    }

    /// 数字の文に無い数字を書いた一言は出さない（今月の状況の一行は定型の文のまま）。
    @Test func dropsRemarkWithUnknownNumbers() async throws {
        let fixture = try Fixture()
        fixture.recordRemarkWriter = StubRemarkWriter { _ in "今月のカフェは5件目です。" }

        await fixture.send("カフェラテ 480")
        await fixture.model.replyRemarkTask?.value

        #expect(fixture.model.replyRemark == nil)
    }

    /// AI が使えない端末では一言を書かせない。収入だけの送信にも書かせない。
    @Test func noRemarkWithoutAIOrForIncome() async throws {
        let fixture = try Fixture()
        await fixture.send("カフェラテ 480")
        await fixture.model.replyRemarkTask?.value
        #expect(fixture.model.replyRemark == nil)

        let writer = StubRemarkWriter { _ in "いいペースです。" }
        fixture.recordRemarkWriter = writer
        await fixture.send("給料 25万")
        await fixture.model.replyRemarkTask?.value
        #expect(fixture.model.replyRemark == nil)
        #expect(writer.calls.count == 0)
    }

    /// 次の送信・取り消しで、前の返事の一言は消える。
    @Test func remarkGoesAwayWithNextSendOrUndo() async throws {
        let fixture = try Fixture()
        fixture.recordRemarkWriter = StubRemarkWriter { _ in "いいペースです。" }
        await fixture.send("カフェラテ 480")
        await fixture.model.replyRemarkTask?.value
        #expect(fixture.model.replyRemark != nil)

        fixture.model.undoLastRecord()
        #expect(fixture.model.replyRemark == nil)

        fixture.model.draft = ""
        await fixture.send("カフェラテ 480")
        await fixture.model.replyRemarkTask?.value
        #expect(fixture.model.replyRemark != nil)
        await fixture.send("今月いくら?")
        #expect(fixture.model.replyRemark == nil)
    }

    /// 照合に通った一言は、記録の読み上げを遮らないよう、控えめに読み上げる（記録の読み上げとは別に）。
    @Test func announcesRemarkAside() async throws {
        let fixture = try Fixture()
        fixture.recordRemarkWriter = StubRemarkWriter { _ in "いいペースです。" }

        await fixture.send("カフェラテ 480")
        await fixture.model.replyRemarkTask?.value

        #expect(fixture.asideAnnouncements == ["いいペースです。"])
        #expect(!fixture.announcements.contains("いいペースです。"))
    }

    /// 一言は書いたときの今月の数字で書いているので、予算を決める・記録を消す・記録にならない文を送ると外す。
    @Test func remarkGoesAwayWhenNumbersChange() async throws {
        let fixture = try Fixture()
        fixture.recordRemarkWriter = StubRemarkWriter { _ in "いいペースです。" }

        await fixture.send("カフェラテ 480")
        await fixture.model.replyRemarkTask?.value
        #expect(fixture.model.replyRemark != nil)
        await fixture.send("今月の予算を5万にして")
        #expect(fixture.model.replyRemark == nil)

        await fixture.send("カフェラテ 480")
        await fixture.model.replyRemarkTask?.value
        #expect(fixture.model.replyRemark != nil)
        let first = try #require(try fixture.entries().first)
        fixture.model.requestDelete(first)
        let deletion = try #require(fixture.model.pendingDeletion)
        fixture.model.delete(deletion)
        #expect(fixture.model.replyRemark == nil)

        await fixture.send("カフェラテ 480")
        await fixture.model.replyRemarkTask?.value
        #expect(fixture.model.replyRemark != nil)
        await fixture.send("残り 5000")
        #expect(fixture.model.replyRemark == nil)
    }

    /// 予算の画面で予算を変えて戻ったら外す（変えずに戻ったときは残す）。
    @Test func remarkGoesAwayWhenBudgetSheetChangesBudget() async throws {
        let fixture = try Fixture()
        fixture.recordRemarkWriter = StubRemarkWriter { _ in "いいペースです。" }
        await fixture.send("カフェラテ 480")
        await fixture.model.replyRemarkTask?.value

        fixture.model.presentBudgetSetup()
        fixture.model.budgetSetup = nil
        #expect(fixture.model.replyRemark != nil)

        fixture.model.presentBudgetSetup()
        let setup = try #require(fixture.model.budgetSetup)
        setup.totalText = "50,000"
        #expect(setup.save())
        fixture.model.budgetSetup = nil
        #expect(fixture.model.replyRemark == nil)
    }

    /// 一言に渡された数字の文を残す（別の Task から呼ばれるので錠で守る）。
    private final class FactsBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: String?
        var value: String? { lock.withLock { stored } }
        func set(_ value: String) { lock.withLock { stored = value } }
    }
}
