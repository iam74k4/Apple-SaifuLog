import Foundation
import Testing
@testable import SaifuLogCore

@Suite("Apple Pay の支払いの記録")
struct PaymentCaptureTests {
    @Test("円だけを受け取り、1 円未満は四捨五入する。ほかの通貨・0 円・上限を超える額は受け取らない")
    func yenAmount() {
        #expect(PaymentCapture.yenAmount(450, currencyCode: "JPY") == 450)
        #expect(PaymentCapture.yenAmount(450, currencyCode: "jpy") == 450)
        #expect(PaymentCapture.yenAmount(Decimal(string: "449.5")!, currencyCode: "JPY") == 450)
        #expect(PaymentCapture.yenAmount(Decimal(string: "449.4")!, currencyCode: "JPY") == 449)
        #expect(PaymentCapture.yenAmount(Decimal(string: "4.50")!, currencyCode: "USD") == nil)
        #expect(PaymentCapture.yenAmount(0, currencyCode: "JPY") == nil)
        #expect(PaymentCapture.yenAmount(Decimal(string: "0.4")!, currencyCode: "JPY") == nil)
        #expect(PaymentCapture.yenAmount(-500, currencyCode: "JPY") == nil)
        #expect(PaymentCapture.yenAmount(Decimal(EntryAmountInput.maximumAmount) + 1, currencyCode: "JPY") == nil)
    }

    @Test("店名は半角のカナを全角に、全角の英数字を半角にし、空白をまとめ、後ろの支店名を外す")
    func memo() {
        #expect(PaymentCapture.memo(fromMerchant: "ｽﾀｰﾊﾞｯｸｽ ｺｰﾋｰ") == "スターバックス コーヒー")
        #expect(PaymentCapture.memo(fromMerchant: "ＳＴＡＲＢＵＣＫＳ　ＣＯＦＦＥＥ") == "STARBUCKS COFFEE")
        #expect(PaymentCapture.memo(fromMerchant: "  ユニクロ   新宿店 ") == "ユニクロ")
        #expect(PaymentCapture.memo(fromMerchant: "ｾﾌﾞﾝｲﾚﾌﾞﾝ ｼﾌﾞﾔ1ﾁｮｳﾒﾃﾝ") == "セブンイレブン")
        // 語が 1 つだけなら外さない。
        #expect(PaymentCapture.memo(fromMerchant: "喫茶店") == "喫茶店")
        #expect(PaymentCapture.memo(fromMerchant: "") == "")
    }

    @Test("カテゴリは店の名前の辞書とキーワード辞書で決め、当たらなければその他")
    func categoryFromDictionaries() {
        let memory = CategoryMemory()
        #expect(PaymentCapture.category(forMerchant: "スターバックス コーヒー", amount: 450, memory: memory) == .cafe)
        #expect(PaymentCapture.category(forMerchant: "7-ELEVEN", amount: 300, memory: memory) == .food)
        #expect(PaymentCapture.category(forMerchant: "マツモトキヨシ 渋谷店", amount: 980, memory: memory) == .daily)
        #expect(PaymentCapture.category(forMerchant: "Suica", amount: 1000, memory: memory) == .transport)
        #expect(PaymentCapture.category(forMerchant: "ユニクロ 新宿店", amount: 3990, memory: memory) == .other)
    }

    @Test("覚えたカテゴリと作ったカテゴリの名前を、辞書より先に使う（一覧に無いカテゴリを指す覚えは使わない）")
    func categoryFromMemory() {
        let catalog = CategoryCatalog(customs: [CustomCategoryInfo(id: "c1", name: "衣服", symbolName: "tshirt", colorIndex: 0)])
        let memory = CategoryMemory(rules: ["ユニクロ": .custom("c1"), "スターバックス": .entertainment, "ジーユー": .custom("gone")])

        #expect(PaymentCapture.category(forMerchant: "ユニクロ 新宿店", amount: 3990, memory: memory, catalog: catalog) == .custom("c1"))
        #expect(PaymentCapture.category(forMerchant: "スターバックス", amount: 450, memory: memory, catalog: catalog) == .entertainment)
        #expect(PaymentCapture.category(forMerchant: "ジーユー", amount: 990, memory: memory, catalog: catalog) == .other)
        #expect(PaymentCapture.category(forMerchant: "衣服のお店", amount: 990, memory: memory, catalog: catalog) == .custom("c1"))
    }

    @Test("支払いの印は ID を小文字にしたもの")
    func occurrenceKey() {
        #expect(PaymentCapture.occurrenceKey(paymentID: "ABC-123") == "wallet/abc-123")
    }
}
