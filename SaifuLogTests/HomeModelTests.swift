import Foundation
import SaifuLogCore
import SwiftData
import Testing
@testable import SaifuLog

/// ホームの送信・取り消し・削除（HomeModel）。メモリの上の保存先と、差し替えた解析器で確かめる。
@MainActor
struct HomeModelTests {
    /// HomeModel と、その保存先・解析器・読み上げの代わり。
    @MainActor
    final class Fixture {
        let context: ModelContext
        /// true の間は保存（書き込み）が失敗する。
        var failsSave = false
        /// 送信のたびに使う解析器。既定はキーワード辞書（固定の日時で読む）。
        var parser: any EntryParsing = RuleBasedParser(calendar: TestSupport.calendar, now: { TestSupport.now })
        var now = TestSupport.now
        /// 解析を待ってから記録する処理の数（保存先の開き直しが待つもの）。
        let pendingWrites = PendingStoreWrites()
        private(set) var announcements: [String] = []
        private(set) var model: HomeModel!

        init() throws {
            context = try TestSupport.makeContext()
            var store = EntryStore(context: context)
            store.save = { [unowned self] context in
                if failsSave { throw TestError() }
                try context.save()
            }
            model = HomeModel(
                store: store,
                pendingWrites: pendingWrites,
                makeParser: { [unowned self] in parser },
                now: { [unowned self] in now },
                announce: { [unowned self] in announcements.append($0) }
            )
        }

        /// 保存先にある記録（記録した順）。
        func entries() throws -> [Entry] {
            try context.fetch(FetchDescriptor<Entry>(sortBy: [SortDescriptor(\.createdAt)]))
        }

        /// 入力欄に文を入れて送り、読み取りと保存が終わるまで待つ。
        func send(_ text: String) async {
            model.draft = text
            await model.send(calendar: TestSupport.calendar)?.value
        }
    }

    // MARK: - 送信

    @Test func sendRecordsEntry() async throws {
        let fixture = try Fixture()
        fixture.model.draft = "  ランチ 850 "

        let task = fixture.model.send(calendar: TestSupport.calendar)
        // 送った時点で入力欄を空け、読み取り中にする（解析を待たずに次を打てるように）。
        #expect(fixture.model.draft.isEmpty)
        #expect(fixture.model.isParsing)
        await task?.value

        let entries = try fixture.entries()
        #expect(entries.map(\.amount) == [850])
        #expect(entries.map(\.memo) == ["ランチ"])
        #expect(entries.map(\.category) == [.food])
        #expect(entries.map(\.originalText) == ["ランチ 850"])
        #expect(entries.allSatisfy { TestSupport.calendar.isDate($0.spentAt, inSameDayAs: TestSupport.now) })
        #expect(!fixture.model.isParsing)
        #expect(fixture.model.canUndo)
        #expect(fixture.model.justRecorded.map(\.amount) == [850])
        #expect(!fixture.model.showsNoAmountAlert)
        #expect(fixture.model.storeFailure == nil)
        // 何円を記録したかを VoiceOver に読み上げる。
        #expect(fixture.announcements.count == 1)
        #expect(fixture.announcements.first?.contains("¥850") == true)
    }

    /// 1 回の送信で複数件を記録したら、取り消しの対象もその全部。
    @Test func sendRecordsMultipleEntries() async throws {
        let fixture = try Fixture()

        await fixture.send("スーパー2480、ドラッグ1200")

        #expect(try fixture.entries().map(\.amount) == [2_480, 1_200])
        #expect(fixture.model.justRecorded.count == 2)
    }

    @Test func sendIgnoresBlankText() throws {
        let fixture = try Fixture()
        fixture.model.draft = "   "

        #expect(fixture.model.send(calendar: TestSupport.calendar) == nil)
        #expect(!fixture.model.isParsing)
        #expect(try fixture.entries().isEmpty)
    }

    /// 読み取り中は次の送信を受け付けない（二度押しで同じ記録を 2 件にしない）。打ちかけの文も消さない。
    @Test func sendIgnoresWhileParsing() async throws {
        let fixture = try Fixture()
        fixture.model.draft = "ランチ 850"
        let first = fixture.model.send(calendar: TestSupport.calendar)

        fixture.model.draft = "コーヒー 400"
        #expect(fixture.model.send(calendar: TestSupport.calendar) == nil)
        #expect(fixture.model.draft == "コーヒー 400")
        await first?.value

        #expect(try fixture.entries().map(\.amount) == [850])
    }

