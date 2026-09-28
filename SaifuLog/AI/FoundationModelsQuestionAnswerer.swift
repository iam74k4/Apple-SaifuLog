#if canImport(FoundationModels)
import Foundation
import FoundationModels
import SaifuLogCore
import Synchronization

/// 端末内 AI（Foundation Models のツール呼び出し）で家計への質問に答える。
///
/// モデルには、質問を読んで `queryLedger` ツールの引数（期間・知りたいこと・カテゴリの選択肢だけ）を選ばせ、ツールの結果から
/// 一言の要約文を書かせるだけにする。数字はツールの中でコア（`LedgerQuestionAnswerer`）が計算する。ツールの引数に自由な数を
/// 受け取らないのは、端末内のモデルが数を作ったり書き換えたりすることがあるため（直近 N 日の N も文からコードが読む）。
///
/// - 答えられない書き方（「去年」「9/26」など）を含む質問は、モデルに渡さずに読めない質問にする（聞かれていない期間の数字を
///   答えないため）。
/// - モデルがツールを呼ばなかったら失敗として投げ、呼び出し側（`FallbackQuestionAnswerer`）がキーワード辞書で答え直す。
/// - モデルの一言にツールの結果に無い数字があれば、一言を捨てて定型文にする（`AnswerSentenceCheck`。照合はコアで確かめる）。
struct FoundationModelsQuestionAnswerer: QuestionAnswering {
    /// モデルに質問を渡し、ツールを使わせて一言を返させる。テストでモデルの代わりを渡す（ツールを直接呼んで一言を返す）。
    typealias Respond = @Sendable (_ question: String, _ tool: LedgerQuestionTool) async throws -> String

    var respond: Respond = Self.respondWithModel

    func answer(_ text: String, ledger: QuestionLedger, now: Date, calendar: Calendar) async throws -> QuestionReply {
        let reading = QuestionParser.read(text, now: now, calendar: calendar)
        guard !reading.hasUnsupportedPart else { return .unreadable }
        let recorder = LedgerToolRecorder()
        let tool = LedgerQuestionTool(reading: reading, ledger: ledger, now: now, calendar: calendar, recorder: recorder)
        let sentence = try await respond(text, tool)
        guard let result = recorder.latest else { throw QuestionAIError.toolNotCalled }
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        let remark: QuestionRemark = AnswerSentenceCheck.accepts(trimmed, facts: result.facts) ? .ai(trimmed) : .fixed
        return .answered(result.answer, remark: remark)
    }

    /// 本物のモデルで答えさせる。質問ごとに新しいセッションにする（前の質問の文脈を引きずらせないため）。
    static func respondWithModel(_ question: String, tool: LedgerQuestionTool) async throws -> String {
        let session = LanguageModelSession(tools: [tool], instructions: instructions)
        return try await session.respond(to: question).content
    }

    /// 指示文には、具体的な数字や単位の例を書かない（モデルが入力に無くても写して返すため。CLAUDE.md の決まり）。
    static let instructions = """
        あなたは家計簿アプリの中で、利用者の家計についての質問に答えるアシスタントです。
        質問を読んだら、必ず queryLedger ツールを呼んで、期間・知りたいこと・カテゴリを選んでください。
        答えは、ツールが返した内容だけを使って、日本語の短い一文で書いてください。
        ツールが返していない数字は書かないでください。計算・換算・四捨五入もしないでください。金額はツールが書いたとおりの表記で書いてください。
        """
}

enum QuestionAIError: Error {
    /// モデルがツールを呼ばずに答えた（数字の根拠が無いので使わない）。
    case toolNotCalled
    /// ツールの引数から質問を作れなかった。
    case unanswerable
}

/// 家計簿の記録を集計するツール。モデルが選んだ期間・知りたいこと・カテゴリから、コアが数字を計算して返す。
struct LedgerQuestionTool: Tool {
    let name = "queryLedger"
    let description = "利用者の家計簿の記録を集計して、質問の答えになる数字を返します。期間・知りたいこと・カテゴリを選んで呼んでください。数字はこのツールが計算します。"

    /// 質問の文からコードが読めたもの。モデルの選択より優先する（`QuestionReading.resolved(with:)`）。
    let reading: QuestionReading
    let ledger: QuestionLedger
    let now: Date
    let calendar: Calendar
    /// 計算した答えを、画面に出すために残す（モデルの一言とは別に、この答えの数字をそのまま出す）。
    let recorder: LedgerToolRecorder

