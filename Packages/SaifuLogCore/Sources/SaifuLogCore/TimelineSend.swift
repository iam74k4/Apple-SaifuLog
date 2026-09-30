import Foundation

/// タイムラインで、1 回の送信で記録したもの（ひとこと入力の複数件・レシートの品目）を 1 つの送信にまとめる決め事。
///
/// ホームのタイムラインは、送った文を自分の吹き出しに、記録したものをアプリの返事のカードに出す（会話の形）。そのために
/// どの記録が同じ送信のものかが要るが、送信は保存しない（記録のモデルを変えると、保存済みの記録の移行と iCloud の
/// スキーマの変更が要るため）。1 回の送信で記録したものは、元の文（`originalText`）と入力元が同じで、記録した日時が
/// 書いた順に 1 ミリ秒ずつずれている（`ParsedEntry.timestamps`。レシートも同じ）ので、そこから組み立てる。
///
/// 記録した日時の順に並べた記録のうち、元の文と入力元が前の記録と同じで、記録した日時の間が `maximumGap` 以下のものは、
/// 前の記録と同じ送信とみなす。同じ文をあとでもう一度送ったとき（昼と夜の「ランチ 850」）は、記録した日時が秒の単位で
/// 離れるので別の送信になる（読み取りを待つ間は次を送れないので、2 回の送信が `maximumGap` より近づくことはない）。
///
/// 記録を直しても、記録した日時・元の文・入力元は変わらないので、同じ送信のまま（`EntryStore.update`）。送信のうち 1 件を
/// 消しても、残りの記録の間は `maximumGap` を超えないので、残りは同じ送信のまま。タイムラインの読み込みの件数の区切りで
/// いちばん古い送信の前の件が切れたときは、読み込んだ件だけの送信になる。
public enum TimelineSend {
    /// 同じ送信とみなす、続いた 2 件の記録した日時の間の最大（秒）。
    ///
    /// 1 回の送信の中は 1 ミリ秒ずつ（`ParsedEntry.orderingStep`）なので、途中の何件かを消しても十分に収まる。
    /// 別の送信は、読み取り（AI なら 1 秒以上）を待たないと送れないので、これより近づかない。
    public static let maximumGap: TimeInterval = 0.1

    /// まとめるのに使う、記録の値（記録のモデルに依存しないように、値だけを渡す）。
    public struct Record<ID: Hashable, Source: Hashable>: Hashable {
        /// 記録の ID（まとめた結果を記録に戻すため）。
        public var id: ID
        /// 元の文（送った文。レシートは店名と合計の要約）。
        public var originalText: String
        /// 入力元（ひとこと入力・声・レシート）。
        public var source: Source
        /// 記録した日時。
        public var createdAt: Date

        public init(id: ID, originalText: String, source: Source, createdAt: Date) {
            self.id = id
            self.originalText = originalText
            self.source = source
            self.createdAt = createdAt
        }
    }

    /// 記録した日時の古い順に並べた記録を、1 回の送信ごとの範囲（`records` の添字）に分ける。
    ///
    /// 範囲は古い順に並び、すべての記録がどれか 1 つに入る。記録した日時が前の記録より前のもの（並べ方が違う）は、
    /// 前の記録と同じ送信にしない。
    public static func groupRanges<ID, Source>(of records: [Record<ID, Source>]) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var start = 0
        for index in records.indices.dropFirst() where !continuesSend(records[index - 1], records[index]) {
            ranges.append(start..<index)
            start = index
        }
        if !records.isEmpty {
            ranges.append(start..<records.count)
        }
        return ranges
    }

    /// 記録した日時の古い順に並べた記録を、1 回の送信ごとにまとめる（`groupRanges(of:)` の範囲の記録）。
    public static func groups<ID, Source>(of records: [Record<ID, Source>]) -> [[Record<ID, Source>]] {
        groupRanges(of: records).map { Array(records[$0]) }
    }

    /// `next` が `previous` と同じ送信の続きか。
    private static func continuesSend<ID, Source>(_ previous: Record<ID, Source>, _ next: Record<ID, Source>) -> Bool {
        let gap = next.createdAt.timeIntervalSince(previous.createdAt)
        return next.originalText == previous.originalText && next.source == previous.source
            && gap >= 0 && gap <= maximumGap
    }
}
