import Foundation
import SaifuLogCore
import Testing
@testable import SaifuLog

/// 記録の返事の下のヒント（`ReplyHints`・`HomeModel.replyHint`）。直し方を最初の数回、その後にカレンダーを数回出し、直したら・
/// カレンダーを開いたら、もう出さない。
@MainActor
struct ReplyHintsTests {
    typealias Fixture = HomeModelTests.Fixture

    @Test("記録した送信の返事に、直し方のヒントを 3 回まで出し、その後はカレンダーのヒントを 3 回まで出す")
    func showsCorrectionThenCalendarHints() async throws {
        let fixture = try Fixture(showsHints: true)
        var shown: [ReplyHints.Hint?] = []
        for index in 0..<7 {
            await fixture.send("ランチ \(800 + index)")
            shown.append(fixture.model.replyHint)
        }

        #expect(shown == [.correction, .correction, .correction, .calendar, .calendar, .calendar, nil])
    }

    @Test("チャットで直したら、直し方のヒントはもう出さず、次の記録はカレンダーのヒントにする")
    func correctingStopsCorrectionHint() async throws {
        let fixture = try Fixture(showsHints: true)
        await fixture.send("ランチ 850")
        #expect(fixture.model.replyHint == .correction)

        await fixture.send("さっきのを900に直して")
        // 直す文を送ったら、前の返事のヒントは外す（送信が替わった）。
        #expect(fixture.model.replyHint == nil)

        await fixture.send("コーヒー 400")
        #expect(fixture.model.replyHint == .calendar)
    }

    @Test("カレンダーのページを開いたら、カレンダーのヒントを外し、もう出さない")
    func openingCalendarStopsCalendarHint() async throws {
        let fixture = try Fixture(showsHints: true)
        fixture.defaults.set(true, for: AppSettings.hasCorrectedEntry)
        await fixture.send("ランチ 850")
        #expect(fixture.model.replyHint == .calendar)

        fixture.model.page = .calendar

        #expect(fixture.model.replyHint == nil)
        fixture.model.page = .conversation
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
