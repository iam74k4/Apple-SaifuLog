import Foundation
import SaifuLogCore
import SwiftData
import Testing
@testable import SaifuLog

/// 回答カードの前の期間との比べ・推移・続けて聞く質問（`QuestionTexts`・`HomeModel.askFollowUp`）。
@MainActor
struct QuestionInsightsTests {
    typealias Fixture = HomeModelTests.Fixture

    private static func comparison(_ baseline: LedgerComparison.Baseline, previous: Int, count: Int, difference: Int) -> LedgerComparison {
        LedgerComparison(
            baseline: baseline, interval: DateInterval(start: TestSupport.date(2026, 8, 1), end: TestSupport.date(2026, 8, 28)),
            previous: previous, previousRecordCount: count, difference: difference
        )
    }

    // MARK: - 比べの一文

    @Test func comparisonTexts() {
        #expect(QuestionTexts.comparison(
            Self.comparison(.lastMonthToDate, previous: 5_400, count: 1, difference: 1_800), value: .amount(7_200)
        ) == "先月の同じ日までより ¥1,800 多い")
        #expect(QuestionTexts.comparison(
            Self.comparison(.monthBeforeLast, previous: 9_000, count: 3, difference: -1_500), value: .amount(7_500)
        ) == "先々月より ¥1,500 少ない")
        #expect(QuestionTexts.comparison(
            Self.comparison(.lastWeekToDate, previous: 4, count: 4, difference: 2), value: .count(6)
        ) == "先週の同じ曜日までより 2 件多い")
        #expect(QuestionTexts.comparison(
            Self.comparison(.previousDays(7), previous: 1_000, count: 2, difference: 0), value: .amount(1_000)
        ) == "その前の 7 日と同じ")
        // 比べた期間に記録が無ければ、差を出さない。
        #expect(QuestionTexts.comparison(
            Self.comparison(.yesterdaySameTime, previous: 0, count: 0, difference: 850), value: .amount(850)
        ) == "昨日の同じ時刻までは記録がありません")
    }

    // MARK: - ホーム

    /// 今月のカフェを聞くと、先月の同じ日までと比べた答えと推移と続けて聞く質問が付き、読み上げにも比べを入れる。
    @Test func answerCarriesInsights() async throws {
        let fixture = try Fixture()
        try fixture.insert(
            TestSupport.entry(amount: 7_200, category: .cafe, memo: "カフェ", spentAt: TestSupport.date(2026, 9, 10)),
            TestSupport.entry(amount: 5_400, category: .cafe, memo: "カフェ", spentAt: TestSupport.date(2026, 8, 10))
        )

        await fixture.send("今月カフェいくら?")

        guard case .answered(let answer, _, _) = fixture.lastQuestionState else {
            Issue.record("答えのカードが出なかった")
            return
        }
        #expect(answer.comparison?.difference == 1_800)
        #expect(answer.trend?.points.suffix(2).map(\.value) == [5_400, 7_200])
        #expect(answer.followUps.map(\.text) == ["先月のカフェはいくら?", "今月の内訳は?"])
        #expect(fixture.announcements.last?.contains("先月の同じ日までより ¥1,800 多い") == true)
    }

    /// 続けて聞く質問は、入力欄の文に触れずに送り、ふつうの質問と同じく答える（自分の吹き出しに送った文を出す）。
    @Test func askFollowUpSendsQuestion() async throws {
        let fixture = try Fixture()
        try fixture.insert(TestSupport.entry(amount: 5_400, category: .cafe, memo: "カフェ", spentAt: TestSupport.date(2026, 8, 10)))
        await fixture.send("今月カフェいくら?")
        guard case .answered(let answer, _, _) = fixture.lastQuestionState else {
            Issue.record("答えのカードが出なかった")
            return
        }
        let followUp = try #require(answer.followUps.first)
        fixture.model.draft = "打ちかけ"

        await fixture.model.askFollowUp(followUp, calendar: TestSupport.calendar)?.value

        #expect(fixture.model.draft == "打ちかけ")
        #expect(fixture.model.questions.last?.text == "先月のカフェはいくら?")
        guard case .answered(let next, _, _) = fixture.lastQuestionState else {
            Issue.record("続けて聞いた質問に答えなかった")
            return
        }
        #expect(next.question == LedgerQuestion(period: .lastMonth, metric: .categoryExpense, category: .cafe))
        #expect(next.value == .amount(5_400))
    }

    /// 読み取りの間は、続けて聞く質問を受け付けない。
    @Test func askFollowUpWaitsForParsing() async throws {
        let fixture = try Fixture()
        await fixture.send("今月の内訳は?")
        guard case .answered(let answer, _, _) = fixture.lastQuestionState, let followUp = answer.followUps.first else {
            Issue.record("続けて聞く質問が無かった")
            return
        }
        fixture.parser = StubParser { _ in
            try await Task.sleep(for: .seconds(60))
            return []
        }
        fixture.model.draft = "ランチ 850"
        let recording = fixture.model.send(calendar: TestSupport.calendar)

        #expect(fixture.model.askFollowUp(followUp, calendar: TestSupport.calendar) == nil)
        recording?.cancel()
    }
}
