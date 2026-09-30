import Foundation
import SaifuLogCore
import SwiftData
import Testing
@testable import SaifuLog

/// ホームのよく使うひとこと（`HomeModel.refreshQuickPhrases`・`pickQuickPhrase`）。メモリの上の保存先で確かめる。
@MainActor
struct HomeModelQuickPhraseTests {
    typealias Fixture = HomeModelTests.Fixture

    /// よく記録する品目を、いちばん新しい額で候補にする。レシートから記録したものと、期間より前の記録は候補にしない。
    @Test func buildsPhrasesFromRecentRecords() async throws {
        let fixture = try Fixture()
        // いちばん新しい記録の額を使うので、送るたびに時計を進める（同じ日時の記録は、どちらが新しいか決まらない）。
        fixture.now = TestSupport.date(2026, 9, 28, hour: 9)
        await fixture.send("ランチ 850")
        fixture.now = TestSupport.date(2026, 9, 28, hour: 12)
        await fixture.send("ランチ 1100")
        fixture.now = TestSupport.date(2026, 9, 28, hour: 13)
        await fixture.send("バス 230")
        let old = TestSupport.entry(amount: 999, memo: "古い品目", createdAt: TestSupport.date(2026, 5, 1))
        let olderTwice = TestSupport.entry(amount: 999, memo: "古い品目", createdAt: TestSupport.date(2026, 5, 2))
        let receipt = Entry(
            amount: 198, isIncome: false, category: .food, memo: "牛乳", spentAt: TestSupport.now, createdAt: TestSupport.now,
            source: .receipt, originalText: "レシート: スーパー 合計 ¥198"
        )
        try fixture.insert(old, olderTwice, receipt)

        fixture.model.refreshQuickPhrases()

        let phrases = fixture.model.quickPhrases
        #expect(phrases.map(\.item) == ["ランチ", "バス"])
        #expect(phrases.first?.amount == 1_100)
        #expect(QuickPhrases.suggestions(phrases, draft: "").map(\.item) == ["ランチ"])
    }

    /// 選ぶと入力欄に「品目 金額」を入れる（送るのは利用者）。声で入れた文の途中でも、入力元はひとこと入力に戻す。
    @Test func pickingPhraseFillsDraft() async throws {
        let fixture = try Fixture()
        await fixture.send("ランチ 850")
        await fixture.send("ランチ 850")
        fixture.model.refreshQuickPhrases()
        let lunch = try #require(fixture.model.quickPhrases.first)

        fixture.model.pickQuickPhrase(lunch)

        #expect(fixture.model.draft == "ランチ 850")
        #expect(fixture.model.draftSource == .text)
        await fixture.model.send(calendar: TestSupport.calendar)?.value
        #expect(try fixture.entries().map(\.amount) == [850, 850, 850])
    }
}
