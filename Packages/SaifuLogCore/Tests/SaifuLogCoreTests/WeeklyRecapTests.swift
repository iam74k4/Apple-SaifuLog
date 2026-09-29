import Foundation
import Testing
@testable import SaifuLogCore

/// Fixture の今日は 2026-09-28 12:00（日本時間、月曜）。月曜始まりなら先週は 9/21〜9/27、日曜始まりなら 9/20〜9/26。
@Suite("先週のふりかえり")
struct WeeklyRecapTests {
    static let mondayFirst = Fixture.calendar(firstWeekday: 2)
    static let sundayFirst = Fixture.calendar(firstWeekday: 1)

    static func recap(
        _ records: [TestRecord], now: Date = Fixture.now, budget: Int? = nil, budgetDecidedAt: Date? = nil,
        calendar: Calendar = mondayFirst
    ) throws -> WeeklyRecap {
        try #require(WeeklyRecap(records: records, now: now, budget: budget, budgetDecidedAt: budgetDecidedAt, calendar: calendar))
    }

    static func span(_ start: Date, _ end: Date) -> DateInterval {
        DateInterval(start: start, end: end)
    }

    // MARK: - 合計と内訳

    @Test("先週の支出・前の週との差・カテゴリ別の内訳（週の始まりは含み、次の週の始まりの 0:00 は含まない）")
    func totalsAndBreakdown() throws {
        let records = [
            // 前の週（9/14〜9/20）。
            TestRecord(amount: 5_000, category: .food, spentAt: Fixture.date(2026, 9, 14, hour: 12)),
            TestRecord(amount: 2_000, category: .cafe, spentAt: Fixture.date(2026, 9, 20, hour: 23, minute: 59)),
            // 先週（9/21〜9/27）。
            TestRecord(amount: 850, category: .food, spentAt: Fixture.date(2026, 9, 21)),
            TestRecord(amount: 3_200, category: .food, spentAt: Fixture.date(2026, 9, 23, hour: 19)),
            TestRecord(amount: 800, category: .cafe, spentAt: Fixture.date(2026, 9, 23, hour: 9)),
            TestRecord(amount: 1_500, category: .transport, spentAt: Fixture.date(2026, 9, 25, hour: 8)),
            TestRecord(amount: 400, category: .daily, spentAt: Fixture.date(2026, 9, 27, hour: 23, minute: 59)),
            TestRecord(amount: 250_000, isIncome: true, spentAt: Fixture.date(2026, 9, 25, hour: 10)),
            // 今週（9/28〜）。
            TestRecord(amount: 1_000, category: .food, spentAt: Fixture.date(2026, 9, 28)),
        ]

        let recap = try Self.recap(records)

        #expect(recap.week == Self.span(Fixture.date(2026, 9, 21), Fixture.date(2026, 9, 28)))
        #expect(recap.expense == 6_750)
        #expect(recap.recordCount == 6)
        #expect(!recap.isEmpty)
        #expect(recap.previousSummary.expense == 7_000)
        #expect(recap.expenseChange == -250)
        #expect(recap.change == .less(250))
        #expect(recap.breakdown.items.map(\.category) == [.food, .transport, .cafe, .daily])
        #expect(recap.topCategories().map(\.category) == [.food, .transport, .cafe])
        #expect(recap.topCategories().map(\.amount) == [4_050, 1_500, 800])
        // 9/23 は 3,200 + 800 = 4,000 でいちばん多い。
        #expect(recap.busiestDay == WeeklyRecap.Day(
            interval: Self.span(Fixture.date(2026, 9, 23), Fixture.date(2026, 9, 24)), expense: 4_000
        ))
        // 記録のある日は 9/21・9/23・9/25（収入も数える）・9/27。
        #expect(recap.recordedDayCount == 4)
        #expect(recap.budgetPace == nil)
    }

    @Test("週の始まりが日曜なら、先週は日曜から土曜")
    func sundayFirstWeek() throws {
        let records = [
            TestRecord(amount: 1_000, spentAt: Fixture.date(2026, 9, 20)),
            TestRecord(amount: 2_000, spentAt: Fixture.date(2026, 9, 26, hour: 23, minute: 59)),
            TestRecord(amount: 4_000, spentAt: Fixture.date(2026, 9, 27)),
            TestRecord(amount: 300, spentAt: Fixture.date(2026, 9, 19, hour: 23, minute: 59)),
        ]

        let recap = try Self.recap(records, calendar: Self.sundayFirst)

        #expect(recap.week == Self.span(Fixture.date(2026, 9, 20), Fixture.date(2026, 9, 27)))
        #expect(recap.expense == 3_000)
        #expect(recap.previousSummary.interval == Self.span(Fixture.date(2026, 9, 13), Fixture.date(2026, 9, 20)))
        #expect(recap.change == .more(2_700))
    }

    @Test("日曜の同じ記録は、日曜始まりなら先週の最初の日、月曜始まりなら先週の最後の日")
    func sundayBelongsToDifferentWeeks() throws {
        let sunday = TestRecord(amount: 1_200, spentAt: Fixture.date(2026, 9, 20, hour: 12))
        let now = Fixture.date(2026, 9, 27, hour: 12) // 日曜

        let sundayStart = try Self.recap([sunday], now: now, calendar: Self.sundayFirst)
        let mondayStart = try Self.recap([sunday], now: now, calendar: Self.mondayFirst)

        // 日曜始まりでは、今日（9/27）から今週で、先週は 9/20〜9/26。
        #expect(sundayStart.week == Self.span(Fixture.date(2026, 9, 20), Fixture.date(2026, 9, 27)))
        #expect(sundayStart.expense == 1_200)
        // 月曜始まりでは、今週は 9/21〜9/27 で、先週は 9/14〜9/20。
        #expect(mondayStart.week == Self.span(Fixture.date(2026, 9, 14), Fixture.date(2026, 9, 21)))
        #expect(mondayStart.expense == 1_200)
        #expect(mondayStart.busiestDay?.interval.start == Fixture.date(2026, 9, 20))
    }

    @Test("前の週に支出の記録が無ければ比べない（収入だけの週も）")
    func noComparisonWithoutPreviousExpense() throws {
        let recap = try Self.recap([
            TestRecord(amount: 250_000, isIncome: true, spentAt: Fixture.date(2026, 9, 15)),
            TestRecord(amount: 850, spentAt: Fixture.date(2026, 9, 22)),
        ])

        #expect(recap.expenseChange == nil)
        #expect(recap.change == .noComparison)
    }

    @Test("前の週と同じ額なら同じ")
    func sameAsPreviousWeek() throws {
        let recap = try Self.recap([
            TestRecord(amount: 850, spentAt: Fixture.date(2026, 9, 15)),
            TestRecord(amount: 850, spentAt: Fixture.date(2026, 9, 22)),
        ])

        #expect(recap.expenseChange == 0)
        #expect(recap.change == .same)
    }

    @Test("記録が 1 件も無い週は、記録が無かった週（いちばん使った日も内訳も無い）")
    func emptyWeek() throws {
        let recap = try Self.recap([TestRecord(amount: 3_000, spentAt: Fixture.date(2026, 9, 15))])

        #expect(recap.isEmpty)
        #expect(recap.recordCount == 0)
        #expect(recap.expense == 0)
        #expect(recap.breakdown.isEmpty)
        #expect(recap.topCategories().isEmpty)
        #expect(recap.busiestDay == nil)
        #expect(recap.recordedDayCount == 0)
        #expect(recap.change == .less(3_000))
    }

    @Test("収入だけの週は、記録のある日は数えるが、いちばん使った日は無い")
    func incomeOnlyWeek() throws {
        let recap = try Self.recap([TestRecord(amount: 250_000, isIncome: true, spentAt: Fixture.date(2026, 9, 25))])

        #expect(!recap.isEmpty)
        #expect(recap.expense == 0)
        #expect(recap.recordedDayCount == 1)
        #expect(recap.busiestDay == nil)
        #expect(recap.breakdown.isEmpty)
    }

    @Test("いちばん使った日が同じ額で並んだら、早い日")
    func busiestDayTieGoesToEarlierDay() throws {
        let recap = try Self.recap([
            TestRecord(amount: 2_000, spentAt: Fixture.date(2026, 9, 26, hour: 9)),
            TestRecord(amount: 1_000, spentAt: Fixture.date(2026, 9, 22, hour: 9)),
            TestRecord(amount: 1_000, spentAt: Fixture.date(2026, 9, 22, hour: 20)),
        ])

        #expect(recap.busiestDay?.interval.start == Fixture.date(2026, 9, 22))
        #expect(recap.busiestDay?.expense == 2_000)
    }

    // MARK: - 週の目安

    @Test("月をまたがない週の目安は、予算 × 7 ÷ 月の日数（切り捨て）")
    func paceWithinMonth() throws {
        let recap = try Self.recap(
            [TestRecord(amount: 40_000, spentAt: Fixture.date(2026, 9, 22))],
            budget: 150_000, budgetDecidedAt: Fixture.date(2026, 9, 1)
        )

        // 150,000 × 7 ÷ 30 = 35,000。
        #expect(recap.budgetPace == 35_000)
        #expect(recap.spentBeyondPace == 5_000)
    }

    /// 9/28〜10/4（月曜始まり）は、9 月の 3 日（30 日の月）と 10 月の 4 日（31 日の月）。
    /// 99,995 × 3 ÷ 30 = 9,999.5、99,995 × 4 ÷ 31 = 12,902.58… で、足して 22,902.08…。月ごとに切り捨ててから足すと 22,901 になる。
    @Test("月をまたぐ週の目安は、日ごとに按分して足し、最後に切り捨てる")
    func paceAcrossMonths() throws {
        let now = Fixture.date(2026, 10, 5, hour: 12)
        let recap = try Self.recap(
            [
                TestRecord(amount: 10_000, spentAt: Fixture.date(2026, 9, 30, hour: 20)),
                TestRecord(amount: 5_000, spentAt: Fixture.date(2026, 10, 1, hour: 8)),
            ],
            now: now, budget: 99_995, budgetDecidedAt: Fixture.date(2026, 9, 1)
        )

        #expect(recap.week == Self.span(Fixture.date(2026, 9, 28), Fixture.date(2026, 10, 5)))
        #expect(recap.expense == 15_000)
        #expect(recap.budgetPace == 22_902)
        #expect(recap.spentBeyondPace == -7_902)
    }

    /// 2026-12-28（月）〜2027-01-03（日）は、12 月の 4 日と 1 月の 3 日（どちらも 31 日の月）。
    @Test("年をまたぐ週も 7 日で、目安は両方の月で按分する")
    func weekAcrossYears() throws {
        let now = Fixture.date(2027, 1, 4, hour: 9)
        let recap = try Self.recap(
            [
                TestRecord(amount: 3_000, category: .food, spentAt: Fixture.date(2026, 12, 31, hour: 23, minute: 59)),
                TestRecord(amount: 5_000, category: .entertainment, spentAt: Fixture.date(2027, 1, 1)),
                TestRecord(amount: 2_000, spentAt: Fixture.date(2026, 12, 27, hour: 23, minute: 59)),
            ],
            now: now, budget: 310_000, budgetDecidedAt: Fixture.date(2026, 11, 1)
        )

        #expect(recap.week == Self.span(Fixture.date(2026, 12, 28), Fixture.date(2027, 1, 4)))
        #expect(recap.summary.dayCount == 7)
        #expect(recap.expense == 8_000)
        #expect(recap.previousSummary.interval == Self.span(Fixture.date(2026, 12, 21), Fixture.date(2026, 12, 28)))
        #expect(recap.change == .more(6_000))
        #expect(recap.busiestDay?.interval.start == Fixture.date(2027, 1, 1))
        // 310,000 × 4 ÷ 31 + 310,000 × 3 ÷ 31 = 70,000。
        #expect(recap.budgetPace == 70_000)
    }

    @Test("予算が無い・0 円なら目安を出さない")
    func noBudget() throws {
        let records = [TestRecord(amount: 850, spentAt: Fixture.date(2026, 9, 22))]

        #expect(try Self.recap(records).budgetPace == nil)
        #expect(try Self.recap(records, budget: 0, budgetDecidedAt: Fixture.date(2026, 9, 1)).budgetPace == nil)
        #expect(try Self.recap(records).spentBeyondPace == nil)
    }

    @Test("予算を決めたのが先週の途中なら目安を出し、先週が終わった後なら出さない（決めた日時が分からなければ出さない）")
    func paceOnlyAfterBudgetWasDecided() throws {
        let records = [TestRecord(amount: 850, spentAt: Fixture.date(2026, 9, 22))]

        #expect(try Self.recap(records, budget: 150_000, budgetDecidedAt: Fixture.date(2026, 9, 27, hour: 23, minute: 59))
            .budgetPace == 35_000)
        #expect(try Self.recap(records, budget: 150_000, budgetDecidedAt: Fixture.date(2026, 9, 28)).budgetPace == nil)
        #expect(try Self.recap(records, budget: 150_000, budgetDecidedAt: nil).budgetPace == nil)
    }

    // MARK: - 夏時間

    static let newYork = Fixture.calendar(firstWeekday: 1, timeZone: "America/New_York")

    static func newYorkDate(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        newYork.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// 2026-03-08（日）はニューヨークで夏時間が始まる日で、23 時間しかない。週は 7 日のまま、日の区切りも暦のまま。
    @Test("夏時間の始まる日を含む週も 7 日で、日の区切りは暦の 0 時")
    func daylightSavingStart() throws {
        let now = Self.newYorkDate(2026, 3, 16, hour: 12)
        let recap = try Self.recap(
            [
                TestRecord(amount: 1_000, spentAt: Self.newYorkDate(2026, 3, 8, hour: 23, minute: 30)),
                TestRecord(amount: 1_500, spentAt: Self.newYorkDate(2026, 3, 9, hour: 0, minute: 30)),
                TestRecord(amount: 800, spentAt: Self.newYorkDate(2026, 3, 14, hour: 23, minute: 59)),
                TestRecord(amount: 9_000, spentAt: Self.newYorkDate(2026, 3, 15)),
            ],
            now: now, budget: 310_000, budgetDecidedAt: Self.newYorkDate(2026, 3, 1), calendar: Self.newYork
        )

        #expect(recap.week == Self.span(Self.newYorkDate(2026, 3, 8), Self.newYorkDate(2026, 3, 15)))
        // 23 時間の日があるので、秒数では 7 日に 1 時間足りない。
        #expect(recap.week.duration == 7 * 24 * 3600 - 3600)
        #expect(recap.summary.dayCount == 7)
        #expect(WeeklyRecap.days(in: recap.week, calendar: Self.newYork).count == 7)
        #expect(recap.expense == 3_300)
        #expect(recap.recordedDayCount == 3)
        // 3/8 23:30 は 3/8、3/9 0:30 は 3/9 に数える。
        #expect(recap.busiestDay == WeeklyRecap.Day(
            interval: Self.span(Self.newYorkDate(2026, 3, 9), Self.newYorkDate(2026, 3, 10)), expense: 1_500
        ))
        // 310,000 × 7 ÷ 31 = 70,000（秒数で数えると 7 日に届かない）。
        #expect(recap.budgetPace == 70_000)
    }

    /// 2026-11-01（日）はニューヨークで夏時間が終わる日で、25 時間ある。
    @Test("夏時間の終わる日を含む週も 7 日")
    func daylightSavingEnd() throws {
        let now = Self.newYorkDate(2026, 11, 9, hour: 12)
        let recap = try Self.recap(
            [
                TestRecord(amount: 1_000, spentAt: Self.newYorkDate(2026, 11, 1, hour: 23, minute: 30)),
                TestRecord(amount: 2_000, spentAt: Self.newYorkDate(2026, 11, 2)),
            ],
            now: now, calendar: Self.newYork
        )

        #expect(recap.week == Self.span(Self.newYorkDate(2026, 11, 1), Self.newYorkDate(2026, 11, 8)))
        #expect(recap.week.duration == 7 * 24 * 3600 + 3600)
        #expect(recap.summary.dayCount == 7)
        #expect(recap.recordedDayCount == 2)
        #expect(recap.busiestDay?.interval == Self.span(Self.newYorkDate(2026, 11, 2), Self.newYorkDate(2026, 11, 3)))
    }

    // MARK: - カードを出すか

    @Test("まだ出していなければ、先週より前に記録があるときだけ出す")
    func dueWhenNeverShown() {
        let calendar = Self.mondayFirst

        #expect(WeeklyRecap.isDue(lastShownAt: nil, earliestRecordAt: Fixture.date(2026, 9, 1), now: Fixture.now, calendar: calendar))
        #expect(WeeklyRecap.isDue(
            lastShownAt: nil, earliestRecordAt: Fixture.date(2026, 9, 27, hour: 23, minute: 59), now: Fixture.now, calendar: calendar
        ))
        // 記録が無い・今週から記録を始めた人には出さない（ふりかえる週が無い）。
        #expect(!WeeklyRecap.isDue(lastShownAt: nil, earliestRecordAt: nil, now: Fixture.now, calendar: calendar))
        #expect(!WeeklyRecap.isDue(lastShownAt: nil, earliestRecordAt: Fixture.date(2026, 9, 28), now: Fixture.now, calendar: calendar))
    }

    @Test("今週もう出していれば出さず、先週までに出したのなら出す")
    func dueOncePerWeek() {
        let calendar = Self.mondayFirst
        let earliest = Fixture.date(2026, 8, 1)

        #expect(!WeeklyRecap.isDue(
            lastShownAt: Fixture.date(2026, 9, 28, hour: 8), earliestRecordAt: earliest, now: Fixture.now, calendar: calendar
        ))
        #expect(!WeeklyRecap.isDue(
            lastShownAt: Fixture.date(2026, 9, 28), earliestRecordAt: earliest, now: Fixture.date(2026, 10, 4, hour: 23), calendar: calendar
        ))
        #expect(WeeklyRecap.isDue(
            lastShownAt: Fixture.date(2026, 9, 27, hour: 23, minute: 59), earliestRecordAt: earliest, now: Fixture.now, calendar: calendar
        ))
        #expect(WeeklyRecap.isDue(
            lastShownAt: Fixture.date(2026, 9, 28, hour: 8), earliestRecordAt: earliest, now: Fixture.date(2026, 10, 5), calendar: calendar
        ))
    }

    @Test("端末の時計を先へずらしていたときに出した日時（今週より後）は、出していないとみなす")
    func dueWhenShownInTheFuture() {
        #expect(WeeklyRecap.isDue(
            lastShownAt: Fixture.date(2026, 12, 1), earliestRecordAt: Fixture.date(2026, 8, 1), now: Fixture.now, calendar: Self.mondayFirst
        ))
    }

    /// 2026-09-27 は日曜。
    @Test("週の始まりを変えたら、変えた後の週の区切りで決める")
    func dueAfterWeekStartChange() {
        let earliest = Fixture.date(2026, 8, 1)
        let sunday = Fixture.date(2026, 9, 27, hour: 12)

        // 日曜始まりで日曜の朝に出した後、月曜始まりに変えても、その週（9/21〜）のうちなので出さない。
        #expect(!WeeklyRecap.isDue(
            lastShownAt: Fixture.date(2026, 9, 27, hour: 8), earliestRecordAt: earliest, now: sunday, calendar: Self.mondayFirst
        ))
        // 月曜始まりで月曜（9/21）に出した後、日曜始まりに変えると、日曜（9/27）から新しい週なので出す。
        #expect(WeeklyRecap.isDue(
            lastShownAt: Fixture.date(2026, 9, 21, hour: 8), earliestRecordAt: earliest, now: sunday, calendar: Self.sundayFirst
        ))
        // 月曜始まりのままなら、同じ週なので出さない。
        #expect(!WeeklyRecap.isDue(
            lastShownAt: Fixture.date(2026, 9, 21, hour: 8), earliestRecordAt: earliest, now: sunday, calendar: Self.mondayFirst
        ))
    }
}
