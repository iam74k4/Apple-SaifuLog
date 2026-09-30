import Foundation
import SaifuLogCore
import SwiftData
import Testing
@testable import SaifuLog

/// ホームの「自分／家族」の切り替えと、家族の家計への記録・取り消し・直す・削除、家族の今月の合計、設定の「家族と共有」の入口。
@MainActor
struct HomeModelHouseholdTests {
    /// HomeModel と、自分の記録の保存先・家計の受け持ち（家計の保存先と CKSyncEngine の代わり）。
    @MainActor
    final class Fixture {
        let context: ModelContext
        let household: HouseholdFixture
        let suiteName = "HomeModelHouseholdTests.\(UUID().uuidString)"
        let defaults: UserDefaults
        private(set) var announcements: [String] = []
        private(set) var model: HomeModel!

        /// - Parameter isEnabled: 家計の共有が有効か（機能フラグ）。
        init(isEnabled: Bool = true) throws {
            context = try TestSupport.makeContext()
            household = try HouseholdFixture(isEnabled: isEnabled)
            defaults = try #require(UserDefaults(suiteName: suiteName))
            model = HomeModel(
                store: EntryStore(context: context),
                household: household.host,
                defaults: defaults,
                makeParser: { now, calendar in RuleBasedParser(calendar: calendar, now: { now }) },
                makeAnswerer: { RuleBasedQuestionAnswerer() },
                makeRemarkWriter: { nil },
                canUseDocumentCamera: true,
                voice: nil,
                now: { TestSupport.now },
                announce: { [unowned self] in announcements.append($0) }
            )
        }

        deinit {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }

        func entries() throws -> [Entry] {
            try context.fetch(FetchDescriptor<Entry>(sortBy: [SortDescriptor(\.createdAt)]))
        }

        func send(_ text: String) async {
            model.draft = text
            await model.send(calendar: TestSupport.calendar)?.value
        }
    }

    // MARK: - 入口

    /// 機能フラグが false なら、家計があっても「自分／家族」の切り替えも設定の「家族と共有」も出さない。
    @Test func disabledFlagHidesEntryPoints() throws {
        let fixture = try Fixture(isEnabled: false)
        // 無効なビルドでは保存先を開かないので、家計を置いても見えない。
        #expect(!fixture.model.showsLedgerSwitch)
        fixture.model.ledgerScope = .household
        #expect(!fixture.model.isHouseholdActive)

        fixture.model.presentSettings()
        #expect(fixture.model.settings?.showsHousehold == false)
    }

    /// 家計の共有が有効でも、家計に入るまでは切り替えを出さない。設定の「家族と共有」は出す（家計を作る入口）。
    @Test func switchAppearsOnlyWithHousehold() throws {
        let fixture = try Fixture()
        #expect(!fixture.model.showsLedgerSwitch)
        fixture.model.presentSettings()
        #expect(fixture.model.settings?.showsHousehold == true)

        try fixture.household.insertHousehold(role: .owner)
        #expect(fixture.model.showsLedgerSwitch)
    }

    // MARK: - 記録先の切り替え

    /// 「家族」のときは家計の保存先に記録した人つきで入り、自分の記録には入らない。「自分」に戻すと自分の記録に入る。
    @Test func scopeSwitchChangesDestination() async throws {
        let fixture = try Fixture()
        try fixture.household.insertHousehold(role: .participant, memberName: "たろう")

        fixture.model.ledgerScope = .household
        await fixture.send("ランチ 850")

        let householdEntries = try fixture.household.entries()
        #expect(householdEntries.map(\.amount) == [850])
        #expect(householdEntries.map(\.recorderName) == ["たろう"])
        #expect(try fixture.entries().isEmpty)
        #expect(fixture.model.canUndo)
        #expect(fixture.model.recordedItems.map(\.summaryText) == ["ランチ ¥850"])
        #expect(fixture.announcements.last?.hasPrefix("家族の家計に記録しました") == true)
        #expect(fixture.household.engines[.shared]?.savedRecordNames == householdEntries.map(\.id.uuidString))

        fixture.model.ledgerScope = .personal
        // 切り替えたら「取り消す」を引っ込める。
        #expect(!fixture.model.canUndo)
        await fixture.send("コーヒー 400")

        #expect(try fixture.entries().map(\.amount) == [400])
        #expect(try fixture.household.entries().count == 1)
    }

