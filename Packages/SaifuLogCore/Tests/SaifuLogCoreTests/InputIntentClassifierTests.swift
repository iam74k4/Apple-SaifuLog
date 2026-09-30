import Foundation
import Testing
@testable import SaifuLogCore

/// 記録か質問かの見分け（InputIntentClassifier）。いちばん大事なのは、質問の文を誤って記録にしないこと。
@Suite("記録か質問かの見分け")
struct InputIntentClassifierTests {
    static func classify(_ text: String) -> InputIntent {
        InputIntentClassifier.classify(text, now: Fixture.now, calendar: Fixture.calendar)
    }

    @Test("これまでどおり記録として読むもの", arguments: [
        "ランチ 850",
        "昨日 焼肉12000 4人で割り勘",
        "スーパー2480とドラッグ1200",
        "給料 25万",
        "返金 -500",
        "9/26 ランチ 850",
        "2025/9/26 ランチ 900",
        "スーパー 合計2480",
        "ランチ850 コーヒー400 合計1250",
        "合計 3000 ランチ",
        "ランチ 850 100円引き",
        "ランチ 1000円（税込1100円）",
        "コンビニで使った 500",
        "一番搾り 300",
        "残業代 5000",
        "いくら丼 1500",
        "イクラ 800",
        "３日間の旅行 30000",
        "１，２００円 ドラッグ",
        "今月 家賃 80000",
        "ボーナス 30万",
    ])
    func records(text: String) {
        #expect(Self.classify(text) == .record, "\(text)")
    }

    @Test("金額の無い文も、質問の語が無ければ記録として扱う（金額が見つからないと知らせる）", arguments: [
        "ランチ",
        "コーヒー",
        "昨日 ランチ",
        "カフェ",
        "",
    ])
    func recordsWithoutAmount(text: String) {
        #expect(Self.classify(text) == .record, "\(text)")
    }

    @Test("はっきり質問を表す語があれば、金額があっても質問（記録にしない）", arguments: [
        "今月カフェいくら?",
        "今月カフェいくら？",
        "先月の食費は?",
        "今月あと何日でいくら使える?",
        "今週いちばん使ったのは?",
        "カフェ何回行った",
        "今月の支出を教えて",
        "食費どれくらい",
        "ランチ850円って高い?",
        "ランチ 850?",
        "今月の収入は何円",
        "何に使ったっけ",
        "今月の食費いくらだっけ",
        "直近7日の支出はいくらですか",
    ])
    func strongQuestions(text: String) {
        #expect(Self.classify(text) == .question, "\(text)")
    }

    @Test("金額が無く、質問の語があれば質問", arguments: [
        "今月の合計",
        "先月の支出",
        "今月の予算の残り",
        "直近7日の支出",
        "過去30日間の合計",
        "ここ1週間の出費",
        "今年の収入",
        "今月一番使ったカテゴリ",
        "1日あたり使える額",
        "今月の収支",
        "カフェの件数",
    ])
    func questionsWithoutAmount(text: String) {
        #expect(Self.classify(text) == .question, "\(text)")
    }

    @Test("金額が無く、期間の語にカテゴリの名前が続くか、期間の語だけなら質問", arguments: [
        "先月の食費",
        "今日のカフェ",
        "今週の交通費",
        "先月",
        "今月は",
        "今年の光熱費",
        "年初からの食費",
        "年明けから",
        "年の初めからの食費",
    ])
    func periodQuestions(text: String) {
        #expect(Self.classify(text) == .question, "\(text)")
    }

    @Test("金額と質問の語が両方あって決められないものは、記録にしない", arguments: [
        "予算 5万",
        "食費の残り 5000",
        "今月の合計 3000円の予算",
        "使える額 20000",
        "収支 30000",
        "今月の件数 10",
        "内訳 5000",
        "合計は 3000",
    ])
    func unclear(text: String) {
        #expect(Self.classify(text) == .unclear, "\(text)")
    }

    /// 決められないもの・質問は、どちらも記録にならない（誤って保存しない）。
    @Test("質問の例はどれも記録にならない")
    func examplesAreNeverRecords() {
        for example in QuestionParser.examples {
            #expect(Self.classify(example) != .record, "\(example)")
        }
    }
}
