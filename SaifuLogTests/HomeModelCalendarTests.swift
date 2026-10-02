import Foundation
import SaifuLogCore
import SwiftData
import Testing
@testable import SaifuLog

/// ホームの会話とカレンダーのページの行き来（「この日に記録」・Siri の頼みで会話へ戻る）。
@MainActor
struct HomeModelCalendarTests {
    typealias Fixture = HomeModelTests.Fixture

    /// 「この日に記録」は、会話へ戻って入力欄の頭にその日の日付を入れ、キーボードを出す。続けて書いて送ると、その日の記録になる。
    @Test func recordOnDayFillsDateAndRecordsOnThatDay() async throws {
        let fixture = try Fixture()
        fixture.model.page = .calendar
        let focusRequest = fixture.model.inputFocusRequest

        fixture.model.prepareDraft(for: TestSupport.date(2026, 9, 25), calendar: TestSupport.calendar)

        #expect(fixture.model.page == .conversation)
        #expect(fixture.model.draft == "9/25 ")
        #expect(fixture.model.inputFocusRequest == focusRequest + 1)
        // 入力欄へフォーカスを移すので、この切り替えでは VoiceOver に画面が替わったことを知らせない。次の切り替えでは知らせる。
        #expect(!fixture.model.consumePageChange())
        #expect(fixture.model.consumePageChange())

        await fixture.send(fixture.model.draft + "ランチ 850")

        let entry = try #require(try fixture.entries().last)
        #expect(entry.amount == 850)
        #expect(entry.memo == "ランチ")
        #expect(TestSupport.calendar.isDate(entry.spentAt, inSameDayAs: TestSupport.date(2026, 9, 25)))
    }

    /// 打ちかけの文は残し、前に入れた日付だけを差し替える。今日を選んだら日付を外す。今年でない日は年も書く。
    @Test func recordOnDayReplacesOnlyTheDate() throws {
        let fixture = try Fixture()
        fixture.model.draft = "ランチ 850"

        fixture.model.prepareDraft(for: TestSupport.date(2026, 9, 25), calendar: TestSupport.calendar)
        #expect(fixture.model.draft == "9/25 ランチ 850")

        fixture.model.prepareDraft(for: TestSupport.date(2026, 9, 20), calendar: TestSupport.calendar)
        #expect(fixture.model.draft == "9/20 ランチ 850")

        fixture.model.prepareDraft(for: TestSupport.date(2026, 9, 28, hour: 23), calendar: TestSupport.calendar)
        #expect(fixture.model.draft == "ランチ 850")

        fixture.model.prepareDraft(for: TestSupport.date(2025, 12, 31), calendar: TestSupport.calendar)
        #expect(fixture.model.draft == "2025/12/31 ランチ 850")
    }

    /// 入れた日付を利用者が消して打ち直したら、次の「この日に記録」は前の日付を探さずに頭に足す（打った文を消さない）。
    @Test func recordOnDayKeepsEditedText() throws {
        let fixture = try Fixture()
        fixture.model.prepareDraft(for: TestSupport.date(2026, 9, 25), calendar: TestSupport.calendar)
        fixture.model.draft = "コーヒー 400"

        fixture.model.prepareDraft(for: TestSupport.date(2026, 9, 24), calendar: TestSupport.calendar)

        #expect(fixture.model.draft == "9/24 コーヒー 400")
    }

    /// 日付を入れた後も、よく使うひとことの候補を出し（日付を除いて絞る）、選ぶと日付の後ろに入れる。送ったら日付は覚えておかない。
    @Test func quickPhrasesKeepCalendarDate() async throws {
        let fixture = try Fixture()
        await fixture.send("ランチ 850")
        await fixture.send("ランチ 850")
        fixture.model.refreshQuickPhrases()

        fixture.model.prepareDraft(for: TestSupport.date(2026, 9, 25), calendar: TestSupport.calendar)
        #expect(fixture.model.quickPhraseSuggestions.map(\.item) == ["ランチ"])
        fixture.model.draft += "ラ"
        #expect(fixture.model.quickPhraseSuggestions.map(\.item) == ["ランチ"])

        fixture.model.pickQuickPhrase(try #require(fixture.model.quickPhraseSuggestions.first))
        #expect(fixture.model.draft == "9/25 ランチ 850")

        await fixture.model.send(calendar: TestSupport.calendar)?.value
        let entry = try #require(try fixture.entries().last)
        #expect(TestSupport.calendar.isDate(entry.spentAt, inSameDayAs: TestSupport.date(2026, 9, 25)))
        // 送った後に自分で打った日付は、カレンダーで入れた日付ではない（数字を含む文なので、これまでどおり候補を出さない）。
        fixture.model.draft = "9/25 ラ"
        #expect(fixture.model.quickPhraseSuggestions.isEmpty)
    }

    /// Siri・ショートカットの頼みを受け取ったら、会話のページに戻す（返事も入力欄・カメラ・声も会話のページに出すため）。
    @Test func quickActionShowsConversation() throws {
        let fixture = try Fixture()
        fixture.model.page = .calendar

        fixture.model.receive(.compose)

        #expect(fixture.model.page == .conversation)
    }

    /// カレンダーのページは「自分」の記録の保存先を読む（ホームと同じ記録・予算・くり返しの記録）。
    @Test func calendarPageReadsSameStore() async throws {
        let fixture = try Fixture()
        fixture.model.calendarPage.configure(calendar: TestSupport.calendar)

        await fixture.send("ランチ 850")
        fixture.model.calendarPage.reload()

        #expect(fixture.model.calendarPage.selectedRecords.map(\.memo) == ["ランチ"])
        #expect(fixture.model.showsCalendarPage)
    }
}
