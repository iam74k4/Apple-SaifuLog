import Foundation
import SaifuLogCore
import SwiftData
import Testing
@testable import SaifuLog

/// チャットの文で頼む操作（金額を直す・消す・月の予算を決める。`ChatCommandReader`・`HomeModel.perform`）と、決まりで読めなかった
/// 文の操作の種類を端末内 AI に選ばせること（`ChatCommandInterpreter`）。
@MainActor
struct HomeModelChatCommandTests {
    typealias Fixture = HomeModelTests.Fixture

    /// 決めた種類を返す AI の代わり。聞かれた文を残す。
    private final class StubInterpreter: ChatCommandInterpreting, @unchecked Sendable {
        let answer: ChatCommandKind
        private let lock = NSLock()
        private var asked: [String] = []

        init(_ answer: ChatCommandKind) {
            self.answer = answer
        }

        var texts: [String] { lock.withLock { asked } }

        func kind(of text: String) async throws -> ChatCommandKind {
            lock.withLock { asked.append(text) }
            return answer
        }
    }

    // MARK: - 金額を直す

    /// 「さっきのを900に直して」で直前の記録の金額を直し、新しい記録にはしない。「取り消す」は引っ込める。
    @Test func changesAmountOfLastEntry() async throws {
        let fixture = try Fixture()
        await fixture.send("ランチ 850")

        await fixture.send("さっきのを900に直して")

        let entries = try fixture.entries()
        #expect(entries.map(\.amount) == [900])
        #expect(entries.map(\.memo) == ["ランチ"])
        #expect(fixture.lastQuestionState == .amountChanged(item: "ランチ", from: 850, to: 900))
        #expect(!fixture.model.canUndo)
        #expect(fixture.model.draft.isEmpty)
    }

    /// 「AじゃなくてB」は後ろの金額にする。割り勘の説明（前の金額で書いたもの）は品目だけにする。
    @Test func changesAmountAfterNegation() async throws {
        let fixture = try Fixture()
        await fixture.send("昨日 焼肉12000 4人で割り勘")

        await fixture.send("3000じゃなくて3500")

        let entry = try #require(try fixture.entries().first)
        #expect(entry.amount == 3_500)
        #expect(entry.memo == "焼肉")
    }

    /// 直前の記録が無ければ、金額を直す文は案内だけにする（新しい記録にしない）。
    @Test func changingAmountNeedsRecentEntry() async throws {
        let fixture = try Fixture()

        await fixture.send("さっきのを900に直して")

        #expect(try fixture.entries().isEmpty)
        #expect(fixture.lastQuestionState == .correction)
        #expect(fixture.model.draft == "さっきのを900に直して")
    }

    // MARK: - 消す

    /// 「さっきの消して」で直前の記録を消す（「取り消す」と同じ。送った文は入力欄に戻さない）。
    @Test func removesLastEntry() async throws {
        let fixture = try Fixture()
        await fixture.send("ランチ 850")

        await fixture.send("さっきの消して")

        #expect(try fixture.entries().isEmpty)
        #expect(fixture.lastQuestionState == .removed(summary: "ランチ ¥850"))
        #expect(fixture.model.draft.isEmpty)
        #expect(fixture.announcements.last?.hasPrefix(String(localized: "取り消しました: 食費 ¥850")) == true)
    }

    /// 直前の記録が無ければ、消す文は何も消さない（ふつうの送信として、金額が無いと知らせる）。
    @Test func removingNeedsRecentEntry() async throws {
        let fixture = try Fixture()
        await fixture.send("ランチ 850")
        await fixture.send("今月いくら?")

        await fixture.send("さっきの消して")

        #expect(try fixture.entries().map(\.amount) == [850])
        #expect(fixture.lastQuestionState == .noAmount)
    }

    // MARK: - 予算

    /// 「今月の予算を5万にして」で月の全体の予算を決める（記録にはしない）。
    @Test func setsMonthlyBudget() async throws {
        let fixture = try Fixture()

        await fixture.send("今月の予算を5万にして")

        #expect(try BudgetStore(context: fixture.context).plan().total == 50_000)
        #expect(try fixture.entries().isEmpty)
        #expect(fixture.lastQuestionState == .budgetSet(amount: 50_000))
        #expect(fixture.model.draft.isEmpty)
    }

    // MARK: - 端末内 AI

    /// 決まりで読めなかった文は、AI が選んだ種類で、文に書かれた値を使って行う。
    @Test func usesAIForUndecidedText() async throws {
        let fixture = try Fixture()
        let stub = StubInterpreter(.changeAmount)
        fixture.commandInterpreter = ChatCommandInterpreter(interpreter: stub, onFallback: nil)
        await fixture.send("ランチ 850")

        // 「直す」の語はあるが、金額が 2 つで決まりでは読めない。AI も金額を決められないので、案内を出す。
        await fixture.send("さっきのを900か950に直して")
        #expect(fixture.lastQuestionState == .correction)

        // 決まりでは記録か質問か決められない文。AI が「金額を直す」を選び、金額は文から読む。
        await fixture.send("ランチは実は900円だった。残りを直して")
        #expect(try fixture.entries().map(\.amount) == [900])
        #expect(stub.texts.count == 2)
    }

    /// AI が「消す」を選んだときは、確認を出してから消す。
    @Test func aiRemovalAsksForConfirmation() async throws {
        let fixture = try Fixture()
        fixture.commandInterpreter = ChatCommandInterpreter(interpreter: StubInterpreter(.removeLast), onFallback: nil)
        await fixture.send("ランチ 850")

        await fixture.send("あれはやっぱりなかったことにしたい")

        #expect(try fixture.entries().map(\.amount) == [850])
        #expect(fixture.model.pendingDeletion != nil)
        #expect(fixture.lastQuestionState == .removalAsked(summary: "ランチ ¥850"))
    }

    /// AI が「どれでもない」を選べば、これまでどおり案内を出す。AI が無い端末も同じ。
    @Test(arguments: [true, false])
    func fallsBackWhenAIChoosesNothing(hasAI: Bool) async throws {
        let fixture = try Fixture()
        if hasAI { fixture.commandInterpreter = ChatCommandInterpreter(interpreter: StubInterpreter(.none), onFallback: nil) }

        await fixture.send("残り 5000")

        #expect(fixture.lastQuestionState == .unclear)
        #expect(fixture.model.draft == "残り 5000")
        #expect(!fixture.model.isParsing)
    }
}