    /// 金額が読めなければ記録せず、送った文を入力欄に戻して知らせる（その場で直して送り直せるように）。
    @Test func unreadableTextReturnsToDraft() async throws {
        let fixture = try Fixture()

        await fixture.send("ランチ")

        #expect(try fixture.entries().isEmpty)
        #expect(fixture.model.draft == "ランチ")
        #expect(fixture.model.showsNoAmountAlert)
        #expect(!fixture.model.canUndo)
        #expect(fixture.announcements.isEmpty)
        #expect(!fixture.model.isParsing)
    }

    /// 解析が失敗（throw）しても同じ。記録はせず、文を戻す。
    @Test func parserErrorReturnsToDraft() async throws {
        let fixture = try Fixture()
        fixture.parser = StubParser { _ in throw TestError() }

        await fixture.send("ランチ 850")

        #expect(try fixture.entries().isEmpty)
        #expect(fixture.model.draft == "ランチ 850")
        #expect(fixture.model.showsNoAmountAlert)
    }

    /// 解析の間に次の入力を打ち始めていたら、送った文で上書きしない。
    @Test func failedSendKeepsNewDraft() async throws {
        let fixture = try Fixture()
        fixture.parser = StubParser { _ in
            await MainActor.run { fixture.model.draft = "コーヒー" }
            return []
        }

        await fixture.send("ランチ")

        #expect(fixture.model.draft == "コーヒー")
        #expect(fixture.model.showsNoAmountAlert)
    }

    /// 保存に失敗したら記録したことにしない。入れかけた記録は残さず、文を戻して知らせる。
    @Test func saveFailureOnSendRollsBack() async throws {
        let fixture = try Fixture()
        fixture.failsSave = true

        await fixture.send("ランチ 850")

        #expect(try fixture.entries().isEmpty)
        #expect(!fixture.context.hasChanges)
        #expect(fixture.model.storeFailure == .record)
        #expect(fixture.model.draft == "ランチ 850")
        #expect(!fixture.model.canUndo)
        // 「記録しました」と読み上げない。
        #expect(fixture.announcements.isEmpty)
    }

    /// 解析を待ってから記録するまでは、書き込み中の処理として数える（保存先を開き直すときに待ってもらうため）。
    /// 記録できても、読めなくても、保存に失敗しても、終われば数えない（数え残すと、開き直しがいつまでも待つ）。
    @Test func sendCountsPendingWriteUntilDone() async throws {
        let fixture = try Fixture()
        fixture.model.draft = "ランチ 850"

        let task = fixture.model.send(calendar: TestSupport.calendar)
        #expect(fixture.pendingWrites.count == 1)
        await task?.value
        #expect(fixture.pendingWrites.count == 0)

        await fixture.send("ランチ")
        #expect(fixture.model.showsNoAmountAlert)
        #expect(fixture.pendingWrites.count == 0)

        fixture.failsSave = true
        await fixture.send("コーヒー 400")
        #expect(fixture.model.storeFailure == .record)
        #expect(fixture.pendingWrites.count == 0)

        // 受け付けなかった送信は数えない。
        fixture.model.draft = "   "
        #expect(fixture.model.send(calendar: TestSupport.calendar) == nil)
        #expect(fixture.pendingWrites.count == 0)
    }

    // MARK: - 取り消し

    @Test func undoDeletesRecordAndRestoresText() async throws {
        let fixture = try Fixture()
        await fixture.send("ランチ 850")

        fixture.model.undoLastRecord()

        #expect(try fixture.entries().isEmpty)
        #expect(!fixture.model.canUndo)
        // 元の文を入力欄に戻し、直して送り直せるようにする。
        #expect(fixture.model.draft == "ランチ 850")
        #expect(fixture.model.storeFailure == nil)
        #expect(fixture.announcements.count == 2)
        #expect(fixture.announcements.last?.contains("¥850") == true)
    }

    /// 取り消す前に次の入力を打ち始めていたら、元の文で上書きしない。
    @Test func undoKeepsTypedDraft() async throws {
        let fixture = try Fixture()
        await fixture.send("ランチ 850")
        fixture.model.draft = "コーヒー"

        fixture.model.undoLastRecord()

        #expect(try fixture.entries().isEmpty)
        #expect(fixture.model.draft == "コーヒー")
    }

