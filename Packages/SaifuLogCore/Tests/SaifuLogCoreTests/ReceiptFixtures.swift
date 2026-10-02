import Foundation
@testable import SaifuLogCore

/// レシートの OCR の文字（テスト用）。実際のレシートの形をまねて作った架空のもの（店名・電話番号・番号はどれも実在しない値）。
///
/// OCR が返すとおり、全角の数字・半角のカナ・全角の記号を混ぜて書く。Fixture の今日は 2026-09-28 12:00（日本時間）。
enum ReceiptFixtures {
    /// 文字だけの行（位置なし）にする。
    static func lines(_ text: String) -> [ReceiptTextLine] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { ReceiptTextLine(String($0)) }
    }

    /// 位置のある行にする（Vision の返し方をまねる）。行の最後の空白の後（金額など）を右に、その前を左に置き、別の塊として返す。
    /// 右の塊は、傾いて写ったように少し下にずらし、左の塊より先に並べる（Vision は上から順に返すとは限らないため）。
    static func positionedLines(_ text: String) -> [ReceiptTextLine] {
        var lines: [ReceiptTextLine] = []
        for (index, row) in text.split(separator: "\n").enumerated() {
            let trimmed = row.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let y = 0.02 + Double(index) * 0.03
            if let split = trimmed.lastIndex(where: \.isWhitespace) {
                let left = trimmed[..<split].trimmingCharacters(in: .whitespaces)
                let right = trimmed[trimmed.index(after: split)...]
                lines.append(ReceiptTextLine(String(right), frame: .init(x: 0.7, y: y + 0.004, width: 0.25, height: 0.02)))
                lines.append(ReceiptTextLine(left, frame: .init(x: 0.05, y: y, width: 0.5, height: 0.02)))
            } else {
                lines.append(ReceiptTextLine(trimmed, frame: .init(x: 0.05, y: y, width: 0.5, height: 0.02)))
            }
        }
        return lines
    }

    static func scan(_ text: String) -> ReceiptScan {
        ReceiptLineScanner.scan(lines(text), now: Fixture.now, calendar: Fixture.calendar)
    }

    /// 1. スーパー・内税（軽減税率の印「※」、税率ごとの対象額と内税の行）。
    static let supermarketInclusive = """
        イオン 渋谷店
        東京都渋谷区道玄坂１－２－３
        TEL 03-0000-0000
        2026年09月27日(日) 18:32 レジ0012
        ※牛乳 ￥198
        ※食パン ￥158
        ※ﾊﾞﾅﾅ ￥128
        ティッシュ ￥298
        小計 ￥782
        (8%対象 ￥484 内税 ￥35)
        (10%対象 ￥298 内税 ￥27)
        合計 ￥782
        お預り ￥1,000
        お釣り ￥218
        ※印は軽減税率対象商品です
        """

    /// 2. スーパー・外税（小計 + 外税 = 合計）とカード払い。
    static let supermarketExclusive = """
        業務スーパー 中野店
        2026/09/26 10:05
        豚肉 498
        キャベツ 158
        卵 10個入 228
        小計 ¥884
        外税 8% ¥70
        合計 ¥954
        クレジット ¥954
        ************1234
        """

    /// 3. コンビニ（「＊」の軽減税率の印を金額の前に置く）。
    static let convenienceStore = """
        セブン-イレブン
        渋谷道玄坂店
        東京都渋谷区道玄坂２丁目
        電話:03-0000-0000
        2026年9月28日(月) 8:15
        領収書
        おにぎり 鮭 ＊１５０
        サンドイッチ ＊３２８
        ホットコーヒーＲ １２０
        合計 ¥598
        (税率8%対象 ¥478)
        (税率10%対象 ¥120)
        (内消費税等 ¥46)
        nanaco支払 ¥598
        nanaco残高 ¥1,402
        """

    /// 4. ドラッグストア（品目の下の値引き「-100」「▲256」）。
    static let drugstoreDiscounts = """
        マツモトキヨシ 新宿店
        2026-09-25 19:40
        シャンプー 698
         値引 -100
        目薬 1,280
         割引20% ▲256
        ﾎﾟﾃﾄﾁｯﾌﾟｽ ※158
        小計 ¥1,780
        合計 ¥1,780
        ポイント 17P
        """

    /// 5. 飲食店（品目が無く、合計だけ）。
    static let restaurantTotalOnly = """
        居酒屋 はなこ
        2026年9月20日
        御会計 ¥8,800
        (内消費税等 ¥800)
        お預り ¥10,000
        お釣り ¥1,200
        またのご来店をお待ちしております
        """

    /// 6. 軽減税率の混在（「軽」の印と、印の無い品目）。
    static let mixedTaxRates = """
        ローソン
        2026/9/27 12:03
        からあげクン 軽 238
        緑茶 500ml 軽 140
        電池 単3 4本 440
        合計 ¥818
        (8%対象 ¥378 消費税 ¥28)
        (10%対象 ¥440 消費税 ¥40)
        """

    /// 7. 数量 × 単価（品名の下・上に置いた数量の行と、同じ行の数量）。
    static let quantities = """
        マルエツ
        2026年09月27日 17:10
        もやし
         2コX単38        76
        ﾖｰｸﾞﾙﾄ          ¥396
         (3個 × @132)
        @98 x 2
        ﾁｮｺﾚｰﾄ 196
        豆腐 3点 単価 88 264
        合計 ¥932
        """

    /// 8. 和暦の日付（令和）と、内税・外税の語の無い「消費税等」（小計 + 税 = 合計なので外税）。
    static let japaneseEraDate = """
        コープ みらい
        令和8年9月26日(土) 15:22
        ｷﾞｭｳﾆｭｳ 1000ml 238
        ﾀﾏｺﾞ 10コ 248
        小計 ¥486
        消費税等 ¥38
        合計 ¥524
        """

    /// 9. 合計が読めない（レシートの下が切れた）。
    static let totalMissing = """
        八百屋 まるやま
        2026/09/27
        トマト 298
        きゅうり 3本 150
        玉ねぎ 198
        """

    /// 10. 品目が 0（金額の無い紙）。
    static let noItems = """
        ご来店ありがとうございます
        ポイントカードをお持ちですか
        またお越しください
        """

    /// 11. ノイズの多い行（区切りの線・郵便番号と住所・電話と FAX・登録番号・営業時間・レジと担当者・JAN のコード・点数・URL）。
    static let noisy = """
        ＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊
          スーパーマーケット さくら
        〒150-0001 東京都渋谷区神宮前1-2-3
        TEL:03-0000-0000 FAX:03-0000-0001
        登録番号 T1234567890123
        営業時間 9:00～22:00
        2026年 9月27日(日) 11:48  #0123
        レジNo.02 責:105 担当:山田
        --------------------------------
        4901234567890 ｷｬﾍﾞﾂ ¥158
        ﾊﾞﾗ肉 ¥580
        お買上点数 2点
        小計 ¥738
        合計 ¥738
        現金 ¥1,000
        お釣 ¥262
        --------------------------------
        次回使えるクーポン券を発行しました
        http://example.com/
        """

    /// 12. 小計の後の値引き（品目に付かない値引き）と外税。
    static let receiptDiscount = """
        サミット
        2026/09/27 09:30
        鶏肉 580
        納豆 98
        小計 ¥678
        小計値引 -100
        外税 ¥46
        合計 ¥624
        """

    /// 13. カフェの英語の品名（「COFFEE」「Coffee」の中の OFF は値引きではない）と、品目の下の「20%OFF」の値引き。
    static let cafeEnglishNames = """
        スターバックス コーヒー 渋谷店
        2026/09/27 15:10
        サンドイッチ ¥480
         20%OFF ▲96
        ICED COFFEE ¥380
        Coffee ¥300
        合計 ¥1,064
        """

    /// 14. 品名の中の「オフ」「引き」（「オフィス」「引き出し」は値引きではない）。
    static let officeSupplies = """
        ダイソー 新宿店
        2026/09/27 13:05
        ノート ¥110
        ｵﾌｨｽｸﾘｯﾌﾟ ¥220
        引き出し整理トレー ¥330
        合計 ¥660
        """

    /// 15. 税率が 1 つの外税で、税率の行とまとめた行（「消費税等」）の両方を印字する（税を二重に数えない）。
    static let singleRateExclusiveWithSummary = """
        西友 中野店
        2026/09/27 19:20
        豚肉 500
        小計 ¥500
        (外税8%対象 ¥500)
        外税8% ¥40
        消費税等 ¥40
        合計 ¥540
        """

    /// 16. 内税（「うち消費税」）のレシートで、品目の 1 行（パン ¥80）を読み落とした。読み落とした額が税と同じでも、外税と取り違えない。
    static let inclusiveMissingLine = """
        まいばすけっと
        2026/09/27 20:10
        牛乳 ¥1,000
        合計 ¥1,080
        (うち消費税 ¥80)
        """

    /// 17. 時刻を日付より上の行に印字する。
    static let timeBeforeDate = """
        ローソン 渋谷店
        18:32
        2026/09/27
        おにぎり 150
        合計 ¥150
        """

    /// 18. OCR（`RecognizeDocumentsRequest`）が「￥」を中点の「·」（U+00B7）と読んだ行（「洗剤 ·398」）。読み違えるのは一部の行で、
    /// 「￥」のまま読めた行も混ざる。
    static let misreadYenMarks = """
        ローソン 中野店
        2026/09/27 16:40
        洗剤 ·398
        おにぎり鮭 ·150
        緑茶500ml ·138
        グリーンサラダ ￥298
        ヨーグルト ·128
        小計 ·1,112
        計 ·1,112
        お預り ·2,000
        お釣り ·888
        """

    /// 19. 集計の語を字間を空けて印字する（「小　計」「合　計」「お　釣」。全角の空白）。
    static let spacedLabels = """
        八百屋 まるやま
        2026/09/27 10:20
        トマト ￥298
        きゅうり ￥58
        小　計 ￥356
        合　計 ￥356
        お預り ￥1,000
        お　釣 ￥644
        """

    /// 20. 字間を空けた外税の行（「外　税」）。
    static let spacedExclusiveTax = """
        業務スーパー 中野店
        2026/09/26 10:05
        豚肉 498
        キャベツ 158
        卵 207
        小　計 ￥863
        外　税 ¥69
        合　計 ￥932
        """

    /// 21. 合計を「現計」と印字する。
    static let currentTotal = """
        トマト 298
        きゅうり 150
        現計 ¥448
        """

    /// 22. 買った日時の行より上に、番地が日付の形（「12-3-4」）の住所がある。Fixture の今日ではなく 2026-10-02 に読む。
    static let addressAboveDate = """
        ローソン 芝浦店
        東京都港区芝浦12-3-4
        2026年10月01日 18:32
        おにぎり 150
        合計 ¥150
        """
}
