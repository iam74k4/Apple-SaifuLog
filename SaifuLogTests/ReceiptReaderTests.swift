import Foundation
import SaifuLogCore
import Testing
import UIKit
@testable import SaifuLog

/// レシートの画像の読み取り（ReceiptReader・ReceiptTextRecognizer・ReceiptImage）。
///
/// シミュレータにはカメラが無いので、写真から選んだときの経路（画像のデータ → ReceiptImage → Vision の文字認識 → コアの読み取り）は、
/// 文字を描いたテスト用の画像で確かめる。AI の経路は偽物で確かめる（シミュレータでは本物のモデルを呼ばない）。
struct ReceiptReaderTests {
    static let lines = [
        "イオン 渋谷店",
        "2026/09/27 18:32",
        "ｷﾞｭｳﾆｭｳ ¥198",
        "ﾃｨｯｼｭ ¥298",
        "合計 ¥496",
    ].map { ReceiptTextLine($0) }

    /// AI の失敗の記録はテストごとに新しくする（アプリの `AIFallbackLog.shared` に、テストの失敗を混ぜないため）。
    static func reader(
        lines: [ReceiptTextLine] = lines, refiner: (any ReceiptItemRefining)?, log: AIFallbackLog = AIFallbackLog()
    ) -> ReceiptReader {
        ReceiptReader(recognize: { _ in lines }, makeRefiner: { refiner }, aiFallbackLog: log)
    }

    static func scan(_ reading: ReceiptReading) throws -> ReceiptScan {
        guard case .read(let scan) = reading else {
            Issue.record("読み取れなかった: \(reading)")
            throw TestError()
        }
        return scan
    }

    // MARK: - AI の品名とカテゴリ

    /// AI の返した金額は使わない。金額が OCR の額と合う品目だけ品名とカテゴリを採り、合わない品目は OCR のまま。
    @Test func aiAmountsAreNeverUsed() async throws {
        let refiner = StubReceiptRefiner { _ in
            [
                ReceiptItemSuggestion(number: 1, name: "牛乳", categoryName: "食費", amountText: "¥198"),
                // 番号を取り違えた・作った金額（OCR は ¥298）。この品目の AI の読みは捨てる。
                ReceiptItemSuggestion(number: 2, name: "ボックスティッシュ", categoryName: "娯楽", amountText: "¥2,980"),
            ]
        }

        let scan = try Self.scan(await Self.reader(refiner: refiner).read(
            [TestSupport.blankReceiptImage], now: TestSupport.now, calendar: TestSupport.calendar
        ))

        #expect(scan.items.map(\.amount) == [198, 298])
        #expect(scan.items.map(\.name) == ["牛乳", "ティッシュ"])
        #expect(scan.items.map(\.category) == [.food, .daily])
        #expect(scan.total == 496)
        #expect(refiner.calls.count == 1)
    }

    /// iOS 27 の画像に対応したモデル（`usesImage`）には、品目の一覧と一緒に最初のページの画像を渡す。文字だけのモデル（iOS 26・
    /// 画像に対応しない端末）には画像を渡さない。
    @Test(arguments: [true, false])
    func imageIsPassedOnlyToImageRefiner(usesImage: Bool) async throws {
        let refiner = StubReceiptRefiner(usesImage: usesImage) { _ in [] }
        let firstPage = TestSupport.blankImage(size: 8)
        let secondPage = TestSupport.blankImage(size: 16)

        _ = try Self.scan(await Self.reader(refiner: refiner).read(
            [firstPage, secondPage], now: TestSupport.now, calendar: TestSupport.calendar
        ))

        let received = refiner.images.all
        #expect(received.count == 1)
        let image = try #require(received.first)
        if usesImage {
            #expect(image?.cgImage.width == 8)
        } else {
            #expect(image == nil)
        }
    }

    /// AI が失敗しても、キーワード辞書のカテゴリのまま読み取る（AI が無くても使える）。失敗は AI の記録に残す（利用者には知らせない）。
    @Test func aiFailureKeepsDictionaryResult() async throws {
        let refiner = StubReceiptRefiner { _ in throw TestError() }
        let log = AIFallbackLog()

        let scan = try Self.scan(await Self.reader(refiner: refiner, log: log).read(
            [TestSupport.blankReceiptImage], now: TestSupport.now, calendar: TestSupport.calendar
        ))

        #expect(scan.items.map(\.name) == ["ギュウニュウ", "ティッシュ"])
        #expect(scan.items.map(\.category) == [.food, .daily])
        #expect(log.snapshot.fallbacks == [.receipt: 1])
        #expect(log.snapshot.lastError?.feature == .receipt)
    }

    /// AI が整えられたときは、AI の記録に何も残さない。
    @Test func aiSuccessIsNotRecorded() async throws {
        let refiner = StubReceiptRefiner { _ in [] }
        let log = AIFallbackLog()

        _ = try Self.scan(await Self.reader(refiner: refiner, log: log).read(
            [TestSupport.blankReceiptImage], now: TestSupport.now, calendar: TestSupport.calendar
        ))

        #expect(refiner.calls.count == 1)
        #expect(log.snapshot == AIFallbackLog.Snapshot())
    }