    func call(arguments: LedgerQueryArguments) async throws -> String {
        guard let question = reading.resolved(with: arguments.choice),
              let answer = LedgerQuestionAnswerer.answer(question, ledger: ledger, now: now, calendar: calendar)
        else { throw QuestionAIError.unanswerable }
        let facts = LedgerAnswerFacts.text(for: answer, calendar: calendar)
        recorder.record(answer: answer, facts: facts)
        return facts
    }
}

/// ツールが計算した答えを残す。ツールはメインスレッドの外で呼ばれるので、錠で守る。
///
/// モデルが何度か呼んだときは、最後の答えを使う（一言もその答えと突き合わせる）。
final class LedgerToolRecorder: Sendable {
    struct Recorded: Sendable {
        let answer: LedgerAnswer
        /// モデルに渡したツールの結果の文。一言の数字の照合に使う。
        let facts: String
    }

    private let state = Mutex<Recorded?>(nil)

    func record(answer: LedgerAnswer, facts: String) {
        state.withLock { $0 = Recorded(answer: answer, facts: facts) }
    }

    var latest: Recorded? {
        state.withLock { $0 }
    }
}

/// モデルに選ばせるツールの引数。選択肢だけで、自由な数は受け取らない。
///
/// 説明（`@Guide`）には具体的な数字や単位の例を書かない（指示文と同じ理由）。
@Generable(description: "家計簿への質問を、集計の条件に直したもの")
struct LedgerQueryArguments {
    @Guide(description: "集計する期間。today は今日、yesterday は昨日、thisWeek は今週、lastWeek は先週、thisMonth は今月、lastMonth は先月、thisYear は今年、recentDays は直近の何日かを日数で区切った期間（日数はアプリが質問の文から読む）。期間が書かれていなければ thisMonth")
    var period: PeriodChoice

    @Guide(description: "知りたいこと。expenseTotal は支出の合計、incomeTotal は収入の合計、balance は収支、expenseByCategory は支出のカテゴリ別の内訳、categoryExpense はあるカテゴリの支出の合計、entryCount は記録の件数、remainingBudget は月の予算の残り、dailyAllowance は月末まで日割りで使える額、topCategory はいちばん多く使ったカテゴリ")
    var metric: MetricChoice

    @Guide(description: "聞かれたカテゴリ。unspecified は特定のカテゴリを聞かれていないとき。food は食費、daily は日用品、transport は交通、cafe はカフェ、entertainment は娯楽、utilities は光熱・通信、medical は医療、other はその他")
    var category: CategoryChoice

    @Generable
    enum PeriodChoice {
        case today, yesterday, thisWeek, lastWeek, thisMonth, lastMonth, thisYear, recentDays
    }

    @Generable
    enum MetricChoice {
        case expenseTotal, incomeTotal, balance, expenseByCategory, categoryExpense, entryCount, remainingBudget, dailyAllowance, topCategory
    }

    @Generable
    enum CategoryChoice {
        case unspecified, food, daily, transport, cafe, entertainment, utilities, medical, other
    }

    /// コアの形（`QuestionChoice`）に写す。
    var choice: QuestionChoice {
        let period: QuestionChoice.Period = switch period {
        case .today: .today
        case .yesterday: .yesterday
        case .thisWeek: .thisWeek
        case .lastWeek: .lastWeek
        case .thisMonth: .thisMonth
        case .lastMonth: .lastMonth
        case .thisYear: .thisYear
        case .recentDays: .recentDays
        }
        let metric: QuestionMetric = switch metric {
        case .expenseTotal: .expenseTotal
        case .incomeTotal: .incomeTotal
        case .balance: .balance
        case .expenseByCategory: .expenseByCategory
        case .categoryExpense: .categoryExpense
        case .entryCount: .entryCount
        case .remainingBudget: .remainingBudget
        case .dailyAllowance: .dailyAllowance
        case .topCategory: .topCategory
        }
        let category: EntryCategory? = switch category {
        case .unspecified: nil
        case .food: .food
        case .daily: .daily
        case .transport: .transport
        case .cafe: .cafe
        case .entertainment: .entertainment
        case .utilities: .utilities
        case .medical: .medical
        case .other: .other
        }
        return QuestionChoice(period: period, metric: metric, category: category)
    }
}
#endif
