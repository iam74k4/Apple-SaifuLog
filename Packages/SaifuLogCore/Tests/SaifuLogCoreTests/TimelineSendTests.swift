import Foundation
import Testing
@testable import SaifuLogCore

@Suite("タイムラインの送信のまとめ方")
struct TimelineSendTests {
    /// 入力元（アプリの `EntrySource` の代わり）。
    enum Source: Hashable {
        case text, voice, receipt
    }

    /// 保存した記録の代わり。直すのは金額・品目・カテゴリ・使った日時で、記録した日時・元の文・入力元は直さない
    /// （`EntryStore.update`）。
    struct StoredEntry {
        var id: Int
        var originalText: String
        var source: Source
        var createdAt: Date
        var amount: Int
        var memo: String
        var category: EntryCategory
        var spentAt: Date

        var record: TimelineSend.Record<Int, Source> {
            TimelineSend.Record(id: id, originalText: originalText, source: source, createdAt: createdAt)
        }
    }

    /// 1 回の送信を、アプリと同じく `ParsedEntry.timestamps` で日時を振って記録にする（ID は `firstID` から順に）。
    static func send(
        _ text: String, _ parsed: [ParsedEntry], source: Source = .text, at sentAt: Date, firstID: Int
    ) -> [StoredEntry] {
        zip(parsed, ParsedEntry.timestamps(for: parsed, now: sentAt, calendar: Fixture.calendar)).enumerated().map { offset, pair in
            StoredEntry(
                id: firstID + offset, originalText: text, source: source, createdAt: pair.1.createdAt,
                amount: pair.0.amount, memo: pair.0.memo, category: pair.0.category, spentAt: pair.1.spentAt
            )
        }
    }

    /// まとめた結果を、記録の ID の組で返す。
    static func groupedIDs(_ entries: [StoredEntry]) -> [[Int]] {
        TimelineSend.groups(of: entries.map(\.record)).map { $0.map(\.id) }
    }

    @Test("1 行に複数件を書いた送信は、1 つの送信にまとまる")
    func multiItemLineIsOneSend() async throws {
        let text = "スーパー2480、ドラッグ1200 コーヒー400"
        let parsed = try await Fixture.parser.parse(text)
        #expect(parsed.count == 3)

        let entries = Self.send(text, parsed, at: Fixture.now, firstID: 1)

        #expect(Self.groupedIDs(entries) == [[1, 2, 3]])
        #expect(TimelineSend.groupRanges(of: entries.map(\.record)) == [0..<3])
    }

    @Test("同じ文を数秒あけて 2 回送ると、2 つの送信になる（1 行に複数件の文も）")
    func sameTextSentTwiceIsTwoSends() {
        let lunch = [ParsedEntry(amount: 850, category: .food, memo: "ランチ")]
        let first = Self.send("ランチ 850", lunch, at: Fixture.now, firstID: 1)
        let second = Self.send("ランチ 850", lunch, at: Fixture.now.addingTimeInterval(4), firstID: 2)
        #expect(Self.groupedIDs(first + second) == [[1], [2]])

        let breakfast = [
            ParsedEntry(amount: 480, category: .cafe, memo: "コーヒー"),
            ParsedEntry(amount: 320, category: .food, memo: "パン"),
        ]
        let morning = Self.send("コーヒー 480 パン 320", breakfast, at: Fixture.now, firstID: 10)
        let again = Self.send("コーヒー 480 パン 320", breakfast, at: Fixture.now.addingTimeInterval(2), firstID: 20)
        #expect(Self.groupedIDs(morning + again) == [[10, 11], [20, 21]])
    }

    @Test("レシートの品目は 1 つの送信にまとまる。同じ要約の文でも、入力元が違えば別の送信")
    func receiptItemsAreOneSend() {
        let summary = "レシート: イオン 渋谷店 合計 ¥496"
        let items = [
            ParsedEntry(amount: 198, category: .food, memo: "牛乳"),
            ParsedEntry(amount: 298, category: .daily, memo: "ティッシュ"),
        ]
        let receipt = Self.send(summary, items, source: .receipt, at: Fixture.now, firstID: 1)
        #expect(Self.groupedIDs(receipt) == [[1, 2]])

        // 入力元だけが違う記録（ひとこと入力で同じ文を、記録した日時の近くに送った形）は、続けてもまとめない。
        var typed = receipt[1]
        typed.id = 3
        typed.source = .text
        typed.createdAt = receipt[1].createdAt.addingTimeInterval(0.001)
        #expect(Self.groupedIDs(receipt + [typed]) == [[1, 2], [3]])
    }

    @Test("元の文が違えば、記録した日時が近くても別の送信")
    func differentTextIsAnotherSend() {
        let entries = [
            StoredEntry(
                id: 1, originalText: "ランチ 850", source: .text, createdAt: Fixture.now, amount: 850, memo: "ランチ",
                category: .food, spentAt: Fixture.now
            ),
            StoredEntry(
                id: 2, originalText: "コーヒー 400", source: .text, createdAt: Fixture.now.addingTimeInterval(0.001),
                amount: 400, memo: "コーヒー", category: .cafe, spentAt: Fixture.now
            ),
        ]
        #expect(Self.groupedIDs(entries) == [[1], [2]])
    }

