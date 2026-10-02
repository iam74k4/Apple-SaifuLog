import Foundation
import SaifuLogCore
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import SaifuLog

/// ホームを開いたとき、いちばん新しい行（送信の返事のカード・質問の回答カード・先週のふりかえり・家計の記録）がタイムラインの
/// 下の端に見えること。
///
/// 大きな文字でタイムラインが空に見えた不具合の再発を防ぐ。行の高さがそろわないタイムラインを LazyVStack で下端に合わせると、
/// 見積もった全体の高さが揺れて行の無い位置で止まり、空に見えた（`HomeView` の `TimelineScrollView`）。どの文字の大きさで
/// 起きるかは記録の中身と画面の幅で変わるので、行の高さがそろわない撮影用のデモの家計（長い品目の割り勘・1 行に 2 件の送信・
/// 日付の見出しを含む）で、標準からアクセシビリティサイズまで確かめる。自分の記録のタイムラインは会話の形（送った文の吹き出しと
/// 返事のカード）で、いちばん下は最後の送信の返事のカード。
///
/// 部品だけを描くのではなく、ウィンドウに実際のホーム（ナビゲーション・帯・入力欄の中のスクロール）を置き、行と見える範囲が
/// 描かれた位置（`timelineFrameObserver`）で確かめる。下端に合わせる動きと LazyVStack の見積もりの揺れは、スクロールの中に
/// 並べた画面で起きるため（タイムラインを LazyVStack に戻すと、この置き方で AX1 の記録と、標準から AX5 まで（AX4 を除く）の
/// ふりかえりのカードが落ちることを確かめた）。
///
/// 開いた後に足した行（送った記録の返事・質問の回答カード・開いたまま出たふりかえりのカード）も、開いたときと同じく下の余白を
/// 残して下の端に出ることを確かめる。行の id まで送っていたときは余白が隠れ、動きを付けて送ると、同じときに見える範囲の高さが
/// 変わった分だけ下端からずれた（`HomeView` の `TimelineScrollView`）。
///
/// 画面を画像にして目で見るときは、環境変数 `SAIFULOG_TIMELINE_SNAPSHOTS` に書き出す先のフォルダを渡す（xcodebuild には
/// `TEST_RUNNER_SAIFULOG_TIMELINE_SNAPSHOTS=…` で渡す）。`SAIFULOG_TIMELINE_SNAPSHOT_STYLE=dark` でダークにする。
/// 家計の共有は署名の無いビルドのアプリでは始まらないので、家計のタイムラインはこの書き出しで見る。
@MainActor
@Suite(.serialized)
struct HomeTimelineLayoutTests {
    /// 標準・大きな文字（xxLarge・xxxLarge）・アクセシビリティサイズ（AX1〜AX5）。
    nonisolated static let sizes: [UIContentSizeCategory] = [
        .large, .extraExtraLarge, .extraExtraExtraLarge,
        .accessibilityMedium, .accessibilityLarge, .accessibilityExtraLarge, .accessibilityExtraExtraLarge,
        .accessibilityExtraExtraExtraLarge,
    ]

    @Test("開いたとき、いちばん新しい送信の返事のカードがタイムラインの下の端に見える", arguments: sizes)
    func newestSendIsAtTheBottom(size: UIContentSizeCategory) async throws {
        let fixture = try TimelineFixture()
        try fixture.insertDemoLedger()
        fixture.markWeeklyRecapShown()
        let newest = try #require(try fixture.latestSend())
        // 前提: いちばん新しい送信は、1 行に 2 件を書いた送信（返事のカードに 2 件が並ぶ）。
        #expect(newest.entries.map(\.originalText) == [ScreenshotDemoLedger.multiItemText, ScreenshotDemoLedger.multiItemText])

        let frames = try await fixture.host(size: size, name: "entries")

        try Self.expectAtTheBottom(frames, key: .row(newest.id), size: size)
    }

