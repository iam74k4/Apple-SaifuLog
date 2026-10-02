import Foundation
import Testing
@testable import SaifuLogCore

/// 記録の下書きと、品目の合計とレシートの合計の照合（`ReceiptReconciler`）。
@Suite("レシートの照合")
struct ReceiptReconcilerTests {
    static func reconcile(_ lines: [ReceiptDraftLine], _ scan: ReceiptScan) -> ReceiptReconciliation {
        ReceiptReconciler.reconcile(linesTotal: lines.reduce(0) { $0 + $1.amount }, receiptTotal: scan.total)
    }

    @Test("内税のレシートは、品目の額のまま合計と合う")
    func inclusiveMatches() {
        let scan = ReceiptFixtures.scan(ReceiptFixtures.supermarketInclusive)
        let lines = ReceiptReconciler.draftLines(for: scan)

        #expect(lines.map(\.kind) == [.item, .item, .item, .item])
        #expect(lines.map(\.amount) == [198, 158, 128, 298])
        #expect(lines.map(\.itemIndex) == [0, 1, 2, 3])
        #expect(Self.reconcile(lines, scan).status == .matched)
    }

    /// 外税は品目に按分せず、「税・その他」の 1 行にする（品目の額をレシートの印字と同じに保つため）。カテゴリは額のいちばん多いもの。
    @Test("外税のレシートは、税を「税・その他」の 1 行にして合計と合わせる")
    func exclusiveTaxBecomesOneLine() {
        let scan = ReceiptFixtures.scan(ReceiptFixtures.supermarketExclusive)
        let lines = ReceiptReconciler.draftLines(for: scan)

        #expect(lines.map(\.kind) == [.item, .item, .item, .taxAndOther])
        #expect(lines.map(\.amount) == [498, 158, 228, 70])
        #expect(lines.last?.category == .food)
        #expect(Self.reconcile(lines, scan).status == .matched)
    }

    @Test("品目の値引きは引いた額にし、引いた額を残す")
    func discountsAreNetted() {
        let scan = ReceiptFixtures.scan(ReceiptFixtures.drugstoreDiscounts)
        let lines = ReceiptReconciler.draftLines(for: scan)

        #expect(lines.map(\.amount) == [598, 1_024, 158])
        #expect(lines.map(\.discount) == [100, 256, 0])
        #expect(Self.reconcile(lines, scan).status == .matched)
    }

    /// 小計の後の値引き（100）が外税（46）より大きいので、残り（54）を品目の額の比で引く（負の行は記録できないため）。
    @Test("品目に付かない値引きが外税より大きければ、差を品目に按分して引く")
    func receiptDiscountIsApportioned() {
        let scan = ReceiptFixtures.scan(ReceiptFixtures.receiptDiscount)
        let lines = ReceiptReconciler.draftLines(for: scan)

        #expect(lines.map(\.kind) == [.item, .item])
        #expect(lines.map(\.amount) == [534, 90])
        #expect(lines.map(\.discount) == [46, 8])
        #expect(Self.reconcile(lines, scan).status == .matched)
    }

    @Test("品目が無く合計だけのレシートは、店名と合計で 1 行にする")
    func totalOnlyBecomesOneLine() {
        let scan = ReceiptFixtures.scan(ReceiptFixtures.restaurantTotalOnly)
        let lines = ReceiptReconciler.draftLines(for: scan)

        #expect(lines == [ReceiptDraftLine(kind: .wholeReceipt, name: "居酒屋 はなこ", amount: 8_800, category: .food)])
        #expect(Self.reconcile(lines, scan).status == .matched)
    }

    @Test("数量 × 単価と軽減税率の混在も、合計と合う")
    func quantitiesAndMixedRatesMatch() {
        for text in [ReceiptFixtures.quantities, ReceiptFixtures.mixedTaxRates, ReceiptFixtures.convenienceStore,
                     ReceiptFixtures.noisy, ReceiptFixtures.japaneseEraDate, ReceiptFixtures.cafeEnglishNames,
                     ReceiptFixtures.officeSupplies, ReceiptFixtures.timeBeforeDate] {
            let scan = ReceiptFixtures.scan(text)
            #expect(Self.reconcile(ReceiptReconciler.draftLines(for: scan), scan).status == .matched)
        }
    }

    // 以前は「小　計」「合　計」「お　釣」を品目として下書きに入れ、合計も読めずに照合できなかった（totalMissing）。
    @Test("字間を空けた集計の語や「現計」のレシートも、品目だけを下書きにして合計と合う", arguments: [
        ReceiptFixtures.spacedLabels, ReceiptFixtures.spacedExclusiveTax, ReceiptFixtures.currentTotal,
    ])
    func spacedLabelsMatch(text: String) {
        let scan = ReceiptFixtures.scan(text)
        let lines = ReceiptReconciler.draftLines(for: scan)

        #expect(lines.filter { $0.kind == .item }.count == scan.items.count)
        #expect(Self.reconcile(lines, scan).status == .matched)
    }

