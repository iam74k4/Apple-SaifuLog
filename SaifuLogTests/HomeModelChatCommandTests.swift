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

    /// 決めた種類を、テストが `resume()` を呼ぶまで返さない AI の代わり（待つ間の出来事を確かめる）。
    private final class BlockingInterpreter: ChatCommandInterpreting, @unchecked Sendable {
        let answer: ChatCommandKind
        private let lock = NSLock()
        private var hasBeenAsked = false
        private var waiting: CheckedContinuation<Void, Never>?
        private var resumed = false
        private var released: CheckedContinuation<Void, Never>?

        init(answer: ChatCommandKind) {
            self.answer = answer
        }

        func kind(of text: String) async throws -> ChatCommandKind {
            let watcher: CheckedContinuation<Void, Never>? = lock.withLock {
                hasBeenAsked = true
                defer { waiting = nil }
                return waiting
            }
            watcher?.resume()
            await withCheckedContinuation { continuation in
                let resumeNow: Bool = lock.withLock {
                    if resumed { return true }
                    released = continuation
                    return false
                }
                if resumeNow { continuation.resume() }
            }
            return answer
        }

        /// AI に聞かれるまで待つ。
        func waitUntilAsked() async {
            await withCheckedContinuation { continuation in
                let resumeNow: Bool = lock.withLock {
                    if hasBeenAsked { return true }
                    waiting = continuation
                    return false
                }
                if resumeNow { continuation.resume() }
            }
        }

        /// 答えを返させる。
        func resume() {
            let continuation: CheckedContinuation<Void, Never>? = lock.withLock {
                resumed = true
                defer { released = nil }
                return released
            }
            continuation?.resume()
        }
    }

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

    /// 「さっきのを900に直して」で直前の記録の金額を直し、新しい記録にはしない。「取り消す」だけを引っ込め、直前の記録は
    /// 続けてチャットで直せる相手として残す。
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
        // 取り消しても、直す前の文が入力欄に戻るだけなので押せない。
        fixture.model.undoLastRecord()
        #expect(try fixture.entries().map(\.amount) == [900])
        // 以前は直前の記録ごと手放していたので、続けて「それ日用品」と送っても直せず、新しい記録の文として読んでいた。
        #expect(fixture.model.recordedItems.map(\.summaryText) == ["ランチ ¥900"])
        await fixture.send("それ日用品")
        #expect(try fixture.entries().map(\.category) == [.daily])
    }

    /// 金額を直しても、カテゴリの聞き返しは残す（カテゴリはまだ決まっていないため）。
    @Test func changingAmountKeepsCategoryQuestion() async throws {
        let fixture = try Fixture()
        await fixture.send("ユニクロ 3990")
        let entry = try #require(try fixture.entries().first)

        await fixture.send("さっきのを4990に直して")

        #expect(entry.amount == 4_990)
        #expect(fixture.model.categoryQuestionIDs == [entry.persistentModelID])
        #expect(fixture.model.justRecordedIDs == [entry.persistentModelID])
    }

    /// 「AじゃなくてB」は後ろの金額にする。
    @Test func changesAmountAfterNegation() async throws {
        let fixture = try Fixture()
        await fixture.send("ランチ 850")

        await fixture.send("850じゃなくて950")

        #expect(try fixture.entries().map(\.amount) == [950])
    }

    /// 割り勘の記録は、チャットでは金額を直さない（1 人分の額を記録しているので、書いた額が 1 人分か合計か決められない）。
    ///
    /// 以前は「3000じゃなくて3500」で 1 人分を 3500 にし、割り勘の説明も消していた。
    @Test func refusesToChangeSplitAmount() async throws {
        let fixture = try Fixture()
        await fixture.send("昨日 焼肉12000 4人で割り勘")
        let entry = try #require(try fixture.entries().first)
        let memo = entry.memo

        await fixture.send("3000じゃなくて3500")

        #expect(entry.amount == 3_000)
        #expect(entry.memo == memo)
        #expect(fixture.lastQuestionState == .splitNotChanged)
        #expect(fixture.model.draft == "3000じゃなくて3500")
    }

    /// 直前の記録が無ければ、金額を直す文は直せる記録が無いと案内する（新しい記録にしない）。
    @Test func changingAmountNeedsRecentEntry() async throws {
        let fixture = try Fixture()

        await fixture.send("さっきのを900に直して")

        #expect(try fixture.entries().isEmpty)
        #expect(fixture.lastQuestionState == .noTarget)
        #expect(fixture.model.draft == "さっきのを900に直して")
        #expect(fixture.announcements.last == String(localized: "直せる直前の記録がありません"))
    }

    /// 品目や店の名前が残る文は、直前の記録の金額を直さない（新しい記録にする）。
    ///
    /// 以前は「名前の」の「前の」と「変更」で直す文と読み、直前の記録を ¥2,500 にしていた。
    @Test func recordLikeTextIsNotACorrection() async throws {
        let fixture = try Fixture()
        await fixture.send("ランチ 850")

        await fixture.send("名前の変更 2500")

        #expect(try fixture.entries().map(\.amount) == [850, 2_500])
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

    /// 1 回の送信で複数件を記録したら、消す文はその送信の記録をすべて消す（返事の「取り消す」と同じ）。2 件以上を消すときは、
    /// 決まりで読んだ文でも確かめてから消す（1 文で品目がすべて消え、戻せないため）。
    @Test func removesWholeLastSendAfterConfirmation() async throws {
        let fixture = try Fixture()
        await fixture.send("スーパー2480、ドラッグ1200")

        await fixture.send("今のなし")

        #expect(try fixture.entries().count == 2)
        let pending = try #require(fixture.model.pendingCommand)
        #expect(pending.command == .removeLast)

        fixture.model.confirmCommand(pending)

        #expect(try fixture.entries().isEmpty)
        #expect(fixture.lastQuestionState == .removed(summary: ["スーパー ¥2,480", "ドラッグ ¥1,200"].formatted(.list(type: .and))))
    }

    /// AI の答えを待つ間などにほかの画面を開いていたら、確認を出さずにやめ、送った文を入力欄に戻す（開いている画面の上や後に
    /// 確認を出さないため）。
    @Test func confirmationIsNotShownOverOtherScreens() async throws {
        let fixture = try Fixture()
        await fixture.send("スーパー2480、ドラッグ1200")
        fixture.model.presentSettings()

        await fixture.send("今のなし")

        #expect(fixture.model.pendingCommand == nil)
        #expect(try fixture.entries().count == 2)
        #expect(fixture.lastQuestionState == .commandCancelled)
        #expect(fixture.model.draft == "今のなし")
    }

    /// 直前の記録が無ければ、消す文は何も消さず、直せる記録が無いと案内する。
    @Test func removingNeedsRecentEntry() async throws {
        let fixture = try Fixture()
        await fixture.send("ランチ 850")
        await fixture.send("今月いくら?")

        await fixture.send("さっきの消して")

        #expect(try fixture.entries().map(\.amount) == [850])
        #expect(fixture.lastQuestionState == .noTarget)
        #expect(fixture.model.draft == "さっきの消して")
    }

    /// 「なし」だけの文や「カテゴリなし」は、直前の記録を消さない。
    @Test func looseRemovalWordsDoNotRemove() async throws {
        let fixture = try Fixture()
        await fixture.send("ランチ 850")

        await fixture.send("カテゴリなし")

        #expect(try fixture.entries().map(\.amount) == [850])
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

        // 決まりでは記録か質問か決められない文。AI が「金額を直す」を選び、金額は文から読む。AI が選んだ操作は、確認してから行う。
        await fixture.send("ランチは実は900円だった。残りを直して")
        #expect(stub.texts.count == 2)
        #expect(try fixture.entries().map(\.amount) == [850])
        let pending = try #require(fixture.model.pendingCommand)
        #expect(pending.question == .changeAmount(summary: "ランチ ¥850", amount: 900))
        #expect(fixture.lastQuestionState == .commandAsked(.changeAmount(summary: "ランチ ¥850", amount: 900)))

        fixture.model.confirmCommand(pending)

        #expect(try fixture.entries().map(\.amount) == [900])
        #expect(fixture.model.pendingCommand == nil)
        #expect(fixture.lastQuestionState == .amountChanged(item: "ランチ", from: 850, to: 900))
        // 同じ確認を 2 度行わない（ボタンと閉じる動きの両方から呼ばれても）。
        fixture.model.cancelCommand(pending)
        #expect(fixture.lastQuestionState == .amountChanged(item: "ランチ", from: 850, to: 900))
    }

    /// AI が「消す」を選んだときは、確認を出してから消す。確認で行えば、直前の送信の記録を消す。
    @Test func aiRemovalAsksForConfirmation() async throws {
        let fixture = try Fixture()
        fixture.commandInterpreter = ChatCommandInterpreter(interpreter: StubInterpreter(.removeLast), onFallback: nil)
        await fixture.send("ランチ 850")

        await fixture.send("あれはやっぱりなかったことにしたい")

        #expect(try fixture.entries().map(\.amount) == [850])
        let pending = try #require(fixture.model.pendingCommand)
        #expect(fixture.lastQuestionState == .commandAsked(.remove(summary: "ランチ ¥850")))

        fixture.model.confirmCommand(pending)

        #expect(try fixture.entries().isEmpty)
        #expect(fixture.lastQuestionState == .removed(summary: "ランチ ¥850"))
        #expect(!fixture.model.canUndo)
    }

    /// 確認で「キャンセル」なら何も変えず、送った文を入力欄に戻す。金額の無い文だったので、直前の送信の「取り消す」も戻す。
    @Test func cancellingAIChoiceChangesNothing() async throws {
        let fixture = try Fixture()
        fixture.commandInterpreter = ChatCommandInterpreter(interpreter: StubInterpreter(.removeLast), onFallback: nil)
        await fixture.send("ランチ 850")
        await fixture.send("あれはやっぱりなかったことにしたい")
        let pending = try #require(fixture.model.pendingCommand)

        fixture.model.cancelCommand(pending)

        #expect(try fixture.entries().map(\.amount) == [850])
        #expect(fixture.lastQuestionState == .commandCancelled)
        #expect(fixture.model.draft == "あれはやっぱりなかったことにしたい")
        #expect(fixture.model.canUndo)
        // キャンセルした後に確認のボタンが届いても行わない。
        fixture.model.confirmCommand(pending)
        #expect(try fixture.entries().map(\.amount) == [850])
    }

    /// AI が選んだ予算も、確認してから決める（「年間」のような月でない予算は、AI が選んでも決めない）。
    @Test func aiBudgetAsksForConfirmation() async throws {
        let fixture = try Fixture()
        fixture.commandInterpreter = ChatCommandInterpreter(interpreter: StubInterpreter(.setMonthlyBudget), onFallback: nil)

        await fixture.send("これからは予算を7万くらいで")

        let pending = try #require(fixture.model.pendingCommand)
        #expect(pending.question == .setMonthlyBudget(amount: 70_000))
        #expect(try BudgetStore(context: fixture.context).plan().total == nil)
        fixture.model.confirmCommand(pending)
        #expect(try BudgetStore(context: fixture.context).plan().total == 70_000)
        #expect(fixture.lastQuestionState == .budgetSet(amount: 70_000))
    }

    /// 送った後、AI を待つ間に直前の送信が替わっても（取り消した）、送った時点の相手のまま。消えた相手は直さない。
    @Test func aiCommandUsesTargetsAtSendTime() async throws {
        let fixture = try Fixture()
        await fixture.send("ランチ 850")
        let lunch = try #require(try fixture.entries().first)
        let interpreter = BlockingInterpreter(answer: .changeAmount)
        // 待つ間に上限の時間で打ち切られないよう、上限を長くする。
        fixture.commandInterpreter = ChatCommandInterpreter(interpreter: interpreter, timeout: .seconds(60), onFallback: nil)
        fixture.model.draft = "ランチは実は900円だった。残りを直して"
        let task = fixture.model.send(calendar: TestSupport.calendar)
        await interpreter.waitUntilAsked()

        // AI を待つ間に、ほかの端末で消された。
        try fixture.deleteElsewhere(lunch.persistentModelID)
        interpreter.resume()
        await task?.value

        #expect(fixture.model.pendingCommand == nil)
        #expect(fixture.lastQuestionState == .noTarget)
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
