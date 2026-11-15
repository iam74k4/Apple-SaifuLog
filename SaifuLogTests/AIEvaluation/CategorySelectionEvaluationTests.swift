#if canImport(FoundationModels)
import Foundation
import SaifuLogCore
import Testing
@testable import SaifuLog

extension AIEvaluationTests {
    /// 品目のカテゴリの聞き直し（`FoundationModelsCategoryClassifier`。アプリでは `CategoryRefiner` が、手元の手がかりで決まらなかった
    /// 品目と、作ったカテゴリがあるときの品目を聞く）。辞書に無い品目（アプリで実際に聞き直す品目）を多めに入れる。
    @Suite("カテゴリの聞き直し")
    struct CategorySelection {
        // 作ったカテゴリは、組み込みのカテゴリと重ならないものにする（衣服は組み込みの「衣服・美容」と重なり、どちらを選んでも
        // 正しいため）。
        static let fandom = CustomCategoryInfo(id: "ai-evaluation-fandom", name: "推し活", symbolName: "sparkles", colorIndex: 2)

        /// 品目・合っているとみなすカテゴリの名前（どちらにも読める品目は 2 つ）・作ったカテゴリ（推し活）があるか。
        static let cases: [(item: String, accepted: Set<String>, hasCustom: Bool)] = [
            ("Netflix", ["娯楽"], false),
            ("ガソリン", ["交通"], false),
            ("歯医者", ["医療"], false),
            ("ジンギスカン", ["食費"], false),
            ("柔軟剤", ["日用品"], false),
            ("フェリー", ["交通"], false),
            ("動物園", ["娯楽"], false),
            ("スマホ代", ["光熱・通信"], false),
            ("タピオカ", ["カフェ", "食費"], false),
            ("PayPay", ["その他"], false),
            ("ワンピース", ["衣服・美容"], false),
            ("家賃", ["住居"], false),
            ("アクリルスタンド", ["推し活"], true),
            ("推しのライブのグッズ", ["推し活"], true),
            ("ジンギスカン", ["食費"], true),
        ]

        @Test("品目のカテゴリを選択肢から選び、上限の時間に収まる。選択肢の外の名前は返さない")
        func choosesCategories() async throws {
            try AIEvaluation.requireModel()
            await AIEvaluation.warmUp()
            var card = AIScorecard("カテゴリの聞き直し（上限 \(AIEvaluation.seconds(AITimeouts.categoryRefine))）")
            for (item, accepted, hasCustom) in Self.cases {
                let catalog = hasCustom ? CategoryCatalog(customs: [Self.fandom]) : .builtIn
                let choices = CategoryRefinement.choices(in: catalog)
                let timed = await AIEvaluation.measure {
                    try await FoundationModelsCategoryClassifier().categoryName(for: item, choices: choices)
                }
                if let name = timed.value {
                    // 揺れてはいけない: 選択肢（組み込みの表示名と作ったカテゴリの名前）の外の名前は返さない。
                    #expect(choices.contains(name), "「\(item)」に選択肢の外の名前: \(name)（選択肢: \(choices)）")
                }
                let label = "「\(item)」\(hasCustom ? "（推し活あり）" : "")"
                let matched = timed.value.map { accepted.contains($0) } ?? false
                card.record(label, passed: matched && timed.isWithin(AITimeouts.categoryRefine), timed.describe { $0 })
            }
            print(card.report)
            #expect(card.rate >= AIEvaluation.passRate, "\(card.report)")
        }
    }
}
#endif
