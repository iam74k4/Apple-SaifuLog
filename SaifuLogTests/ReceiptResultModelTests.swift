import Foundation
import SaifuLogCore
import Testing
@testable import SaifuLog

/// ⑤ 読み取り結果のシートの状態と操作（ReceiptResultModel）。固定の日時は 2026-09-28 12:00（日本時間）。
@MainActor
struct ReceiptResultModelTests {
    /// ReceiptResultModel と、記録・撮り直し・読み上げの代わり。
    @MainActor
    final class Fixture {
        private(set) var submissions: [ReceiptResultModel.Submission] = []
        private(set) var retakes = 0
        private(set) var announcements: [String] = []
        var outcome = ReceiptResultModel.RecordOutcome.recorded
        private(set) var model: ReceiptResultModel!

        init(source: ReceiptCaptureSource = .photos, firstSkippedPage: Int? = nil) {
            model = ReceiptResultModel(
                source: source,
                readAt: TestSupport.now,
                calendar: TestSupport.calendar,
                firstSkippedPage: firstSkippedPage,
                announce: { [unowned self] in announcements.append($0) },
                record: { [unowned self] in
                    submissions.append($0)
                    return outcome
                },
                retake: { [unowned self] in retakes += 1 }
            )
        }

        /// 文字を読み取った結果を入れる。
        func load(_ text: String) {
            let lines = text.split(separator: "\n").map { ReceiptTextLine(String($0)) }
            model.load(.read(ReceiptLineScanner.scan(lines, now: TestSupport.now, calendar: TestSupport.calendar)))
        }

        func line(named name: String) throws -> ReceiptResultModel.Line {
            try #require(model.lines.first { $0.name == name })
        }
    }

    /// 外税のスーパーのレシート（小計 ¥884 + 外税 ¥70 = 合計 ¥954）。
    static let exclusiveReceipt = """
        業務スーパー 中野店 TEL03-0000-0000
        2026/09/26 10:05
        豚肉 498
        キャベツ 158
        卵 10個入 228
        小計 ¥884
        外税 8% ¥70
        合計 ¥954
        """

    // MARK: - 読み取りの結果

    @Test func loadBuildsLinesAndDefaults() throws {
        let fixture = Fixture()

        fixture.load(Self.exclusiveReceipt)

        let model = fixture.model!
        #expect(model.state == .ready)
        // 店名の行の電話番号は除く。
        #expect(model.storeName == "業務スーパー 中野店")
        #expect(model.lines.map(\.name) == ["豚肉", "キャベツ", "卵 10個入", ""])
        #expect(model.lines.map(\.amountText) == ["498", "158", "228", "70"])
        #expect(model.lines.last?.kind == .taxAndOther)
        #expect(model.displayName(of: try #require(model.lines.last)) == String(localized: "税・その他"))
        #expect(model.mode == .perItem)
        #expect(model.singleCategory == .food)
        #expect(model.receiptTotal == 954)
        #expect(model.linesTotal == 954)
        #expect(model.reconciliation.status == .matched)
        #expect(model.recordCount == 4)
        #expect(model.canRecord)
        // 日付はレシートの日時（時刻もレシートのまま）。
        #expect(model.day == TestSupport.date(2026, 9, 26, hour: 10, minute: 5))
        #expect(model.spentAt == TestSupport.date(2026, 9, 26, hour: 10, minute: 5))
        #expect(fixture.announcements.last?.contains(String(localized: "品目を\(4)件読み取りました。\("")")) == true)
    }

    /// 品目が無く合計だけのレシートは 1 行で、まとめて 1 件を既定にする。
    @Test func totalOnlyDefaultsToSingle() {
        let fixture = Fixture()

        fixture.load("""
            居酒屋 はなこ
            御会計 ¥8,800
            """)

        #expect(fixture.model.lines.map(\.kind) == [.wholeReceipt])
        #expect(fixture.model.mode == .single)
        #expect(fixture.model.singleCategory == .food)
        // 日付が読めなければ、読み取った日時にする。
        #expect(fixture.model.spentAt == TestSupport.now)
    }

    @Test(arguments: [ReceiptUnreadableReason.noText, .noAmounts, .imageUnavailable])
    func unreadable(reason: ReceiptUnreadableReason) {
        let fixture = Fixture()

        fixture.model.load(.unreadable(reason))

        #expect(fixture.model.state == .unreadable(reason))
        #expect(!fixture.model.canRecord)
        #expect(fixture.announcements == [String(localized: "レシートを読み取れませんでした")])
    }

    /// 書類カメラで上限より多く撮ったときは、読み取らなかったページがあることを出し、読み上げる（合計や後ろの品目が足りないことに
    /// 気づけるように）。
    @Test func skippedPagesAreNoticed() throws {
        let fixture = Fixture(source: .camera, firstSkippedPage: 5)

        fixture.load(Self.exclusiveReceipt)

        let notice = try #require(fixture.model.skippedPagesNotice)
        #expect(notice == String(localized: "\(5)ページ目からは読み取っていません。合計や品目が足りないときは、\(4)ページまでで撮り直してください。"))
        #expect(fixture.announcements.last?.hasSuffix(notice) == true)
        #expect(Fixture().model.skippedPagesNotice == nil)
    }