    @Test("送信のうち 1 件を消しても、残りは同じ送信のまま（途中・先頭・最後のどれを消しても）")
    func deletingOneItemKeepsTheRest() async throws {
        let text = "スーパー2480、ドラッグ1200 コーヒー400"
        let entries = Self.send(text, try await Fixture.parser.parse(text), at: Fixture.now, firstID: 1)
        let next = Self.send(
            "ランチ 850", [ParsedEntry(amount: 850, category: .food, memo: "ランチ")], at: Fixture.now.addingTimeInterval(60),
            firstID: 4
        )

        for removed in 0..<entries.count {
            var remaining = entries
            remaining.remove(at: removed)
            let expected = remaining.map(\.id)
            #expect(Self.groupedIDs(remaining + next) == [expected, [4]], "\(removed) 件目を消したとき")
        }
    }

    @Test("直した記録も、同じ送信のまま（直すのは金額・品目・カテゴリ・使った日時で、記録した日時と元の文は変えない）")
    func editedItemStaysInItsSend() async throws {
        let text = "スーパー2480、ドラッグ1200 コーヒー400"
        var entries = Self.send(text, try await Fixture.parser.parse(text), at: Fixture.now, firstID: 1)
        let before = Self.groupedIDs(entries)

        entries[1].amount = 1_280
        entries[1].memo = "ドラッグストア"
        entries[1].category = .medical
        entries[1].spentAt = Fixture.date(2026, 9, 26, hour: 19)

        #expect(Self.groupedIDs(entries) == before)
        #expect(before == [[1, 2, 3]])
    }

    @Test("読み込みの件数の区切りで前の件が切れたいちばん古い送信は、読み込んだ件だけの送信になる")
    func pageLimitCutsTheOldestSend() async throws {
        let text = "スーパー2480、ドラッグ1200 コーヒー400"
        let multi = Self.send(text, try await Fixture.parser.parse(text), at: Fixture.now, firstID: 1)
        let lunch = Self.send(
            "ランチ 850", [ParsedEntry(amount: 850, category: .food, memo: "ランチ")], at: Fixture.now.addingTimeInterval(60),
            firstID: 4
        )
        let cafe = Self.send(
            "カフェ 520", [ParsedEntry(amount: 520, category: .cafe, memo: "カフェ")], at: Fixture.now.addingTimeInterval(120),
            firstID: 5
        )
        let all = multi + lunch + cafe

        // タイムラインは記録した日時の新しい方から件数で区切って読み、古い順に並べ直す（新しい 4 件）。
        let loaded = Array(all.suffix(4))

        #expect(Self.groupedIDs(loaded) == [[2, 3], [4], [5]])
    }

    /// 日時は 2001 年からの秒を浮動小数点で持つので、上限ちょうどの間は丸めでどちらにも転ぶ。上限の少し手前と少し先で確かめる
    /// （実際の送信の中の間は 1 ミリ秒ずつで、別の送信の間は秒の単位なので、上限の近くには来ない）。
    @Test("記録した日時の間が上限より短ければ同じ送信、上限より長ければ別の送信")
    func gapBoundary() {
        func entry(_ id: Int, at offset: TimeInterval) -> StoredEntry {
            StoredEntry(
                id: id, originalText: "コーヒー 480 パン 320", source: .voice, createdAt: Fixture.now.addingTimeInterval(offset),
                amount: 480, memo: "コーヒー", category: .cafe, spentAt: Fixture.now
            )
        }
        #expect(Self.groupedIDs([entry(1, at: 0), entry(2, at: TimelineSend.maximumGap - 0.001)]) == [[1, 2]])
        #expect(Self.groupedIDs([entry(1, at: 0), entry(2, at: TimelineSend.maximumGap + 0.001)]) == [[1], [2]])
        // 間は続いた 2 件ごとに見る（1 回の送信の件が多くても、最初の件からの間では区切らない）。
        let chained = (0..<5).map { entry($0 + 1, at: Double($0) * TimelineSend.maximumGap * 0.9) }
        #expect(Self.groupedIDs(chained) == [[1, 2, 3, 4, 5]])
    }

    @Test("記録した日時が前の記録より前（並べ方が違う）なら、同じ送信にしない")
    func outOfOrderIsNotContinued() {
        let later = StoredEntry(
            id: 1, originalText: "ランチ 850", source: .text, createdAt: Fixture.now.addingTimeInterval(0.002), amount: 850,
            memo: "ランチ", category: .food, spentAt: Fixture.now
        )
        var earlier = later
        earlier.id = 2
        earlier.createdAt = Fixture.now
        #expect(Self.groupedIDs([later, earlier]) == [[1], [2]])
    }

    @Test("記録が無ければ、送信も無い")
    func emptyHasNoSends() {
        let records: [TimelineSend.Record<Int, Source>] = []
        #expect(TimelineSend.groupRanges(of: records).isEmpty)
        #expect(TimelineSend.groups(of: records).isEmpty)
    }
}