    @Test("質問の回答カードがいちばん下なら、カードが下の端に見える", arguments: sizes)
    func answerCardIsAtTheBottom(size: UIContentSizeCategory) async throws {
        let fixture = try TimelineFixture()
        try fixture.insertDemoLedger()
        fixture.markWeeklyRecapShown()
        fixture.model.draft = "今月カフェいくら?"
        await fixture.model.send(calendar: TestSupport.calendar)?.value
        let exchange = try #require(fixture.model.questions.last)
        // 前提: 答えが出ている（読めない質問の案内ではない）。
        guard case .answered = exchange.state else {
            Issue.record("質問に答えられていません: \(exchange.state)")
            return
        }

        let frames = try await fixture.host(size: size, name: "question")

        try Self.expectAtTheBottom(frames, key: .row(exchange.id), size: size)
    }

    @Test("先週のふりかえりのカードは、出したときにいちばん下で、下の端に見える", arguments: sizes)
    func weeklyRecapCardIsAtTheBottom(size: UIContentSizeCategory) async throws {
        let fixture = try TimelineFixture()
        try fixture.insertDemoLedger()
        // 出した日時を書かずに開く（ホームが出たときに、週が替わって最初に開いたとしてカードを出す）。

        let frames = try await fixture.host(size: size, name: "recap")

        let recap = try #require(fixture.model.weeklyRecap)
        try Self.expectAtTheBottom(frames, key: .row(recap.id), size: size)
    }

    @Test("「家族」のときは、いちばん新しい家計の記録が下の端に見える", arguments: sizes)
    func newestHouseholdEntryIsAtTheBottom(size: UIContentSizeCategory) async throws {
        let fixture = try TimelineFixture(household: true)
        try fixture.insertDemoLedger()
        fixture.markWeeklyRecapShown()
        let newest = try #require(try fixture.insertHouseholdLedger())
        fixture.model.ledgerScope = .household
        #expect(fixture.model.isHouseholdActive)

        let frames = try await fixture.host(size: size, name: "household")

        try Self.expectAtTheBottom(frames, key: .row(newest), size: size)
    }

    /// 開いた後に送ったものを確かめる文字の大きさ（標準・AX1・AX5）。
    nonisolated static let sendSizes: [UIContentSizeCategory] = [
        .large, .accessibilityMedium, .accessibilityExtraExtraExtraLarge,
    ]

    /// 開いた後に送った記録も、開いたときと同じく下の余白（16pt）を残した下の端に出る。行の id まで送ると、行の下の端が
    /// 見える範囲の下の端にそろい、余白が見える範囲の外に隠れた（中身が画面より高いときだけ。`HomeView` の `TimelineScrollView`）。
    /// 送った後は、送った文の吹き出しと「取り消す」つきの返事のカードが足され、前の返事のカードは「取り消す」の無い形のまま
    /// （見出しの高さは変えない）なので、その形のまま確かめる。
    @Test("開いた後に記録を送ると、送った記録の返事のカードが下の余白を残して下の端に見える", arguments: sendSizes)
    func sentEntryIsAtTheBottom(size: UIContentSizeCategory) async throws {
        let fixture = try TimelineFixture()
        try fixture.insertDemoLedger()
        fixture.markWeeklyRecapShown()
        let before = try #require(try fixture.latestSend()).id

        let frames = try await fixture.host(size: size, name: "sent") { opened in
            try Self.expectTallerThanViewport(opened, size: size)
            return try await fixture.send("コンビニ 650")
        }

        let sent = try #require(try fixture.latestSend())
        #expect(sent.id != before)
        #expect(sent.entries.map(\.originalText) == ["コンビニ 650"])
        #expect(fixture.model.canUndo, "送った後に返事の「取り消す」が出ていません（\(size.rawValue)）")
        try Self.expectAtTheBottom(frames, key: .row(sent.id), size: size)
    }

