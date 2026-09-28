import Foundation

/// 端末内 AI（Foundation Models のガイド付き生成）が 1 件分として抜き出した値。表記のまま持つ。
///
/// `@Generable` の型は FoundationModels に依存するのでアプリ側にしか置けない。ここでは文字列と数だけで
/// 受け取り、入力との突き合わせと記録への組み立てをコアで行う。AI の出力をどこまで信じるかを、
/// 端末に依存しない swift test で確かめられるようにするため。
public struct ExtractedEntry: Sendable, Hashable {
    /// 何に使ったか、何の収入か（品目や店名）。
    public var item: String
    /// 金額の表記（「12000」「25万」）。
    public var amountText: String
    /// カテゴリの表示名（`EntryCategory.displayName`）。
    public var categoryName: String
    /// 収入なら true。
    public var isIncome: Bool
    /// 割り勘の人数。割り勘でなければ 1。
    public var splitCount: Int
    /// 日付の表記（「昨日」「9/26」）。書かれていなければ空。
    public var dateText: String

    public init(
        item: String,
        amountText: String,
        categoryName: String,
        isIncome: Bool,
        splitCount: Int,
        dateText: String
    ) {
        self.item = item
        self.amountText = amountText
        self.categoryName = categoryName
        self.isIncome = isIncome
        self.splitCount = splitCount
        self.dateText = dateText
    }

    public enum ResolveError: Error, Equatable {
        /// 金額が入力に書かれていない（計算した値や作った数字）。
        case ungroundedAmount
    }

    /// 入力と突き合わせて 1 件の記録にする。
    ///
    /// 数字は AI に作らせない。モデルが入力に無い値を返しても、それで保存する金額や日付が
    /// 変わらないよう、次のように扱う。
    /// - 金額: 入力に書かれた金額のどれとも一致しなければ `ResolveError.ungroundedAmount` を投げる。
    ///   呼び出し側（`FallbackEntryParser`）がルールベースで読み直す
    /// - 日付: 表記の指す日が、入力の日付の言い回しの指す日のどれかと一致するときだけ使う。
    ///   そうでなければ入力そのものから読む（「一昨日」の入力に「昨日」と返されても 1 日ずれない）
    /// - 割り勘の人数: 入力に割り勘の語があり、「N人」「N名」の N と一致するときだけ採る。
    ///   それ以外は割らない。ルールベースと同じく、人数だけ・語だけでは割り勘とみなさない
    ///   （「4人でランチ 4000」は 4000 円を払ったのかもしれない）
    public func resolved(against input: String, now: Date, calendar: Calendar) throws -> ParsedEntry {
        let scan = EntryScan(TextNormalizer.normalize(input), now: now, calendar: calendar)
        guard let total = AmountParser.yen(from: amountText),
              scan.amounts.contains(where: { $0.value == total })
        else {
            throw ResolveError.ungroundedAmount
        }

        let daysAgo: Int
        if let fromModel = DateExpression.daysAgo(in: dateText, now: now, calendar: calendar),
           scan.dateCandidates.contains(fromModel) {
            daysAgo = fromModel
        } else {
            daysAgo = scan.daysAgo ?? 0
        }

        let isGroundedSplit = splitCount >= 2 && scan.hasSplitWord && scan.peopleCounts.contains(splitCount)

        return ParsedEntry.assemble(
            total: total,
            category: EntryCategory(displayName: categoryName) ?? .other,
            isIncome: isIncome,
            item: item,
            daysAgo: daysAgo,
            splitCount: isGroundedSplit ? splitCount : 1
        )
    }
}
