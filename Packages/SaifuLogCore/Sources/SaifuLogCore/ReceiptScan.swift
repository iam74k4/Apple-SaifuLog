import Foundation

// MARK: - 入力

/// 文字認識（OCR）が読んだ 1 行。
///
/// 画像や Vision の型はアプリの側に置き、コアには文字と位置だけを渡す。コアを `swift test` だけで確かめられるようにするため。
public struct ReceiptTextLine: Sendable, Hashable {
    /// 読んだ文字（全角・半角のまま）。
    public var text: String
    /// 画像の中の位置。分からなければ nil（文字だけの行として、渡した順に並べる）。
    public var frame: Frame?

    public init(_ text: String, frame: Frame? = nil) {
        self.text = text
        self.frame = frame
    }

    /// 画像の中の位置。画像の幅と高さを 1 とした値で、左上を原点にする（Vision の左下の原点とは上下が逆）。
    public struct Frame: Sendable, Hashable {
        public var minX: Double
        public var minY: Double
        public var maxX: Double
        public var maxY: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            minX = x
            minY = y
            maxX = x + max(0, width)
            maxY = y + max(0, height)
        }

        var height: Double { maxY - minY }
        var midY: Double { (minY + maxY) / 2 }
    }
}

// MARK: - 読み取った結果

/// レシートの文字から読み取ったもの（`ReceiptLineScanner.scan`）。
///
/// 金額はすべてコードが OCR の文字から読んだ値で、AI の答えは入らない（AI には品名とカテゴリだけを整えさせる。
/// `ReceiptItemRefinement`）。
public struct ReceiptScan: Sendable, Hashable {
    /// 店名。読めなければ nil。
    public var storeName: String?
    /// 店名から推定した、レシート全体の既定のカテゴリ（スーパー・コンビニは食費、ドラッグストアは日用品、カフェはカフェ）。
    /// 推定できなければ nil。
    public var storeCategory: EntryCategory?
    /// 買った日（と時刻）。読めなければ nil。
    public var purchasedOn: ReceiptDate?
    /// 品目（レシートの順）。
    public var items: [ReceiptItem]
    /// 品目に付かない値引き（小計の後の値引きなど）の合計。正の数。
    public var receiptDiscount: Int
    /// 小計。読めなければ nil。
    public var subtotal: Int?
    /// 内税か外税か。
    public var taxMode: ReceiptTaxMode
    /// 外税のレシートで、品目の額に足す税の額（内税なら 0）。
    public var exclusiveTax: Int
    /// レシートの合計（税込み）。読めなければ nil。
    public var total: Int?
    /// お預かり（現金で渡した額）。記録には使わない。
    public var tendered: Int?
    /// お釣り。記録には使わない。
    public var change: Int?
    /// ポイント。円ではないので記録には使わない。
    public var points: Int?
    /// 行ごとの見分け（読み取りの順）。テストと、読めなかった理由の見分けに使う。
    public var rows: [ReceiptRow]

    /// 読み取った文字が 1 つも無かったか（白紙・真っ暗・ピンぼけ）。
    public var hasNoText: Bool {
        rows.isEmpty
    }

    /// 記録できるものが無いか（品目も合計も読めなかった）。
    public var hasNoAmounts: Bool {
        items.isEmpty && total == nil
    }

    /// 品目の額（値引きを引いた額）の合計。
    public var itemsTotal: Int {
        items.reduce(0) { $0 + $1.netAmount }
    }
}

/// 読めなかった理由。
public enum ReceiptUnreadableReason: Sendable, Hashable {
    /// 文字が 1 つも読めなかった。
    case noText
    /// 文字は読めたが、品目も合計も見つからなかった。
    case noAmounts
    /// 画像を読み込めなかった（選んだ写真のデータを読めない・iCloud から取り出せない、撮った画像を取り出せない）。
    /// 読み取りの前の失敗なので、コアの読み取りは返さない（アプリが返す）。
    case imageUnavailable
}

