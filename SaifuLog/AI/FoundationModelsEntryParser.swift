#if canImport(FoundationModels)
import Foundation
import FoundationModels
import SaifuLogCore

/// 端末内 AI（Foundation Models のガイド付き生成）で一行を読み解く。
///
/// 件の分け方はコードで決め、モデルには区間ごとに 1 件だけ生成させる（`SegmentedExtraction`）。
/// 記録の配列は返させない。配列だと 1 件の入力にも余分な要素や同じ記録の繰り返しが返るため。
///
/// モデルには値を「抜き出す」ことだけをさせる。金額は書かれたとおりの表記、日付も表記のまま返させ、
/// 換算・割り勘の割り算・日付の計算は SaifuLogCore で行う。端末内のモデルは小さく、計算を任せると数字を間違えるため。
struct FoundationModelsEntryParser: EntryParsing {
    var calendar: Calendar = .current

    /// この端末でいま AI を使えるか。
    static var isAvailable: Bool {
        status.isAvailable
    }

    /// この端末でいま AI を使えるか。使えないときはその理由（ようこその案内に使う）。
    ///
    /// 非対応機種・Apple Intelligence がオフ・モデルのダウンロード中は使えない。
    /// 入力は日本語なので、日本語に対応しているかも見る。
    /// `SystemLanguageModel` は Observable なので、画面の描画の中で読めば、使えるようになったときに描き直される。
    static var status: OnDeviceAIStatus {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return model.supportsLocale(Locale(identifier: "ja_JP")) ? .available : .unavailable
        case .unavailable(.deviceNotEligible):
            return .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled):
            return .appleIntelligenceNotEnabled
        case .unavailable(.modelNotReady):
            return .modelNotReady
        // 理由の列挙は @frozen ではなく、OS が増やすことがある。知らない理由は、使えないとだけ伝える。
        case .unavailable:
            return .unavailable
        }
    }

    func parse(_ text: String) async throws -> [ParsedEntry] {
        // 金額・日付・割り勘の人数・収入・品目は、入力のその件の区間と突き合わせてから使う
        // （SaifuLogCore の ExtractedEntry）。合わない件が 1 つでもあれば throw し、呼び出し側
        // （FallbackEntryParser）がルールベースで読み直す。突き合わせをコアに置くのは、swift test で確かめられるようにするため。
        try await SegmentedExtraction.entries(from: text, now: .now, calendar: calendar) { segment in
            try await Self.extract(segment.text)
        }
    }

    /// 区間の文字列 1 件を、1 件の記録として読ませる。
    private static func extract(_ segmentText: String) async throws -> ExtractedEntry {
        // 区間ごとに新しいセッションにする。前の件や前の入力の文脈を引きずらず（前の件を繰り返さず）、
        // 文脈の長さも超えないようにするため。
        let session = LanguageModelSession(instructions: instructions)
        let generated = try await session.respond(to: segmentText, generating: GeneratedEntry.self).content
        return ExtractedEntry(
            item: generated.item,
            amountText: generated.amountText,
            categoryName: generated.category,
            isIncome: generated.isIncome,
            // 割り勘の人数はモデルに尋ねない。保存する人数は、入力のその件にかかる割り勘の語と「N人」から
            // コアが決め、ここに入れた値は使わない（ExtractedEntry.resolved(against:)）。
            splitCount: 1,
            dateText: generated.dateText
        )
    }

    private static let instructions = """
        あなたは家計簿アプリの入力を読み取るアシスタントです。
        利用者が書いた 1 件分の支出または収入の記録から、値を抜き出してください。
        金額と日付は、入力に書かれている表記をそのまま抜き出してください。計算や換算はしないでください。
        割り勘のときも、金額は割る前の、書かれたとおりの額を抜き出してください。
        """
}

/// モデルに返させる形（1 件分）。`@Generable` にすると、モデルはこの形の値だけを出力する。
///
/// 説明（指示文と `@Guide`）には具体的な数字や単位の例を書かない。端末内のモデルは、説明に書いた数字や
/// 単位を、入力に無くても写して返すことがあるため（「ドラッグ1200」に「1200万」を返すなど）。
@Generable(description: "家計簿の 1 件の記録")
struct GeneratedEntry {
    @Guide(description: "何に使ったか、何の収入か（品目や店名）。入力に書かれた言葉を短く抜き出す。金額・日付・人数は含めない。書かれていなければ空文字")
    var item: String

    @Guide(description: "入力に書かれている金額の部分を、書かれた文字のまま抜き出す。書かれていない単位や桁は足さない。計算や換算はしない")
    var amountText: String

    @Guide(description: "支出のカテゴリ。収入のときは その他", .anyOf(EntryCategory.allCases.map(\.displayName)))
    var category: String

    @Guide(description: "給料・賞与などお金を受け取った記録なら true、お金を払った記録なら false")
    var isIncome: Bool

    @Guide(description: "日付の表記（今日、昨日、一昨日、月日など）をそのまま抜き出す。書かれていなければ空文字")
    var dateText: String
}
#endif