    // MARK: - 閉じる

    /// 読み取っただけ（何も直していない）なら、確かめずに閉じる。読み取り中・読めなかったときも同じ。
    @Test func closeWithoutChangesDoesNotAsk() {
        let reading = Fixture()
        #expect(reading.model.requestClose())

        let unreadable = Fixture()
        unreadable.model.load(.unreadable(.noText))
        #expect(unreadable.model.requestClose())

        let fixture = Fixture()
        fixture.load(Self.exclusiveReceipt)
        #expect(!fixture.model.hasChanges)
        #expect(fixture.model.requestClose())
        #expect(!fixture.model.showsDiscardConfirmation)
    }

    /// 直した内容があれば、閉じずに捨てるかを確かめる（画像は保存しないので、閉じると撮り直すしか戻す方法が無い）。
    @Test(arguments: [
        "storeName", "day", "name", "amount", "category", "exclude", "difference", "mode", "singleCategory",
    ])
    func closeWithChangesAsks(change: String) throws {
        let fixture = Fixture()
        fixture.load(Self.exclusiveReceipt)
        let model = fixture.model!
        let pork = try fixture.line(named: "豚肉")
        let index = try #require(model.lines.firstIndex { $0.id == pork.id })

        switch change {
        case "storeName": model.storeName = "業務スーパー"
        case "day": model.day = TestSupport.date(2026, 9, 20)
        case "name": model.lines[index].name = "豚こま"
        case "amount": model.lines[index].amountText = "598"
        case "category": model.lines[index].category = .other
        case "exclude": model.setIncluded(false, for: pork.id)
        case "difference":
            // 差額の行を足した後で、金額を元に戻しても、足した行が残るので直したことになる。
            model.lines[index].amountText = "398"
            model.addDifferenceLine()
            model.lines[index].amountText = "498"
        case "mode": model.mode = .single
        case "singleCategory": model.singleCategory = .daily
        default: Issue.record("知らない直し方: \(change)")
        }

        #expect(model.hasChanges)
        #expect(!model.requestClose())
        #expect(model.showsDiscardConfirmation)
    }

    /// 直してから元に戻したら、直していないことにする（外して戻した・同じ店名に戻した）。
    @Test func revertedChangesDoNotAsk() throws {
        let fixture = Fixture()
        fixture.load(Self.exclusiveReceipt)
        let cabbage = try fixture.line(named: "キャベツ")

        fixture.model.setIncluded(false, for: cabbage.id)
        fixture.model.setIncluded(true, for: cabbage.id)
        fixture.model.storeName = "別の店"
        fixture.model.storeName = "業務スーパー 中野店"

        #expect(!fixture.model.hasChanges)
        #expect(fixture.model.requestClose())
    }

    // MARK: - 外す・直す

    /// 行を外すと合計から除き、照合がずれる。VoiceOver にも何を外したかを読み上げる。
    @Test func excludeAndIncludeLine() throws {
        let fixture = Fixture()
        fixture.load(Self.exclusiveReceipt)
        let cabbage = try fixture.line(named: "キャベツ")

        fixture.model.setIncluded(false, for: cabbage.id)

        #expect(fixture.model.linesTotal == 796)
        #expect(fixture.model.reconciliation.status == .mismatched(difference: 158))
        #expect(fixture.model.recordCount == 3)
        #expect(fixture.announcements.last == String(localized: "外しました: \("キャベツ")"))

        fixture.model.setIncluded(true, for: cabbage.id)

        #expect(fixture.model.reconciliation.status == .matched)
        #expect(fixture.announcements.last == String(localized: "戻しました: \("キャベツ")"))
    }

    @Test func editAmountAndCategory() throws {
        let fixture = Fixture()
        fixture.load(Self.exclusiveReceipt)
        let pork = try fixture.line(named: "豚肉")
        let index = try #require(fixture.model.lines.firstIndex { $0.id == pork.id })

        fixture.model.lines[index].amountText = "5a98"
        fixture.model.normalizeAmountText(for: pork.id)
        fixture.model.lines[index].category = .other
        fixture.model.lines[index].name = "豚こま"

        #expect(fixture.model.lines[index].amountText == "598")
        #expect(fixture.model.reconciliation.status == .mismatched(difference: -100))
        fixture.model.recordNow()
        let records = try #require(fixture.submissions.last?.records)
        #expect(records.first == ReceiptRecord(memo: "豚こま", amount: 598, category: .other))
    }

    /// 金額を消した行があれば、記録できない（金額を入れるか、行を外す）。
    @Test func emptyAmountBlocksRecording() throws {
        let fixture = Fixture()
        fixture.load(Self.exclusiveReceipt)
        let pork = try fixture.line(named: "豚肉")
        let index = try #require(fixture.model.lines.firstIndex { $0.id == pork.id })

        fixture.model.lines[index].amountText = ""

        #expect(fixture.model.hasInvalidAmount)
        #expect(!fixture.model.canRecord)
        fixture.model.requestRecord()
        #expect(fixture.submissions.isEmpty)

        fixture.model.setIncluded(false, for: pork.id)
        #expect(!fixture.model.hasInvalidAmount)
        #expect(fixture.model.canRecord)
    }

