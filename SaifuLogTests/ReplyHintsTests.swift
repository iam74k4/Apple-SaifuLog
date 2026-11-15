import Foundation
import SaifuLogCore
import Testing
@testable import SaifuLog

/// 記録の返事の下のヒント（`ReplyHints`・`HomeModel.replyHint`）。直し方を最初の数回だけ出し、直したら、もう出さない。
@MainActor
struct ReplyHintsTests {
    typealias Fixture = HomeModelTests.Fixture

    @Test("記録した送信の返事に、直し方のヒントを 3 回まで出す")
    func showsCorrectionHintThreeTimes() async throws {
        let fixture = try Fixture(showsHints: true)
        var shown: [ReplyHints.Hint?] = []
        for index in 0..<4 {
            await fixture.send("ランチ \(800 + index)")
            shown.append(fixture.model.replyHint)
        }

        #expect(shown == [.correction, .correction, .correction, nil])
    }

    @Test("チャットで直したら、直し方のヒントはもう出さない")
    func correctingStopsCorrectionHint() async throws {
        let fixture = try Fixture(showsHints: true)
        await fixture.send("ランチ 850")
        #expect(fixture.model.replyHint == .correction)

        await fixture.send("さっきのを900に直して")
        // 直す文を送ったら、前の返事のヒントは外す（送信が替わった）。
        #expect(fixture.model.replyHint == nil)

        await fixture.send("コーヒー 400")
        #expect(fixture.model.replyHint == nil)
    }

    @Test("取り消したら、ヒントも外す")
    func undoRemovesHint() async throws {
        let fixture = try Fixture(showsHints: true)
        await fixture.send("ランチ 850")
        #expect(fixture.model.replyHint == .correction)

        fixture.model.undoLastRecord()

        #expect(fixture.model.replyHint == nil)
    }

    @Test("ヒントを覚えるものを渡さなければ（テストと撮影用のデモ）、ヒントは出さない")
    func noHintsWithoutStore() async throws {
        let fixture = try Fixture()
        await fixture.send("ランチ 850")

        #expect(fixture.model.replyHint == nil)
    }
}
