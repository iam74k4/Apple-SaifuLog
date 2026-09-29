import Foundation
import SaifuLogCore
import SwiftData

/// 保存する 1 件の記録。
///
/// 最初から iCloud 同期（SwiftData + CloudKit）の制約に合わせている。
/// 一意制約を使わない、すべてのプロパティに既定値を持たせる、関係を持たせるなら任意にする。
/// 後から合わせると、保存済みのデータの移行が要るため。
///
/// **項目はすべて CloudKit の暗号化フィールドにする**（`.allowsCloudEncryption`。docs/design.md §5-3）。iCloud 同期をオンにした
/// 利用者の記録は、端末の中で暗号化してから iCloud に置かれ、高度なデータ保護をオンにしていればエンドツーエンドで暗号化される
/// （ふつうの項目では、高度なデータ保護でもエンドツーエンドにならない）。記録した日時も入れるのは、たいていは使った日時と
/// ほぼ同じで、残すと「いつ使ったか」が分かってしまうため。暗号化フィールドは CloudKit のサーバーで検索や並べ替えに使えないが、
/// SwiftData の同期は変わった記録を取ってくるだけで、アプリの検索と並べ替えは端末の保存先で行うので困らない。
/// CloudKit は、スキーマにある項目を後から暗号化フィールドに変えられない（Production に出した後は戻せもしない）ので、項目を
/// 足すときも最初から付ける（付け忘れは ModelContainerFactoryTests が止める）。端末の保存先には効かない（端末の中はデータ保護で守る。§5-4）。
@Model
final class Entry {
    /// 金額（円）。支出も収入も正の数で持つ。浮動小数点の誤差を家計簿に持ち込まないよう整数にする。
    @Attribute(.allowsCloudEncryption) var amount: Int = 0
    @Attribute(.allowsCloudEncryption) var isIncome: Bool = false
    /// カテゴリの rawValue。列挙型のまま保存すると、検索条件（#Predicate）で扱いにくいため文字列で持つ。
    @Attribute(.allowsCloudEncryption) var categoryRawValue: String = EntryCategory.other.rawValue
    @Attribute(.allowsCloudEncryption) var memo: String = ""
    /// 使った日時（収入なら受け取った日時）。
    @Attribute(.allowsCloudEncryption) var spentAt: Date = Date.now
    /// 記録した日時。タイムラインはこの順に並べる（チャットと同じく、送った順）。
    @Attribute(.allowsCloudEncryption) var createdAt: Date = Date.now
    /// 入力元の rawValue（`EntrySource`）。
    @Attribute(.allowsCloudEncryption) var sourceRawValue: String = EntrySource.text.rawValue
    /// 元の入力文。直すときや、解析の見直しに使う。
    @Attribute(.allowsCloudEncryption) var originalText: String = ""

    init(
        amount: Int,
        isIncome: Bool,
        category: EntryCategory,
        memo: String,
        spentAt: Date,
        createdAt: Date = .now,
        source: EntrySource,
        originalText: String
    ) {
        self.amount = amount
        self.isIncome = isIncome
        self.categoryRawValue = category.rawValue
        self.memo = memo
        self.spentAt = spentAt
        self.createdAt = createdAt
        self.sourceRawValue = source.rawValue
        self.originalText = originalText
    }

    var category: EntryCategory {
        get { EntryCategory(rawValue: categoryRawValue) ?? .other }
        set { categoryRawValue = newValue.rawValue }
    }

    var source: EntrySource {
        get { EntrySource(rawValue: sourceRawValue) ?? .text }
        set { sourceRawValue = newValue.rawValue }
    }
}