/// 内税か外税か。
public enum ReceiptTaxMode: Sendable, Hashable {
    /// 品目の額に税が含まれている（合計 = 品目の額の合計）。
    case inclusive
    /// 品目の額は税抜きで、合計に税を足す（合計 = 品目の額の合計 + 税）。
    case exclusive
}

/// 品目 1 つ。
public struct ReceiptItem: Sendable, Hashable {
    /// 品名（OCR の文字を整えたもの。AI が整えたら差し替わる）。
    public var name: String
    /// その行の額（数量 × 単価なら掛けた額）。値引きは引く前。正の数。
    public var amount: Int
    /// 数量（「2コ X 単98」の 2）。書かれていなければ nil。
    public var quantity: Int?
    /// 単価（「2コ X 単98」の 98）。書かれていなければ nil。
    public var unitPrice: Int?
    /// この品目に付いた値引き（すぐ下の「値引 -20」など）の合計。正の数。
    public var discount: Int
    /// 軽減税率の印（「※」「*」「軽」）があったか。
    public var isReducedTaxRate: Bool
    /// カテゴリ（品名のキーワード、当たらなければ店の既定のカテゴリ、それも無ければその他）。
    public var category: EntryCategory

    public init(
        name: String, amount: Int, quantity: Int? = nil, unitPrice: Int? = nil, discount: Int = 0,
        isReducedTaxRate: Bool = false, category: EntryCategory = .other
    ) {
        self.name = name
        self.amount = amount
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.discount = discount
        self.isReducedTaxRate = isReducedTaxRate
        self.category = category
    }

    /// 値引きを引いた額（記録する額）。
    public var netAmount: Int {
        amount - discount
    }
}

/// レシートに書かれた日付。
public struct ReceiptDate: Sendable, Hashable {
    /// 何日前か（0 = 今日）。レシートは使った後のものなので、先の日付は読まない。
    public var daysAgo: Int
    /// 時刻（時）。書かれていなければ nil。
    public var hour: Int?
    /// 時刻（分）。書かれていなければ nil。
    public var minute: Int?

    public init(daysAgo: Int, hour: Int? = nil, minute: Int? = nil) {
        self.daysAgo = daysAgo
        self.hour = hour
        self.minute = minute
    }

    /// 記録に使う日時。時刻が書かれていればその時刻、無ければ `now` と同じ時刻のその日。
    public func date(now: Date, calendar: Calendar) -> Date {
        let day = DateExpression.date(daysAgo: daysAgo, now: now, calendar: calendar)
        guard let hour, let minute else { return day }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }
}

/// 1 行の見分け。
public struct ReceiptRow: Sendable, Hashable {
    /// 表記ゆれをそろえた行の文字。
    public var text: String
    public var kind: Kind

    public init(text: String, kind: Kind) {
        self.text = text
        self.kind = kind
    }

    public enum Kind: Sendable, Hashable {
        /// 店名。
        case storeName
        /// 日付・時刻。
        case date
        /// 品目（数量の行と合わせたものも）。
        case item
        /// 数量 × 単価の行（前後の品目に合わせた）。
        case quantity
        /// 値引き・割引の行。
        case discount
        /// 小計。
        case subtotal
        /// 消費税（内税・外税）。
        case tax
        /// 税率ごとの対象額（「8%対象 ¥1,000」）。記録には使わない。
        case taxBase
        /// 合計。
        case total
        /// お預かり・現金。
        case tendered
        /// お釣り。
        case change
        /// ポイント。
        case points
        /// 支払いの方法（カード・電子マネーなど）。
        case payment
        /// カード番号（「************1234」）。記録にも要約にも入れない。
        case cardNumber
        /// 点数（「お買上点数 5点」）。
        case count
        /// そのほか（電話番号・住所・登録番号・レジの番号・挨拶・区切りの線など）。
        case noise
    }
}