    /// 税率の行（外税8% ¥40）とまとめた行（消費税等 ¥40）を足すと、正しく読んだレシートでも合わなくなる。
    @Test("税率が 1 つの外税で、税率の行とまとめた行が並んでも、税を二重に足さずに合う")
    func singleRateTaxSummaryMatches() {
        let scan = ReceiptFixtures.scan(ReceiptFixtures.singleRateExclusiveWithSummary)
        let lines = ReceiptReconciler.draftLines(for: scan)

        #expect(lines.map(\.kind) == [.item, .taxAndOther])
        #expect(lines.map(\.amount) == [500, 40])
        #expect(Self.reconcile(lines, scan).status == .matched)
    }

    /// 読み落とした額（¥80）が内税の額と同じでも、外税の税として埋めず、差として出す（黙って記録しない）。
    @Test("内税のレシートで品目を読み落としたら、税の行で埋めずに差を返す")
    func inclusiveMissingLineIsMismatched() {
        let scan = ReceiptFixtures.scan(ReceiptFixtures.inclusiveMissingLine)
        let lines = ReceiptReconciler.draftLines(for: scan)

        #expect(lines.map(\.kind) == [.item])
        #expect(Self.reconcile(lines, scan).status == .mismatched(difference: 80))
    }

    @Test("合計が読めなければ、行の合計で記録する（照合できないことを返す）")
    func totalMissing() {
        let scan = ReceiptFixtures.scan(ReceiptFixtures.totalMissing)
        let lines = ReceiptReconciler.draftLines(for: scan)
        let result = Self.reconcile(lines, scan)

        #expect(result.status == .totalMissing)
        #expect(result.linesTotal == 646)
        #expect(result.receiptTotal == nil)
    }

    @Test("品目も合計も無ければ、下書きは空")
    func noItemsNoLines() {
        #expect(ReceiptReconciler.draftLines(for: ReceiptFixtures.scan(ReceiptFixtures.noItems)).isEmpty)
    }

    /// 品目を読み落としたり、読み違えたりしたときは、差（レシートの合計 − 行の合計）を返す。黙って記録しない（画面が確かめる）。
    @Test("合わないときは差を返す（足りなければ正、多ければ負）")
    func mismatchReportsDifference() {
        #expect(ReceiptReconciler.reconcile(linesTotal: 700, receiptTotal: 782).status == .mismatched(difference: 82))
        #expect(ReceiptReconciler.reconcile(linesTotal: 900, receiptTotal: 782).status == .mismatched(difference: -118))
        #expect(ReceiptReconciler.reconcile(linesTotal: 782, receiptTotal: 782).status == .matched)
    }

    @Test("額のいちばん多いカテゴリ（同じ額なら先に出てきたもの）")
    func dominantCategory() {
        #expect(ReceiptReconciler.dominantCategory(of: [(100, .food), (80, .daily), (50, .daily)]) == .daily)
        #expect(ReceiptReconciler.dominantCategory(of: [(100, .cafe), (100, .food)]) == .cafe)
        #expect(ReceiptReconciler.dominantCategory(of: []) == nil)
    }

    @Test("按分は最大剰余法で、引いた額の合計をちょうどにし、どの行も 1 円以上残す")
    func deducting() {
        #expect(ReceiptReconciler.deducting(54, from: [580, 98]) == [534, 90])
        #expect(ReceiptReconciler.deducting(3, from: [100, 100, 100]) == [99, 99, 99])
        #expect(ReceiptReconciler.deducting(2, from: [100, 100, 100]) == [99, 99, 100])
        #expect(ReceiptReconciler.deducting(200, from: [100, 100]) == nil)
        #expect(ReceiptReconciler.deducting(0, from: [100]) == [100])
    }

    // MARK: - 記録

    @Test("品目ごと: 1 行を 1 件にする（品名が空なら店名）")
    func recordsPerItem() {
        let records = ReceiptReconciler.records(
            [
                ReceiptRecordLine(name: "牛乳", amount: 198, category: .food),
                ReceiptRecordLine(name: " ", amount: 70, category: .food),
                ReceiptRecordLine(name: "ティッシュ", amount: 0, category: .daily),
            ],
            mode: .perItem, storeName: "イオン 渋谷店 TEL03-0000-0000", singleCategory: .food
        )

        #expect(records == [
            ReceiptRecord(memo: "牛乳", amount: 198, category: .food),
            ReceiptRecord(memo: "イオン 渋谷店", amount: 70, category: .food),
        ])
    }

    @Test("まとめて 1 件: 合計を 1 件にし、品目は店名、カテゴリは選んだもの")
    func recordsSingle() {
        let records = ReceiptReconciler.records(
            [
                ReceiptRecordLine(name: "牛乳", amount: 198, category: .food),
                ReceiptRecordLine(name: "ティッシュ", amount: 298, category: .daily),
            ],
            mode: .single, storeName: "イオン 渋谷店", singleCategory: .food
        )

        #expect(records == [ReceiptRecord(memo: "イオン 渋谷店", amount: 496, category: .food)])
        #expect(ReceiptReconciler.records([], mode: .single, storeName: nil, singleCategory: .food).isEmpty)
    }
}
