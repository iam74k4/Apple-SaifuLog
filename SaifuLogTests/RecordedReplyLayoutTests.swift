import SaifuLogCore
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import SaifuLog

/// タイムラインの返事のカード（「記録しました」）の並べ方。
///
/// 品目と金額（`SplitRowLayout`）は、1 行に収まるときだけ横に並べて金額を行の右の端に置き、収まらなければ金額を品目の下の行の
/// 右の端に置く。品目が折り返すほど長いのに横に並べると、金額が品目の 1 行目の右に並び、「…総額」「¥3,000」のように続けて
/// 読めてしまうため（吹き出しの `EntryTitleAmountRow` と同じ選び方）。SwiftUI に測らせた大きさと、品目を赤・金額を青で描いた
/// 画像の画素で確かめる（`EntryBubbleLayoutTests` と同じ確かめ方）。
///
/// 見出しの高さが「取り消す」の有無で変わらないこと（次の文を送ると前の返事の「取り消す」が消えるので、変わるとその瞬間に
/// タイムラインの行がずれて見える）も、実際のカードを測って確かめる。
@MainActor
struct RecordedReplyLayoutTests {
    /// 撮影用のデモの割り勘の記録と同じ品目（2 行以上に折り返す長さ）。
    static let longMemo = "焼肉（4人で割り勘・総額 ¥12,000・立替 ¥9,000）"
    /// 6.3 インチの iPhone（幅 402pt）の返事のカードで、品目と金額の行に使える幅のおよその値。
    static let rowWidth: CGFloat = 230

    @Test("品目と金額が 1 行に収まれば横に並べて幅いっぱいを使い、収まらなければ縦に積む（大きさの決まった部品で）")
    func stacksOnlyWhenTheRowDoesNotFit() {
        // 100 + 8 + 60 = 168 ≤ 200 なので横に並ぶ（高さは 1 行分、幅は提案された幅いっぱい）。
        let fits = Self.size(of: Self.standInRow(titleWidth: 100), width: 200)
        #expect(fits == CGSize(width: 200, height: 20))
        // 150 + 8 + 60 = 218 > 200 なので縦に積む（品目 + 間 + 金額）。
        let stacked = Self.size(of: Self.standInRow(titleWidth: 150), width: 200)
        #expect(stacked.height == CGFloat(20 + 2 + 20))
        // 改行の入った品目は、収まっても縦に積む。
        let multiline = Self.size(of: Self.standInRow(titleWidth: 100, alwaysStacks: true), width: 200)
        #expect(multiline.height == CGFloat(20 + 2 + 20))
    }

    @Test("短い品目は金額と 1 行に並べ、品目は左の端・金額は右の端")
    func shortMemoStaysOnOneLine() throws {
        let image = try #require(Self.render(Self.coloredRow(memo: "ランチ", amount: "¥850"), width: Self.rowWidth))
        let memo = try #require(image.bounds(of: .title))
        let amount = try #require(image.bounds(of: .amount))
        #expect(amount.minY < memo.maxY && memo.minY < amount.maxY)
        #expect(memo.minX <= 4)
        #expect(amount.maxX >= image.width - 4)
    }

    @Test("長い品目は折り返し、金額は品目の下の行の右の端に置く")
    func longMemoPutsTheAmountOnItsOwnLine() throws {
        let image = try #require(Self.render(Self.coloredRow(memo: Self.longMemo, amount: "¥3,000"), width: Self.rowWidth))
        let memo = try #require(image.bounds(of: .title))
        let amount = try #require(image.bounds(of: .amount))
        // 前提: 品目が 2 行以上に折り返している（金額の行の高さの倍を超える）。
        #expect(memo.height > amount.height * 2)
        // 金額は品目のどの行とも重ならず、その下にある。
        #expect(amount.minY > memo.maxY)
        #expect(amount.maxX >= image.width - 4)
    }

    @Test("アクセシビリティサイズの文字（AX5）では、収まらない金額を品目の下の行に移す（金額は 1 行のまま）")
    func largestTextMovesTheAmountDown() throws {
        let row = Self.coloredRow(memo: "スーパー", amount: "¥12,380")
        let image = try #require(Self.render(row, width: 338, dynamicTypeSize: .accessibility5))
        let memo = try #require(image.bounds(of: .title))
        let amount = try #require(image.bounds(of: .amount))
        #expect(amount.minY > memo.maxY)
        // 金額は折り返さない（1 行の高さ。品目の 1 行の高さの 1.5 倍より低い）。
        #expect(Double(amount.height) < Double(memo.height) * 1.5)
    }

    @Test("返事のカードの高さは「取り消す」の有無で変わらない（標準の文字）")
    func undoButtonDoesNotChangeTheCardHeight() throws {
        let context = try TestSupport.makeContext()
        let entry = TestSupport.entry(memo: "ランチ", spentAt: TestSupport.now, createdAt: TestSupport.now)
        context.insert(entry)
        try context.save()
        let send = try #require(EntrySend.sends(from: [entry]).first)

        let withUndo = Self.size(of: Self.card(send, canUndo: true), width: 370)
        let withoutUndo = Self.size(of: Self.card(send, canUndo: false), width: 370)

        #expect(withUndo.height == withoutUndo.height)
    }