    /// 「家族」のときの質問は、答えずに送った文を戻して知らせる（家計への質問は v1 では出さない）。記録もしない。
    @Test func questionInHouseholdIsNotAnswered() async throws {
        let fixture = try Fixture()
        try fixture.household.insertHousehold(role: .owner)
        fixture.model.ledgerScope = .household

        await fixture.send("今月カフェいくら?")

        #expect(fixture.model.householdInputAlert == .question)
        #expect(fixture.model.draft == "今月カフェいくら?")
        #expect(fixture.model.questions.isEmpty)
        #expect(try fixture.household.entries().isEmpty)
        #expect(try fixture.entries().isEmpty)
    }

    /// 「家族」のときの取り消しは、家計の記録を消して送った文を入力欄に戻し、消す変更を登録する。
    @Test func undoInHouseholdDeletesHouseholdEntries() async throws {
        let fixture = try Fixture()
        try fixture.household.insertHousehold(role: .owner)
        fixture.model.ledgerScope = .household
        await fixture.send("ランチ 850")
        let id = try #require(try fixture.household.entries().first?.id)

        fixture.model.undoLastRecord()

        #expect(try fixture.household.entries().isEmpty)
        #expect(fixture.model.draft == "ランチ 850")
        #expect(!fixture.model.canUndo)
        #expect(fixture.household.engines[.private]?.deletedRecordNames == [id.uuidString])
    }

    /// 「家族」のときはレシートの読み取りを始めない（v1 は「自分」だけ）。
    @Test func receiptScanIsPersonalOnly() async throws {
        let fixture = try Fixture()
        try fixture.household.insertHousehold(role: .owner)
        fixture.model.ledgerScope = .household

        await fixture.model.requestReceiptScan(calendar: TestSupport.calendar).value

        #expect(!fixture.model.showsReceiptSourceChoice)
        #expect(fixture.model.premiumSheet == nil)
    }

    /// 家計の記録は、ほかの参加者の記録も直せる（直した日時を書き、送る変更に登録する）。
    @Test func editOtherMembersEntry() throws {
        let fixture = try Fixture()
        try fixture.household.insertHousehold(role: .participant, memberName: "たろう")
        let entry = TestSupport.householdEntry(amount: 850, recorderName: "はなこ", modifiedAt: TestSupport.date(2026, 9, 27))
        try fixture.household.store.insert([entry])
        fixture.model.ledgerScope = .household

        fixture.model.presentHouseholdEdit(entry, calendar: TestSupport.calendar)
        let editing = try #require(fixture.model.editing)
        #expect(editing.originalText.isEmpty)
        editing.amountText = "1,200"
        #expect(editing.save())

        #expect(entry.amount == 1_200)
        #expect(entry.recorderName == "はなこ")
        #expect(entry.modifiedAt == TestSupport.now)
        #expect(fixture.household.engines[.shared]?.savedRecordNames == [entry.id.uuidString])
    }

    /// 家計に複数件を記録したときも、入力欄の VoiceOver の「直す: …」で選んだ家計の記録のシートを開く。
    @Test func choosingRecordedHouseholdItemOpensItsEdit() async throws {
        let fixture = try Fixture()
        try fixture.household.insertHousehold(role: .owner)
        fixture.model.ledgerScope = .household
        await fixture.send("スーパー2480、ドラッグ1200")
        #expect(fixture.model.recordedItems.map(\.summaryText) == ["スーパー ¥2,480", "ドラッグ ¥1,200"])

        let drug = try #require(fixture.model.recordedItems.last)
        fixture.model.presentEdit(drug, calendar: TestSupport.calendar)

        #expect(fixture.model.editing?.memo == "ドラッグ")
        #expect(fixture.model.canUndo)
        #expect(try fixture.entries().isEmpty)
    }