    /// 開いた後に送った質問の回答カードも、下の余白を残した下の端に出る（送ったときと、答えが出てカードが伸びたときに送る）。
    @Test("開いた後に質問を送ると、回答カードが下の余白を残して下の端に見える", arguments: sendSizes)
    func askedAnswerCardIsAtTheBottom(size: UIContentSizeCategory) async throws {
        let fixture = try TimelineFixture()
        try fixture.insertDemoLedger()
        fixture.markWeeklyRecapShown()

        let frames = try await fixture.host(size: size, name: "asked") { opened in
            try Self.expectTallerThanViewport(opened, size: size)
            fixture.model.draft = "今月カフェいくら?"
            await fixture.model.send(calendar: TestSupport.calendar)?.value
            return .row(try #require(fixture.model.questions.last).id)
        }

        let exchange = try #require(fixture.model.questions.last)
        // 前提: 答えが出ている（読めない質問の案内ではない）。
        guard case .answered = exchange.state else {
            Issue.record("質問に答えられていません: \(exchange.state)")
            return
        }
        try Self.expectAtTheBottom(frames, key: .row(exchange.id), size: size)
    }

    /// 開いたまま週が替わってふりかえりのカードが出たときも、下の余白を残して下の端に出る。同じときに見える範囲の高さが変わっても
    /// （ここでは入力欄の上に声の入力の知らせを出す。見える範囲が縮む）。
    /// 動きを付けて送っていたときは、変わった分が下端に合わせ直されず、AX1 と AX5 ではカードが見える範囲の下に 400pt 以上隠れた。
    @Test("開いたままふりかえりのカードが出ると、見える範囲が同時に縮んでも、カードが下の余白を残して下の端に見える", arguments: sendSizes)
    func weeklyRecapShownWhileOpenIsAtTheBottom(size: UIContentSizeCategory) async throws {
        let fixture = try TimelineFixture()
        try fixture.insertDemoLedger()
        // 開いたときは今週もう出したことにして、開いた後に週が替わったとして出す。
        fixture.markWeeklyRecapShown()

        let frames = try await fixture.host(size: size, name: "recap-while-open") { opened in
            try Self.expectTallerThanViewport(opened, size: size)
            #expect(fixture.model.weeklyRecap == nil)
            fixture.defaults.set(nil, for: AppSettings.weeklyRecapShownAt)
            fixture.model.showWeeklyRecapIfDue(calendar: TestSupport.calendar)
            fixture.model.voice.notice = .nothingHeard
            return .row(try #require(fixture.model.weeklyRecap).id)
        }

        let recap = try #require(fixture.model.weeklyRecap)
        // 前提: 知らせが出たまま（画面が 5 秒で引っ込める）。
        #expect(fixture.model.voice.notice == .nothingHeard)
        try Self.expectAtTheBottom(frames, key: .row(recap.id), size: size)
    }

    /// 家計に記録した直後の「記録しました 取り消す」の行は、自分が記録した吹き出しのすぐ下に出る。「取り消す」は次の文を送るまで
    /// 出したままなので、その間に家族の記録が同期で届くことがある。いちばん下の吹き出しの下に出すと、ほかの人の記録の下に並び、
    /// その記録を取り消すように見える（押すと消えるのは自分の記録）。
    @Test("家計に記録した後に家族の記録が届いても、「取り消す」の行は自分が記録した吹き出しのすぐ下に出る", arguments: sendSizes)
    func householdUndoRowStaysUnderOwnRecord(size: UIContentSizeCategory) async throws {
        let fixture = try TimelineFixture(household: true)
        fixture.markWeeklyRecapShown()
        _ = try fixture.insertHouseholdLedger()
        fixture.model.ledgerScope = .household
        fixture.model.draft = "コンビニ 650"
        await fixture.model.send(calendar: TestSupport.calendar)?.value
        let own = try #require(fixture.model.justRecordedHousehold.first)
        #expect(fixture.model.canUndo)
        // 家族の記録が 1 分後に届く（同期で取り込んだ代わりに、家計の保存先へ入れる）。
        let later = try #require(try fixture.insertHouseholdEntry(
            memo: "コーヒー", amount: 400, recorderName: "たろう", createdAt: fixture.now.addingTimeInterval(60)
        ))

        let frames = try await fixture.host(size: size, name: "household-undo")

        let ownRow = try #require(frames[.row(own.id)].flatMap { $0.isNull ? nil : $0 }, "自分の記録が描かれていません（\(size.rawValue)）")
        let laterRow = try #require(frames[.row(later)].flatMap { $0.isNull ? nil : $0 }, "家族の記録が描かれていません（\(size.rawValue)）")
        let undoRow = try #require(
            frames[.householdUndo].flatMap { $0.isNull ? nil : $0 }, "「取り消す」の行が描かれていません（\(size.rawValue)）"
        )
        #expect(ownRow.maxY <= undoRow.minY, "「取り消す」の行が自分の記録の下にありません（\(size.rawValue)）")
        #expect(undoRow.maxY <= laterRow.minY, "「取り消す」の行が家族の記録の下にあります（\(size.rawValue)）")
        // いちばん下は、後から届いた家族の記録（下の余白を残して下の端に見える）。
        try Self.expectAtTheBottom(frames, key: .row(later), size: size)
    }

    /// 前提: 中身が画面より高い（見える範囲より上に行がある）。行の id まで送ったときに下の余白が隠れたのは、この形のときだけ。
    private static func expectTallerThanViewport(
        _ frames: [TimelineFrameKey: CGRect], size: UIContentSizeCategory
    ) throws {
        let viewport = try #require(frames[.viewport], "タイムラインの見える範囲が描かれていません（\(size.rawValue)）")
        let hasRowAbove = frames.contains { key, frame in
            if case .row = key { !frame.isNull && frame.maxY < viewport.minY } else { false }
        }
        #expect(hasRowAbove, "中身が画面より高くありません（\(size.rawValue)）")
    }

    /// 行が見える範囲に描かれ、その下の端が見える範囲の下の端（タイムラインの余白の分だけ上）にある。行が見える範囲より
    /// 高いとき（AX5 のふりかえりのカードなど）も、下の端が見えていればよい。
    private static func expectAtTheBottom(
        _ frames: [TimelineFrameKey: CGRect], key: TimelineFrameKey, size: UIContentSizeCategory
    ) throws {
        let viewport = try #require(frames[.viewport], "タイムラインの見える範囲が描かれていません（\(size.rawValue)）")
        let row = try #require(frames[key].flatMap { $0.isNull ? nil : $0 }, "いちばん新しい行が描かれていません（\(size.rawValue)）")
        #expect(viewport.height > 0)
        #expect(row.intersects(viewport), "いちばん新しい行が見える範囲の外にあります（\(size.rawValue)。行 \(row)・見える範囲 \(viewport)）")
        // タイムラインの余白（`padding()` の 16pt）の分だけ、見える範囲の下の端より上。
        let gap = viewport.maxY - row.maxY
        #expect(abs(gap - 16) <= 1, "いちばん新しい行が下の端にありません（\(size.rawValue)。下の端との間 \(gap)pt）")
    }
}