extension Entry {
    /// 1 回の送信の解析結果から、保存する記録を書いた順に作る。
    ///
    /// 記録した日時と使った日時の振り方（複数件を書いた順に並べるためのずらし）は、swift test で
    /// 確かめられるようコアの `ParsedEntry.timestamps` に置いている。
    static func records(
        from parsed: [ParsedEntry], originalText: String, source: EntrySource, now: Date, calendar: Calendar
    ) -> [Entry] {
        zip(parsed, ParsedEntry.timestamps(for: parsed, now: now, calendar: calendar)).map { entry, timestamps in
            Entry(
                amount: entry.amount,
                isIncome: entry.isIncome,
                category: entry.category,
                memo: entry.memo,
                spentAt: timestamps.spentAt,
                createdAt: timestamps.createdAt,
                source: source,
                originalText: originalText
            )
        }
    }
}

extension Entry {
    /// レシートの読み取り結果（⑤）から、保存する記録を行の順に作る。
    ///
    /// 記録した日時は、ひとこと入力の複数件と同じく書いた順に並ぶよう 1 ミリ秒ずつずらす（`ParsedEntry.timestamps`）。
    /// 使った日時はどの記録もレシートの日時（`spentAt`）にする。元の文は OCR の全文ではなく、店名と合計の要約。
    static func records(fromReceipt submission: ReceiptResultModel.Submission, now: Date, calendar: Calendar) -> [Entry] {
        let parsed = submission.records.map { ParsedEntry(amount: $0.amount, category: $0.category, memo: $0.memo) }
        return zip(submission.records, ParsedEntry.timestamps(for: parsed, now: now, calendar: calendar)).map { record, timestamps in
            Entry(
                amount: record.amount,
                isIncome: false,
                category: record.category,
                memo: record.memo,
                spentAt: submission.spentAt,
                createdAt: timestamps.createdAt,
                source: .receipt,
                originalText: submission.originalText
            )
        }
    }
}

// MARK: - 読み込みの条件

extension Entry {
    /// `date` を含む月の記録だけを読む条件。今月の合計に使う。
    ///
    /// 全期間を読んで数えると、記録が増えるほど描画のたびに遅くなる（2 万件で 0.2 秒ほど）ため、
    /// 月の範囲で絞ってから読む。月は `ReportPeriod.thisMonth` で区切る（合計の `MonthlySummary`、
    /// まとめ・質問の「今月」と同じ区切りにするため）。
    static func monthDescriptor(containing date: Date, calendar: Calendar) -> FetchDescriptor<Entry> {
        guard let month = ReportPeriod.thisMonth.interval(now: date, calendar: calendar) else {
            return FetchDescriptor(predicate: #Predicate { _ in false })
        }
        return descriptor(spentIn: month)
    }

    /// 使った日時が `interval` に入る記録だけを読む条件（始まりは含み、終わりは含まない。`LedgerSummary` と同じ区切り）。
    /// 月のまとめが、その月と前の月の記録を読むのに使う。
    static func descriptor(spentIn interval: DateInterval) -> FetchDescriptor<Entry> {
        let start = interval.start
        let end = interval.end
        return FetchDescriptor(predicate: #Predicate { $0.spentAt >= start && $0.spentAt < end })
    }

    /// 使った日時のいちばん古い記録 1 件。月のまとめで、どの月までさかのぼれるかを決めるのに使う。
    static var earliestDescriptor: FetchDescriptor<Entry> {
        var descriptor = FetchDescriptor<Entry>(sortBy: [SortDescriptor(\.spentAt)])
        descriptor.fetchLimit = 1
        return descriptor
    }

    /// タイムラインに出す、記録した日時の新しいものから `limit` 件。
    ///
    /// 件数で区切るので新しい順に読む（画面では古い順に並べ直す）。
    static func timelineDescriptor(limit: Int) -> FetchDescriptor<Entry> {
        var descriptor = FetchDescriptor<Entry>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = limit
        return descriptor
    }
}

/// 集計（SaifuLogCore の LedgerSummary・MonthlySummary）と CSV の書き出し（LedgerCSVWriter）にそのまま渡せるようにする。
extension Entry: LedgerCSVRecord {}

/// どこから記録したか。rawValue は保存に使うので変えないこと。
enum EntrySource: String, Codable, CaseIterable, Sendable {
    /// ひとこと入力
    case text
    /// レシート・スクショの読み取り
    case receipt
    /// 声で記録
    case voice
}
