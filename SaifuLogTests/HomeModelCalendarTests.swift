import Foundation
import SaifuLogCore
import SwiftData
import Testing
@testable import SaifuLog

/// ホームの会話とカレンダーのページの行き来（Siri の頼みで会話へ戻る・同じ保存先を読む）。
@MainActor
struct HomeModelCalendarTests {
    typealias Fixture = HomeModelTests.Fixture

    /// Siri・ショートカットの頼みを受け取ったら、会話のページに戻す（返事を会話のページに出すため）。
    @Test func quickActionShowsConversation() throws {
        let fixture = try Fixture()
        fixture.model.page = .calendar

        fixture.model.receive(.record(""))

        #expect(fixture.model.page == .conversation)
    }

    /// カレンダーのページはホームと同じ記録の保存先を読む。
    @Test func calendarPageReadsSameStore() async throws {
        let fixture = try Fixture()
        fixture.model.calendarPage.configure(calendar: TestSupport.calendar)

        await fixture.send("ランチ 850")
        fixture.model.calendarPage.reload()

        #expect(fixture.model.calendarPage.selectedRecords.map(\.memo) == ["ランチ"])
    }
}