/// ホームのモデルと、その保存先・家計の受け持ちと、ホームを置くウィンドウ。
@MainActor
private final class TimelineFixture {
    let context: ModelContext
    let suiteName = "HomeTimelineLayoutTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let household: HouseholdFixture?
    /// ホームの「いま」。撮影用のデモの家計の「いま」（2026 年 9 月 15 日 20:30）にそろえる。
    let now = ScreenshotDemo.pinnedNow(on: TestSupport.now, calendar: TestSupport.calendar)
    private(set) var model: HomeModel!

    init(household: Bool = false) throws {
        context = try TestSupport.makeContext()
        defaults = try #require(UserDefaults(suiteName: suiteName))
        self.household = household ? try HouseholdFixture() : nil
        let now = now
        model = HomeModel(
            store: EntryStore(context: context),
            household: self.household?.host,
            defaults: defaults,
            makeParser: { now, calendar in RuleBasedParser(calendar: calendar, now: { now }) },
            makeCategoryRefiner: { nil },
            makeAnswerer: { RuleBasedQuestionAnswerer() },
            makeRemarkWriter: { nil },
            canUseDocumentCamera: true,
            // 端末の書き起こしを使わない（マイクのボタンを出すかを調べるだけでも、音声のフレームワークに問い合わせるため）。
            voice: VoiceInputModel(transcriber: FakeVoiceTranscriber()),
            now: { now },
            announce: { _ in }
        )
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    /// 撮影用のデモの家計（先月の 1 日から「いま」まで毎日の記録と、月の予算）を入れる。
    func insertDemoLedger() throws {
        try ScreenshotDemoLedger.insert(into: context, now: now, calendar: TestSupport.calendar)
    }

    /// 先週のふりかえりを今週はもう出したことにする（記録だけのタイムラインで確かめるため）。
    func markWeeklyRecapShown() {
        defaults.set(now, for: AppSettings.weeklyRecapShownAt)
    }

    /// いちばん新しい送信（タイムラインのいちばん下の返事のカード）。画面と同じく、読み込む件数の記録を送信にまとめて決める。
    func latestSend() throws -> EntrySend? {
        let entries = try context.fetch(Entry.timelineDescriptor(limit: HomeModel.timelinePageSize))
        return EntrySend.sends(from: Array(entries.reversed())).last
    }

    /// 家計を端末に置き、撮影用のデモの記録と同じ品目の家計の記録（家族 2 人が交互に記録したもの）を入れる。いちばん新しく
    /// 記録したものの id を返す。
    func insertHouseholdLedger() throws -> UUID? {
        guard let household else { return nil }
        try household.insertHousehold(role: .owner)
        let records = ScreenshotDemoLedger.records(now: now, calendar: TestSupport.calendar)
        for (index, record) in records.enumerated() {
            household.context.insert(TestSupport.householdEntry(
                amount: record.amount, memo: record.memo, category: record.category,
                recorderName: index.isMultiple(of: 2) ? "はなこ" : "たろう",
                spentAt: record.spentAt, createdAt: record.createdAt, modifiedAt: record.createdAt
            ))
        }
        try household.context.save()
        let newest = try household.context.fetch(
            HouseholdEntry.timelineDescriptor(zoneName: TestSupport.householdZoneName, limit: 1)
        ).first
        return newest?.id
    }

    /// 家族の記録を 1 件、家計の保存先に入れる（同期で取り込んだ代わり）。入れた記録の id を返す。
    func insertHouseholdEntry(memo: String, amount: Int, recorderName: String, createdAt: Date) throws -> UUID? {
        guard let household else { return nil }
        let entry = TestSupport.householdEntry(
            amount: amount, memo: memo, category: .cafe, recorderName: recorderName,
            spentAt: createdAt, createdAt: createdAt, modifiedAt: createdAt
        )
        household.context.insert(entry)
        try household.context.save()
        return entry.id
    }

    /// 入力欄から記録を送り（送信のボタンと同じ `HomeModel.send`）、保存し終えるまで待つ。送った記録の返事のカードの行を返す。
    func send(_ text: String) async throws -> TimelineFrameKey {
        model.draft = text
        await model.send(calendar: TestSupport.calendar)?.value
        let send = try #require(try latestSend())
        #expect(send.originalText == text, "送った文が記録されていません")
        return .row(send.id)
    }

    /// ホームを文字の大きさ `size` でウィンドウに置き、行の位置が落ち着くまで待って、描かれた位置を返す（落ち着かなければ投げる）。
    ///
    /// `then` を渡すと、落ち着いたところで、その時点の位置を渡して呼ぶ（記録を送るなど、開いた後の操作）。返した行が描かれ、
    /// 位置がまた落ち着くまで待ってから返す。
    func host(
        size: UIContentSizeCategory,
        name: String,
        then action: (@MainActor ([TimelineFrameKey: CGRect]) async throws -> TimelineFrameKey)? = nil
    ) async throws -> [TimelineFrameKey: CGRect] {
        let recorder = FrameRecorder()
        let root = HomeView(model: model)
            .modelContainer(context.container)
            .environment(\.calendar, TestSupport.calendar)
            .environment(\.timeZone, TestSupport.calendar.timeZone)
            .environment(\.locale, Locale(identifier: "ja_JP"))
            .environment(\.timelineFrameObserver, TimelineFrameObserver { key, frame in recorder.frames[key] = frame })
        let controller = UIHostingController(rootView: root)
        controller.traitOverrides.preferredContentSizeCategory = size
        let style = ProcessInfo.processInfo.environment["SAIFULOG_TIMELINE_SNAPSHOT_STYLE"] == "dark"
            ? UIUserInterfaceStyle.dark : .light
        controller.traitOverrides.userInterfaceStyle = style

        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        try await recorder.waitUntilSettled("\(name)・\(size.rawValue)")
        if let action {
            let key = try await action(recorder.frames)
            try await recorder.waitUntilSettled("\(name)・\(size.rawValue)・操作の後", drawing: key)
        }
        if let folder = ProcessInfo.processInfo.environment["SAIFULOG_TIMELINE_SNAPSHOTS"] {
            let styleName = style == .dark ? "dark" : "light"
            try Self.snapshot(window, to: URL(fileURLWithPath: folder).appending(path: "\(name)-\(size.rawValue)-\(styleName).png"))
        }
        return recorder.frames
    }

    /// ウィンドウを PNG に書き出す（目で見る確かめ用）。
    private static func snapshot(_ window: UIWindow, to url: URL) throws {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #require(image.pngData()).write(to: url)
    }
}

/// タイムラインの行と見える範囲が描かれた位置を覚える。
@MainActor
private final class FrameRecorder {
    var frames: [TimelineFrameKey: CGRect] = [:]

