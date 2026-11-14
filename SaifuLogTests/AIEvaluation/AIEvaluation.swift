#if canImport(FoundationModels)
import Foundation
import SaifuLogCore
import Testing
@testable import SaifuLog

extension Tag {
    /// 本物の端末内 AI（Foundation Models）の答え方を確かめるテスト（`make test-ai`）。
    @Tag static var aiEvaluation: Self
}

/// 本物の端末内 AI（Foundation Models）の答え方を確かめるテスト。`make test-ai`（`scripts/test-ai.sh`）で動かす。
///
/// ほかのアプリのテストは AI を偽物に替え、AI の答えを受けたアプリの振る舞いを確かめる。ここでは本物のモデルに日本語の文を渡し、
/// 選ぶもの・読み取るものが合っているか、上限の時間（`AITimeouts`）に収まるか、一言が数字の照合に通るかを確かめる。指示文・
/// `@Guide`・モデルの版が変わったときに答え方が崩れていないかを、実機に入れる前に気づけるようにするため。
///
/// - Apple Intelligence が使えない端末（CI のランナー・Apple Intelligence がオフの Mac のシミュレータ）では飛ばす。`make test-ai` は
///   REQUIRE_AI_EVALUATION=1 を渡し、そのときは飛ばさずに、使えない理由をつけて失敗する（`AIEvaluation.requireModel()`）。飛ばした
///   だけでは成功のままで、何も確かめていないのに通ったように見えるため。
/// - モデルの答えは版や端末で揺れるので、答えの合い方は表ごとの割合（`AIEvaluation.passRate`・`remarkPassRate`）で見る（1 件の
///   間違いでは落とさない）。上限の時間に収まったかも、その件が合ったかに含める（1 回だけ遅いことはあるため）。
/// - 揺れてはいけないこと（アプリの安全の決まり）は、1 件でも外れたら落とす: 読み取りが入力に無い金額を作らない・件の数が区間の
///   数と同じ、カテゴリが選択肢の外にならない、記録や質問の文をチャットの操作として行わない、質問の答えの数字がコードの計算と同じ。
/// - モデルはひとつずつ順に呼ぶ（`.serialized`。下の表のテストもすべて、この型の中に置く）。同時に呼ぶと待ち合わせで遅くなり、
///   時間を測れないため。
/// - `make test-app`（と CI）はこのテストを外して動かす（`-skip-testing`）。Apple Intelligence を使える Mac で `make ci` を通すと、
///   モデルの揺れで結果が変わるため。
@Suite(
    "端末内 AI の答え方（本物のモデル）",
    .serialized,
    .tags(.aiEvaluation),
    .timeLimit(.minutes(10)),
    .enabled("Apple Intelligence が使えない端末（CI のランナーなど）では飛ばす（REQUIRE_AI_EVALUATION=1 なら失敗にする）") {
        AIEvaluation.shouldRun
    }
)
struct AIEvaluationTests {}

/// 本物の端末内 AI の答え方のテストの決め事と道具。
enum AIEvaluation {
    /// 選ぶ・読み取る答え（読み取り・カテゴリ・チャットの操作の種類・質問）が合った件の割合の下限。
    static let passRate = 0.8
    /// 一言（記録の返事・月のまとめ・質問の答え）が照合に通った割合の下限。自由に書く文なので、選ぶ答えより低くする（通らなかった
    /// 一言は画面に出さずに定型文にするので、低すぎなければ使える）。
    static let remarkPassRate = 0.6
    /// 同じ数字の文から一言を書かせる回数（毎回違う文になるので、何度か書かせて割合を見る）。
    static let remarkRuns = 5
    /// 1 回の呼び出しを待つ上限（止まったモデルを待ち続けないための見張り）。アプリの上限（`AITimeouts`）より長くし、遅くても返った
    /// 答えの中身と時間を見られるようにする。アプリの上限で打ち切ると、打ち切った生成が裏で動き続け、次の件の時間まで延びるため。
    static let hangLimit: Duration = .seconds(30)

    /// 飛ばさずに動かすことを求められているか（`make test-ai` が REQUIRE_AI_EVALUATION=1 を渡す。xcodebuild は環境変数
    /// TEST_RUNNER_REQUIRE_AI_EVALUATION の TEST_RUNNER_ を外してテストに渡す）。
    static var isRequired: Bool {
        ProcessInfo.processInfo.environment["REQUIRE_AI_EVALUATION"] == "1"
    }

    /// テストを動かすか。求められていれば、AI が使えなくても動かして失敗させる（`requireModel()`）。
    static var shouldRun: Bool {
        isRequired || FoundationModelsEntryParser.isAvailable
    }

