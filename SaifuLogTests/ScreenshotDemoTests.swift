// 撮影用のデモは DEBUG のビルドだけにある（Release に入っていないことは release.mk のアーカイブの検査が確かめる）。
#if DEBUG
import Foundation
import SaifuLogCore
import SwiftData
import Testing
@testable import SaifuLog

/// 撮影用のデモ（App Store のスクリーンショット）。起動引数の読み方、架空の記録の組み立て（件数・日付の範囲・カテゴリ）、
/// 保存先と設定が使い捨てであること、撮る画面の開き方を、メモリの上の保存先と固定の日時で確かめる。
@MainActor
struct ScreenshotDemoTests {
    // MARK: - 起動引数

    @Test("起動引数から撮る画面と購入の状態を読む（購入の状態を省けば、プレミアムのシートは無料・ほかは購入済み）")
    func parsesArguments() {
        let arguments = ["SaifuLog", "-AppleLanguages", "(ja)"]
        #expect(ScreenshotDemo.parse(arguments: arguments + ["-SaifuLogScreenshotDemo", "ask"])
            == .init(screen: .ask, premium: .purchased))
        #expect(ScreenshotDemo.parse(arguments: arguments + ["-SaifuLogScreenshotDemo", "premium"])
            == .init(screen: .premium, premium: .free))
        #expect(ScreenshotDemo.parse(arguments: arguments + ["-SaifuLogScreenshotDemo", "trial"])
            == .init(screen: .trial, premium: .free))
        #expect(ScreenshotDemo.parse(arguments: [
            "SaifuLog", "-SaifuLogScreenshotPremium", "free", "-SaifuLogScreenshotDemo", "report",
        ]) == .init(screen: .report, premium: .free))
        // 知らない購入の状態は、画面ごとの既定にする。
        #expect(ScreenshotDemo.parse(arguments: [
            "SaifuLog", "-SaifuLogScreenshotDemo", "home", "-SaifuLogScreenshotPremium", "lifetime",
        ]) == .init(screen: .home, premium: .purchased))
    }

    @Test("撮る画面の引数が無い・値が無い・知らない画面なら、撮影用のデモにしない（ふだんの起動）")
    func ignoresMissingOrUnknownScreen() {
        #expect(ScreenshotDemo.parse(arguments: ["SaifuLog"]) == nil)
        #expect(ScreenshotDemo.parse(arguments: ["SaifuLog", "-SaifuLogScreenshotDemo"]) == nil)
        #expect(ScreenshotDemo.parse(arguments: ["SaifuLog", "-SaifuLogScreenshotDemo", "settings"]) == nil)
        #expect(ScreenshotDemo.parse(arguments: ["SaifuLog", "-SaifuLogScreenshotPremium", "free"]) == nil)
    }

    @Test("テストのプロセスは起動引数を持たないので、撮影用のデモにならない")
    func testProcessIsNotDemo() {
        #expect(ScreenshotDemo.current == nil)
    }

    @Test("デモの「いま」は撮影の月の 15 日の 20:30（月のどの日のどの時刻に撮っても同じ）")
    func pinsNowToMiddleOfShootingMonth() {
        let calendar = TestSupport.calendar
        let september = TestSupport.date(2026, 9, 15, hour: 20, minute: 30)
        for day in [
            TestSupport.date(2026, 9, 1),
            TestSupport.date(2026, 9, 15, hour: 7, minute: 5),
            TestSupport.date(2026, 9, 28, hour: 12),
            TestSupport.date(2026, 9, 30, hour: 23, minute: 59),
        ] {
            #expect(ScreenshotDemo.pinnedNow(on: day, calendar: calendar) == september)
        }
        #expect(ScreenshotDemo.pinnedNow(on: TestSupport.date(2026, 10, 1, hour: 8), calendar: calendar)
            == TestSupport.date(2026, 10, 15, hour: 20, minute: 30))
        #expect(ScreenshotDemo.pinnedNow(on: TestSupport.date(2027, 2, 28, hour: 10), calendar: calendar)
            == TestSupport.date(2027, 2, 15, hour: 20, minute: 30))
    }

    @Test("デモの「いま」は、和暦の暦でもホームの「今月」の 15 日")
    func pinsNowWithJapaneseCalendar() {
        var japanese = Calendar(identifier: .japanese)
        japanese.timeZone = TestSupport.calendar.timeZone
        let pinned = ScreenshotDemo.pinnedNow(on: TestSupport.date(2026, 9, 30, hour: 9), calendar: japanese)
        #expect(pinned == TestSupport.date(2026, 9, 15, hour: 20, minute: 30))
        #expect(ReportPeriod.thisMonth.interval(now: pinned, calendar: japanese)
            == ReportPeriod.thisMonth.interval(now: TestSupport.date(2026, 9, 30), calendar: japanese))
    }

    // MARK: - 架空の記録の組み立て

    /// 撮影の日（月の初め・終わり・月曜・土曜・日曜・年の初め・うるう年でない 3 月）。デモの「いま」はどれもその月の 15 日
    /// （15 日の曜日は月ごとに変わるので、いろいろな月で確かめる）。
    nonisolated static let shootingDays: [Date] = [
        TestSupport.date(2026, 9, 28, hour: 12),
        TestSupport.date(2026, 9, 26, hour: 9),
        TestSupport.date(2026, 9, 27, hour: 18),
        TestSupport.date(2026, 10, 1, hour: 8),
        TestSupport.date(2026, 10, 7, hour: 21),
        TestSupport.date(2026, 8, 31, hour: 23, minute: 50),
        TestSupport.date(2027, 1, 3, hour: 10),
        TestSupport.date(2027, 3, 1, hour: 10),
    ]

    @Test("記録は先月の 1 日からデモの「いま」（撮影の月の 15 日の 20:30）まで、毎日あり、タイムラインの 1 回の読み込み（200 件）に収まる", arguments: shootingDays)
    func recordsCoverLastMonthThroughToday(day: Date) throws {
        let calendar = TestSupport.calendar
        let now = ScreenshotDemo.pinnedNow(on: day, calendar: calendar)
        let records = ScreenshotDemoLedger.records(now: now, calendar: calendar)
        let start = try #require(ScreenshotDemoLedger.startDate(now: now, calendar: calendar))
        #expect(start == ReportPeriod.lastMonth.interval(now: now, calendar: calendar)?.start)

        #expect(!records.isEmpty)
        #expect(records.count < HomeModel.timelinePageSize)
        for record in records {
            #expect(record.spentAt >= start && record.spentAt <= now)
            #expect(record.createdAt >= record.spentAt && record.createdAt <= now)
            #expect(record.amount > 0)
        }
        // 毎日、少なくとも 1 件ある（つけ忘れた日が無い家計にする）。
        let recordedDays = Set(records.map { calendar.startOfDay(for: $0.spentAt) })
        var cursor = start
        while cursor <= now {
            #expect(recordedDays.contains(cursor), "\(cursor) に記録がありません")
            cursor = try #require(calendar.date(byAdding: .day, value: 1, to: cursor))
        }
        // 同じ日時からは同じ記録を作る（日本語と英語で同じ画面になる）。
        #expect(ScreenshotDemoLedger.records(now: now, calendar: calendar) == records)
    }

    @Test("カテゴリは食費・日用品・交通・カフェ・娯楽・光熱・通信・医療の 7 つと給料の収入。割り勘は 1 件だけ", arguments: shootingDays)
    func recordsUseNaturalCategories(day: Date) throws {
        let calendar = TestSupport.calendar
        let now = ScreenshotDemo.pinnedNow(on: day, calendar: calendar)
        let records = ScreenshotDemoLedger.records(now: now, calendar: calendar)

        let expenseCategories = Set(records.filter { !$0.isIncome }.map(\.category))
        #expect(expenseCategories == [.food, .daily, .transport, .cafe, .entertainment, .utilities, .medical])
        let incomes = records.filter(\.isIncome)
        // 給料は毎月 10 日。デモの「いま」（15 日）までに、先月と今月の 2 回が入る。
        #expect(incomes.count == 2)
        #expect(incomes.allSatisfy { calendar.component(.day, from: $0.spentAt) == 10 })
        #expect(incomes.allSatisfy { $0.memo == "給料" && $0.amount == 250_000 && $0.originalText == "給料 25万" })

        let splits = records.filter { $0.originalText == ScreenshotDemoLedger.splitBillText }
        let split = try #require(splits.first)
        #expect(splits.count == 1)
        #expect(split.amount == 3_000)
        #expect(split.category == .food)
        #expect(split.memo == "焼肉（4人で割り勘・総額 ¥12,000・立替 ¥9,000）")
        // 「昨日 …」と翌朝に送った記録（使った日は記録した日の前の日）。
        let recordedDay = calendar.startOfDay(for: split.createdAt)
        #expect(calendar.date(byAdding: .day, value: -1, to: recordedDay) == calendar.startOfDay(for: split.spentAt))
    }

    @Test("数字がスクリーンショットに向く: 先週と今月は食費がいちばん多く、今月は予算の内で、予算の目安の提案は出ない", arguments: shootingDays)
    func figuresSuitScreenshots(day: Date) throws {
        let calendar = TestSupport.calendar
        let demo = try Self.makeDemo(.recap, on: day)
        defer { Self.removeDefaults(of: demo) }
        // mainContext はコンテナが生きている間しか使えないので、コンテナを持っておく。
        let container = try demo.makeContainer()
        let context = container.mainContext
        let entries = try context.fetch(FetchDescriptor<Entry>())
        let budget = ScreenshotDemoLedger.monthlyBudget
        #expect(try BudgetStore(context: context).plan().total == budget)

        // 先週のふりかえり: 先週も前の週も支出があり（前の週との差を出せる）、食費がいちばん多い。
        let recap = try #require(WeeklyRecap(records: entries, now: demo.now, budget: budget, calendar: calendar))
        #expect(!recap.isEmpty)
        #expect(recap.previousSummary.expense > 0)
        #expect(recap.topCategories().first?.category == .food)

        // 月のまとめで開く今月も食費がいちばん多い。
        let thisMonth = try #require(ReportPeriod.thisMonth.interval(now: demo.now, calendar: calendar))
        let monthSummary = LedgerSummary(records: entries, interval: thisMonth, calendar: calendar)
        #expect(CategoryBreakdown(monthSummary).items.first?.category == .food)

        // 帯は「今月あと ¥…」（予算を超えていない）。
        #expect(monthSummary.expense < budget)

        // 予算の目安の提案（予算との差が 2 割以上のときだけ）は、ふりかえりのカードに出さない。
        if let suggestion = BudgetSuggestion(records: entries, now: demo.now, calendar: calendar) {
            #expect(!suggestion.differsNotably(from: budget))
        }
    }

    /// 2 年分の月末（月の支出がいちばん多くなる日）。
    nonisolated static let monthEnds: [Date] = (0..<24).compactMap { offset in
        let firstOfNextMonth = TestSupport.calendar.date(byAdding: .month, value: offset + 1, to: TestSupport.date(2026, 1, 1))
        return firstOfNextMonth.flatMap { TestSupport.calendar.date(byAdding: .minute, value: -1, to: $0) }
    }

    /// 月の最後の日に撮ったときに、帯と月のまとめの「1日あたり」が「残り」と同じ額になり、「今日までの目安」が予算と同じ額に
    /// なっていた（ストアの画像に向かない）。デモの「いま」を月の半ばに置いたので、月末に撮っても月の半ばの数字になる。
    @Test("どの月の月末に撮っても、今月は予算の内で、1日あたりは残りより十分少なく、予算の目安の提案は出ない（2 月のような短い月の後も）", arguments: monthEnds)
    func budgetFitsEveryMonth(day: Date) throws {
        let calendar = TestSupport.calendar
        let now = ScreenshotDemo.pinnedNow(on: day, calendar: calendar)
        #expect(calendar.component(.day, from: now) == ScreenshotDemo.pinnedDay)
        let records = ScreenshotDemoLedger.records(now: now, calendar: calendar).map {
            LedgerRecordValue(amount: $0.amount, isIncome: $0.isIncome, category: $0.category, spentAt: $0.spentAt)
        }
        let budget = ScreenshotDemoLedger.monthlyBudget
        let thisMonth = try #require(ReportPeriod.thisMonth.interval(now: now, calendar: calendar))
        let spent = LedgerSummary(records: records, interval: thisMonth, calendar: calendar).expense
        #expect(spent < budget)
        // 帯と月のまとめの「1日あたり」「のこり N 日」。
        let status = try #require(BudgetStatus(budget: budget, spent: spent, now: now, month: thisMonth, calendar: calendar))
        #expect(status.remainingDays >= 14)
        #expect(status.dailyAllowance * 10 < status.remaining)
        if let suggestion = BudgetSuggestion(records: records, now: now, calendar: calendar) {
            #expect(!suggestion.differsNotably(from: budget), "目安 \(suggestion.amount)")
        }
    }

    // MARK: - 使い捨ての保存先と設定

    @Test("保存先はメモリの上だけ（利用者の記録のファイルを開かない・iCloud と同期しない）で、デモの記録と予算が入っている")
    func containerIsInMemory() throws {
        let demo = try Self.makeDemo(.home)
        defer { Self.removeDefaults(of: demo) }
        let container = try demo.makeContainer()

        #expect(!container.configurations.isEmpty)
        for configuration in container.configurations {
            #expect(configuration.isStoredInMemoryOnly)
            #expect(configuration.url != ModelContainerFactory.storeURL)
            #expect(configuration.cloudKitContainerIdentifier == nil)
        }
        let expected = ScreenshotDemoLedger.records(now: demo.now, calendar: demo.calendar).count
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Entry>()) == expected)
    }

    @Test("撮影用のデモの保存先を開くもの（StoreHost）は、iCloud を使わずにメモリの上の保存先を開く")
    func storeHostOpensInMemoryContainer() throws {
        let demo = try Self.makeDemo(.home)
        defer { Self.removeDefaults(of: demo) }
        let host = demo.makeStoreHost()
        host.start()

        guard case .ready(let container) = host.state else {
            Issue.record("保存先を開けていません: \(host.state)")
            return
        }
        #expect(host.cloudKitDatabase == .none)
        #expect(container.configurations.allSatisfy { $0.isStoredInMemoryOnly })
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Entry>()) > 0)
    }

    @Test("設定は専用の領域を空にして使い、利用者の設定（standard）には書かない。ふりかえりのカードはふりかえりの画面でだけ出す")
    func defaultsAreDisposableAndSeparate() throws {
        let suiteName = "ScreenshotDemoTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        // 前の撮影の残り。
        let leftover = try #require(UserDefaults(suiteName: suiteName))
        leftover.set(true, forKey: "leftover")
        leftover.set(Date.distantPast, for: AppSettings.weeklyRecapShownAt)
        let standardOnboarding = UserDefaults.standard.object(forKey: AppSettings.hasCompletedOnboarding.key) as? Bool
        let standardRecap = UserDefaults.standard.object(forKey: AppSettings.weeklyRecapShownAt.key) as? Date

        let recap = ScreenshotDemo(
            configuration: .init(screen: .recap, premium: .purchased), launchedAt: TestSupport.now,
            calendar: TestSupport.calendar, uiLanguage: "ja", defaultsSuiteName: suiteName
        )
        #expect(recap.defaults !== UserDefaults.standard)
        #expect(recap.defaults.object(forKey: "leftover") == nil)
        #expect(recap.defaults.bool(for: AppSettings.hasCompletedOnboarding))
        #expect(recap.defaults.date(for: AppSettings.weeklyRecapShownAt) == nil)

        let home = ScreenshotDemo(
            configuration: .init(screen: .home, premium: .purchased), launchedAt: TestSupport.now,
            calendar: TestSupport.calendar, uiLanguage: "ja", defaultsSuiteName: suiteName
        )
        #expect(home.defaults.date(for: AppSettings.weeklyRecapShownAt) == home.now)

        #expect(UserDefaults.standard.object(forKey: AppSettings.hasCompletedOnboarding.key) as? Bool == standardOnboarding)
        #expect(UserDefaults.standard.object(forKey: AppSettings.weeklyRecapShownAt.key) as? Date == standardRecap)
    }

    // MARK: - 購入の状態

    @Test("購入の状態は選んだとおりで、価格は App Store を読まずに日本の価格の表示を出す")
    func purchasesFollowChoice() async throws {
        let purchased = try Self.makeDemo(.home)
        defer { Self.removeDefaults(of: purchased) }
        let premium = purchased.makePurchases()
        await premium.refreshPurchases()
        #expect(premium.status == .premium(.purchased))

        let free = try Self.makeDemo(.premium)
        defer { Self.removeDefaults(of: free) }
        let manager = free.makePurchases()
        await manager.refreshPurchases()
        #expect(manager.status == .free)
        #expect(manager.productsState == .loaded)
        #expect(manager.displayPrice(for: .premium) == 1_800.formatted(.currency(code: "JPY")))
        #expect(manager.isOffered(.premium))
        #expect(manager.isOffered(.trial14))
        // シートは読み込み済みとして価格と購入・体験のボタンを出す。
        let sheet = PremiumSheetModel(purchases: manager, announce: { _ in })
        #expect(sheet.premiumPrice == 1_800.formatted(.currency(code: "JPY")))
        #expect(sheet.canPurchase)
        #expect(sheet.canStartTrial)
    }

    // MARK: - 撮る画面の開き方

    @Test("質問の画面: 2 つの質問に答え、日本語の画面では照合を通る AI の一言の代わりを添える")
    func askScreenAnswersWithCheckedRemarks() async throws {
        let (demo, home) = try Self.makeHome(.ask, uiLanguage: "ja")
        defer { Self.removeDefaults(of: demo) }
        await demo.stage(on: home, calendar: demo.calendar)

        #expect(home.questions.map(\.text) == ScreenshotDemo.questions)
        for exchange in home.questions {
            guard case .answered(let answer, let remark, let freeQuestionsLeft) = exchange.state else {
                Issue.record("答えていません: \(exchange.state)")
                continue
            }
            #expect(freeQuestionsLeft == nil)
            guard case .ai(let sentence) = remark else {
                Issue.record("一言がありません: \(String(describing: remark))")
                continue
            }
            #expect(AnswerSentenceCheck.accepts(sentence, facts: LedgerAnswerFacts.text(for: answer, calendar: demo.calendar)))
        }
        // 送った文は入力欄に残らない。
        #expect(home.draft.isEmpty)
    }

    @Test("質問の画面（英語）: AI の一言を添えない（一言は日本語で書かれるため）")
    func askScreenInEnglishHasNoRemarks() async throws {
        let (demo, home) = try Self.makeHome(.ask, uiLanguage: "en")
        defer { Self.removeDefaults(of: demo) }
        await demo.stage(on: home, calendar: demo.calendar)

        #expect(home.questions.count == 2)
        for exchange in home.questions {
            guard case .answered(_, let remark, _) = exchange.state else {
                Issue.record("答えていません: \(exchange.state)")
                continue
            }
            #expect(remark == nil)
        }
    }

    @Test("レシートの画面: 架空の店のレシートを読み、7 品目（食費 5・日用品 2）が合計と合う")
    func receiptScreenReadsDemoReceipt() async throws {
        let (demo, home) = try Self.makeHome(.receipt, uiLanguage: "ja")
        defer { Self.removeDefaults(of: demo) }
        await demo.stage(on: home, calendar: demo.calendar)

        let result = try #require(home.receiptResult)
        #expect(result.state == .ready)
        #expect(result.storeName == ScreenshotDemoReceipt.storeName)
        #expect(result.receiptTotal == ScreenshotDemoReceipt.total)
        #expect(result.lines.count == 7)
        #expect(result.lines.compactMap(\.amount).reduce(0, +) == ScreenshotDemoReceipt.total)
        #expect(result.lines.filter { $0.category == .food }.count == 5)
        #expect(result.lines.filter { $0.category == .daily }.count == 2)
        #expect(demo.calendar.isDate(result.day, inSameDayAs: demo.now))
    }

    @Test("声の画面: 聞いている表示のまま止まらず、確定した文と途中の文を出す")
    func voiceScreenKeepsListening() async throws {
        let (demo, home) = try Self.makeHome(.voice, uiLanguage: "ja")
        defer { Self.removeDefaults(of: demo) }
        await demo.stage(on: home, calendar: demo.calendar)
        await Self.waitUntil { !home.voice.preview(prefix: "").full.isEmpty }

        #expect(home.voice.phase == .listening)
        let preview = home.voice.preview(prefix: "")
        #expect(preview.settled == "ドラッグストア")
        #expect(preview.tentative == "1280円")
        // 時計を止めてあるので、時間がたっても自動で止まらない。
        home.voice.tick()
        #expect(home.voice.phase == .listening)
        home.voice.cancel()
    }

    @Test("月のまとめの画面: 今月を下の端（カテゴリ別のグラフと金額の行）から開き、日本語の画面では照合を通る一言を添える")
    func reportScreenOpensMonthWithRemark() async throws {
        let (demo, home) = try Self.makeHome(.report, uiLanguage: "ja")
        defer { Self.removeDefaults(of: demo) }
        await demo.stage(on: home, calendar: demo.calendar)

        let report = try #require(home.monthlyReport)
        #expect(report.month == ReportPeriod.thisMonth.interval(now: demo.now, calendar: demo.calendar))
        #expect(report.screenshotScrollsToBottom)
        #expect(report.report?.breakdown.isEmpty == false)
        await report.remark.currentTask?.value
        guard case .written(let sentence) = report.remark.state else {
            Issue.record("一言がありません: \(report.remark.state)")
            return
        }
        #expect(sentence.contains("食費"))
    }

    @Test("ふりかえりの画面: ホームが出る前にカードと一言（日本語の画面）を出しそろえる。ほかの画面ではカードを出さない")
    func recapScreenShowsCard() async throws {
        let (demo, home) = try Self.makeHome(.recap, uiLanguage: "ja")
        defer { Self.removeDefaults(of: demo) }
        await demo.prepare(home, calendar: demo.calendar)

        let recap = try #require(home.weeklyRecap)
        #expect(recap.recap?.isEmpty == false)
        guard case .written(let sentence) = recap.remark.state else {
            Issue.record("一言がありません: \(recap.remark.state)")
            return
        }
        #expect(sentence.hasPrefix("先週いちばん多かったのは食費でした。"))

        let (other, otherHome) = try Self.makeHome(.home, uiLanguage: "ja")
        defer { Self.removeDefaults(of: other) }
        await other.prepare(otherHome, calendar: other.calendar)
        otherHome.showWeeklyRecapIfDue(calendar: other.calendar)
        #expect(otherHome.weeklyRecap == nil)
    }

    @Test("ふりかえりの一言の代わりは、数字を書かず、数字の文との照合を通る")
    func recapRemarksPassCheck() {
        let weekly = "期間: 先週の1週間（2026年9月20日から2026年9月26日まで）\n支出の合計: ¥21,390（支出の記録 17件）\n支出の多いカテゴリ: 光熱・通信 ¥9,800（46%）、食費 ¥8,000（37%）"
        let monthly = "期間: 2026年8月1日から2026年8月31日まで\n支出の合計: ¥123,230（支出の記録 80件）"
        #expect(ScreenshotDemoRemarkWriter.remark(from: weekly) == "先週いちばん多かったのは光熱・通信でした。こまめに記録できていて、いい調子です。")
        #expect(RecapRemark.checked(ScreenshotDemoRemarkWriter.remark(from: weekly), facts: weekly) != nil)
        // カテゴリの行が無ければ、カテゴリに触れない。
        #expect(ScreenshotDemoRemarkWriter.remark(from: monthly) == "記録を続けられていて、いい調子です。")
        #expect(RecapRemark.checked(ScreenshotDemoRemarkWriter.remark(from: monthly), facts: monthly) != nil)
    }

    @Test("プレミアムと体験の画面: プレミアムのシートを出し、体験の画面は下の端から開く")
    func premiumScreensPresentSheet() async throws {
        let (premiumDemo, premiumHome) = try Self.makeHome(.premium, uiLanguage: "ja")
        defer { Self.removeDefaults(of: premiumDemo) }
        await premiumDemo.stage(on: premiumHome, calendar: premiumDemo.calendar)
        #expect(premiumHome.premiumSheet?.screenshotScrollsToBottom == false)

        let (trialDemo, trialHome) = try Self.makeHome(.trial, uiLanguage: "ja")
        defer { Self.removeDefaults(of: trialDemo) }
        await trialDemo.stage(on: trialHome, calendar: trialDemo.calendar)
        #expect(trialHome.premiumSheet?.screenshotScrollsToBottom == true)
    }

    // MARK: - Release に入らないことの印

    /// release.mk の RELEASE_SCREENSHOT_DEMO_MARKER と同じ値。15 バイトまでの文字列は、Swift がバイナリに文字列として置かない
    /// ことがあり、そうなると release.mk の「入っていないか」の確かめが空振りする。
    @Test("撮影用のデモの印は release.mk と同じ値で、16 バイト以上")
    func markerMatchesReleaseCheck() {
        #expect(ScreenshotDemo.marker == "SaifuLog-ScreenshotDemo-v1")
        #expect(ScreenshotDemo.marker.utf8.count >= 16)
    }

    // MARK: - 手伝い

    static func makeDemo(_ screen: ScreenshotDemo.Screen, on day: Date = TestSupport.now, uiLanguage: String = "ja") throws
        -> ScreenshotDemo
    {
        ScreenshotDemo(
            configuration: .init(screen: screen, premium: screen.defaultPremium), launchedAt: day,
            calendar: TestSupport.calendar, uiLanguage: uiLanguage,
            defaultsSuiteName: "ScreenshotDemoTests.\(UUID().uuidString)"
        )
    }

    static func removeDefaults(of demo: ScreenshotDemo) {
        UserDefaults.standard.removePersistentDomain(forName: demo.defaultsDomain)
    }

    /// デモのホームのモデル（メモリの上の保存先。購入の事実は読み終えた状態）。
    static func makeHome(_ screen: ScreenshotDemo.Screen, uiLanguage: String) throws -> (ScreenshotDemo, HomeModel) {
        let demo = try makeDemo(screen, uiLanguage: uiLanguage)
        let container = try demo.makeContainer()
        retained.append(container)
        let home = demo.makeHomeModel(
            context: container.mainContext, pendingWrites: PendingStoreWrites(), purchases: demo.makePurchases(),
            storeHost: nil, household: nil
        )
        return (demo, home)
    }

    /// 保存先はコンテナが生きている間しか使えないので、テストの間は持っておく。
    private static var retained: [ModelContainer] = []

    /// 条件がそろうまで待つ（書き起こしの知らせは別の Task で受け取るため）。2 秒でやめる。
    static func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
#endif