    /// 割り勘の記録は、品目（「焼肉」）だけを見出しにし、説明を文にして行の下に添える。見出しが短くなるので、金額は品目と同じ行に
    /// 並ぶ（長いメモのまま見出しにすると、金額が品目の下の行に落ちる）。メモか金額を直した記録は、メモをそのまま見出しにする。
    @Test("割り勘の記録は品目だけを見出しにして説明の文を行の下に添え、直した記録はメモのまま")
    func splitRowShowsItemAndNote() throws {
        let context = try TestSupport.makeContext()
        let split = TestSupport.entry(amount: 3_000, memo: Self.longMemo)
        let plain = TestSupport.entry(amount: 3_000, memo: "焼肉", createdAt: TestSupport.now.addingTimeInterval(60))
        // 金額だけを直した記録（説明の額と合わない）。
        let edited = TestSupport.entry(amount: 3_500, memo: Self.longMemo, createdAt: TestSupport.now.addingTimeInterval(120))
        for entry in [split, plain, edited] { context.insert(entry) }
        try context.save()

        #expect(RecordedReplyRow.text(of: split).item == "焼肉")
        #expect(RecordedReplyRow.text(of: split).note == "¥12,000 を4人で割り勘。立て替えた ¥9,000 はメモに残しました。")
        #expect(RecordedReplyRow.text(of: plain).item == "焼肉")
        #expect(RecordedReplyRow.text(of: plain).note == nil)
        #expect(RecordedReplyRow.text(of: edited).item == Self.longMemo)
        #expect(RecordedReplyRow.text(of: edited).note == nil)

        let sends = EntrySend.sends(from: [split, plain, edited])
        #expect(sends.count == 3)
        let heights = sends.map { Self.size(of: Self.card($0, canUndo: false), width: 370).height }
        // 説明の文の分だけ、品目だけの記録のカードより高い。
        #expect(heights[0] > heights[1])
    }

    /// 直前の送信の返事（「取り消す」を出している間）には、最後に今月の状況の一行を足す。一行は今月の記録と予算を保存先から読む。
    @Test("直前の送信の返事には、今月の状況の一行を足す（前の送信の返事には足さない）")
    func latestReplyAddsStatusLine() throws {
        let context = try TestSupport.makeContext()
        let entry = TestSupport.entry(memo: "ランチ", spentAt: TestSupport.now, createdAt: TestSupport.now)
        context.insert(entry)
        try context.save()
        let send = try #require(EntrySend.sends(from: [entry]).first)

        let latest = Self.size(
            of: Self.card(send, canUndo: true, showsStatus: true).modelContainer(context.container), width: 370
        )
        let earlier = Self.size(of: Self.card(send, canUndo: false).modelContainer(context.container), width: 370)

        // 一行（標準の文字で 20pt ほど）と区切りの線と間の分だけ高い。
        #expect(latest.height > earlier.height + 20)
    }

    // MARK: - 部品

    private static func card(_ send: EntrySend, canUndo: Bool, showsStatus: Bool = false) -> some View {
        RecordedReplyCard(
            send: send, today: TestSupport.now, canUndo: canUndo, showsStatus: showsStatus, undo: {}, edit: { _ in },
            requestDelete: { _ in }
        )
    }

    /// 品目を赤、金額を青で描いた行（字の形は返事の行と同じ）。
    private static func coloredRow(memo: String, amount: String) -> some View {
        SplitRowLayout(spacing: 8, stackedSpacing: 2, alwaysStacks: memo.contains(where: \.isNewline)) {
            Text(verbatim: memo)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color(red: 1, green: 0, blue: 0))
            Text(verbatim: amount)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color(red: 0, green: 0, blue: 1))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }

    /// 品目の代わりに赤、金額の代わりに青の、高さ 20 の四角を並べた行。
    private static func standInRow(titleWidth: CGFloat, alwaysStacks: Bool = false) -> some View {
        SplitRowLayout(spacing: 8, stackedSpacing: 2, alwaysStacks: alwaysStacks) {
            Color(red: 1, green: 0, blue: 0).frame(width: titleWidth, height: 20)
            Color(red: 0, green: 0, blue: 1).frame(width: 60, height: 20)
        }
    }

    /// 文字の大きさと言語を決めて、幅 `width` を与えたときの大きさを SwiftUI に測らせる。
    private static func size(of view: some View, width: CGFloat) -> CGSize {
        UIHostingController(rootView: fixedEnvironment(view, dynamicTypeSize: .large))
            .sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
    }

    private static func render(_ view: some View, width: CGFloat, dynamicTypeSize: DynamicTypeSize = .large) -> RGBAImage? {
        let renderer = ImageRenderer(content: fixedEnvironment(view, dynamicTypeSize: dynamicTypeSize))
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        renderer.scale = 1
        return renderer.cgImage.flatMap(RGBAImage.init)
    }

    private static func fixedEnvironment(_ view: some View, dynamicTypeSize: DynamicTypeSize) -> some View {
        view
            .environment(\.dynamicTypeSize, dynamicTypeSize)
            .environment(\.locale, Locale(identifier: "ja_JP"))
            .environment(\.calendar, TestSupport.calendar)
    }
}
