#if canImport(FoundationModels)
import Foundation
import SaifuLogCore
import Testing
@testable import SaifuLog

extension AIEvaluationTests {
    /// チャットで頼む操作の種類の選び（`FoundationModelsChatCommandInterpreter`）と、選んだ種類で文から組み立てる操作
    /// （`ChatCommandReader.candidates(in:now:calendar:catalog:)`。アプリの `HomeModel` と同じ組み合わせで、文から組み立てられる種類だけを
    /// AI に選ばせ、組み立てられる種類が無い文は AI に聞かない。アプリは AI の選んだ操作を、確認を出してから行う）。
    @Suite("チャットで頼む操作")
    struct ChatCommandChoice {
        /// 決まりより緩く読む文（アプリでは決まりで読めないときに AI に種類を選ばせる）と、組み立てる操作。
        static let commands: [(text: String, command: ChatCommand)] = [
            ("あれ実は900円だった", .changeAmount(900)),
            ("さっきのランチ、850じゃなくて950", .changeAmount(950)),
            ("さっきのやっぱりなしで", .removeLast),
            ("あれはなかったことで", .removeLast),
            ("これからは予算を7万くらいで", .setMonthlyBudget(70_000)),
            ("あれは交通かな", .recategorize(.transport)),
            ("交通費じゃなくて食費かな", .recategorize(.food)),
        ]

        /// 操作ではない文（新しい記録・質問・店を直した記録・比べる文）。「どれでもない」になるのが正しい。どの種類も文から組み立て
        /// られないので、AI には聞かない（`ChatCommandReader` が、種類に合う語や値の無い文を断る）。
        static let nonCommands = [
            "ランチ 850",
            "昨日 焼肉12000 4人で割り勘",
            "今月カフェいくら?",
            "先月の食費は?",
            "スタバじゃなくてドトール 400",
            "今月の食費 3万超えた",
        ]

        /// 直す語のある記録の文（直したり変えたりしてもらった費用）。「どれでもない」になるのが正しい。モデルはこの形の文をどれも
        /// 金額を直す文として選んだので、前の記録を指す語・言い直しの語・直した先を示す直す語の無い文は、金額を直す操作の候補にしない
        /// （`ChatCommandReader`）。候補にして AI が金額を直す種類を選ぶと、文の金額で直す確認を出してしまう（書き換えは確認の後）ので、
        /// 合った件の割合に数える。
        static let lookalikes = [
            "名前の変更 2500",
            "前のタイヤ変えて 20000",
        ]

        @Test("操作の種類を選んで文から操作を組み立て、上限の時間に収まる。記録や質問の文からは操作を組み立てない")
        func choosesKinds() async throws {
            try AIEvaluation.requireModel()
            await AIEvaluation.warmUp()
            var card = AIScorecard("チャットで頼む操作の種類（上限 \(AIEvaluation.seconds(AITimeouts.chatCommand))）")
            for (text, command) in Self.commands {
                let candidates = Self.candidates(in: text)
                let timed = await AIEvaluation.measure { try await Self.kind(of: text, among: candidates) }
                let built = timed.value.flatMap { candidates[$0] }
                card.record(
                    "「\(text)」→ \(command)",
                    passed: built == command && timed.isWithin(AITimeouts.chatCommand),
                    timed.describe { "\(Self.describe(candidates)) \($0) → \(Self.describe(built))" }
                )
            }
            for text in Self.nonCommands + Self.lookalikes {
                let candidates = Self.candidates(in: text)
                let timed = await AIEvaluation.measure { try await Self.kind(of: text, among: candidates) }
                let built = timed.value.flatMap { candidates[$0] }
                if Self.nonCommands.contains(text) {
                    // 揺れてはいけない: AI がどの種類を選んでも、記録や質問の文から操作を組み立てない。
                    let kindText = timed.value.map { String(describing: $0) } ?? "-"
                    #expect(built == nil, "「\(text)」から操作を組み立てた: AI の種類 \(kindText)、操作 \(Self.describe(built))")
                }
                card.record(
                    "「\(text)」→ どれでもない",
                    passed: timed.value == ChatCommandKind.none && timed.isWithin(AITimeouts.chatCommand),
                    timed.describe { "\(Self.describe(candidates)) \($0) → \(Self.describe(built))" }
                )
            }
            print(card.report)
            #expect(card.rate >= AIEvaluation.passRate, "\(card.report)")
        }

        private static func candidates(in text: String) -> [ChatCommandKind: ChatCommand] {
            ChatCommandReader.candidates(in: text, now: TestSupport.now, calendar: TestSupport.calendar)
        }

        /// アプリと同じく、組み立てられる種類が無ければ AI に聞かずに「どれでもない」にする（`ChatCommandInterpreter`）。
        private static func kind(
            of text: String, among candidates: [ChatCommandKind: ChatCommand]
        ) async throws -> ChatCommandKind {
            let kinds = ChatCommandKind.allCases.filter { candidates[$0] != nil }
            guard !kinds.isEmpty else { return .none }
            return try await FoundationModelsChatCommandInterpreter().kind(of: text, among: kinds)
        }

        private static func describe(_ candidates: [ChatCommandKind: ChatCommand]) -> String {
            let kinds = ChatCommandKind.allCases.filter { candidates[$0] != nil }
            return kinds.isEmpty ? "（候補なし・AI に聞かない）" : "（候補 \(kinds.map { String(describing: $0) }.joined(separator: "・"))）"
        }

        private static func describe(_ command: ChatCommand?) -> String {
            command.map { String(describing: $0) } ?? "行わない"
        }
    }
}
#endif