    /// 見える範囲（と `key` の行）が描かれ、位置が 0.3 秒のあいだ変わらなくなるまで待つ（最大 5 秒）。下端に合わせる動きや、
    /// 帯の高さが決まるまでの並べ直しが済んでから確かめるため。開いた後の操作で足した行は `key` に渡す（足した行が描かれる前の、
    /// 操作の前のまま動かない位置で返らないように）。
    ///
    /// 5 秒たっても落ち着かなければ `TimelineDidNotSettle` を投げて、そこで失敗にする。この不具合は見積もりが揺れて位置が動き続ける
    /// ものなので、落ち着かないまま確かめると、動いている途中にたまたま条件を満たした位置で通ったり、下の端に無いと別の理由で
    /// 落ちたりして、位置が落ち着かなかったこと自体が分からなくなるため。
    func waitUntilSettled(_ label: String, drawing key: TimelineFrameKey = .viewport) async throws {
        var last = frames
        var stableSince = Date.now
        let deadline = Date.now.addingTimeInterval(5)
        while Date.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
            if frames != last {
                last = frames
                stableSince = .now
            } else if isDrawn(.viewport), isDrawn(key), Date.now.timeIntervalSince(stableSince) >= 0.3 {
                return
            }
        }
        throw TimelineDidNotSettle(label: label, viewport: frames[.viewport])
    }

    private func isDrawn(_ key: TimelineFrameKey) -> Bool {
        frames[key].map { !$0.isNull } ?? false
    }
}

/// タイムラインの位置が待つ時間のうちに落ち着かなかった（`FrameRecorder.waitUntilSettled`）。
private struct TimelineDidNotSettle: Error, CustomStringConvertible {
    let label: String
    let viewport: CGRect?

    var description: String {
        let viewport = viewport.map { "\($0)" } ?? "描かれていない"
        return "タイムラインの行と見える範囲の位置が 5 秒たっても落ち着きませんでした（\(label)。見える範囲 \(viewport)）"
    }
}
