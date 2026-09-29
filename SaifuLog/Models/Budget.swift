import Foundation
import SaifuLogCore
import SwiftData

/// 月の予算の 1 件（全体か、カテゴリ別）。毎月同じ額を使う（月ごとには持たない）。
///
/// 記録（`Entry`）と同じく、最初から iCloud 同期（SwiftData + CloudKit）の制約に合わせている。
/// すべてのプロパティに既定値を持たせ、一意制約も関係も持たせない。
///
/// 予算をなくすときも行は消さず、金額 0（設定なし）を書く。CloudKit では削除が他の端末に伝わるのが遅れたり、
/// 別の端末で同時に書いた値と食い違ったりするため、「最後に書いた値」が勝つ形にしておく。一意制約が無いので、
/// 同じ対象の行が複数できることもある。どの行を採るかは `BudgetPlan.resolve`（updatedAt の新しいもの）が決める。
///
/// 記録と同じく、**項目はすべて CloudKit の暗号化フィールドにする**（`.allowsCloudEncryption`。理由は `Entry`）。
/// 書き込んだ日時も入れる（予算を変えた時機も家計の情報で、暗号化してもサーバーで使うことは無いため）。
@Model
final class Budget {
    /// 対象（`BudgetScope.rawValue`）。全体は "total"、カテゴリ別はカテゴリの rawValue。
    /// 列挙型のまま保存すると、検索条件（#Predicate）で扱いにくいため文字列で持つ（Entry のカテゴリと同じ）。
    @Attribute(.allowsCloudEncryption) var scopeRawValue: String = BudgetScope.totalRawValue
    /// 月の予算（円）。0 は設定なし。
    @Attribute(.allowsCloudEncryption) var amount: Int = 0
    /// 最後に書いた日時。同じ対象の行が複数あるときは、これが新しいものを採る。
    @Attribute(.allowsCloudEncryption) var updatedAt: Date = Date.now

    init(scope: BudgetScope, amount: Int, updatedAt: Date) {
        self.scopeRawValue = scope.rawValue
        self.amount = amount
        self.updatedAt = updatedAt
    }

    /// 対象。知らない値（新しい版で足したカテゴリが iCloud で届いたときなど）は nil。
    var scope: BudgetScope? {
        BudgetScope(rawValue: scopeRawValue)
    }
}

/// 予算の決め方（SaifuLogCore の BudgetPlan.resolve）にそのまま渡せるようにする。
extension Budget: BudgetRecord {}
