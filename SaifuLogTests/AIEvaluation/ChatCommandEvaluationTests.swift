#if canImport(FoundationModels)
import Foundation
import SaifuLogCore
import Testing
@testable import SaifuLog

extension AIEvaluationTests {
    /// チャットで頼む操作の種類の選び（`FoundationModelsChatCommandInterpreter`）と、選んだ種類で文から組み立てる操作
    /// （`ChatCommandReader.command(kind:in:now:calendar:catalog:)`。アプリの `HomeModel` と同じ組み合わせ。アプリは AI の選んだ操作を、
    /// 確認を出してから行う）。
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

        /// 操作ではない文（新しい記録・質問・店を直した記録・比べる文）。AI は「どれでもない」を選ぶのが正しい。ほかの種類を選んでも、
        /// 文から操作を組み立ててはいけない（`ChatCommandReader` が、種類に合う語や値の無い文を断る）。
        static let nonCommands = [
            "ランチ 850",
            "昨日 焼肉12000 4人で割り勘",
            "今月カフェいくら?",
            "先月の食費は?",
            "スタバじゃなくてドトール 400",
            "今月の食費 3万超えた",
        ]

        /// 直す語のある記録の文（アプリは前の記録を直そうとする文として、AI に種類を選ばせる）。AI は「どれでもない」を選ぶのが正しい。
        /// 金額を直す種類を選ぶと、文の金額で直す操作を組み立てて確認を出してしまう（書き換えは確認の後）ので、合った件の割合に数える。
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
                let timed = await AIEvaluation.measure { try await FoundationModelsChatCommandInterpreter().kind(of: text) }
                let built = timed.value.flatMap { Self.command($0, in: text) }
                card.record(
                    "「\(text)」→ \(command)",
                    passed: built == command && timed.isWithin(AITimeouts.chatCommand),
                    timed.describe { "\($0) → \(Self.describe(built))" }
                )
            }
            for text in Self.nonCommands + Self.lookalikes {
                let timed = await AIEvaluation.measure { try await FoundationModelsChatCommandInterpreter().kind(of: text) }
                let built = timed.value.flatMap { Self.command($0, in: text) }
                if Self.nonCommands.contains(text) {
                    // 揺れてはいけない: AI がどの種類を選んでも、記録や質問の文から操作を組み立てない。
                    let kindText = timed.value.map { String(describing: $0) } ?? "-"
                    #expect(built == nil, "「\(text)」から操作を組み立てた: AI の種類 \(kindText)、操作 \(Self.describe(built))")
                }
                card.record(
                    "「\(text)」→ どれでもない",
                    passed: timed.value == ChatCommandKind.none && timed.isWithin(AITimeouts.chatCommand),
                    timed.describe { "\($0) → \(Self.describe(built))" }
                )
            }
            print(card.report)
            #expect(card.rate >= AIEvaluation.passRate, "\(card.report)")
        }

        private static func command(_ kind: ChatCommandKind, in text: String) -> ChatCommand? {
            ChatCommandReader.command(kind: kind, in: text, now: TestSupport.now, calendar: TestSupport.calendar)
        }

        private static func describe(_ command: ChatCommand?) -> String {
            command.map { String(describing: $0) } ?? "行わない"
        }
    }
}
#endif
