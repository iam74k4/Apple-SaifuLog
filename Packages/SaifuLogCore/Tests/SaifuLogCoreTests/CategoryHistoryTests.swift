import Foundation
import Testing
@testable import SaifuLogCore

@Suite("過去の記録のいつものカテゴリ")
struct CategoryHistoryTests {
    private static func records(_ pairs: [(String, EntryCategory)]) -> [CategoryHistory.Record] {
        pairs.map { CategoryHistory.Record(item: $0.0, category: $0.1) }
    }

    @Test("同じ品目の記録が 2 件以上あり、半分を超えるカテゴリがあれば当てる")
    func usesClearMajority() {
        let history = CategoryHistory(records: Self.records([
            ("スタバ", .cafe), ("スタバ", .cafe), ("スタバ", .food),
            ("ジム", .entertainment),
        ]))

        #expect(history.category(forItem: "スタバ") == .cafe)
        // 1 件だけでは決めない。
        #expect(history.category(forItem: "ジム") == nil)
    }

    @Test("割れているときは決めない")
    func ignoresTies() {
        let history = CategoryHistory(records: Self.records([
            ("ドンキ", .daily), ("ドンキ", .daily), ("ドンキ", .food), ("ドンキ", .food),
        ]))

        #expect(history.category(forItem: "ドンキ") == nil)
    }

    @Test("表記ゆれをそろえて同じ品目として数え、品目に含まれるだけでは当てない")
    func foldsVariantsButNeedsSameItem() {
        let history = CategoryHistory(records: Self.records([("らんち", .food), ("ランチ", .food)]))

        #expect(history.category(forItem: "ランチ") == .food)
        #expect(history.category(forItem: "ランチ 会社") == nil)
    }

    @Test("その他は数えない")
    func skipsOther() {
        let history = CategoryHistory(records: Self.records([("なぞ", .other), ("なぞ", .other), ("なぞ", .daily)]))

        #expect(history.category(forItem: "なぞ") == nil)
        #expect(history.rules.isEmpty)
    }
}
