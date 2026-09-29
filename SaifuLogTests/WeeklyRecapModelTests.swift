import Foundation
import SaifuLogCore
import SwiftData
import Testing
@testable import SaifuLog

/// 先週のふりかえり（HomeModel のカードの出し入れ・WeeklyRecapModel・AI の一言・定型文）。メモリの上の保存先と、
/// 固定の日時（2026-09-28 12:00、日本時間、月曜）で確かめる。月曜始まりの先週は 9/21〜9/27、前の週は 9/14〜9/20。
@MainActor
struct WeeklyRecapModelTests {
    static let mondayFirst: Calendar = {
        var calendar = TestSupport.calendar
        calendar.firstWeekday = 2
        return calendar
    }()

    static let sundayFirst: Calendar = {
        var calendar = TestSupport.calendar
        calendar.firstWeekday = 1
        return calendar
    }()

    /// 記録の購入の事実を途中で差し替えられる箱（体験を始めた・買ったを起こす）。
    @MainActor
    final class PurchaseBox {
        var records: [PremiumPurchase]

        init(_ records: [PremiumPurchase]) {
            self.records = records
        }
    }

    /// HomeModel と、その保存先・時計・プレミアムの状態・AI の一言の書き手の代わり。
    @MainActor
    final class Fixture {
        let context: ModelContext
        let suiteName = "WeeklyRecapModelTests.\(UUID().uuidString)"
        let defaults: UserDefaults
        let box: PurchaseBox
        let purchases: PurchaseManager
        var now = TestSupport.now
        /// AI の一言の書き手。nil なら AI が使えない端末。
        var writer: StubRemarkWriter?
        private(set) var announcements: [String] = []
        private(set) var model: HomeModel!

        init(purchases records: [PremiumPurchase] = []) async throws {
            context = try TestSupport.makeContext()
            defaults = try #require(UserDefaults(suiteName: suiteName))
            let box = PurchaseBox(records)
            self.box = box
            purchases = PurchaseManager(
                now: { TestSupport.now },
                loadPurchases: {
                    box.records.enumerated().map { VerifiedPurchase(transactionID: UInt64($0.offset), purchase: $0.element) }
                },
                loadProducts: { _ in [] },
                sync: {}
            )
            await purchases.refreshPurchases()
            model = makeModel()
        }

        deinit {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }

        /// 同じ保存先と設定で、新しいホームを作る（アプリを開き直したとき）。
        func makeModel() -> HomeModel {
            HomeModel(
                store: EntryStore(context: context),
                purchases: purchases,
                defaults: defaults,
                makeRemarkWriter: { [unowned self] in writer },
                now: { [unowned self] in now },
                announce: { [unowned self] in announcements.append($0) }
            )
        }

        func insert(_ entries: Entry...) throws {
            try EntryStore(context: context).insert(entries)
        }

        /// 全体の予算を `date` の日時に決める。
        func setBudget(_ amount: Int, at date: Date) throws {
            try BudgetStore(context: context, now: { date }).setAmount(amount, for: .total)
        }

        /// 最後にカードを出した日時（設定）。
        var shownAt: Date? {
            defaults.date(for: AppSettings.weeklyRecapShownAt)
        }

        /// カードを出すかを決め、出したカードの AI の一言を書き終えるまで待つ。
        @discardableResult
        func showRecap(calendar: Calendar = WeeklyRecapModelTests.mondayFirst) async -> WeeklyRecapModel? {
            model.showWeeklyRecapIfDue(calendar: calendar)
            await model.weeklyRecap?.remark.currentTask?.value
            return model.weeklyRecap
        }
    }

    static func spend(_ amount: Int, _ category: EntryCategory = .food, at date: Date) -> Entry {
        TestSupport.entry(amount: amount, category: category, memo: category.displayName, spentAt: date, createdAt: date)
    }

