import Foundation

/// 割り勘の計算。
///
/// AI には「総額」と「人数」を取り出させるだけにして、割り算はここで行う。
/// 端末内のモデルは小さく、割り算を任せると間違えることがあるため。
public struct BillSplit: Sendable, Hashable {
    /// 割る前の総額（円）。
    public let total: Int
    /// 割る人数（自分を含む）。
    public let count: Int

    /// 割り勘として成り立たない値（総額が 0 以下、人数が 1 以下）なら nil。
    public init?(total: Int, count: Int) {
        guard total > 0, count >= 2 else { return nil }
        self.total = total
        self.count = count
    }

    /// 自分の負担額。割り切れないときは端数を切り上げて自分が持つ。
    /// 立て替えた額（あとで返ってくる額）を多めに見積もらないようにするため。
    public var share: Int {
        (total + count - 1) / count
    }

    /// 立て替えた額（ほかの人の分）。
    public var advance: Int {
        total - share
    }

    /// 記録のメモに残す説明。「4人で割り勘・総額 ¥12,000・立替 ¥9,000」。
    public var note: String {
        "\(count)人で割り勘・総額 \(YenFormatter.string(from: total))・立替 \(YenFormatter.string(from: advance))"
    }
}
