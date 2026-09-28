#if canImport(FoundationModels)
import Foundation
import FoundationModels
import SaifuLogCore

/// 端末内 AI（Foundation Models のガイド付き生成）で一行を読み解く。
///
/// モデルには値を「抜き出す」ことだけをさせる。金額は書かれたとおりの表記、日付も表記のまま、
/// 割り勘は人数だけを返させ、換算・割り算・日付の計算は SaifuLogCore で行う。
/// 端末内のモデルは小さく、計算を任せると数字を間違えるため。
struct FoundationModelsEntryParser: EntryParsing {
    var calendar: Calendar = .current

    /// この端末でいま AI を使えるか。
    ///
    /// 非対応機種・Apple Intelligence がオフ・モデルのダウンロード中は使えない。
    /// 入力は日本語なので、日本語に対応しているかも見る。
    static var isAvailable: Bool {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return false }
        return model.supportsLocale(Locale(identifier: "ja_JP"))
    }

    func parse(_ text: String) async throws -> [ParsedEntry] {
        // 記録ごとに新しいセッションにする。前の入力の文脈を引きずらず、文脈の長さも超えないようにするため。
        let session = LanguageModelSession(instructions: Self.instructions)
        let response = try await session.respond(to: text, generating: GeneratedEntries.self)
        let now = Date.now
        // 金額・日付・割り勘の人数は、入力と突き合わせてから使う（SaifuLogCore の ExtractedEntry）。
        // 入力に書かれていない金額が来たら throw し、呼び出し側（FallbackEntryParser）が
        // ルールベースで読み直す。突き合わせをコアに置くのは、swift test で確かめられるようにするため。
        return try response.content.entries.map { generated in
            try ExtractedEntry(
                item: generated.item,
                amountText: generated.amountText,
                categoryName: generated.category,
                isIncome: generated.isIncome,
                splitCount: generated.splitCount,
                dateText: generated.dateText
            )
            .resolved(against: text, now: now, calendar: calendar)
        }
    }

    private static let instructions = """
        あなたは家計簿アプリの入力を読み取るアシスタントです。
        利用者が書いた一行から、支出または収入の記録を取り出してください。
        複数の品目に別々の金額が書かれていれば、それぞれを別の記録にします。
        金額と日付は、入力に書かれている表記をそのまま抜き出してください。計算や換算はしないでください。
        割り勘のときは、金額は割る前の総額のまま抜き出し、人数だけを答えてください。
        """
}

/// モデルに返させる形。`@Generable` にすると、モデルはこの形の値だけを出力する。
@Generable(description: "一行の入力に含まれる家計簿の記録の一覧")
struct GeneratedEntries {
    @Guide(description: "入力に書かれた記録。品目ごとに金額が書かれていれば、その数だけ分ける", .count(1...10))
    var entries: [GeneratedEntry]
}

@Generable(description: "家計簿の 1 件の記録")
struct GeneratedEntry {
    @Guide(description: "何に使ったか、何の収入か（品目や店名）。短く。金額・日付・人数は含めない")
    var item: String

    @Guide(description: "入力に書かれている金額の表記をそのまま抜き出す。例: 850、12000、25万、1万2千。計算や換算はしない")
    var amountText: String

    @Guide(description: "支出のカテゴリ。収入のときは その他", .anyOf(EntryCategory.allCases.map(\.displayName)))
    var category: String

    @Guide(description: "給料・賞与などの収入なら true、支出なら false")
    var isIncome: Bool

    // 省略できない数なので、割り勘でない入力にもモデルは何かの数を返す。入力に割り勘の語と
    // 「N人」が無ければ、ここで何を返されても割らない（ExtractedEntry.resolved）。
    @Guide(description: "割り勘の人数（自分を含む）。割り勘でなければ 1", .range(1...100))
    var splitCount: Int

    @Guide(description: "日付の表記をそのまま抜き出す。例: 今日、昨日、一昨日、3日前、9/26。書かれていなければ空文字")
    var dateText: String
}
#endif