    /// 9/10 から記録していて、前の週（9/14〜9/20）に ¥2,000、先週（9/21〜9/27）に食費 ¥3,000 とカフェ ¥800。
    static func insertTwoWeeks(_ fixture: Fixture) throws {
        try fixture.insert(
            spend(500, at: TestSupport.date(2026, 9, 10, hour: 12)),
            spend(2_000, at: TestSupport.date(2026, 9, 15, hour: 12)),
            spend(3_000, at: TestSupport.date(2026, 9, 22, hour: 19)),
            spend(800, .cafe, at: TestSupport.date(2026, 9, 24, hour: 9))
        )
    }

    // MARK: - カードを出す条件

    @Test func recapIsShownOnFirstOpenOfWeek() async throws {
        let fixture = try await Fixture()
        try Self.insertTwoWeeks(fixture)

        let card = try #require(await fixture.showRecap())

        let recap = try #require(card.recap)
        #expect(recap.week == DateInterval(start: TestSupport.date(2026, 9, 21), end: TestSupport.date(2026, 9, 28)))
        #expect(recap.expense == 3_800)
        #expect(recap.change == .more(1_800))
        #expect(recap.topCategories().map(\.category) == [.food, .cafe])
        #expect(card.shownAt == TestSupport.now)
        #expect(card.periodTitle == QuestionTexts.dateRange(recap.week, calendar: Self.mondayFirst))
        // 出した日時を設定に書く（同じ週にはもう出さない）。
        #expect(fixture.shownAt == TestSupport.now)
    }

    @Test func dismissedRecapIsNotShownAgainInSameWeek() async throws {
        let fixture = try await Fixture()
        try Self.insertTwoWeeks(fixture)
        await fixture.showRecap()

        fixture.model.dismissWeeklyRecap()

        #expect(fixture.model.weeklyRecap == nil)
        #expect(fixture.announcements == ["先週のふりかえりを閉じました"])
        // 前面に戻っても、週の終わりまで出さない。
        #expect(await fixture.showRecap() == nil)
        fixture.now = TestSupport.date(2026, 10, 4, hour: 23, minute: 59)
        #expect(await fixture.showRecap() == nil)
    }

    /// 閉じなくても、同じ週にアプリを開き直したら出さない（週が替わって最初に開いたときだけ）。
    @Test func recapIsNotShownAfterRelaunchInSameWeek() async throws {
        let fixture = try await Fixture()
        try Self.insertTwoWeeks(fixture)
        await fixture.showRecap()

        let relaunched = fixture.makeModel()
        relaunched.showWeeklyRecapIfDue(calendar: Self.mondayFirst)

        #expect(relaunched.weeklyRecap == nil)
    }

    @Test func recapIsShownAgainWhenWeekChanges() async throws {
        let fixture = try await Fixture()
        try Self.insertTwoWeeks(fixture)
        let first = try #require(await fixture.showRecap())

        // 開いたまま同じ週のうちは、同じカードのまま。
        #expect(await fixture.showRecap() === first)

        fixture.now = TestSupport.date(2026, 10, 5, hour: 9)
        let second = try #require(await fixture.showRecap())

        #expect(second !== first)
        #expect(second.shownAt == TestSupport.date(2026, 10, 5, hour: 9))
        #expect(second.recap?.week == DateInterval(start: TestSupport.date(2026, 9, 28), end: TestSupport.date(2026, 10, 5)))
        #expect(fixture.shownAt == TestSupport.date(2026, 10, 5, hour: 9))
    }

    /// 記録が無い人・今週から記録を始めた人には、ふりかえる週が無いので出さない（出したことにもしない）。
    @Test func recapIsNotShownWithoutEarlierRecords() async throws {
        let fixture = try await Fixture()

        #expect(await fixture.showRecap() == nil)

        try fixture.insert(Self.spend(850, at: TestSupport.date(2026, 9, 28, hour: 9)))
        #expect(await fixture.showRecap() == nil)
        #expect(fixture.shownAt == nil)
    }

    /// 記録を始めた後で記録の無かった週は、「記録が無かった週」として出す。
    @Test func emptyWeekIsShownAsWeekWithoutRecords() async throws {
        let fixture = try await Fixture()
        try fixture.insert(Self.spend(500, at: TestSupport.date(2026, 9, 10, hour: 12)))

        let card = try #require(await fixture.showRecap())

        let recap = try #require(card.recap)
        #expect(recap.isEmpty)
        #expect(RecapTexts.fixedSentence(for: recap) == "先週は記録がありませんでした。")
    }

