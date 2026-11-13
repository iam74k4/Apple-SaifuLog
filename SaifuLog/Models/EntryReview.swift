import Foundation
import SaifuLogCore
import SwiftData

/// 確認待ちの一覧の 1 行。画面は記録の控えを使う（同期で消された SwiftData オブジェクトを画面から読まないため）。
struct EntryReviewItem: Identifiable {
    let id: PersistentIdentifier
    let memo: String
    let amount: Int
    let category: EntryCategory
    let spentAt: Date
}
