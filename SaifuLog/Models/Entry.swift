import Foundation
import SaifuLogCore
import SwiftData

/// 保存する 1 件の記録。
///
/// 最初から iCloud 同期（SwiftData + CloudKit）の制約に合わせている。
/// 一意制約を使わない、すべてのプロパティに既定値を持たせる、関係を持たせるなら任意にする。
/// 後から合わせると、保存済みのデータの移行が要るため。
@Model
final class Entry {
    /// 金額（円）。支出も収入も正の数で持つ。浮動小数点の誤差を家計簿に持ち込まないよう整数にする。
    var amount: Int = 0
    var isIncome: Bool = false
    /// カテゴリの rawValue。列挙型のまま保存すると、検索条件（#Predicate）で扱いにくいため文字列で持つ。
    var categoryRawValue: String = EntryCategory.other.rawValue
    var memo: String = ""
    /// 使った日時（収入なら受け取った日時）。
    var spentAt: Date = Date.now
    /// 記録した日時。タイムラインはこの順に並べる（チャットと同じく、送った順）。
    var createdAt: Date = Date.now
    /// 入力元の rawValue（`EntrySource`）。
    var sourceRawValue: String = EntrySource.text.rawValue
    /// 元の入力文。直すときや、解析の見直しに使う。
    var originalText: String = ""

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

// MARK: - 読み込みの条件

extension Entry {
    /// `date` を含む月の記録だけを読む条件。今月の合計に使う。
    ///
    /// 全期間を読んで数えると、記録が増えるほど描画のたびに遅くなる（2 万件で 0.2 秒ほど）ため、
    /// 月の範囲で絞ってから読む。
    static func monthDescriptor(containing date: Date, calendar: Calendar) -> FetchDescriptor<Entry> {
        guard let month = calendar.dateInterval(of: .month, for: date) else {
            return FetchDescriptor(predicate: #Predicate { _ in false })
        }
        let start = month.start
        let end = month.end
        return FetchDescriptor(predicate: #Predicate { $0.spentAt >= start && $0.spentAt < end })
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

/// 月の集計（SaifuLogCore の MonthlySummary）にそのまま渡せるようにする。
extension Entry: LedgerRecord {}

/// どこから記録したか。rawValue は保存に使うので変えないこと。
enum EntrySource: String, Codable, CaseIterable, Sendable {
    /// ひとこと入力
    case text
    /// レシート・スクショの読み取り
    case receipt
    /// 声で記録
    case voice
}
