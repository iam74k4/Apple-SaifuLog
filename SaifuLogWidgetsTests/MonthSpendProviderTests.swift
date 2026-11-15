import Foundation
import SaifuLogCore
import Testing

/// ウィジェットの予定（`MonthSpendProvider`）。いまの分と次の月の始まりの分を並べ、アプリを開かなくても月が替わったら 0 から出す。
struct MonthSpendProviderTests {
    typealias Fixture = WidgetFixture

    @Test("いまの分と、次の月の始まりの分（使った額は 0、予算は同じ）を並べる")
    func entriesIncludeNextMonth() throws {
        let snapshot = WidgetSnapshot.figures(spent: 57_000, budget: 150_000, month: Fixture.september)

        let entries = MonthSpendProvider.entries(now: Fixture.now, snapshot: snapshot, calendar: Fixture.calendar)

        #expect(entries.map(\.date) == [Fixture.now, Fixture.date(2026, 10, 1)])
        guard case .figures(let spentNow, let budgetNow) = entries[0].display,
              case .figures(let spentNext, let budgetNext) = entries[1].display
        else {
            Issue.record("数字が並びません: \(entries)")
            return
        }
        let thisMonth = try #require(budgetNow)
        let nextMonth = try #require(budgetNext)
        #expect(spentNow == 57_000)
        #expect(thisMonth.remaining == 93_000)
        #expect(spentNext == 0)
        #expect(nextMonth.remaining == 150_000)
    }

    @Test("アプリのロック中は、どの分も数字を出さない。数字が無ければ、どの分も「開くと出ます」")
    func hiddenAndEmptyStayForAllEntries() {
        let hidden = MonthSpendProvider.entries(now: Fixture.now, snapshot: .hidden, calendar: Fixture.calendar)
        #expect(hidden.count == 2)
        #expect(hidden.allSatisfy { $0.display == .hidden })

        let empty = MonthSpendProvider.entries(now: Fixture.now, snapshot: nil, calendar: Fixture.calendar)
        #expect(empty.count == 2)
        #expect(empty.allSatisfy { $0.display == nil })
    }

    /// ウィジェットを選ぶ画面では、何が出るか分かるよう、数字が無ければ見本を出す。ほかでは見本を出さない（本物の数字と
    /// 取り違えないように）。
    @Test("見本は、選ぶ画面で数字が無いときだけ")
    func sampleOnlyInPreviewWithoutFigures() {
        let empty = MonthSpendEntry(date: Fixture.now, display: nil)
        let real = MonthSpendEntry(date: Fixture.now, display: .figures(spent: 850, budget: nil))

        let previewEmpty = MonthSpendProvider.snapshotEntry(empty, isPreview: true, calendar: Fixture.calendar)
        guard case .figures = previewEmpty.display else {
            Issue.record("選ぶ画面で見本が出ません")
            return
        }
        #expect(MonthSpendProvider.snapshotEntry(empty, isPreview: false, calendar: Fixture.calendar) == empty)
        #expect(MonthSpendProvider.snapshotEntry(real, isPreview: true, calendar: Fixture.calendar) == real)
        let hidden = MonthSpendEntry(date: Fixture.now, display: .hidden)
        #expect(MonthSpendProvider.snapshotEntry(hidden, isPreview: true, calendar: Fixture.calendar) == hidden)
    }
}
