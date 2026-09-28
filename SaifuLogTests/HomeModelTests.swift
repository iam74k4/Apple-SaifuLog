import Foundation
import SaifuLogCore
import SwiftData
import Testing
@testable import SaifuLog

/// ホームの送信・取り消し・直す・削除・予算を決める画面（HomeModel）。メモリの上の保存先と、差し替えた解析器で確かめる。
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
        /// 解析器の作り方を差し替える（送った瞬間の日時と暦を受け取る）。nil なら `parser` を使う。
        var makeParser: ((Date, Calendar) -> any EntryParsing)?
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
                makeParser: { [unowned self] now, calendar in makeParser?(now, calendar) ?? parser },
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

    // MARK: - 送った瞬間の日時

    /// 解析の基準の日時と保存する日時は、送った瞬間の 1 つの値にする。
    ///
    /// 以前は保存のときに時計を読み直していたので、読み取りを待つ間に日付が変わると（23:59:59 に送って 0:00:01 に保存）、
    /// 「9/26」と書いた記録が 9/27 で保存されていた。
    @Test func parsingAndSavingShareSendTime() async throws {
        let fixture = try Fixture()
        let sentAt = TestSupport.date(2026, 9, 28, hour: 23, minute: 59).addingTimeInterval(59)
        let savedAt = TestSupport.date(2026, 9, 29).addingTimeInterval(1)
        fixture.now = sentAt
        var parsedWith: Date?
        fixture.makeParser = { now, calendar in
            parsedWith = now
            return StubParser { text in
                // 読み取っている間に日付が変わる。
                await MainActor.run { fixture.now = savedAt }
                return RuleBasedParser(calendar: calendar, now: { now }).entries(from: text)
            }
        }

        await fixture.send("9/26 ランチ 850")

        #expect(parsedWith == sentAt)
        let entry = try #require(try fixture.entries().first)
        #expect(entry.createdAt == sentAt)
        #expect(TestSupport.calendar.isDate(entry.spentAt, inSameDayAs: TestSupport.date(2026, 9, 26)))
        // 読み上げの「今日」も送った瞬間で決める（9/26 の記録として日付を読む）。
        #expect(fixture.announcements.first?.contains(entry.spentAt.formatted(.dateTime.month().day())) == true)
    }

    /// 月末の 23:59:59.9995 に送った複数件も、すべて今月の記録にする（書いた順に並べるためにずらした日時が翌月へはみ出さない）。
    @Test func multipleEntriesAtMonthEndStayInMonth() async throws {
        let fixture = try Fixture()
        let sentAt = TestSupport.date(2026, 9, 30, hour: 23, minute: 59).addingTimeInterval(59.9995)
        fixture.now = sentAt
        fixture.makeParser = { now, calendar in RuleBasedParser(calendar: calendar, now: { now }) }

        await fixture.send("スーパー2480とドラッグ1200とカフェ400")

        let entries = try fixture.entries()
        #expect(entries.map(\.amount) == [2_480, 1_200, 400])
        #expect(entries.allSatisfy { TestSupport.calendar.isDate($0.spentAt, inSameDayAs: sentAt) })
        let month = Entry.monthDescriptor(containing: sentAt, calendar: TestSupport.calendar)
        #expect(try fixture.context.fetchCount(month) == 3)
    }

    // MARK: - 取り消し

    /// 次の文を送ったら、前の記録の「取り消す」を引っ込める（読み取りの間も押せない。VoiceOver の操作も出さない）。
    ///
    /// 以前は読み取りの間も「取り消す」が前の記録を指したまま押せ、押すと前の記録が消えて、送った記録だけが残った。
    @Test func sendingRetractsPreviousUndo() async throws {
        let fixture = try Fixture()
        await fixture.send("ランチ 850")
        #expect(fixture.model.canUndo)
        let rules = fixture.parser
        fixture.parser = StubParser { text in
            await MainActor.run {
                #expect(fixture.model.isParsing)
                #expect(!fixture.model.canUndo)
                #expect(!fixture.model.autoHidesUndo)
                #expect(fixture.model.justRecorded.isEmpty)
                // 押せたとしても、前の記録は消さない。
                fixture.model.undoLastRecord()
            }
            return try await rules.parse(text)
        }

        await fixture.send("コーヒー 400")

        #expect(try fixture.entries().map(\.amount) == [850, 400])
        #expect(fixture.model.justRecorded.map(\.amount) == [400])
        #expect(fixture.model.draft.isEmpty)
        #expect(fixture.announcements.count == 2)
    }

    /// 前の記録の後に送った文が読めなかったら、その文を入力欄に戻す（前の記録の文を戻さない）。
    @Test func failedSendAfterRecordRestoresItsOwnText() async throws {
        let fixture = try Fixture()
        await fixture.send("ランチ 850")
        fixture.parser = StubParser { _ in
            await MainActor.run { fixture.model.undoLastRecord() }
            return []
        }

        await fixture.send("コーヒー")

        #expect(fixture.model.showsNoAmountAlert)
        #expect(fixture.model.draft == "コーヒー")
        #expect(try fixture.entries().map(\.amount) == [850])
        #expect(!fixture.model.canUndo)
    }

    /// 複数件を送った後の「取り消す」は、全件を消し、元の文を 1 回だけ戻し、読み上げに全件を並べる。
    @Test func undoRemovesAllEntriesOfSend() async throws {
        let fixture = try Fixture()
        await fixture.send("スーパー2480、ドラッグ1200")

        fixture.model.undoLastRecord()

        #expect(try fixture.entries().isEmpty)
        #expect(!fixture.model.canUndo)
        #expect(fixture.model.draft == "スーパー2480、ドラッグ1200")
        #expect(fixture.announcements.count == 2)
        let announcement = try #require(fixture.announcements.last)
        #expect(announcement.contains("¥2,480"))
        #expect(announcement.contains("¥1,200"))
    }

    /// 取り消しの保存に失敗してアラートを出している間は、「取り消す」を時間で引っ込めない（閉じたら数え直す）。
    ///
    /// 数え続けると、アラートを読んでいる間にバナーが消え、「もう一度お試しください」に従えなくなるため。
    @Test func undoFailureAlertPausesAutoHide() async throws {
        let fixture = try Fixture()
        await fixture.send("ランチ 850")
        fixture.failsSave = true

        fixture.model.undoLastRecord()

        #expect(fixture.model.storeFailure == .undo)
        #expect(fixture.model.canUndo)
        #expect(!fixture.model.autoHidesUndo)
        // アラートを閉じると、画面が nil に戻す。
        fixture.model.storeFailure = nil
        #expect(fixture.model.autoHidesUndo)
    }

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

    // MARK: - 読み上げ

    /// 『記録しました』は、今日の記録には日付を添えず、今日でない記録には日付を、今年でない記録には年も添える。
    @Test func recordedAnnouncementAddsDateWhenNotToday() async throws {
        let fixture = try Fixture()

        await fixture.send("ランチ 850")
        let today = try #require(fixture.announcements.last)
        #expect(!today.contains(TestSupport.now.formatted(.dateTime.month().day())))

        await fixture.send("昨日 ランチ 850")
        let yesterday = TestSupport.date(2026, 9, 27, hour: 12)
        let thisYear = try #require(fixture.announcements.last)
        #expect(thisYear.contains(yesterday.formatted(.dateTime.month().day())))
        #expect(!thisYear.contains(yesterday.formatted(.dateTime.year().month().day())))

        await fixture.send("2025/9/26 ランチ 900")
        let lastYear = TestSupport.date(2025, 9, 26, hour: 12)
        #expect(fixture.announcements.last?.contains(lastYear.formatted(.dateTime.year().month().day())) == true)
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

    // MARK: - 直す

    /// 吹き出し・長押しのメニュー・バナー・VoiceOver の操作から、その記録の「直す」のシートを開く。
    @Test func presentEditOpensSheetForEntry() async throws {
        let fixture = try Fixture()
        await fixture.send("ランチ 850")
        let entry = try #require(try fixture.entries().first)
        #expect(fixture.model.editing == nil)

        fixture.model.presentEdit(entry, calendar: TestSupport.calendar)

        let editing = try #require(fixture.model.editing)
        #expect(editing.amountText == "850")
        #expect(editing.memo == "ランチ")
        #expect(editing.category == .food)
        #expect(editing.originalText == "ランチ 850")
        // 開いただけでは何も変えない。
        #expect(!editing.canSave)
        #expect(fixture.model.canUndo)
    }

    /// 直した内容は、同じ保存先に書き込まれる。送信の書き込みとしては数えない（同期的に書き込むので、開き直しを待たせない）。
    @Test func editSavesToStore() async throws {
        let fixture = try Fixture()
        await fixture.send("ドラッグ1200")
        let entry = try #require(try fixture.entries().first)
        fixture.model.presentEdit(entry, calendar: TestSupport.calendar)
        let editing = try #require(fixture.model.editing)

        // キーワード辞書は「ドラッグ」を日用品と読む。薬を買ったので医療に直す。
        #expect(editing.category == .daily)
        editing.category = .medical
        #expect(editing.save())

        #expect(try fixture.entries().map(\.category) == [.medical])
        #expect(fixture.pendingWrites.count == 0)
        #expect(fixture.announcements.last?.contains(String(localized: EntryCategory.medical.label)) == true)
    }

    /// 直前に記録したものを直したら「取り消す」を引っ込める（取り消すと直す前の文が入力欄に戻り、直した内容と食い違うため）。
    @Test func editingJustRecordedDismissesUndo() async throws {
        let fixture = try Fixture()
        await fixture.send("スーパー2480、ドラッグ1200")
        let drug = try #require(try fixture.entries().last)
        fixture.model.presentEdit(drug, calendar: TestSupport.calendar)
        let editing = try #require(fixture.model.editing)
        editing.category = .medical

        #expect(editing.save())

        #expect(!fixture.model.canUndo)
        // 記録はどちらも残る。
        #expect(try fixture.entries().map(\.amount) == [2_480, 1_200])
    }

    /// 前の記録を直しても、直前の記録の「取り消す」は残る。
    @Test func editingOlderRecordKeepsUndo() async throws {
        let fixture = try Fixture()
        await fixture.send("ランチ 850")
        fixture.model.dismissUndo()
        await fixture.send("コーヒー 400")
        let lunch = try #require(try fixture.entries().first { $0.amount == 850 })
        fixture.model.presentEdit(lunch, calendar: TestSupport.calendar)
        let editing = try #require(fixture.model.editing)
        editing.amountText = "900"

        #expect(editing.save())

        #expect(fixture.model.justRecorded.map(\.amount) == [400])
    }

    /// 直すのをやめても（保存せずに閉じる）、「取り消す」はそのまま残る。
    ///
    /// 時間で引っ込めるタイマーは画面にあるので、ここでは「シートを出している間は数えない」（`autoHidesUndo`）までを確かめる。
    /// 数え続けると、直すのに 8 秒以上かけてやめたときには、画面の上では「取り消す」が消えているため。
    @Test func cancellingEditKeepsUndo() async throws {
        let fixture = try Fixture()
        await fixture.send("ランチ 850")
        #expect(fixture.model.autoHidesUndo)
        let entry = try #require(try fixture.entries().first)
        fixture.model.presentEdit(entry, calendar: TestSupport.calendar)
        fixture.model.editing?.amountText = "900"

        // シートを出している間は、「取り消す」を時間で引っ込めない。
        #expect(fixture.model.canUndo)
        #expect(!fixture.model.autoHidesUndo)

        // シートを閉じると、画面が nil に戻す。閉じたら数え直す（閉じた直後にも取り消せる）。
        fixture.model.editing = nil

        #expect(fixture.model.canUndo)
        #expect(fixture.model.autoHidesUndo)
        #expect(try fixture.entries().map(\.amount) == [850])
    }

    /// 直前の記録を直して保存したら「取り消す」は引っ込むので、シートを閉じても数え直さない。
    @Test func savingEditOfJustRecordedStopsUndoCountdown() async throws {
        let fixture = try Fixture()
        await fixture.send("ランチ 850")
        let entry = try #require(try fixture.entries().first)
        fixture.model.presentEdit(entry, calendar: TestSupport.calendar)
        let editing = try #require(fixture.model.editing)
        editing.amountText = "900"

        #expect(editing.save())
        fixture.model.editing = nil

        #expect(!fixture.model.canUndo)
        #expect(!fixture.model.autoHidesUndo)
    }

    /// 取り消せるものが無ければ、数えるものも無い（直すシートを閉じた後も）。
    @Test func autoHidesUndoNeedsSomethingToUndo() async throws {
        let fixture = try Fixture()
        #expect(!fixture.model.autoHidesUndo)

        await fixture.send("ランチ 850")
        fixture.model.dismissUndo()
        let entry = try #require(try fixture.entries().first)
        fixture.model.presentEdit(entry, calendar: TestSupport.calendar)
        fixture.model.editing = nil

        #expect(!fixture.model.autoHidesUndo)
    }

    /// 直すシートから消した記録は、「取り消す」の対象からも外す（消えた記録を取り消そうとしないように）。
    @Test func deletingFromEditSheetRemovesUndoTarget() async throws {
        let fixture = try Fixture()
        await fixture.send("スーパー2480、ドラッグ1200")
        let supermarket = try #require(try fixture.entries().first)
        fixture.model.presentEdit(supermarket, calendar: TestSupport.calendar)
        let editing = try #require(fixture.model.editing)

        #expect(editing.delete())

        #expect(try fixture.entries().map(\.amount) == [1_200])
        #expect(fixture.model.justRecorded.map(\.amount) == [1_200])
        // 残った記録は、まだ取り消せる。
        fixture.model.undoLastRecord()
        #expect(try fixture.entries().isEmpty)
    }

    /// 直すシートで保存に失敗したら、シートは開いたまま（ホームの失敗のアラートは出さない）、「取り消す」も残す。
    @Test func editSaveFailureKeepsUndo() async throws {
        let fixture = try Fixture()
        await fixture.send("ランチ 850")
        let entry = try #require(try fixture.entries().first)
        fixture.model.presentEdit(entry, calendar: TestSupport.calendar)
        let editing = try #require(fixture.model.editing)
        editing.amountText = "900"
        fixture.failsSave = true

        #expect(!editing.save())

        #expect(editing.failure == .save)
        #expect(fixture.model.storeFailure == nil)
        #expect(fixture.model.editing != nil)
        #expect(fixture.model.canUndo)
        #expect(try fixture.entries().map(\.amount) == [850])
    }

    // MARK: - 設定

    @Test func presentSettingsOpensSettings() throws {
        let fixture = try Fixture()
        #expect(fixture.model.settings == nil)

        fixture.model.presentSettings()

        let settings = try #require(fixture.model.settings)
        #expect(settings.exportPeriod == .thisMonth)
        #expect(settings.budgetSetup == nil)
    }

    // MARK: - 月のまとめ

    /// 帯の今月の合計を押すと、今月のまとめへ進む（帯と同じ月・同じ合計）。
    @Test func presentMonthlyReportOpensCurrentMonth() async throws {
        let fixture = try Fixture()
        await fixture.send("ランチ 850")
        #expect(fixture.model.monthlyReport == nil)

        fixture.model.presentMonthlyReport(calendar: TestSupport.calendar)

        let report = try #require(fixture.model.monthlyReport)
        #expect(report.month.start == TestSupport.date(2026, 9, 1))
        #expect(report.report?.expense == 850)
        // 開いただけでは「取り消す」は残る（戻ってからも取り消せる）。
        #expect(fixture.model.canUndo)
    }

    /// まとめの一覧から消した記録は、ホームの「取り消す」の対象からも外す（戻ったあとで消えた記録を取り消そうとしないように）。
    @Test func deletingFromMonthlyReportRemovesUndoTarget() async throws {
        let fixture = try Fixture()
        await fixture.send("スーパー2480、ドラッグ1200")
        let supermarket = try #require(try fixture.entries().first)
        fixture.model.presentMonthlyReport(calendar: TestSupport.calendar)
        let report = try #require(fixture.model.monthlyReport)

        report.presentEdit(supermarket)
        #expect(try #require(report.editing).delete())

        #expect(fixture.model.justRecorded.map(\.amount) == [1_200])
        #expect(report.report?.expense == 1_200)
    }

    /// まとめの一覧から直前の記録を直したら、ホームから直したときと同じく「取り消す」を引っ込める。
    @Test func editingFromMonthlyReportDismissesUndo() async throws {
        let fixture = try Fixture()
        await fixture.send("ドラッグ1200")
        let drug = try #require(try fixture.entries().first)
        fixture.model.presentMonthlyReport(calendar: TestSupport.calendar)
        let report = try #require(fixture.model.monthlyReport)

        report.presentEdit(drug)
        let editing = try #require(report.editing)
        editing.category = .medical
        #expect(editing.save())

        #expect(!fixture.model.canUndo)
        #expect(report.report?.breakdown.item(for: .medical)?.amount == 1_200)
    }

    // MARK: - 予算

    /// 帯のボタンで「予算を決める」を開く。予算を決めていなければ空欄で開く。
    @Test func presentBudgetSetupOpensEmptyForm() throws {
        let fixture = try Fixture()
        #expect(fixture.model.budgetSetup == nil)

        fixture.model.presentBudgetSetup()

        let setup = try #require(fixture.model.budgetSetup)
        #expect(setup.totalText.isEmpty)
        #expect(!setup.hadTotalBudget)
        // カテゴリ別の予算（プレミアム）は、無料では出さない。
        #expect(!setup.showsCategoryBudgets)
    }

    /// 保存した予算は、次に開いたときの入力欄に入っている（「予算を変更」でも同じ画面を使う）。
    @Test func savedBudgetIsShownNextTime() throws {
        let fixture = try Fixture()
        fixture.model.presentBudgetSetup()
        let setup = try #require(fixture.model.budgetSetup)
        setup.selectQuickAmount(150_000)

        #expect(setup.save())
        // シートを閉じると、画面が nil に戻す。
        fixture.model.budgetSetup = nil

        #expect(try BudgetStore(context: fixture.context).plan().total == 150_000)
        #expect(fixture.announcements.last?.contains("¥150,000") == true)
        fixture.model.presentBudgetSetup()
        #expect(fixture.model.budgetSetup?.totalText == "150,000")
        #expect(fixture.model.budgetSetup?.hadTotalBudget == true)
    }

    /// 予算の保存は記録と同じ保存先に書く。送信の書き込みとして数えない（同期的に書き込むので、開き直しを待たせない）。
    @Test func budgetSaveDoesNotCountAsPendingWrite() throws {
        let fixture = try Fixture()
        fixture.model.presentBudgetSetup()
        let setup = try #require(fixture.model.budgetSetup)
        setup.totalText = "120,000"

        #expect(setup.save())

        #expect(fixture.pendingWrites.count == 0)
        #expect(try fixture.context.fetchCount(FetchDescriptor<Budget>()) == 1)
    }

    // MARK: - プレミアム

    /// プレミアムの状態を決めたホーム（StoreKit を使わない）。設定の領域は使い捨て。
    @MainActor
    final class PremiumFixture {
        let context: ModelContext
        let suiteName = "HomeModelTests.\(UUID().uuidString)"
        let defaults: UserDefaults
        let purchases: PurchaseManager
        let model: HomeModel

        init(_ records: [PremiumPurchase], load: Bool = true) async throws {
            context = try TestSupport.makeContext()
            defaults = try #require(UserDefaults(suiteName: suiteName))
            purchases = await TestSupport.purchases(records, load: load)
            model = HomeModel(
                store: EntryStore(context: context), purchases: purchases, defaults: defaults,
                now: { TestSupport.now }, announce: { _ in }
            )
        }

        func cleanUp() {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    /// カテゴリ別の予算は、プレミアムと体験中だけ出す。体験が終わったら出さない。
    @Test(arguments: [
        ([PremiumPurchase](), false),
        ([TestSupport.trial(startedDaysAgo: 3)], true),
        ([TestSupport.trial(startedDaysAgo: 20)], false),
        ([PremiumPurchase(product: .premium, purchaseDate: TestSupport.now)], true),
        ([PremiumPurchase(product: .premium, ownership: .familyShared, purchaseDate: TestSupport.now)], true),
    ])
    func categoryBudgetsFollowPremium(records: [PremiumPurchase], expected: Bool) async throws {
        let fixture = try await PremiumFixture(records)
        defer { fixture.cleanUp() }

        fixture.model.presentBudgetSetup()

        #expect(fixture.model.budgetSetup?.showsCategoryBudgets == expected)
    }

    /// 設定にも同じ PurchaseManager を渡す（設定から開く予算の画面・プレミアムのシートが同じ状態を見る）。
    @Test func settingsShareSamePurchases() async throws {
        let fixture = try await PremiumFixture([TestSupport.trial(startedDaysAgo: 1)])
        defer { fixture.cleanUp() }

        fixture.model.presentSettings()

        let settings = try #require(fixture.model.settings)
        #expect(settings.purchases === fixture.purchases)
        settings.presentBudgetSetup()
        #expect(settings.budgetSetup?.showsCategoryBudgets == true)
    }

    /// 体験が終わった後の最初の起動で一度だけ出し、二度と出さない。
    @Test func trialEndedPremiumIsShownOnce() async throws {
        let fixture = try await PremiumFixture([TestSupport.trial(startedDaysAgo: 15)])
        defer { fixture.cleanUp() }

        fixture.model.presentPremiumIfTrialEnded()

        #expect(fixture.model.premiumSheet != nil)
        #expect(fixture.defaults.bool(for: AppSettings.hasShownTrialEndedPremium))

        // 閉じた後、前面に戻っても、次の起動（新しいホーム）でも出さない。
        fixture.model.premiumSheet = nil
        fixture.model.presentPremiumIfTrialEnded()
        #expect(fixture.model.premiumSheet == nil)
        let relaunched = HomeModel(
            store: EntryStore(context: fixture.context), purchases: fixture.purchases, defaults: fixture.defaults,
            now: { TestSupport.now }, announce: { _ in }
        )
        relaunched.presentPremiumIfTrialEnded()
        #expect(relaunched.premiumSheet == nil)
    }

    /// 体験中・無料（体験の前）・プレミアムでは出さない。
    @Test(arguments: [
        [PremiumPurchase](),
        [TestSupport.trial(startedDaysAgo: 13)],
        [TestSupport.trial(startedDaysAgo: 20), PremiumPurchase(product: .premium, purchaseDate: TestSupport.now)],
    ])
    func trialEndedPremiumIsNotShownOtherwise(records: [PremiumPurchase]) async throws {
        let fixture = try await PremiumFixture(records)
        defer { fixture.cleanUp() }

        fixture.model.presentPremiumIfTrialEnded()

        #expect(fixture.model.premiumSheet == nil)
        #expect(!fixture.defaults.bool(for: AppSettings.hasShownTrialEndedPremium))
    }

    /// 購入の事実を読み終える前は、無料と見分けがつかないので出さない。読み終えたら出す。
    @Test func trialEndedPremiumWaitsForPurchasesToLoad() async throws {
        let fixture = try await PremiumFixture([TestSupport.trial(startedDaysAgo: 15)], load: false)
        defer { fixture.cleanUp() }

        fixture.model.presentPremiumIfTrialEnded()
        #expect(fixture.model.premiumSheet == nil)

        await fixture.purchases.refreshPurchases()
        fixture.model.presentPremiumIfTrialEnded()
        #expect(fixture.model.premiumSheet != nil)
    }

    /// ほかのシートや画面を出しているときは重ねて出さず、閉じた後に出す（出したことにもしない）。
    @Test func trialEndedPremiumWaitsForOtherScreens() async throws {
        let fixture = try await PremiumFixture([TestSupport.trial(startedDaysAgo: 15)])
        defer { fixture.cleanUp() }
        fixture.model.presentBudgetSetup()

        fixture.model.presentPremiumIfTrialEnded()

        #expect(fixture.model.premiumSheet == nil)
        #expect(!fixture.defaults.bool(for: AppSettings.hasShownTrialEndedPremium))

        fixture.model.budgetSetup = nil
        fixture.model.presentPremiumIfTrialEnded()
        #expect(fixture.model.premiumSheet != nil)
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
