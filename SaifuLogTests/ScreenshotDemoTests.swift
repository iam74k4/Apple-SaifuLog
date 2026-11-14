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

    @Test("起動引数から撮る画面を読む")
    func parsesArguments() {
        let arguments = ["SaifuLog", "-AppleLanguages", "(ja)"]
        #expect(ScreenshotDemo.parse(arguments: arguments + ["-SaifuLogScreenshotDemo", "ask"]) == .init(screen: .ask))
        #expect(ScreenshotDemo.parse(arguments: ["SaifuLog", "-SaifuLogScreenshotDemo", "report"]) == .init(screen: .report))
        #expect(ScreenshotDemo.parse(arguments: arguments + ["-SaifuLogScreenshotDemo", "calendar"]) == .init(screen: .calendar))
    }

    @Test("撮る画面の引数が無い・値が無い・知らない画面なら、撮影用のデモにしない（ふだんの起動）")
    func ignoresMissingOrUnknownScreen() {
        #expect(ScreenshotDemo.parse(arguments: ["SaifuLog"]) == nil)
        #expect(ScreenshotDemo.parse(arguments: ["SaifuLog", "-SaifuLogScreenshotDemo"]) == nil)
        #expect(ScreenshotDemo.parse(arguments: ["SaifuLog", "-SaifuLogScreenshotDemo", "settings"]) == nil)
        // プレミアムをやめたので、プレミアムと体験のシートの画面は無い。
        #expect(ScreenshotDemo.parse(arguments: ["SaifuLog", "-SaifuLogScreenshotDemo", "premium"]) == nil)
        #expect(ScreenshotDemo.parse(arguments: ["SaifuLog", "-SaifuLogScreenshotDemo", "trial"]) == nil)
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

    @Test("記録は先月の 1 日からデモの「いま」（撮影の月の 15 日の 20:30）まで、毎日ある", arguments: shootingDays)
    func recordsCoverLastMonthThroughToday(day: Date) throws {
        let calendar = TestSupport.calendar
        let now = ScreenshotDemo.pinnedNow(on: day, calendar: calendar)
        let records = ScreenshotDemoLedger.records(now: now, calendar: calendar)
        let start = try #require(ScreenshotDemoLedger.startDate(now: now, calendar: calendar))
        #expect(start == ReportPeriod.lastMonth.interval(now: now, calendar: calendar)?.start)

        // タイムラインの 1 回の読み込み（`HomeModel.timelinePageSize`）に収まらないことがある（いちばん上に「前の記録を表示」が出る）が、
        // スクリーンショットに写るのは下の端の直近の記録だけなので、件数は決めない。
        #expect(!records.isEmpty)
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

    /// ホームは送った文（元の文）を自分の吹き出しに、記録を返事に出すので、元の文は実際に送る書き方で、読み直すと同じ記録になる
    /// ものにする（読み取りの AI が無い端末と同じキーワード辞書で確かめる）。1 行に 2 件の送信は、アプリと同じく書いた順に
    /// 記録した日時をずらす（`ParsedEntry.timestamps`）。
    @Test("デモの元の文は、キーワード辞書で読み直すと同じ記録になる（1 行に 2 件の送信・割り勘・収入も）", arguments: shootingDays)
    func originalTextsReadBackToRecords(day: Date) async throws {
        let calendar = TestSupport.calendar
        let now = ScreenshotDemo.pinnedNow(on: day, calendar: calendar)
        let records = ScreenshotDemoLedger.records(now: now, calendar: calendar).sorted { $0.createdAt < $1.createdAt }
        let sends = TimelineSend.groups(of: records.enumerated().map { index, record in
            TimelineSend.Record(id: index, originalText: record.originalText, source: "text", createdAt: record.createdAt)
        }).map { group in group.map { records[$0.id] } }

        for send in sends {
            let first = try #require(send.first)
            let parsed = try await RuleBasedParser(calendar: calendar, now: { first.createdAt }).parse(first.originalText)
            #expect(parsed.map(\.amount) == send.map(\.amount), "\(first.originalText)")
            #expect(parsed.map(\.memo) == send.map(\.memo), "\(first.originalText)")
            #expect(parsed.map(\.category) == send.map(\.category), "\(first.originalText)")
            #expect(parsed.map(\.isIncome) == send.map(\.isIncome), "\(first.originalText)")
            // 使った日（「昨日」なら記録した日の前の日）。時刻はデモのほうが実際に使った時刻（割り勘の夕食）なので比べない。
            let timestamps = ParsedEntry.timestamps(for: parsed, now: first.createdAt, calendar: calendar)
            #expect(timestamps.map(\.createdAt) == send.map(\.createdAt), "\(first.originalText)")
            #expect(
                timestamps.map { calendar.startOfDay(for: $0.spentAt) } == send.map { calendar.startOfDay(for: $0.spentAt) },
                "\(first.originalText)"
            )
        }
    }

    @Test("デモの「いま」の日の最後の送信は、1 行に 2 件を書いた送信（ホームのいちばん下に、2 件の返事のカードが写る）", arguments: shootingDays)
    func latestSendIsMultiItemLine(day: Date) throws {
        let calendar = TestSupport.calendar
        let now = ScreenshotDemo.pinnedNow(on: day, calendar: calendar)
        let records = ScreenshotDemoLedger.records(now: now, calendar: calendar).sorted { $0.createdAt < $1.createdAt }
        let groups = TimelineSend.groups(of: records.enumerated().map { index, record in
            TimelineSend.Record(id: index, originalText: record.originalText, source: "text", createdAt: record.createdAt)
        })
        let latest = try #require(groups.last).map { records[$0.id] }

        #expect(latest.map(\.originalText) == [ScreenshotDemoLedger.multiItemText, ScreenshotDemoLedger.multiItemText])
        #expect(latest.map(\.memo) == ["牛乳", "洗剤"])
        #expect(latest.allSatisfy { calendar.isDate($0.createdAt, inSameDayAs: now) })
        // 同じ文の送信は、デモの「いま」の日と先月の同じ日だけ（ほかの日の送信とまとまらない）。
        #expect(groups.filter { records[$0[0].id].originalText == ScreenshotDemoLedger.multiItemText }.allSatisfy { $0.count == 2 })
    }

    @Test("数字がスクリーンショットに向く: 今月は食費がいちばん多く、予算の内", arguments: shootingDays)
    func figuresSuitScreenshots(day: Date) throws {
        let calendar = TestSupport.calendar
        let demo = try Self.makeDemo(.report, on: day)
        defer { Self.removeDefaults(of: demo) }
        // mainContext はコンテナが生きている間しか使えないので、コンテナを持っておく。
        let container = try demo.makeContainer()
        let context = container.mainContext
        let entries = try context.fetch(FetchDescriptor<Entry>())
        let budget = ScreenshotDemoLedger.monthlyBudget
        let plan = try BudgetStore(context: context).plan()
        #expect(plan.total == budget)

        // 月のまとめで開く今月も食費がいちばん多い。
        let thisMonth = try #require(ReportPeriod.thisMonth.interval(now: demo.now, calendar: calendar))
        let monthSummary = LedgerSummary(records: entries, interval: thisMonth, calendar: calendar)
        #expect(CategoryBreakdown(monthSummary).items.first?.category == .food)

        // 帯は「今月あと ¥…」（予算を超えていない）。
        #expect(monthSummary.expense < budget)
    }

    /// 2 年分の月末（月の支出がいちばん多くなる日）。
    nonisolated static let monthEnds: [Date] = (0..<24).compactMap { offset in
        let firstOfNextMonth = TestSupport.calendar.date(byAdding: .month, value: offset + 1, to: TestSupport.date(2026, 1, 1))
        return firstOfNextMonth.flatMap { TestSupport.calendar.date(byAdding: .minute, value: -1, to: $0) }
    }

    /// 月の最後の日に撮ったときに、帯と月のまとめの「1日あたり」が「残り」と同じ額になり、「今日までの目安」が予算と同じ額に
    /// なっていた（ストアの画像に向かない）。デモの「いま」を月の半ばに置いたので、月末に撮っても月の半ばの数字になる。
    @Test("どの月の月末に撮っても、今月は予算の内で、1日あたりは残りより十分少ない（2 月のような短い月の後も）", arguments: monthEnds)
    func budgetFitsEveryMonth(day: Date) throws {
        let calendar = TestSupport.calendar
        let now = ScreenshotDemo.pinnedNow(on: day, calendar: calendar)
        #expect(calendar.component(.day, from: now) == ScreenshotDemo.pinnedDay)
        let records = ScreenshotDemoLedger.records(now: now, calendar: calendar).map {
            LedgerRecordValue(amount: $0.amount, isIncome: $0.isIncome, category: $0.category, spentAt: $0.spentAt)
        }
        let budget = ScreenshotDemoLedger.monthlyBudget
        let thisMonth = try #require(ReportPeriod.thisMonth.interval(now: now, calendar: calendar))
        let summary = LedgerSummary(records: records, interval: thisMonth, calendar: calendar)
        let spent = summary.expense
        #expect(spent < budget)
        // 帯と月のまとめの「1日あたり」「のこり N 日」。
        let status = try #require(BudgetStatus(budget: budget, spent: spent, now: now, month: thisMonth, calendar: calendar))
        #expect(status.remainingDays >= 14)
        #expect(status.dailyAllowance * 10 < status.remaining)
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

    @Test("設定は専用の領域を空にして使い、利用者の設定（standard）には書かない")
    func defaultsAreDisposableAndSeparate() throws {
        let suiteName = "ScreenshotDemoTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        // 前の撮影の残り。
        let leftover = try #require(UserDefaults(suiteName: suiteName))
        leftover.set(true, forKey: "leftover")
        let standardOnboarding = UserDefaults.standard.object(forKey: AppSettings.hasCompletedOnboarding.key) as? Bool

        let demo = ScreenshotDemo(
            configuration: .init(screen: .home), launchedAt: TestSupport.now,
            calendar: TestSupport.calendar, uiLanguage: "ja", defaultsSuiteName: suiteName
        )
        #expect(demo.defaults !== UserDefaults.standard)
        #expect(demo.defaults.object(forKey: "leftover") == nil)
        #expect(demo.defaults.bool(for: AppSettings.hasCompletedOnboarding))

        #expect(UserDefaults.standard.object(forKey: AppSettings.hasCompletedOnboarding.key) as? Bool == standardOnboarding)
    }

    // MARK: - 撮る画面の開き方

    @Test("質問の画面: 2 つの質問に答え、日本語の画面では照合を通る AI の一言の代わりを添える")
    func askScreenAnswersWithCheckedRemarks() async throws {
        let (demo, home) = try Self.makeHome(.ask, uiLanguage: "ja")
        defer { Self.removeDefaults(of: demo) }
        await demo.stage(on: home, calendar: demo.calendar)

        #expect(home.questions.map(\.text) == ScreenshotDemo.questions)
        for exchange in home.questions {
            guard case .answered(let answer, let remark) = exchange.state else {
                Issue.record("答えていません: \(exchange.state)")
                continue
            }
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
            guard case .answered(_, let remark) = exchange.state else {
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

    /// デモの時計は、作ってからの経過だけ進む。起動の日時に過去の日時（テストの決まった日時）を渡しても、実際の時間の
    /// 経過で週や月の境目を越えない（越えると、写す数字が、テストを動かした日によって変わる）。
    @Test func demoClockAdvancesOnlyFromCreation() throws {
        let demo = try Self.makeDemo(.home, on: TestSupport.date(2020, 1, 1, hour: 12))
        defer { Self.removeDefaults(of: demo) }

        let elapsed = demo.makeClock()().timeIntervalSince(demo.now)

        #expect(elapsed >= 0)
        #expect(elapsed < 60)
    }

    @Test("月のまとめの一言の代わりは、数字を書かず、数字の文との照合を通る")
    func recapRemarksPassCheck() {
        let thisMonth = "期間: 今月（2026年9月1日から2026年9月30日まで。まだ月の途中）\n支出の合計: ¥21,390（支出の記録 17件）\n支出の多いカテゴリ: 光熱・通信 ¥9,800（46%）、食費 ¥8,000（37%）"
        let monthly = "期間: 2026年8月1日から2026年8月31日まで\n支出の合計: ¥123,230（支出の記録 80件）"
        #expect(ScreenshotDemoRemarkWriter.remark(from: thisMonth) == "今月は光熱・通信がいちばん多くなっています。記録を続けられていて、いい調子です。")
        #expect(RecapRemark.checked(ScreenshotDemoRemarkWriter.remark(from: thisMonth), facts: thisMonth) != nil)
        // カテゴリの行が無ければ、カテゴリに触れない。
        #expect(ScreenshotDemoRemarkWriter.remark(from: monthly) == "記録を続けられていて、いい調子です。")
        #expect(RecapRemark.checked(ScreenshotDemoRemarkWriter.remark(from: monthly), facts: monthly) != nil)
    }

    @Test("ホームの画面: 日本語では記録を 1 つ送り、返事に AI の一言を添える。英語では送らない")
    func homeScreenShowsReplyRemark() async throws {
        let (demo, home) = try Self.makeHome(.home, uiLanguage: "ja")
        defer { Self.removeDefaults(of: demo) }
        await demo.stage(on: home, calendar: demo.calendar)

        let remark = try #require(home.replyRemark)
        #expect(remark.text.hasPrefix("今月のカフェは"))
        #expect(home.justRecorded.map(\.memo) == ["カフェラテ"])

        let (english, englishHome) = try Self.makeHome(.home, uiLanguage: "en")
        defer { Self.removeDefaults(of: english) }
        await english.stage(on: englishHome, calendar: english.calendar)
        #expect(englishHome.replyRemark == nil)
        #expect(englishHome.justRecorded.isEmpty)
    }

    @Test("カレンダーの画面: カレンダーのページを出し、今月の使った額を出す。ほかの画面には入れない")
    func calendarScreenShowsSpending() async throws {
        let (demo, home) = try Self.makeHome(.calendar, uiLanguage: "ja")
        defer { Self.removeDefaults(of: demo) }
        home.calendarPage.configure(calendar: demo.calendar)
        await demo.stage(on: home, calendar: demo.calendar)

        #expect(home.page == .calendar)
        #expect((home.calendarPage.days?.expense ?? 0) > 0)

        let (other, otherHome) = try Self.makeHome(.home, uiLanguage: "ja")
        defer { Self.removeDefaults(of: other) }
        otherHome.calendarPage.configure(calendar: other.calendar)
        #expect(otherHome.page == .conversation)
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
            configuration: .init(screen: screen), launchedAt: day,
            calendar: TestSupport.calendar, uiLanguage: uiLanguage,
            defaultsSuiteName: "ScreenshotDemoTests.\(UUID().uuidString)"
        )
    }

    static func removeDefaults(of demo: ScreenshotDemo) {
        UserDefaults.standard.removePersistentDomain(forName: demo.defaultsDomain)
    }

    /// デモのホームのモデル（メモリの上の保存先）。
    static func makeHome(_ screen: ScreenshotDemo.Screen, uiLanguage: String) throws -> (ScreenshotDemo, HomeModel) {
        let demo = try makeDemo(screen, uiLanguage: uiLanguage)
        let container = try demo.makeContainer()
        retained.append(container)
        let home = demo.makeHomeModel(context: container.mainContext, pendingWrites: PendingStoreWrites(), storeHost: nil)
        return (demo, home)
    }

    /// 保存先はコンテナが生きている間しか使えないので、テストの間は持っておく。
    private static var retained: [ModelContainer] = []
}
#endif