    /// AI が使えなければ、使えない理由をつけて失敗する（`make test-ai` で、飛ばさずに知らせるため）。
    static func requireModel() throws {
        let status = FoundationModelsEntryParser.status
        try #require(
            status.isAvailable,
            "端末内 AI が使えません（\(String(describing: status))）。Apple シリコンの Mac（macOS 26 以降）で Apple Intelligence をオンにし、モデルを入れ終えてから動かしてください。"
        )
    }

    /// 測る前に、モデルを読み込んで 1 回生成しておく（テストの間で 1 回だけ）。起動して初めての生成はモデルの読み込みで遅く、
    /// アプリは打ち始める前に読み込んでおく（`AIPrewarm`）ので、測る条件をアプリにそろえる。
    static func warmUp() async {
        await warmUpTask.value
    }

    private static let warmUpTask: Task<Void, Never> = Task {
        await FoundationModelsEntryParser.prewarm()
        _ = await AIEvaluation.measure { try await AIEvaluation.entryParser.parse("ランチ 850") }
    }

    /// テストの「いま」と暦で読む、ひとこと入力の読み取り。
    static var entryParser: FoundationModelsEntryParser {
        FoundationModelsEntryParser(calendar: TestSupport.calendar, now: TestSupport.now)
    }

    // MARK: - 測る

    /// 1 回の呼び出しの答えと、かかった時間。
    struct Timed<Value: Sendable>: Sendable {
        /// 返った答え。失敗したか、見張りの時間（`hangLimit`）を過ぎたら nil。
        let value: Value?
        /// 失敗の説明（返ったら nil）。
        let failure: String?
        let elapsed: Duration

        /// 返って、かかった時間がアプリの上限（`AITimeouts`）までか。アプリは上限を過ぎたら AI の答えを待たずに、AI の使えない端末と
        /// 同じ経路に切り替える。
        func isWithin(_ limit: Duration) -> Bool {
            value != nil && elapsed <= limit
        }

        /// 表の 1 行に書く、答えとかかった時間。
        func describe(_ show: (Value) -> String) -> String {
            let time = AIEvaluation.seconds(elapsed)
            if let value { return "\(show(value))（\(time)）" }
            return "失敗: \(failure ?? "-")（\(time)）"
        }
    }

    /// `operation` を呼び、答えとかかった時間を返す。見張りの時間（`hangLimit`）を過ぎたら待たずに失敗とする。
    static func measure<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async -> Timed<Value> {
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let value = try await withDeadline(hangLimit, operation: operation)
            return Timed(value: value, failure: nil, elapsed: start.duration(to: clock.now))
        } catch {
            return Timed(value: nil, failure: String(describing: error), elapsed: start.duration(to: clock.now))
        }
    }

    /// 秒の表記（小数 2 桁）。
    static func seconds(_ duration: Duration) -> String {
        let (seconds, attoseconds) = duration.components
        return String(format: "%.2f 秒", Double(seconds) + Double(attoseconds) / 1e18)
    }

    // MARK: - 記録

    /// 質問と一言に使う記録（2026 年 9 月と 8 月。「いま」は `TestSupport.now`（9/28 の正午。月曜日））。
    static let records: [LedgerRecordValue] = [
        record(450, .cafe, month: 9, day: 3),
        record(1_200, .food, month: 9, day: 10),
        record(1_800, .transport, month: 9, day: 15),
        record(500, .cafe, month: 9, day: 20),
        record(250_000, .other, month: 9, day: 25, isIncome: true),
        record(220, .transport, month: 9, day: 27),
        record(850, .food, month: 9, day: 28),
        record(3_200, .food, month: 8, day: 5),
        record(600, .cafe, month: 8, day: 12),
        record(1_900, .entertainment, month: 8, day: 20),
        record(250_000, .other, month: 8, day: 25, isIncome: true),
    ]

    /// 月の予算（質問・一言の記録と組み合わせる）と、決めた日時（8 月から）。
    static let budget = 100_000
    static let budgetDecidedAt = TestSupport.date(2026, 8, 1)

    private static func record(
        _ amount: Int, _ category: EntryCategory, month: Int, day: Int, isIncome: Bool = false
    ) -> LedgerRecordValue {
        LedgerRecordValue(
            amount: amount, isIncome: isIncome, category: category, spentAt: TestSupport.date(2026, month, day, hour: 9)
        )
    }
}

/// 表の 1 件ずつの結果と、合った割合。落ちたときに、どの件がどう外れたかをそのまま読めるようにする。
struct AIScorecard {
    let title: String
    private(set) var lines: [String] = []
    private(set) var passed = 0
    private(set) var total = 0

    init(_ title: String) {
        self.title = title
    }

    mutating func record(_ label: String, passed ok: Bool, _ detail: String) {
        total += 1
        if ok { passed += 1 }
        lines.append("\(ok ? "○" : "×") \(label): \(detail)")
    }

    /// 合った割合（件が無ければ 0）。
    var rate: Double {
        total == 0 ? 0 : Double(passed) / Double(total)
    }

    var report: String {
        (["\(title): \(passed)/\(total) 件"] + lines).joined(separator: "\n")
    }
}
#endif
