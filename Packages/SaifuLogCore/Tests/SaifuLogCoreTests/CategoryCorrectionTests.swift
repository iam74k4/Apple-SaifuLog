import Foundation
import Testing
@testable import SaifuLogCore

@Suite("チャットでカテゴリを直す文")
struct CategoryCorrectionTests {
    static let clothes = CustomCategoryInfo(id: "clothes", name: "衣服", symbolName: "tshirt", colorIndex: 0)
    static let catalog = CategoryCatalog(customs: [clothes])

    @Test("前の記録を指す語・直す語・語尾とカテゴリの名前だけの文は、直す文", arguments: [
        ("それ日用品", EntryCategory.daily),
        ("さっきのは日用品にして", .daily),
        ("今のはカフェだよ", .cafe),
        ("カテゴリは交通に変えて", .transport),
        ("日用品", .daily),
        ("日用品です。", .daily),
        ("食費じゃなくて日用品", .daily),
        ("光熱費", .utilities),
        ("医療費でお願いします", .medical),
        ("その他にして", .other),
        ("それ衣服", EntryCategory.custom("clothes")),
        ("さっきの 衣服で", EntryCategory.custom("clothes")),
        ("先ほどのは日用品で", .daily),
    ])
    func readsCorrections(text: String, category: EntryCategory) {
        #expect(CategoryCorrection.category(in: text, catalog: Self.catalog) == category)
    }

    @Test("ほかの語が残る文・金額のある文・質問の文・名前の無い文は、直す文にしない", arguments: [
        "ランチは食費",
        "今月の食費",
        "食費の予算",
        "日用品 500",
        "さっきのを900に直して",
        "食費?",
        "食費いくら",
        "コーヒー",
        "ランチ",
        "食費と日用品",
        "",
    ])
    func ignoresOtherTexts(text: String) {
        #expect(CategoryCorrection.category(in: text, catalog: Self.catalog) == nil)
    }

    /// 名前の確かめの前の版では、組み込みの言い換えと同じ名前のカテゴリを作れた。利用者がその名前で作ったものを優先する。
    @Test("作ったカテゴリと組み込みの言い換えが同じ名前なら、作ったカテゴリ")
    func customWinsTieWithAlias() {
        let hobby = CustomCategoryInfo(id: "hobby", name: "趣味", symbolName: "gamecontroller", colorIndex: 1)
        let catalog = CategoryCatalog(customs: [hobby])

        #expect(CategoryCorrection.category(in: "それ趣味", catalog: catalog) == hobby.category)
        #expect(CategoryCorrection.category(in: "それ娯楽", catalog: catalog) == .entertainment)
    }

    @Test("作ったカテゴリが一覧に無ければ、その名前では直さない")
    func needsCustomInCatalog() {
        #expect(CategoryCorrection.category(in: "それ衣服") == nil)
    }
}
