import Foundation
import SaifuLogCore
import SwiftData
import Testing
@testable import SaifuLog

/// ホームからのレシートの読み取り（④⑤）。読み取りの代わり（決めた OCR の文字）とメモリの上の保存先で確かめる。
/// 固定の日時は 2026-09-28 12:00（日本時間）。
@MainActor
struct HomeModelReceiptTests {
    typealias Fixture = HomeModelTests.Fixture

    static let receiptText = """
        イオン 渋谷店
        TEL 03-0000-0000
        2026年09月27日(日) 18:32
        ※牛乳 ￥198
        ティッシュ ￥298
        合計 ￥496
        お預り ￥1,000
        お釣り ￥504
        ************1234
        """

    /// カメラのボタンを押してから、読み取りが終わるまで進める。
    static func read(_ fixture: Fixture, text: String = receiptText, source: ReceiptCaptureSource = .photos) async throws
        -> ReceiptResultModel {
        fixture.receipt.setText(text)
        fixture.model.requestReceiptScan()
        #expect(fixture.model.showsReceiptSourceChoice)
        fixture.model.startReceiptCapture(source)
        await fixture.model.readReceipt([TestSupport.blankReceiptImage], source: source, calendar: TestSupport.calendar).value
        return try #require(fixture.model.receiptResult)
    }

    // MARK: - 入口

    @Test func cameraButtonOffersSources() throws {
        let fixture = try Fixture()

        fixture.model.requestReceiptScan()

        #expect(fixture.model.showsReceiptSourceChoice)
        fixture.model.startReceiptCapture(.camera)
        #expect(fixture.model.receiptCapture == .camera)
    }

    /// 書類カメラを使えない端末では、「撮る」を選べない（写真からは選べる）。
    @Test func cameraUnavailableOnlyOffersPhotos() throws {
        let fixture = try Fixture(canUseDocumentCamera: false)

        fixture.model.startReceiptCapture(.camera)
        #expect(fixture.model.receiptCapture == nil)
        fixture.model.startReceiptCapture(.photos)
        #expect(fixture.model.receiptCapture == .photos)
    }

    // MARK: - 読み取りと記録

    @Test func readingShowsResultWithoutRecording() async throws {
        let fixture = try Fixture()

        let result = try await Self.read(fixture)

        #expect(result.state == .ready)
        #expect(result.storeName == "イオン 渋谷店")
        #expect(result.lines.map(\.name) == ["牛乳", "ティッシュ"])
        #expect(result.reconciliation.status == .matched)
        #expect(fixture.model.receiptCapture == nil)
        // 読み取っただけでは記録しない。
        #expect(try fixture.entries().isEmpty)
    }

    /// 品目ごとに記録すると、記録の吹き出しと「取り消す」が出る。元の文は店名と合計の要約だけ。
    @Test func recordingPerItemSavesEntries() async throws {
        let fixture = try Fixture()
        let result = try await Self.read(fixture)

        result.requestRecord()

        let entries = try fixture.entries()
        #expect(entries.map(\.memo) == ["牛乳", "ティッシュ"])
        #expect(entries.map(\.amount) == [198, 298])
        #expect(entries.map(\.category) == [.food, .daily])
        #expect(entries.allSatisfy { $0.source == .receipt })
        #expect(entries.allSatisfy { $0.spentAt == TestSupport.date(2026, 9, 27, hour: 18, minute: 32) })
        // 書いた順に並ぶよう、記録した日時をずらす。
        #expect(entries.map(\.createdAt) == entries.map(\.createdAt).sorted())
        let summary = String(localized: "レシート: イオン 渋谷店 合計 ¥496")
        #expect(entries.allSatisfy { $0.originalText == summary })
        #expect(fixture.model.receiptResult == nil)
        #expect(fixture.model.justRecorded.count == 2)
        #expect(fixture.model.canUndo)
        #expect(fixture.announcements.last?.contains("¥198") == true)
        #expect(fixture.announcements.last?.contains("¥298") == true)
    }

    /// 記録の元の文に、OCR の全文（電話番号・カード番号）や品名を入れない。
    @Test func summaryHasNoPersonalDetails() async throws {
        let fixture = try Fixture()
        let result = try await Self.read(fixture)

        result.requestRecord()

        for entry in try fixture.entries() {
            #expect(!entry.originalText.contains("1234"))
            #expect(!entry.originalText.contains("03-0000"))
            #expect(!entry.originalText.contains("TEL"))
            #expect(!entry.originalText.contains("牛乳"))
            #expect(!entry.originalText.contains("お釣り"))
        }
    }

