import Foundation
import Testing
@testable import SaifuLogCore

@Suite("無料の回数")
struct UsageQuotaTests {
    static let trial = PremiumStatus.trial(daysRemaining: 10, endsAt: Fixture.date(2026, 10, 8))

    /// 使った回数を `times` 回数えたもの。
    static func quota(
        _ feature: QuotaFeature = .receiptScan, used times: Int, at now: Date = Fixture.now,
        calendar: Calendar = Fixture.calendar
    ) -> UsageQuota {
        var quota = UsageQuota()
        for _ in 0..<times {
            quota.recordUse(of: feature, status: .free, now: now, calendar: calendar)
        }
        return quota
    }

    @Test("無料はレシート月 5 回・質問月 10 回")
    func freeLimits() {
        #expect(QuotaFeature.receiptScan.freeMonthlyLimit == 5)
        #expect(QuotaFeature.question.freeMonthlyLimit == 10)
        #expect(UsageQuota().allowance(for: .receiptScan, status: .free, now: Fixture.now, calendar: Fixture.calendar)
            == .limited(remaining: 5, limit: 5))
        #expect(UsageQuota().allowance(for: .question, status: .free, now: Fixture.now, calendar: Fixture.calendar)
            == .limited(remaining: 10, limit: 10))
    }

    /// 保存に使うので変えない。
    @Test("機能の rawValue は変えない")
    func featureRawValuesAreStable() {
        #expect(QuotaFeature.receiptScan.rawValue == "receiptScan")
        #expect(QuotaFeature.question.rawValue == "question")
    }

    @Test("上限まで使えて、使い切ったら数えずに断る", arguments: QuotaFeature.allCases)
    func usesUpToLimit(feature: QuotaFeature) {
        var quota = UsageQuota()
        for used in 0..<feature.freeMonthlyLimit {
            #expect(quota.allowance(for: feature, status: .free, now: Fixture.now, calendar: Fixture.calendar)
                == .limited(remaining: feature.freeMonthlyLimit - used, limit: feature.freeMonthlyLimit))
            let used = quota.recordUse(of: feature, status: .free, now: Fixture.now, calendar: Fixture.calendar)
            #expect(used)
        }

        let allowance = quota.allowance(for: feature, status: .free, now: Fixture.now, calendar: Fixture.calendar)
        #expect(allowance == .limited(remaining: 0, limit: feature.freeMonthlyLimit))
        #expect(!allowance.canUse)
        let refused = !quota.recordUse(of: feature, status: .free, now: Fixture.now, calendar: Fixture.calendar)
        #expect(refused)
        #expect(quota.count(at: Fixture.now, calendar: Fixture.calendar) == feature.freeMonthlyLimit)
    }

    /// 体験が月の途中で終わっても、その月の無料の回数を体験中に使った分で減らさない。
    @Test("プレミアムと体験中は無制限で、使っても数えない", arguments: [
        PremiumStatus.premium(.purchased), .premium(.familyShared), UsageQuotaTests.trial,
    ])
    func unlimitedWhenUnlocked(status: PremiumStatus) {
        var quota = Self.quota(used: 5)

        #expect(quota.allowance(for: .receiptScan, status: status, now: Fixture.now, calendar: Fixture.calendar) == .unlimited)
        #expect(quota.allowance(for: .receiptScan, status: status, now: Fixture.now, calendar: Fixture.calendar).canUse)
        for _ in 0..<20 {
            let used = quota.recordUse(of: .receiptScan, status: status, now: Fixture.now, calendar: Fixture.calendar)
            #expect(used)
        }
        #expect(quota.count(at: Fixture.now, calendar: Fixture.calendar) == 5)
    }

    @Test("体験が終わったら無料の上限に戻る")
    func trialEndedIsLimited() {
        let quota = Self.quota(used: 2)

        #expect(quota.allowance(
            for: .receiptScan, status: .trialEnded(endedAt: Fixture.date(2026, 9, 20)), now: Fixture.now, calendar: Fixture.calendar
        ) == .limited(remaining: 3, limit: 5))
    }

    @Test("月末 23:59 は同じ月、翌月 0:00 から 0 に戻る")
    func resetsAtStartOfNextMonth() {
        var quota = Self.quota(used: 5, at: Fixture.date(2026, 9, 1))

        #expect(quota.count(at: Fixture.date(2026, 9, 30, hour: 23, minute: 59), calendar: Fixture.calendar) == 5)
        let refused = !quota.recordUse(
            of: .receiptScan, status: .free, now: Fixture.date(2026, 9, 30, hour: 23, minute: 59), calendar: Fixture.calendar
        )
        #expect(refused)

        let october = Fixture.date(2026, 10, 1)
        #expect(quota.count(at: october, calendar: Fixture.calendar) == 0)
        #expect(quota.allowance(for: .receiptScan, status: .free, now: october, calendar: Fixture.calendar)
            == .limited(remaining: 5, limit: 5))
        let used = quota.recordUse(of: .receiptScan, status: .free, now: october, calendar: Fixture.calendar)
        #expect(used)
        #expect(quota.count(at: october, calendar: Fixture.calendar) == 1)
        #expect(quota.month == QuotaMonth(containing: october, calendar: Fixture.calendar))
    }

    @Test("年をまたいでも 0 に戻る")
    func resetsAcrossYear() {
        let quota = Self.quota(.question, used: 10, at: Fixture.date(2026, 12, 31, hour: 23, minute: 59))

        #expect(quota.count(at: Fixture.date(2027, 1, 1), calendar: Fixture.calendar) == 0)
        // 1 年後の同じ月も別の月。
        #expect(quota.count(at: Fixture.date(2027, 12, 15), calendar: Fixture.calendar) == 0)
    }

    @Test("閏年の 2/29 は 2 月、3/1 0:00 から 0 に戻る")
    func leapYear() {
        let quota = Self.quota(used: 5, at: Fixture.date(2028, 2, 1))

        #expect(quota.count(at: Fixture.date(2028, 2, 29, hour: 23, minute: 59), calendar: Fixture.calendar) == 5)
        #expect(quota.count(at: Fixture.date(2028, 3, 1), calendar: Fixture.calendar) == 0)

        // 閏年でない年は 2/28 の次が 3/1。
        let common = Self.quota(used: 5, at: Fixture.date(2027, 2, 28, hour: 23, minute: 59))
        #expect(common.count(at: Fixture.date(2027, 3, 1), calendar: Fixture.calendar) == 0)
    }

    /// 月の区切りは端末の時間帯の暦。時間帯を変えても、同じ月のうちは使った回数を残す。
    @Test("同じ月のうちに時間帯を変えても、使った回数は残る")
    func timeZoneChangeWithinMonthKeepsCount() {
        let honolulu = Fixture.calendar(firstWeekday: 1, timeZone: "Pacific/Honolulu")
        // 東京の 9/1 0:30 に使い切り、ホノルルに移った（その瞬間のホノルルは 8/31 5:30）。
        let usedAt = Fixture.date(2026, 9, 1, minute: 30)
        let quota = Self.quota(used: 5, at: usedAt)

        // ホノルルの 9/1 以降（東京の 9/1 19:00 以降）は、同じ 9 月。
        #expect(quota.count(at: Fixture.date(2026, 9, 2), calendar: honolulu) == 5)
        #expect(quota.count(at: Fixture.date(2026, 9, 30, hour: 23), calendar: honolulu) == 5)
        // ホノルルで 10 月になったら 0 に戻る（東京の 10/1 19:00 がホノルルの 10/1 0:00）。
        #expect(quota.count(at: Fixture.date(2026, 10, 1, hour: 18, minute: 59), calendar: honolulu) == 5)
        #expect(quota.count(at: Fixture.date(2026, 10, 1, hour: 19), calendar: honolulu) == 0)
    }

    /// 東京の 10/1 0:30 に使い、その瞬間にホノルル（9/30 5:30）へ移ると、暦の上では前の月に戻る。
    /// 前に戻ったときも別の月として 0 から数える（`UsageQuota.count(at:calendar:)` の説明）。
    @Test("時間帯を変えて前の月に戻ったら、別の月として 0 から数える")
    func timeZoneChangeBackwardAcrossMonthStartsOver() {
        let honolulu = Fixture.calendar(firstWeekday: 1, timeZone: "Pacific/Honolulu")
        let usedAt = Fixture.date(2026, 10, 1, minute: 30)
        let quota = Self.quota(used: 5, at: usedAt)

        #expect(quota.count(at: usedAt, calendar: Fixture.calendar) == 5)
        #expect(quota.count(at: usedAt, calendar: honolulu) == 0)
    }

    /// 和暦は元号が変わると年が 1 に戻る。紀元も見るので、別の元号の同じ年・月を同じ月とみなさない。
    @Test("和暦でも暦の月で区切り、紀元の違う同じ年と月は別の月")
    func japaneseCalendarUsesEra() throws {
        let japanese = Fixture.calendar(firstWeekday: 1, identifier: .japanese)
        let quota = Self.quota(used: 5, at: Fixture.date(2026, 9, 10), calendar: japanese)

        #expect(quota.count(at: Fixture.date(2026, 9, 30, hour: 23, minute: 59), calendar: japanese) == 5)
        #expect(quota.count(at: Fixture.date(2026, 10, 1), calendar: japanese) == 0)

        // 平成 8 年 9 月（1996 年）と令和 8 年 9 月（2026 年）は、年と月の数字が同じでも別の月。
        let heisei = QuotaMonth(containing: Fixture.date(1996, 9, 10), calendar: japanese)
        let reiwa = try #require(quota.month)
        #expect(heisei.year == reiwa.year)
        #expect(heisei.month == reiwa.month)
        #expect(heisei != reiwa)
    }

    @Test("保存用に書き出して読み戻せる")
    func codableRoundTrip() throws {
        let quota = Self.quota(.question, used: 3)

        let data = try JSONEncoder().encode(quota)
        let decoded = try JSONDecoder().decode(UsageQuota.self, from: data)

        #expect(decoded == quota)
        #expect(decoded.count(at: Fixture.now, calendar: Fixture.calendar) == 3)
    }

    @Test("壊れた値（負の回数）でも上限を超えて使えない")
    func negativeCountIsClamped() throws {
        let month = QuotaMonth(containing: Fixture.now, calendar: Fixture.calendar)
        let json = try JSONEncoder().encode(month)
        let text = try #require(String(data: json, encoding: .utf8))
        let broken = try JSONDecoder().decode(UsageQuota.self, from: Data("{\"month\":\(text),\"count\":-3}".utf8))

        #expect(broken.count(at: Fixture.now, calendar: Fixture.calendar) == 0)
        #expect(broken.allowance(for: .receiptScan, status: .free, now: Fixture.now, calendar: Fixture.calendar)
            == .limited(remaining: 5, limit: 5))
    }
    // MARK: - 数えた 1 回を戻す

    /// レシートから記録した直後に「取り消す」を押したら、数えた 1 回を戻す（取り消した記録は数えない決め事。docs/design.md §6）。
    @Test("数えた月を返し、取り消したらその 1 回を戻す")
    func useAndRefund() throws {
        var quota = Self.quota(used: 2)

        let use = quota.use(.receiptScan, status: .free, now: Fixture.now, calendar: Fixture.calendar)
        let month = QuotaMonth(containing: Fixture.now, calendar: Fixture.calendar)
        #expect(use == .counted(month))
        #expect(quota.count(at: Fixture.now, calendar: Fixture.calendar) == 3)

        quota.refund(month)
        #expect(quota.count(at: Fixture.now, calendar: Fixture.calendar) == 2)
    }

    @Test("プレミアムと体験中は数えず、使い切っていたら数えない")
    func useReportsUnlimitedAndLimit() {
        var quota = Self.quota(used: 5)

        #expect(quota.use(.receiptScan, status: .premium(.purchased), now: Fixture.now, calendar: Fixture.calendar) == .unlimited)
        #expect(quota.use(.receiptScan, status: .free, now: Fixture.now, calendar: Fixture.calendar) == .limitReached)
        #expect(quota.count(at: Fixture.now, calendar: Fixture.calendar) == 5)
    }

    /// 月が替わった後は 0 から数えているので、前の月に数えた 1 回を戻して新しい月の回数を減らさない。
    @Test("数えた月と違う月には戻さず、0 回より少なくしない")
    func refundOnlyInCountedMonth() {
        let september = QuotaMonth(containing: Fixture.date(2026, 9, 30, hour: 23), calendar: Fixture.calendar)
        var quota = Self.quota(used: 1, at: Fixture.date(2026, 10, 1, hour: 9))

        quota.refund(september)
        #expect(quota.count(at: Fixture.date(2026, 10, 1, hour: 10), calendar: Fixture.calendar) == 1)

        var empty = UsageQuota()
        empty.refund(september)
        #expect(empty.count == 0)
    }
}