    /// 家計の記録を長押しで消す（確認のあと）。消す変更を登録する。
    @Test func deleteHouseholdEntry() throws {
        let fixture = try Fixture()
        try fixture.household.insertHousehold(role: .owner)
        let entry = TestSupport.householdEntry(amount: 850)
        try fixture.household.store.insert([entry])
        let id = entry.id
        fixture.model.ledgerScope = .household

        fixture.model.requestHouseholdDelete(entry)
        let pending = try #require(fixture.model.pendingHouseholdDeletion)
        #expect(pending.summary == "ランチ ¥850")
        fixture.model.deleteHouseholdEntry(pending)

        #expect(try fixture.household.entries().isEmpty)
        #expect(fixture.household.engines[.private]?.deletedRecordNames == [id.uuidString])
        #expect(fixture.announcements.last == "削除しました: ランチ ¥850")
    }

    /// 家計が消えたら（抜けた・共有が消えた）「自分」に戻る。
    @Test func removedHouseholdFallsBackToPersonal() async throws {
        let fixture = try Fixture()
        try fixture.household.insertHousehold(role: .participant)
        fixture.model.ledgerScope = .household
        #expect(fixture.model.isHouseholdActive)

        await fixture.household.host.leaveHousehold()
        #expect(!fixture.model.isHouseholdActive)
        fixture.model.householdAvailabilityDidChange()

        #expect(fixture.model.ledgerScope == .personal)
        await fixture.send("ランチ 850")
        #expect(try fixture.entries().map(\.amount) == [850])
    }

    // MARK: - 家族の合計

    /// 家族の今月の合計は、だれが記録したかによらず家計の今月の記録を足す（前の月・収入は支出に入れない）。
    @Test func householdMonthlyTotal() {
        let records = [
            TestSupport.householdEntry(amount: 850, recorderName: "はなこ", spentAt: TestSupport.date(2026, 9, 1)),
            TestSupport.householdEntry(amount: 1_200, recorderName: "たろう", spentAt: TestSupport.date(2026, 9, 28)),
            TestSupport.householdEntry(amount: 9_999, recorderName: "たろう", spentAt: TestSupport.date(2026, 8, 31, hour: 23)),
            {
                let income = TestSupport.householdEntry(amount: 50_000, recorderName: "はなこ", spentAt: TestSupport.date(2026, 9, 25))
                income.isIncome = true
                return income
            }(),
        ]

        let summary = HouseholdSummaryHeader.summary(records: records, today: TestSupport.now, calendar: TestSupport.calendar)

        #expect(summary.expense == 2_050)
        #expect(summary.income == 50_000)
    }

    /// 家族の今月の記録を読む条件は、その家計の今月の記録だけ（ほかの家計・前の月は読まない）。
    @Test func householdMonthDescriptorFiltersZoneAndMonth() throws {
        let context = try TestSupport.makeHouseholdContext()
        let store = HouseholdStore(context: context)
        try store.insert([
            TestSupport.householdEntry(amount: 850),
            TestSupport.householdEntry(amount: 700, spentAt: TestSupport.date(2026, 8, 20)),
            TestSupport.householdEntry(zoneName: HouseholdZoneName.make(householdID: UUID()), amount: 300),
        ])

        let descriptor = HouseholdEntry.monthDescriptor(
            zoneName: TestSupport.householdZoneName, containing: TestSupport.now, calendar: TestSupport.calendar
        )

        #expect(try context.fetch(descriptor).map(\.amount) == [850])
    }
}