    @Test func recordingAsOneEntry() async throws {
        let fixture = try Fixture()
        let result = try await Self.read(fixture)
        result.mode = .single

        result.requestRecord()

        let entries = try fixture.entries()
        #expect(entries.map(\.amount) == [496])
        #expect(entries.map(\.memo) == ["イオン 渋谷店"])
        #expect(entries.map(\.category) == [.daily])
    }

    /// 記録の直後に取り消したら、その回の記録をすべて消す。元の文（要約）は入力欄に戻さない
    /// （送り直すと、合計の 1 件をひとこと入力として記録してしまうため）。
    @Test func undoRemovesAllEntriesOfReceipt() async throws {
        let fixture = try Fixture()
        let result = try await Self.read(fixture)
        result.requestRecord()

        fixture.model.undoLastRecord()

        #expect(try fixture.entries().isEmpty)
        #expect(!fixture.model.canUndo)
        #expect(fixture.model.draft.isEmpty)
        #expect(fixture.announcements.last?.contains("¥198") == true)
    }

    /// 保存に失敗したら、シートを閉じずに知らせ、記録しない。
    @Test func saveFailureKeepsSheet() async throws {
        let fixture = try Fixture()
        let result = try await Self.read(fixture)
        fixture.failsSave = true

        result.requestRecord()

        #expect(result.showsSaveFailure)
        #expect(fixture.model.receiptResult === result)
        #expect(try fixture.entries().isEmpty)
        #expect(!fixture.model.canUndo)
    }

    /// レシートの読み取りに回数の制限は無い（以前は無料で月 5 回までだった）。6 回目も読み取って記録できる。
    @Test func receiptScansAreUnlimited() async throws {
        let fixture = try Fixture()

        for _ in 0..<6 {
            let result = try await Self.read(fixture)
            result.requestRecord()
        }

        #expect(try fixture.entries().count == 12)
        #expect(fixture.model.receiptResult == nil)
    }

    // MARK: - 読めなかった

    /// 文字が無い・品目も合計も無いときは、撮り直しを案内する。
    @Test(arguments: [("", ReceiptUnreadableReason.noText), ("ご来店ありがとうございます\nまたお越しください", .noAmounts)])
    func unreadableShowsGuidance(text: String, reason: ReceiptUnreadableReason) async throws {
        let fixture = try Fixture()

        let result = try await Self.read(fixture, text: text)

        #expect(result.state == .unreadable(reason))
        #expect(!result.canRecord)
        #expect(fixture.announcements.last == String(localized: "レシートを読み取れませんでした"))
    }

    /// 画像が無い（撮った画像を取り出せなかった）ときは、文字を読まずに「画像を読み込めなかった」を理由にする。
    @Test func missingImageIsUnreadable() async throws {
        let fixture = try Fixture()

        await fixture.model.readReceipt([], source: .camera, calendar: TestSupport.calendar).value

        #expect(fixture.model.receiptResult?.state == .unreadable(.imageUnavailable))
        #expect(fixture.receipt.recognizeCalls == 0)
    }

    // MARK: - 写真から選ぶ

    /// 写真を選んだら、写真を読み込む前に ⑤ を読み取り中で出す（iCloud にだけある写真を取り出す間も、選んだことが分かるように）。
    @Test func photoShowsReadingWhileLoading() async throws {
        let fixture = try Fixture()
        fixture.receipt.setText(Self.receiptText)
        let loaded = Gate()

        let reading = fixture.model.readReceiptPhoto(calendar: TestSupport.calendar) {
            await loaded.wait()
            return TestSupport.blankReceiptImage
        }

        let result = try #require(fixture.model.receiptResult)
        #expect(result.source == .photos)
        #expect(result.state == .reading)
        #expect(fixture.receipt.recognizeCalls == 0)
        loaded.open()
        await reading.value
        #expect(result.state == .ready)
        #expect(fixture.receipt.recognizeCalls == 1)
    }