    /// 品目の無いレシート（合計だけ）では、AI を呼ばない。
    @Test func aiIsNotCalledWithoutItems() async throws {
        let refiner = StubReceiptRefiner { _ in [] }
        let reader = Self.reader(lines: [ReceiptTextLine("居酒屋 はなこ"), ReceiptTextLine("御会計 ¥8,800")], refiner: refiner)

        let scan = try Self.scan(await reader.read([TestSupport.blankReceiptImage], now: TestSupport.now, calendar: TestSupport.calendar))

        #expect(scan.total == 8_800)
        #expect(refiner.calls.count == 0)
    }

    @Test func unreadableReasons() async {
        let noText = await Self.reader(lines: [], refiner: nil)
            .read([TestSupport.blankReceiptImage], now: TestSupport.now, calendar: TestSupport.calendar)
        let noAmounts = await Self.reader(lines: [ReceiptTextLine("ご来店ありがとうございます")], refiner: nil)
            .read([TestSupport.blankReceiptImage], now: TestSupport.now, calendar: TestSupport.calendar)
        let noImage = await Self.reader(refiner: nil).read([], now: TestSupport.now, calendar: TestSupport.calendar)

        #expect(noText == .unreadable(.noText))
        #expect(noAmounts == .unreadable(.noAmounts))
        #expect(noImage == .unreadable(.imageUnavailable))
    }

    #if canImport(FoundationModels)
    /// 指示文と説明に、具体的な数字や単位の例を書かない（モデルが入力に無くても写して返すため）。
    @Test func refinerInstructionsHaveNoNumberExamples() {
        for text in [FoundationModelsReceiptItemRefiner.instructions, FoundationModelsReceiptItemRefiner.imageInstructions] {
            #expect(!text.contains { ("0"..."9").contains($0) || ("０"..."９").contains($0) }, "\(text)")
            #expect(!text.contains("円"), "\(text)")
            #expect(!text.contains("¥"), "\(text)")
        }
    }

    /// AI には品目の一覧と、電話番号を除いた店名だけを渡す（ほかの行は渡さない）。
    @Test func refinerPromptHasOnlyItems() {
        let prompt = FoundationModelsReceiptItemRefiner.prompt(
            items: [ReceiptItem(name: "ｷﾞｭｳﾆｭｳ", amount: 198)], storeName: "イオン TEL 03-0000-0000"
        )

        #expect(prompt.contains("1. ｷﾞｭｳﾆｭｳ ¥198"))
        #expect(prompt.contains("イオン"))
        #expect(!prompt.contains("03-0000"))
    }
    #endif

    // MARK: - 画像と文字認識

    /// レシートの形の画像を描く（白地に黒の文字。品名は左、金額は右に離して置く）。
    @MainActor
    static func renderReceipt(_ rows: [(String, String?)]) -> Data {
        let size = CGSize(width: 900, height: 120 + rows.count * 90)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.pngData { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let font = UIFont(name: "HiraginoSans-W6", size: 44) ?? .systemFont(ofSize: 44, weight: .semibold)
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
            for (index, row) in rows.enumerated() {
                let y = CGFloat(60 + index * 90)
                NSAttributedString(string: row.0, attributes: attributes).draw(at: CGPoint(x: 60, y: y))
                if let price = row.1 {
                    let text = NSAttributedString(string: price, attributes: attributes)
                    text.draw(at: CGPoint(x: size.width - 60 - text.size().width, y: y))
                }
            }
        }
    }

    /// 写真から選んだときの経路（データ → 画像 → Vision の文字認識 → コアの読み取り）を、描いた画像で通す。
    /// 品名と金額が離れていても、同じ行として読み、金額と合計はコードが読む。
    @Test @MainActor func recognizesRenderedReceipt() async throws {
        let data = Self.renderReceipt([
            ("サンプル商店", nil),
            ("2026/09/27 18:32", nil),
            ("牛乳", "¥198"),
            ("食パン", "¥158"),
            ("合計", "¥356"),
        ])
        let image = try #require(ReceiptImage(data: data))
        let reader = ReceiptReader(makeRefiner: { nil })

        let scan = try Self.scan(await reader.read([image], now: TestSupport.now, calendar: TestSupport.calendar))

        #expect(scan.items.map(\.amount) == [198, 158])
        #expect(scan.total == 356)
        #expect(scan.purchasedOn == ReceiptDate(daysAgo: 1, hour: 18, minute: 32))
        #expect(scan.items.first?.name.contains("牛乳") == true)
    }

    /// 写真のデータは向きを焼き込み、長い辺を上限まで縮めて、メモリの上だけで画像にする。
    @Test @MainActor func imageFromDataIsOrientedAndDownscaled() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let wide = UIGraphicsImageRenderer(size: CGSize(width: 5_000, height: 50), format: format).pngData { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 5_000, height: 50))
        }

        let image = try #require(ReceiptImage(data: wide))

        #expect(image.orientation == .up)
        #expect(image.cgImage.width == ReceiptImage.maximumPixelSize)
        #expect(ReceiptImage(data: Data("not an image".utf8)) == nil)
    }
}