    /// 取り消しを保存できなければ、記録は残し、「取り消す」も残してもう一度押せるようにする。
    @Test func saveFailureOnUndoKeepsRecord() async throws {
        let fixture = try Fixture()
        await fixture.send("ランチ 850")
        fixture.failsSave = true

        fixture.model.undoLastRecord()

        #expect(try fixture.entries().map(\.amount) == [850])
        #expect(!fixture.context.hasChanges)
        #expect(fixture.model.storeFailure == .undo)
        #expect(fixture.model.canUndo)
        #expect(fixture.model.draft.isEmpty)
        #expect(fixture.announcements.count == 1)

        // 保存できるようになれば、もう一度押して取り消せる。
        fixture.failsSave = false
        fixture.model.undoLastRecord()
        #expect(try fixture.entries().isEmpty)
    }

    /// 「取り消す」を引っ込めても（時間切れ・閉じる）、記録はそのまま残る。
    @Test func dismissUndoKeepsRecord() async throws {
        let fixture = try Fixture()
        await fixture.send("ランチ 850")

        fixture.model.dismissUndo()

        #expect(!fixture.model.canUndo)
        #expect(try fixture.entries().map(\.amount) == [850])
    }

    // MARK: - 削除

    @Test func deleteRemovesRecordAfterConfirmation() async throws {
        let fixture = try Fixture()
        await fixture.send("ランチ 850")
        let entry = try #require(try fixture.entries().first)

        fixture.model.requestDelete(entry)
        let pending = try #require(fixture.model.pendingDeletion)
        #expect(pending.summary == "ランチ ¥850")
        // 確認を出しただけでは消さない。
        #expect(try fixture.entries().count == 1)

        fixture.model.delete(pending)

        #expect(try fixture.entries().isEmpty)
        #expect(fixture.model.pendingDeletion == nil)
        // 直前に記録したものを消したら、「取り消す」の対象からも外す。
        #expect(!fixture.model.canUndo)
        #expect(fixture.announcements.last?.contains("ランチ ¥850") == true)
    }

    /// 前の記録を消しても、直前の記録の「取り消す」は残る。
    @Test func deletingOlderRecordKeepsUndo() async throws {
        let fixture = try Fixture()
        await fixture.send("ランチ 850")
        fixture.model.dismissUndo()
        await fixture.send("コーヒー 400")
        let lunch = try #require(try fixture.entries().first { $0.amount == 850 })

        fixture.model.requestDelete(lunch)
        fixture.model.delete(try #require(fixture.model.pendingDeletion))

        #expect(try fixture.entries().map(\.amount) == [400])
        #expect(fixture.model.justRecorded.map(\.amount) == [400])
    }

    /// 削除を保存できなければ、記録を元に戻して知らせる（消えたように見えて、次の起動で戻ってこないように）。
    @Test func saveFailureOnDeleteKeepsRecord() async throws {
        let fixture = try Fixture()
        await fixture.send("ランチ 850")
        let entry = try #require(try fixture.entries().first)
        fixture.failsSave = true

        fixture.model.requestDelete(entry)
        fixture.model.delete(try #require(fixture.model.pendingDeletion))

        #expect(try fixture.entries().map(\.amount) == [850])
        #expect(!fixture.context.hasChanges)
        #expect(fixture.model.storeFailure == .delete)
        #expect(fixture.model.canUndo)
    }

    // MARK: - 日付とタイムライン

    /// 前面に戻ったときや日付が変わったときに「今日」を読み直す（月をまたいでも前の月の合計を出し続けない）。
    @Test func refreshTodayReadsClock() throws {
        let fixture = try Fixture()
        #expect(fixture.model.today == TestSupport.now)

        fixture.now = TestSupport.date(2026, 10, 1, hour: 0, minute: 1)
        fixture.model.refreshToday()

        #expect(fixture.model.today == TestSupport.date(2026, 10, 1, hour: 0, minute: 1))
    }

    @Test func showMoreTimelineAddsPage() throws {
        let fixture = try Fixture()
        #expect(fixture.model.timelineLimit == HomeModel.timelinePageSize)

        fixture.model.showMoreTimeline()

        #expect(fixture.model.timelineLimit == HomeModel.timelinePageSize * 2)
    }
}