    /// 写真を読み込めなかったら、「文字が見つからない」ではなく「写真を読み込めなかった」を理由にする。
    @Test func photoLoadFailureShowsReason() async throws {
        let fixture = try Fixture()

        await fixture.model.readReceiptPhoto(calendar: TestSupport.calendar) { nil }.value

        #expect(fixture.model.receiptResult?.state == .unreadable(.imageUnavailable))
        #expect(fixture.receipt.recognizeCalls == 0)
        #expect(fixture.announcements.last == String(localized: "レシートを読み取れませんでした"))
    }

    /// 写真を読み込む間にシートを閉じたら、読み込み終えても文字を読まず、読み上げもしない。
    @Test func closingWhileLoadingPhotoSkipsReading() async throws {
        let fixture = try Fixture()
        fixture.receipt.setText(Self.receiptText)
        let loaded = Gate()
        let reading = fixture.model.readReceiptPhoto(calendar: TestSupport.calendar) {
            await loaded.wait()
            return TestSupport.blankReceiptImage
        }
        let result = try #require(fixture.model.receiptResult)

        fixture.model.receiptResult = nil
        loaded.open()
        await reading.value

        #expect(result.state == .reading)
        #expect(fixture.receipt.recognizeCalls == 0)
        #expect(fixture.announcements.isEmpty)
    }

    /// 読み取りの間にシートを閉じたら、読み終えても結果を入れず、読み上げもしない。
    @Test func closingWhileReadingIgnoresResult() async throws {
        let fixture = try Fixture()
        fixture.receipt.setText(Self.receiptText)
        let reading = fixture.model.readReceipt([TestSupport.blankReceiptImage], source: .photos, calendar: TestSupport.calendar)
        let result = try #require(fixture.model.receiptResult)

        fixture.model.receiptResult = nil
        await reading.value

        #expect(result.state == .reading)
        #expect(fixture.announcements.isEmpty)
    }

    /// 撮り直すと、シートを閉じ、閉じきったら同じ取り込み口をもう一度開く。
    @Test func retakeReopensSameSource() async throws {
        let fixture = try Fixture()
        let result = try await Self.read(fixture, text: "", source: .camera)

        result.retake()

        #expect(fixture.model.receiptResult == nil)
        #expect(fixture.model.receiptCapture == nil)
        fixture.model.receiptResultDidDismiss()
        #expect(fixture.model.receiptCapture == .camera)
    }

    /// 書類カメラで撮った画像は、カメラの画面が閉じきってから読み取る（出し入れが重ならないように）。
    @Test func documentCameraReadsAfterDismiss() async throws {
        let fixture = try Fixture()
        fixture.receipt.setText(Self.receiptText)
        fixture.model.startReceiptCapture(.camera)

        fixture.model.finishDocumentCamera([TestSupport.blankReceiptImage])

        #expect(fixture.model.receiptCapture == nil)
        #expect(fixture.model.receiptResult == nil)
        let reading = fixture.model.receiptCaptureDidDismiss(calendar: TestSupport.calendar)
        let result = try #require(fixture.model.receiptResult)
        #expect(result.source == .camera)
        await reading?.value
        #expect(result.state == .ready)
        // もう一度閉じた知らせが来ても、同じ画像を二度読まない。
        #expect(fixture.model.receiptCaptureDidDismiss(calendar: TestSupport.calendar) == nil)
        #expect(fixture.model.receiptResult === result)
        #expect(fixture.receipt.recognizeCalls == 1)
        // 上限を超えたページが無ければ、読み取らなかったページの知らせは出さない。
        #expect(result.firstSkippedPage == nil)
    }

    /// 書類カメラで上限（4 ページ）より多く撮ったら、⑤ に 5 ページ目からは読み取っていないことを出す。
    @Test func documentCameraSkippedPagesAreReported() async throws {
        let fixture = try Fixture()
        fixture.receipt.setText(Self.receiptText)
        fixture.model.startReceiptCapture(.camera)

        fixture.model.finishDocumentCamera([TestSupport.blankReceiptImage], skippedPageCount: 2)
        await fixture.model.receiptCaptureDidDismiss(calendar: TestSupport.calendar)?.value

        let result = try #require(fixture.model.receiptResult)
        #expect(result.firstSkippedPage == DocumentCameraView.maximumPages + 1)
        #expect(result.state == .ready)
        let notice = try #require(result.skippedPagesNotice)
        #expect(fixture.announcements.last?.hasSuffix(notice) == true)
    }
}
