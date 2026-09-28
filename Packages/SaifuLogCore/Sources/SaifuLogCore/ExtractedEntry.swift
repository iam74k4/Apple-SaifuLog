import Foundation

/// 端末内 AI（Foundation Models のガイド付き生成）が 1 件分として抜き出した値。表記のまま持つ。
///
/// `@Generable` の型は FoundationModels に依存するのでアプリ側にしか置けない。ここでは文字列と数だけで
/// 受け取り、入力との突き合わせと記録への組み立てをコアで行う。AI の出力をどこまで信じるかを、
/// 端末に依存しない swift test で確かめられるようにするため。
public struct ExtractedEntry: Sendable, Hashable {
    /// 何に使ったか、何の収入か（品目や店名）。書かれていなければ空。
    public var item: String
    /// 金額の表記（「12000」「25万」）。
    public var amountText: String
    /// カテゴリの表示名（`EntryCategory.displayName`）。
    public var categoryName: String
    /// 収入なら true。
    public var isIncome: Bool
    /// 割り勘の人数。割り勘でなければ 1。
    ///
    /// 保存する人数には使わない（入力のその件にかかる割り勘の人数を使う。`resolved(against:)`）。
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
        /// 金額が入力（のその件の区間）に書かれていない（計算した値や作った数字）。
        case ungroundedAmount
        /// AI が返した件数が、入力の区間の数と合わない（同じ記録の繰り返しや抜け）。
        case entryCountMismatch
    }

    /// 区間ごとに 1 件ずつ読ませた AI の結果を、入力全体とまとめて突き合わせる。
    ///
    /// `entries[i]` を `input.segments[i]` と突き合わせる（区間の順に 1 件ずつ）。件数が区間の数と合わないとき
    /// （同じ記録を繰り返した・抜けた）や、どれか 1 件でも金額が区間に書かれていないときは throw する。
    /// 呼び出し側（`FallbackEntryParser`）がルールベースで読み直す。
    /// 区間どうしの金額は重ならないので、入力の金額を二重に使うことも、使い残すこともない。
    public static func resolveAll(_ entries: [ExtractedEntry], against input: EntryInput) throws -> [ParsedEntry] {
        guard entries.count == input.segments.count else { throw ResolveError.entryCountMismatch }
        return try zip(entries, input.segments).map { entry, segment in
            try entry.resolved(against: segment)
        }
    }

    /// 入力の区間 1 件と突き合わせて、1 件の記録にする。
    ///
    /// 数字は AI に作らせない。モデルが入力に無い値を返しても、それで保存する金額や日付が
    /// 変わらないよう、次のように扱う。
    /// - 金額: 区間に書かれた金額のどれとも一致しなければ `ResolveError.ungroundedAmount` を投げる。
    ///   その件の金額に採らない額（税抜きの値段・値引き・合計・おつり・ポイント）とは突き合わせない。
    ///   マイナスを付けない値引き（「850 100円引き」）は、ルールベースと同じく引いた額で記録する。
    ///   「-500」のようにマイナスを付けて書かれた額は、モデルの答えによらず返金として収入にする
    /// - 日付: 表記の指す日が、区間に書かれた日付かこの件に割り当てた日付と一致するときだけ使う。
    ///   そうでなければ入力から割り当てた日付を使う（「一昨日」の入力に「昨日」と返されても 1 日ずれない）
    /// - 割り勘の人数: モデルの値は使わず、入力のこの件にかかる割り勘（割り勘の語と「N人」の組）の人数で割る。
    ///   モデルが違う人数や 1 を返しても、ルールベースと同じ額になるようにするため。
    ///   「1人あたり3000」のように 1 人分として書かれた額は割らない（メモに「1人分」と書き足す）
    /// - 収入: モデルが収入と返しても、区間に打ち消しの語（「収入印紙」）や支出の言い回し（「入金手数料」）が
    ///   あれば支出にする。収入の語が無いだけなら収入のまま（「お小遣いもらった」）
    /// - 品目: 区間に書かれた言葉でなければ（「昨日」だけ・作った品目）ルールベースのメモにする
    ///   （`InputSegment.groundedItem(from:memo:)`）。そのときはカテゴリもルールベースの推定にする（根拠の無い「食費」を保存しない）
    public func resolved(against segment: InputSegment) throws -> ParsedEntry {
        guard let value = AmountParser.yen(from: amountText),
              let candidate = segment.candidate(matching: value)
        else {
            throw ResolveError.ungroundedAmount
        }
        let amount = candidate.amount

        let daysAgo: Int
        if let fromModel = DateExpression.daysAgo(in: dateText, now: segment.now, calendar: segment.calendar),
           segment.dateCandidates.contains(fromModel) {
            daysAgo = fromModel
        } else {
            daysAgo = segment.daysAgo ?? 0
        }

        let groundedItem = segment.groundedItem(from: item, memo: candidate.memo)
        return ParsedEntry.assemble(
            total: candidate.value,
            category: groundedItem == nil ? segment.ruleCategory : EntryCategory(displayName: categoryName) ?? .other,
            isIncome: amount.isNegative || (isIncome && !IncomeRule.contradictsIncome(segment.contextText)),
            item: groundedItem ?? candidate.memo,
            daysAgo: daysAgo,
            splitCount: segment.splitCount ?? 1,
            isPerPerson: amount.isPerPerson
        )
    }

    /// 入力全体と突き合わせて 1 件の記録にする。金額が書かれた最初の区間と突き合わせる（`resolved(against:)`）。
    ///
    /// 1 件ずつ呼ぶと、件数の過不足や同じ金額の二重使用を見つけられない。複数件を読むときは
    /// `resolveAll(_:against:)` を使う。
    public func resolved(against input: String, now: Date, calendar: Calendar) throws -> ParsedEntry {
        let parsed = EntryInput(input, now: now, calendar: calendar)
        guard let value = AmountParser.yen(from: amountText),
              let segment = parsed.segments.first(where: { $0.candidate(matching: value) != nil })
        else {
            throw ResolveError.ungroundedAmount
        }
        return try resolved(against: segment)
    }
}
