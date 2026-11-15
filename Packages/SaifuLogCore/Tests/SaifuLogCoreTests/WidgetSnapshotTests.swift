import Foundation
import Testing
@testable import SaifuLogCore

/// ウィジェットに渡す今月の数字（`WidgetSnapshot`）。アプリが書いた数字を、ウィジェットが描く時点の月に合わせて出す。
@Suite("ウィジェットの数字")
struct WidgetSnapshotTests {
    /// 2026 年 9 月（Fixture の今日の月）。
    static let september = DateInterval(start: Fixture.date(2026, 9, 1), end: Fixture.date(2026, 10, 1))

    @Test("同じ月なら、使った額と予算の残りをそのまま出す")
    func sameMonth() throws {
        let snapshot = WidgetSnapshot.figures(spent: 57_000, budget: 150_000, month: Self.september)

        guard case .figures(let spent, let budget) = snapshot.display(now: Fixture.now, calendar: Fixture.calendar) else {
            Issue.record("数字が出ません")
            return
        }
        #expect(spent == 57_000)
        let status = try #require(budget)
        #expect(status.budget == 150_000)
        #expect(status.remaining == 93_000)
        #expect(!status.isOver)
    }

    @Test("予算を超えたら、超えた額とバーの割合 1 を出す")
    func overBudget() throws {
        let snapshot = WidgetSnapshot.figures(spent: 162_000, budget: 150_000, month: Self.september)

        guard case .figures(_, let budget) = snapshot.display(now: Fixture.now, calendar: Fixture.calendar) else {
            Issue.record("数字が出ません")
            return
        }
        let status = try #require(budget)
        #expect(status.isOver)
        #expect(status.overspent == 12_000)
        #expect(status.spentFraction == 1)
    }

    @Test("予算を決めていなければ（0 以下も）、使った額だけ")
    func withoutBudget() {
        for budget in [nil, 0, -1] {
            let snapshot = WidgetSnapshot.figures(spent: 42_380, budget: budget, month: Self.september)
            #expect(snapshot.budget == nil)
            #expect(snapshot.display(now: Fixture.now, calendar: Fixture.calendar) == .figures(spent: 42_380, budget: nil))
        }
    }

    /// 月が替わってからアプリを開いていなければ、前の月の額を今月の額として出さない。
    @Test("数えた月が終わっていれば、使った額は 0 にし、予算は同じ全体の予算で数える")
    func nextMonthStartsFromZero() throws {
        let snapshot = WidgetSnapshot.figures(spent: 57_000, budget: 150_000, month: Self.september)

        for now in [Fixture.date(2026, 10, 1), Fixture.date(2026, 10, 15, hour: 9), Fixture.date(2026, 12, 3)] {
            guard case .figures(let spent, let budget) = snapshot.display(now: now, calendar: Fixture.calendar) else {
                Issue.record("数字が出ません")
                return
            }
            #expect(spent == 0)
            let status = try #require(budget)
            #expect(status.budget == 150_000)
            #expect(status.remaining == 150_000)
        }
        // 月の終わりの直前までは、その月の数字。
        guard case .figures(let lastMinute, _) = snapshot.display(
            now: Fixture.date(2026, 9, 30, hour: 23, minute: 59), calendar: Fixture.calendar
        ) else {
            Issue.record("数字が出ません")
            return
        }
        #expect(lastMinute == 57_000)
    }

    @Test("アプリのロック中は数字を出さない（数字の項目も持たない）")
    func hiddenWhileAppLocked() {
        let snapshot = WidgetSnapshot.hidden

        #expect(snapshot.hidesFigures)
        #expect(snapshot.spent == 0)
        #expect(snapshot.budget == nil)
        #expect(snapshot.monthStart == nil)
        #expect(snapshot.display(now: Fixture.now, calendar: Fixture.calendar) == .hidden)
    }

    @Test("ファイルに書いた中身を読み戻せる。形や版の違うものは読まない")
    func roundTrip() throws {
        let snapshot = WidgetSnapshot.figures(spent: 57_000, budget: 150_000, month: Self.september)

        #expect(WidgetSnapshot.decode(try snapshot.encoded()) == snapshot)
        #expect(WidgetSnapshot.decode(try WidgetSnapshot.hidden.encoded()) == .hidden)
        #expect(WidgetSnapshot.decode(Data("not json".utf8)) == nil)

        var object = try #require(JSONSerialization.jsonObject(with: try snapshot.encoded()) as? [String: Any])
        object["version"] = WidgetSnapshot.currentVersion + 1
        #expect(WidgetSnapshot.decode(try JSONSerialization.data(withJSONObject: object)) == nil)
    }

    /// 渡すのは月・使った額・予算だけ（記録の品目やメモは、保存先より弱い保護の場所に置かない）。
    @Test("ファイルに書くのは版・隠すか・月・使った額・予算だけ")
    func encodesOnlyFigures() throws {
        let data = try WidgetSnapshot.figures(spent: 57_000, budget: 150_000, month: Self.september).encoded()
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(Set(object.keys) == ["version", "hidesFigures", "monthStart", "monthEnd", "spent", "budget"])
    }

    @Test("次に描き直すのは次の月の始まり")
    func nextRefreshIsNextMonth() {
        #expect(WidgetSnapshot.nextRefresh(after: Fixture.now, calendar: Fixture.calendar) == Fixture.date(2026, 10, 1))
        #expect(WidgetSnapshot.nextRefresh(after: Fixture.date(2026, 12, 31, hour: 23), calendar: Fixture.calendar)
            == Fixture.date(2027, 1, 1))
    }
}
