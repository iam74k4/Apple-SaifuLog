import Foundation
import Testing
@testable import SaifuLogCore

/// 端末内 AI の品目の読みの当てはめ（`ReceiptItemRefinement`）と、要約に入れる店名（`ReceiptSummary`）。
@Suite("レシートの AI の読みと要約")
struct ReceiptItemRefinementTests {
    static let items = [
        ReceiptItem(name: "ｷﾞｭｳﾆｭｳ", amount: 198, category: .food),
        ReceiptItem(name: "BPﾁｯﾌﾟ", amount: 158, category: .food),
        ReceiptItem(name: "ｼｬﾝﾌﾟｰ", amount: 698, discount: 100, category: .daily),
        ReceiptItem(name: "ﾓﾔｼ", amount: 76, quantity: 2, unitPrice: 38, category: .food),
    ]

    /// AI の金額は照合にだけ使い、記録する額はいつも OCR の額。
    @Test("金額が合う品目は品名とカテゴリを採り、金額は OCR のまま")
    func appliesNameAndCategoryButNotAmount() {
        let refined = ReceiptItemRefinement.apply(
            [
                ReceiptItemSuggestion(number: 1, name: "牛乳", categoryName: "食費", amountText: "198円"),
                ReceiptItemSuggestion(number: 3, name: "シャンプー", categoryName: "日用品", amountText: "¥598"),
                ReceiptItemSuggestion(number: 4, name: "もやし", categoryName: "食費", amountText: "38"),
            ],
            to: Self.items
        )

        #expect(refined.map(\.name) == ["牛乳", "BPﾁｯﾌﾟ", "シャンプー", "もやし"])
        #expect(refined.map(\.amount) == Self.items.map(\.amount))
        #expect(refined.map(\.discount) == Self.items.map(\.discount))
        #expect(refined.map(\.category) == [.food, .food, .daily, .food])
    }

    /// 番号を取り違えた・別の行を読んだ・作った金額は、品目の額と合わないので、その品目の AI の読みを捨てる。
    @Test("AI の金額が OCR の額と合わなければ、その品目の AI の読みを使わない")
    func ignoresSuggestionWhenAmountDiffers() {
        let refined = ReceiptItemRefinement.apply(
            [
                ReceiptItemSuggestion(number: 1, name: "コーヒー牛乳", categoryName: "カフェ", amountText: "298"),
                ReceiptItemSuggestion(number: 2, name: "ポテトチップス", categoryName: "食費", amountText: ""),
            ],
            to: Self.items
        )

        #expect(refined == Self.items)
    }

    @Test("一覧に無い番号・同じ番号の 2 つ目・知らないカテゴリ・長すぎる品名は使わない")
    func ignoresInvalidSuggestions() {
        let refined = ReceiptItemRefinement.apply(
            [
                ReceiptItemSuggestion(number: 0, name: "作った品目", categoryName: "食費", amountText: "198"),
                ReceiptItemSuggestion(number: 9, name: "作った品目", categoryName: "食費", amountText: "198"),
                ReceiptItemSuggestion(number: 1, name: "牛乳", categoryName: "飲み物", amountText: "198"),
                ReceiptItemSuggestion(number: 1, name: "低脂肪乳", categoryName: "食費", amountText: "198"),
                ReceiptItemSuggestion(number: 2, name: String(repeating: "ポ", count: 41), categoryName: "娯楽", amountText: "158"),
            ],
            to: Self.items
        )

        #expect(refined.count == Self.items.count)
        #expect(refined[0].name == "牛乳")
        #expect(refined[0].category == .food)
        #expect(refined[1].name == "BPﾁｯﾌﾟ")
        #expect(refined[1].category == .entertainment)
    }

    @Test("品名に金額や印を付けて返したら、それを除く。文字の無い品名は使わない")
    func cleansSuggestedNames() {
        #expect(ReceiptItemRefinement.acceptedName("牛乳 ¥198") == "牛乳")
        #expect(ReceiptItemRefinement.acceptedName("※牛乳") == "牛乳")
        #expect(ReceiptItemRefinement.acceptedName("198") == nil)
        #expect(ReceiptItemRefinement.acceptedName("  ") == nil)
    }

    // MARK: - 要約に入れる店名

    /// 記録の元の文には OCR の全文を入れず、店名と合計だけにする。店名の行に並ぶ電話番号やカード番号も入れない。
    @Test("店名から、電話番号・長い数字・記号の並びを除く")
    func storeLabelDropsPersonalNumbers() {
        #expect(ReceiptSummary.storeLabel("イオン 渋谷店 TEL 03-0000-0000") == "イオン 渋谷店")
        #expect(ReceiptSummary.storeLabel("ローソン 1234-5678-9012-3456") == "ローソン")
        #expect(ReceiptSummary.storeLabel("カフェ ****1234") == "カフェ")
        #expect(ReceiptSummary.storeLabel("セブン-イレブン") == "セブン-イレブン")
        // 端の「·」（OCR が読み違えた「¥」かつなぎの点）は品名と同じく除き、店名の中の「·」は残す。
        #expect(ReceiptSummary.storeLabel("カフェ\u{B7}ひかり \u{B7}") == "カフェ\u{B7}ひかり")
        #expect(ReceiptSummary.storeLabel("0120-000-000") == nil)
        #expect(ReceiptSummary.storeLabel(nil) == nil)
        #expect(ReceiptSummary.storeLabel(String(repeating: "あ", count: 40))?.count == ReceiptSummary.maximumStoreNameLength)
    }
}