    // MARK: - 照合と記録

    /// 合計が合わないときは黙って記録せず、確認を出す。確認のあとで記録する。
    @Test func mismatchAsksBeforeRecording() throws {
        let fixture = Fixture()
        fixture.load(Self.exclusiveReceipt)
        fixture.model.setIncluded(false, for: try fixture.line(named: "キャベツ").id)

        fixture.model.requestRecord()

        #expect(fixture.model.showsMismatchConfirmation)
        #expect(fixture.submissions.isEmpty)

        fixture.model.recordNow()

        let submission = try #require(fixture.submissions.last)
        #expect(submission.records.map(\.amount) == [498, 228, 70])
        #expect(submission.records.last?.memo == String(localized: "税・その他"))
    }

    /// 合計が足りないとき、差額を「税・その他」の 1 行として足せる（足すと合う）。
    @Test func addDifferenceLineMakesTotalsMatch() throws {
        let fixture = Fixture()
        fixture.load(Self.exclusiveReceipt)
        let tax = try #require(fixture.model.lines.last)
        fixture.model.setIncluded(false, for: tax.id)
        #expect(fixture.model.reconciliation.status == .mismatched(difference: 70))

        fixture.model.addDifferenceLine()

        #expect(fixture.model.lines.count == 5)
        #expect(fixture.model.lines.last?.amountText == "70")
        #expect(fixture.model.lines.last?.category == .food)
        #expect(fixture.model.reconciliation.status == .matched)
        fixture.model.requestRecord()
        #expect(!fixture.model.showsMismatchConfirmation)
        #expect(fixture.submissions.count == 1)
    }

    /// 合計が読めなければ、確認を出さずに品目の合計で記録する（画面に「合計を読み取れませんでした」を出している）。
    @Test func totalMissingRecordsItemsTotal() throws {
        let fixture = Fixture()
        fixture.load("""
            八百屋 まるやま
            2026/09/27
            トマト 298
            玉ねぎ 198
            """)

        fixture.model.requestRecord()

        #expect(fixture.model.reconciliation.status == .totalMissing)
        #expect(!fixture.model.showsMismatchConfirmation)
        let submission = try #require(fixture.submissions.last)
        #expect(submission.records.map(\.amount) == [298, 198])
        #expect(submission.originalText == String(localized: "レシート: 八百屋 まるやま 合計 ¥496"))
    }

    @Test func singleModeRecordsOneEntry() throws {
        let fixture = Fixture()
        fixture.load(Self.exclusiveReceipt)
        fixture.model.mode = .single
        fixture.model.singleCategory = .daily

        fixture.model.requestRecord()

        let submission = try #require(fixture.submissions.last)
        #expect(submission.records == [ReceiptRecord(memo: "業務スーパー 中野店", amount: 954, category: .daily)])
        #expect(fixture.model.recordCount == 1)
    }

    /// 日付を直しても、時刻はレシートのまま。
    @Test func editingDateKeepsReceiptTime() throws {
        let fixture = Fixture()
        fixture.load(Self.exclusiveReceipt)

        fixture.model.day = TestSupport.date(2026, 9, 20)
        fixture.model.requestRecord()

        #expect(fixture.submissions.last?.spentAt == TestSupport.date(2026, 9, 20, hour: 10, minute: 5))
    }

    /// 書き込めなければ、シートは閉じずにアラートを出す（直した内容を残す）。
    @Test func failedRecordShowsAlert() {
        let fixture = Fixture()
        fixture.load(Self.exclusiveReceipt)
        fixture.outcome = .failed

        fixture.model.requestRecord()

        #expect(fixture.model.showsSaveFailure)
        #expect(fixture.model.state == .ready)
    }

    @Test func retakeAsksHome() {
        let fixture = Fixture(source: .camera)
        fixture.model.load(.unreadable(.noText))

        fixture.model.retake()

        #expect(fixture.retakes == 1)
    }

    // MARK: - 要約

    /// 記録の元の文は「レシート: 店名 合計 ¥…」だけ。店名に続く電話番号やカード番号は除き、店名が無ければ合計だけ。
    @Test func summaryTextHasOnlyStoreAndTotal() {
        #expect(ReceiptResultModel.summaryText(storeName: "イオン 渋谷店", total: 1_280)
            == String(localized: "レシート: \("イオン 渋谷店") 合計 \("¥1,280")"))
        let withNumbers = ReceiptResultModel.summaryText(storeName: "イオン TEL 03-0000-0000 ****1234", total: 1_280)
        #expect(!withNumbers.contains("03-0000"))
        #expect(!withNumbers.contains("1234"))
        #expect(ReceiptResultModel.summaryText(storeName: "  ", total: 500) == String(localized: "レシート: 合計 \("¥500")"))
    }
}
