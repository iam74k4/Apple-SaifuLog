import Foundation
import SaifuLogCore
import SwiftData
import Testing
@testable import SaifuLog

/// タイムラインの送信のまとめ方（`EntrySend`）。ホームから記録を送って保存先に入れ、画面と同じ読み方（記録した日時の新しい方から
/// 件数で区切って読み、古い順に並べ直す）で 1 回の送信ごとにまとまることを確かめる。まとめ方の決め事はコアの `TimelineSend`
/// （`swift test`）で、ここでは記録のモデル・保存先・直すシート・レシートを通した形を見る。
@MainActor
struct EntrySendTests {
    typealias Fixture = HomeModelTests.Fixture

    /// 画面と同じ読み方で、保存先の記録を送信にまとめる。
    static func sends(_ fixture: Fixture, limit: Int = HomeModel.timelinePageSize) throws -> [EntrySend] {
        let entries = try fixture.context.fetch(Entry.timelineDescriptor(limit: limit))
        return EntrySend.sends(from: Array(entries.reversed()))
    }

    /// 送信ごとの金額（送信の中は書いた順）。
    static func amounts(_ sends: [EntrySend]) -> [[Int]] {
        sends.map { $0.entries.map(\.amount) }
    }

    @Test("1 行に複数件を書いた送信は 1 つの送信になり、同じ文を数秒あけてもう一度送ると別の送信になる")
    func multiItemSendAndRepeatedText() async throws {
        let fixture = try Fixture()
        await fixture.send("スーパー2480、ドラッグ1200")
        fixture.now = TestSupport.now.addingTimeInterval(5)
        await fixture.send("スーパー2480、ドラッグ1200")

        let sends = try Self.sends(fixture)

        #expect(Self.amounts(sends) == [[2_480, 1_200], [2_480, 1_200]])
        #expect(sends.map(\.originalText) == ["スーパー2480、ドラッグ1200", "スーパー2480、ドラッグ1200"])
        #expect(sends.map(\.source) == [.text, .text])
        #expect(sends.map(\.sentAt) == [TestSupport.now, TestSupport.now.addingTimeInterval(5)])
        // 送信の ID は、送信のいちばん古い記録の ID。
        #expect(sends.map(\.id) == sends.map { $0.entries[0].persistentModelID })
    }

    @Test("直した記録も、1 件を消した残りも、同じ送信のまま")
    func editedAndPartlyDeletedSendStaysTogether() async throws {
        let fixture = try Fixture()
        await fixture.send("スーパー2480、ドラッグ1200 コーヒー400")
        let entries = try fixture.entries()
        #expect(entries.map(\.amount) == [2_480, 1_200, 400])

        // 2 件目の金額・品目・カテゴリ・日付を直す（記録した日時・送った文・入力元は直さない）。
        fixture.model.presentEdit(entries[1], calendar: TestSupport.calendar)
        let editing = try #require(fixture.model.editing)
        editing.amountText = "1,280"
        editing.memo = "ドラッグストア"
        editing.category = .medical
        editing.day = TestSupport.date(2026, 9, 26)
        #expect(editing.save())
        fixture.model.editing = nil

        #expect(Self.amounts(try Self.sends(fixture)) == [[2_480, 1_280, 400]])

        // 1 件目を消す。
        fixture.model.requestDelete(entries[0])
        fixture.model.delete(try #require(fixture.model.pendingDeletion))

        let sends = try Self.sends(fixture)
        #expect(Self.amounts(sends) == [[1_280, 400]])
        #expect(sends.map(\.originalText) == ["スーパー2480、ドラッグ1200 コーヒー400"])
    }

    @Test("声で入れた文の送信は、入力元が声の 1 つの送信")
    func voiceSendKeepsItsSource() async throws {
        let fixture = try Fixture(voice: VoiceInputModel(transcriber: FakeVoiceTranscriber()))
        // 書き起こした文を入力欄に入れる（マイクで聞いて止めたときと同じ入れ方。`HomeModelVoiceTests`）。
        fixture.model.voice.insertTranscript("コーヒー 480 パン 320")
        #expect(fixture.model.draftSource == .voice)
        await fixture.model.send(calendar: TestSupport.calendar)?.value

        let sends = try Self.sends(fixture)

        #expect(Self.amounts(sends) == [[480, 320]])
        #expect(sends.map(\.source) == [.voice])
    }

    @Test("レシートから記録した品目は 1 つの送信（入力元はレシート、送った文は店名と合計の要約）")
    func receiptIsOneSend() async throws {
        let fixture = try Fixture()
        await fixture.send("ランチ 850")
        fixture.now = TestSupport.now.addingTimeInterval(60)
        let result = try await HomeModelReceiptTests.read(fixture)
        result.requestRecord()

        let sends = try Self.sends(fixture)

        #expect(Self.amounts(sends) == [[850], [198, 298]])
        #expect(sends.map(\.source) == [.text, .receipt])
        #expect(sends.last?.originalText == String(localized: "レシート: イオン 渋谷店 合計 ¥496"))
    }

    @Test("読み込みの件数の区切りで前の件が切れたいちばん古い送信は、読み込んだ件だけの送信になる")
    func pageLimitCutsTheOldestSend() async throws {
        let fixture = try Fixture()
        await fixture.send("スーパー2480、ドラッグ1200 コーヒー400")
        fixture.now = TestSupport.now.addingTimeInterval(60)
        await fixture.send("ランチ 850")

        #expect(Self.amounts(try Self.sends(fixture, limit: 3)) == [[1_200, 400], [850]])
    }
}