    /// 2026-09-27 は日曜。日曜始まりで出した後に月曜始まりに変えると、同じカードのまま、変えた後の先週で数え直す。
    @Test func weekStartChangeRecountsShownRecap() async throws {
        let fixture = try await Fixture()
        fixture.now = TestSupport.date(2026, 9, 27, hour: 12)
        try Self.insertTwoWeeks(fixture)
        let card = try #require(await fixture.showRecap(calendar: Self.sundayFirst))
        #expect(card.recap?.week == DateInterval(start: TestSupport.date(2026, 9, 20), end: TestSupport.date(2026, 9, 27)))
        #expect(card.recap?.expense == 3_800)

        #expect(await fixture.showRecap(calendar: Self.mondayFirst) === card)

        #expect(card.recap?.week == DateInterval(start: TestSupport.date(2026, 9, 14), end: TestSupport.date(2026, 9, 21)))
        #expect(card.recap?.expense == 2_000)
        #expect(fixture.shownAt == TestSupport.date(2026, 9, 27, hour: 12))
    }

    /// 月曜始まりで月曜（9/21）に出した後、日曜（9/27）に日曜始まりに変えると、その日から新しい週なので出す。
    @Test func weekStartChangeCanStartNewWeek() async throws {
        let fixture = try await Fixture()
        fixture.now = TestSupport.date(2026, 9, 27, hour: 12)
        try Self.insertTwoWeeks(fixture)
        fixture.defaults.set(TestSupport.date(2026, 9, 21, hour: 8), for: AppSettings.weeklyRecapShownAt)

        #expect(await fixture.showRecap(calendar: Self.mondayFirst) == nil)
        #expect(await fixture.showRecap(calendar: Self.sundayFirst) != nil)
        #expect(fixture.shownAt == TestSupport.date(2026, 9, 27, hour: 12))
    }

    // MARK: - 中身

    /// reload() で、保存先の今の記録から数字を数え直す（先週の日付で記録したとき）。保存を受けて reload() を呼ぶのは画面
    /// （HomeView が ModelContext.didSave を受ける）なので、ここでは reload() そのものを確かめる。
    @Test func reloadRecountsFromStore() async throws {
        let fixture = try await Fixture()
        try Self.insertTwoWeeks(fixture)
        let card = try #require(await fixture.showRecap())

        try fixture.insert(Self.spend(1_000, .transport, at: TestSupport.date(2026, 9, 26, hour: 8)))
        card.reload()

        #expect(card.recap?.expense == 4_800)
        #expect(card.recap?.topCategories().map(\.category) == [.food, .transport, .cafe])
    }

    @Test func budgetPromptWithoutBudgetOrSuggestion() async throws {
        let fixture = try await Fixture()
        try Self.insertTwoWeeks(fixture)

        let card = try #require(await fixture.showRecap())

        // 記録が 9/10 からで 1 か月分に満たないので、目安は出さず「予算を決める」だけ。
        #expect(card.budgetPrompt == .setBudget(nil))
        #expect(card.recap?.budgetPace == nil)
    }

    /// 8 月 1 日から記録していれば、8 月の支出（¥70,000）を目安にする（表示だけで、予算は変えない）。
    @Test func budgetPromptSuggestsAmountWithoutBudget() async throws {
        let fixture = try await Fixture()
        try fixture.insert(
            Self.spend(40_000, at: TestSupport.date(2026, 8, 1, hour: 9)),
            Self.spend(30_000, at: TestSupport.date(2026, 8, 20))
        )
        try Self.insertTwoWeeks(fixture)

        let card = try #require(await fixture.showRecap())

        guard case .setBudget(let suggestion?) = card.budgetPrompt else {
            Issue.record("予算の目安が出ていない: \(String(describing: card.budgetPrompt))")
            return
        }
        #expect(suggestion.amount == 70_000)
        #expect(suggestion.monthCount == 1)
        #expect(try fixture.context.fetch(FetchDescriptor<Budget>()).isEmpty)
    }

