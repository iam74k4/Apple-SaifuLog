import Foundation
import SaifuLogCore

/// 入力をコードで件ごとの区間に分け、区間ごとに 1 件ずつ AI に読ませてから、入力全体とまとめて突き合わせる。
///
/// 件の分け方をモデルに任せない。1 回の生成で記録の配列を返させると、端末内のモデルは 1 件の入力にも
/// 余分な要素や同じ記録の繰り返しをほぼ必ず返し、重複した記録がそのまま保存されてしまうため。
/// 区間はルールベースの解析と同じもの（SaifuLogCore の `EntryInput`）なので、どちらで読んでも件の分け方と、
/// 件ごとの日付・割り勘の割り当てが変わらない。
///
/// モデルの呼び出し（`extract`）を引数にしているのは、FoundationModels を使わずに、区間の渡し方と
/// 突き合わせをテストで確かめるため（SaifuLogTests の SegmentedExtractionTests）。
enum SegmentedExtraction {
    /// - Parameters:
    ///   - now: 「昨日」「9/26」を解釈する基準の日時。
    ///   - extract: 区間 1 件を、1 件の記録として読む（端末内 AI）。
    /// - Returns: 読み取った記録。金額が 1 つも無ければ、モデルを呼ばずに空配列。
    /// - Throws: どれか 1 件でも入力と突き合わなければ（金額が区間に無い・件数が合わない）、
    ///   `ExtractedEntry.ResolveError`。呼び出し側（`FallbackEntryParser`）がルールベースで読み直す。
    static func entries(
        from text: String,
        now: Date,
        calendar: Calendar,
        extract: (InputSegment) async throws -> ExtractedEntry
    ) async throws -> [ParsedEntry] {
        let input = EntryInput(text, now: now, calendar: calendar)
        var extracted: [ExtractedEntry] = []
        for segment in input.segments {
            // 取り消された（画面を閉じたなど）あとは、残りの件の生成を始めない。
            try Task.checkCancellation()
            extracted.append(try await extract(segment))
        }
        // 件数と、各件の金額がその件の区間に書かれているかを、まとめてコアで確かめる。
        return try ExtractedEntry.resolveAll(extracted, against: input)
    }
}
