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
    /// 解析結果から記録を作る。
    convenience init(parsed: ParsedEntry, originalText: String, source: EntrySource, now: Date, calendar: Calendar) {
        self.init(
            amount: parsed.amount,
            isIncome: parsed.isIncome,
            category: parsed.category,
            memo: parsed.memo,
            spentAt: parsed.date(relativeTo: now, calendar: calendar),
            createdAt: now,
            source: source,
            originalText: originalText
        )
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