    @Test(arguments: [(100_000, true), (75_000, false)])
    func budgetPromptWithBudget(budget: Int, suggestsChange: Bool) async throws {
        let fixture = try await Fixture()
        try fixture.insert(Self.spend(70_000, at: TestSupport.date(2026, 8, 1, hour: 9)))
        try Self.insertTwoWeeks(fixture)
        try fixture.setBudget(budget, at: TestSupport.date(2026, 9, 1))

        let card = try #require(await fixture.showRecap())

        // 予算があれば、目安（¥70,000）といまの予算の差が 2 割以上のときだけ「予算を変更」を出す。
        let suggestion = try #require(card.suggestion)
        #expect(suggestion.amount == 70_000)
        if suggestsChange {
            #expect(card.budgetPrompt == .changeBudget(suggestion, current: budget))
        } else {
            #expect(card.budgetPrompt == nil)
        }
        // 週の目安は予算 × 7 ÷ 30（9 月）。
        #expect(card.recap?.budgetPace == budget * 7 / 30)
    }

    // MARK: - 内訳

    @Test func detailShowsCardModelAndWeekEntries() async throws {
        let fixture = try await Fixture()
        try Self.insertTwoWeeks(fixture)
        try fixture.insert(
            Self.spend(1_200, at: TestSupport.date(2026, 9, 26, hour: 20)),
            Entry(
                amount: 250_000, isIncome: true, category: .food, memo: "給料", spentAt: TestSupport.date(2026, 9, 25),
                source: .text, originalText: "給料 250000"
            )
        )
        let card = try #require(await fixture.showRecap())

        fixture.model.presentWeeklyRecapDetail()

        #expect(fixture.model.weeklyRecapDetail === card)
        // 先週の食費の支出だけを、使った日時の新しい順に（前の週と収入は入れない）。
        #expect(card.entries(in: .food).map(\.amount) == [1_200, 3_000])
        #expect(card.breakdownItem(for: .food)?.amount == 4_200)
        #expect(card.emptyEntriesText.key == "この週の記録はありません")
    }

    /// 内訳の一覧から直したら、カードと内訳の数字をすぐ読み直す（直してカテゴリが変わった記録は一覧から外れる）。
    @Test func editingFromDetailReloads() async throws {
        let fixture = try await Fixture()
        try Self.insertTwoWeeks(fixture)
        let card = try #require(await fixture.showRecap())
        let lunch = try #require(card.entries(in: .food).first)

        card.presentEdit(lunch)
        let editing = try #require(card.editing)
        editing.category = .entertainment
        #expect(editing.save())

        #expect(card.recap?.breakdown.item(for: .entertainment)?.amount == 3_000)
        #expect(card.entries(in: .food).isEmpty)
    }

    /// 内訳を出している間は、体験の終わりの案内を重ねて出さない。
    @Test func trialEndedPremiumWaitsForRecapDetail() async throws {
        let fixture = try await Fixture(purchases: [TestSupport.trial(startedDaysAgo: 15)])
        try Self.insertTwoWeeks(fixture)
        await fixture.showRecap()
        fixture.model.presentWeeklyRecapDetail()

        fixture.model.presentPremiumIfTrialEnded()

        #expect(fixture.model.premiumSheet == nil)
        fixture.model.weeklyRecapDetail = nil
        fixture.model.presentPremiumIfTrialEnded()
        #expect(fixture.model.premiumSheet != nil)
    }

    // MARK: - AI の一言

    static let premium = [PremiumPurchase(product: .premium, purchaseDate: TestSupport.now)]

    @Test func premiumRecapGetsCheckedAIRemark() async throws {
        let fixture = try await Fixture(purchases: Self.premium)
        fixture.writer = StubRemarkWriter { facts in
            #expect(facts.contains("支出の合計: ¥3,800"))
            return " 先週は¥3,800で、前の週より¥1,800多めでした。\n"
        }
        try Self.insertTwoWeeks(fixture)

        let card = try #require(await fixture.showRecap())

        #expect(card.remark.state == .written("先週は¥3,800で、前の週より¥1,800多めでした。"))
        let recap = try #require(card.recap)
        #expect(RecapTexts.spokenSummary(for: recap, remark: card.remark.state.sentence, calendar: Self.mondayFirst)
            .contains("先週は¥3,800で、前の週より¥1,800多めでした。"))
    }

    /// 体験中もプレミアムと同じく一言を添える。
    @Test func trialRecapGetsAIRemark() async throws {
        let fixture = try await Fixture(purchases: [TestSupport.trial(startedDaysAgo: 2)])
        fixture.writer = StubRemarkWriter { _ in "よく続けられています。" }
        try Self.insertTwoWeeks(fixture)

        #expect(try #require(await fixture.showRecap()).remark.state == .written("よく続けられています。"))
    }

    /// 一言に数字の文に無い数字があれば捨て、定型文だけにする。
    @Test func aiRemarkWithOtherNumbersIsDropped() async throws {
        let fixture = try await Fixture(purchases: Self.premium)
        fixture.writer = StubRemarkWriter { _ in "先週は¥4,000でした。" }
        try Self.insertTwoWeeks(fixture)

        #expect(try #require(await fixture.showRecap()).remark.state == .none)
    }

    /// 無料では AI に書かせない（定型文だけ）。
    @Test func freeRecapHasNoAIRemark() async throws {
        let fixture = try await Fixture()
        let writer = StubRemarkWriter { _ in "よく続けられています。" }
        fixture.writer = writer
        try Self.insertTwoWeeks(fixture)

        #expect(try #require(await fixture.showRecap()).remark.state == .none)
        #expect(writer.calls.count == 0)
    }

    /// AI が使えない端末では、プレミアムでも定型文だけ。
    @Test func recapWithoutAIHasNoRemarkEvenForPremium() async throws {
        let fixture = try await Fixture(purchases: Self.premium)
        try Self.insertTwoWeeks(fixture)

        #expect(try #require(await fixture.showRecap()).remark.state == .none)
    }

    /// 記録が無かった週は、ふりかえる数字が無いので AI に書かせない。
    @Test func emptyWeekHasNoAIRemark() async throws {
        let fixture = try await Fixture(purchases: Self.premium)
        let writer = StubRemarkWriter { _ in "よく続けられています。" }
        fixture.writer = writer
        try fixture.insert(Self.spend(500, at: TestSupport.date(2026, 9, 10, hour: 12)))

        #expect(try #require(await fixture.showRecap()).remark.state == .none)
        #expect(writer.calls.count == 0)
    }

    /// 書けなかった（生成の失敗）ときは添えない。
    @Test func failedAIRemarkIsNotShown() async throws {
        let fixture = try await Fixture(purchases: Self.premium)
        fixture.writer = StubRemarkWriter { _ in throw TestError() }
        try Self.insertTwoWeeks(fixture)

        #expect(try #require(await fixture.showRecap()).remark.state == .none)
    }

    /// 数字の文の支出の合計（¥3,800・¥4,800）ごとに違う一言を書く書き手（書き直した一言が新しい数字のものかを見分けるため）。
    static func totalEchoingWriter() -> StubRemarkWriter {
        StubRemarkWriter { facts in
            facts.contains("支出の合計: ¥4,800") ? "先週は¥4,800でした。" : "先週は¥3,800でした。"
        }
    }

    /// 数字の文が同じなら、読み直しても書き直さない（保存のたびに AI を呼ばない）。変われば、新しい数字で書き直す。
    @Test func aiRemarkIsRewrittenOnlyWhenFactsChange() async throws {
        let fixture = try await Fixture(purchases: Self.premium)
        let writer = Self.totalEchoingWriter()
        fixture.writer = writer
        try Self.insertTwoWeeks(fixture)
        let card = try #require(await fixture.showRecap())
        #expect(card.remark.state == .written("先週は¥3,800でした。"))

        card.reload()
        await card.remark.currentTask?.value
        #expect(writer.calls.count == 1)

        try fixture.insert(Self.spend(1_000, at: TestSupport.date(2026, 9, 26, hour: 8)))
        card.reload()
        await card.remark.currentTask?.value
        #expect(writer.calls.count == 2)
        #expect(card.remark.state == .written("先週は¥4,800でした。"))
    }

    /// 一言を書いている途中で記録が増えて数字の文が替わったら、古い数字の文に合わせた一言は、後から書き終わっても出さない
    /// （照合は古い文で通ってしまうので、画面の新しい数字の隣に古い数字の一言が並ばないように）。
    @Test func staleAIRemarkIsDiscardedWhenFactsChangeMidWrite() async throws {
        let fixture = try await Fixture(purchases: Self.premium)
        let started = Gate(), release = Gate()
        let writer = StubRemarkWriter { facts in
            guard facts.contains("支出の合計: ¥4,800") else {
                started.open()
                await release.wait()
                return "先週は¥3,800でした。"
            }
            return "先週は¥4,800でした。"
        }
        fixture.writer = writer
        try Self.insertTwoWeeks(fixture)
        fixture.model.showWeeklyRecapIfDue(calendar: Self.mondayFirst)
        let card = try #require(fixture.model.weeklyRecap)
        let staleTask = try #require(card.remark.currentTask)
        await started.wait()
        #expect(card.remark.state == .writing)

        try fixture.insert(Self.spend(1_000, .transport, at: TestSupport.date(2026, 9, 26, hour: 8)))
        card.reload()
        await card.remark.currentTask?.value
        #expect(card.remark.state == .written("先週は¥4,800でした。"))

        release.open()
        await staleTask.value

        #expect(card.remark.state == .written("先週は¥4,800でした。"))
        #expect(writer.calls.count == 2)
    }

    /// 無料のときに出したカードでも、体験を始めたら一言を添える（ホームがプレミアムの状態の変化で決め直させる）。
    @Test func aiRemarkAppearsAfterTrialStarts() async throws {
        let fixture = try await Fixture()
        fixture.writer = StubRemarkWriter { _ in "よく続けられています。" }
        try Self.insertTwoWeeks(fixture)
        let card = try #require(await fixture.showRecap())
        #expect(card.remark.state == .none)

        fixture.box.records = [TestSupport.trial(startedDaysAgo: 0)]
        await fixture.purchases.refreshPurchases()
        fixture.model.premiumStatusDidChange()
        await card.remark.currentTask?.value

        #expect(card.remark.state == .written("よく続けられています。"))
    }

    /// 返金されて無料に戻ったら、出しているカードの一言を外す（ホームがプレミアムの状態の変化で決め直させる）。
    @Test func aiRemarkIsRemovedAfterRefund() async throws {
        let fixture = try await Fixture(purchases: Self.premium)
        let writer = StubRemarkWriter { _ in "よく続けられています。" }
        fixture.writer = writer
        try Self.insertTwoWeeks(fixture)
        let card = try #require(await fixture.showRecap())
        #expect(card.remark.state == .written("よく続けられています。"))

        fixture.box.records = []
        await fixture.purchases.refreshPurchases()
        fixture.model.premiumStatusDidChange()
        await card.remark.currentTask?.value

        #expect(card.remark.state == .none)
        #expect(writer.calls.count == 1)
    }

    // MARK: - 月のまとめの AI の一言

    @Test func monthlyReportGetsAIRemarkForPremium() async throws {
        let fixture = try await Fixture(purchases: Self.premium)
        let writer = StubRemarkWriter { facts in
            facts.contains("2026年8月") ? "先月もおつかれさまでした。" : "今月の支出は¥6,300です。"
        }
        fixture.writer = writer
        try Self.insertTwoWeeks(fixture)
        try fixture.insert(Self.spend(4_000, at: TestSupport.date(2026, 8, 20)))

        fixture.model.presentMonthlyReport(calendar: TestSupport.calendar)
        let report = try #require(fixture.model.monthlyReport)
        await report.remark.currentTask?.value
        #expect(report.remark.state == .written("今月の支出は¥6,300です。"))

        // 月送りで行き来しても、同じ月の一言は書き直さない。
        report.showPreviousMonth()
        await report.remark.currentTask?.value
        #expect(report.remark.state == .written("先月もおつかれさまでした。"))
        report.showNextMonth()
        await report.remark.currentTask?.value
        #expect(report.remark.state == .written("今月の支出は¥6,300です。"))
        #expect(writer.calls.count == 2)
    }

    @Test func monthlyReportHasNoAIRemarkForFree() async throws {
        let fixture = try await Fixture()
        let writer = StubRemarkWriter { _ in "今月もおつかれさまでした。" }
        fixture.writer = writer
        try Self.insertTwoWeeks(fixture)

        fixture.model.presentMonthlyReport(calendar: TestSupport.calendar)
        let report = try #require(fixture.model.monthlyReport)
        await report.remark.currentTask?.value

        #expect(report.remark.state == .none)
        #expect(writer.calls.count == 0)
    }

    // MARK: - 定型文

    static func recap(thisWeek: Int?, previousWeek: Int?) throws -> WeeklyRecap {
        var records: [LedgerRecordValue] = []
        if let thisWeek { records.append(LedgerRecordValue(amount: thisWeek, spentAt: TestSupport.date(2026, 9, 23))) }
        if let previousWeek { records.append(LedgerRecordValue(amount: previousWeek, spentAt: TestSupport.date(2026, 9, 16))) }
        return try #require(WeeklyRecap(records: records, now: TestSupport.now, calendar: mondayFirst))
    }

    @Test(arguments: [
        (12_300, 14_400, "先週の支出は ¥12,300。前の週より ¥2,100 少なめでした。"),
        (12_300, 10_000, "先週の支出は ¥12,300。前の週より ¥2,300 多めでした。"),
        (12_300, 12_300, "先週の支出は ¥12,300。前の週と同じでした。"),
    ])
    func fixedSentenceComparesWithPreviousWeek(thisWeek: Int, previousWeek: Int, expected: String) throws {
        #expect(RecapTexts.fixedSentence(for: try Self.recap(thisWeek: thisWeek, previousWeek: previousWeek)) == expected)
    }

    /// 前の週に支出の記録が無ければ比べない。
    @Test func fixedSentenceWithoutPreviousWeek() throws {
        #expect(RecapTexts.fixedSentence(for: try Self.recap(thisWeek: 12_300, previousWeek: nil)) == "先週の支出は ¥12,300 でした。")
    }

    /// 記録が 0 件の週は「記録が無かった週」（前の週に支出があっても、比べる文にしない）。
    @Test func fixedSentenceForWeekWithoutRecords() throws {
        #expect(RecapTexts.fixedSentence(for: try Self.recap(thisWeek: nil, previousWeek: 5_000)) == "先週は記録がありませんでした。")
        #expect(RecapTexts.emptyWeekHint.contains("9/23 ランチ 850"))
    }

    @Test func paceComparisonText() throws {
        let records = [LedgerRecordValue(amount: 12_300, spentAt: TestSupport.date(2026, 9, 23))]
        let recap = try #require(WeeklyRecap(
            records: records, now: TestSupport.now, budget: 150_000, budgetDecidedAt: TestSupport.date(2026, 9, 1),
            calendar: Self.mondayFirst
        ))

        #expect(RecapTexts.paceComparison(for: recap)?.text == "週の目安 ¥35,000 より ¥22,700 少ない")
        #expect(RecapTexts.paceComparison(for: try Self.recap(thisWeek: 1_000, previousWeek: nil)) == nil)
    }

    // MARK: - 指示文

    #if canImport(FoundationModels)
    /// 指示文に、具体的な数字や単位の例を書かない（モデルが入力に無くても写して返すため）。
    @Test func remarkInstructionsHaveNoNumberExamples() {
        let text = FoundationModelsRecapRemarkWriter.instructions
        #expect(!text.contains { ("0"..."9").contains($0) || ("０"..."９").contains($0) })
        #expect(!text.contains("円"))
        #expect(!text.contains("¥"))
    }
    #endif
}
