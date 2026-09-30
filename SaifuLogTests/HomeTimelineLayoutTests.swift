import Foundation
import SaifuLogCore
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import SaifuLog

/// ホームを開いたとき、いちばん新しい行（記録・回答カード・先週のふりかえり・家計の記録）がタイムラインの下の端に見えること。
///
/// 大きな文字でタイムラインが空に見えた不具合の再発を防ぐ。行の高さがそろわないタイムラインを LazyVStack で下端に合わせると、
/// 見積もった全体の高さが揺れて行の無い位置で止まり、空に見えた（`HomeView` の `TimelineScrollView`）。どの文字の大きさで
/// 起きるかは記録の中身と画面の幅で変わるので、行の高さがそろわない撮影用のデモの家計（長い品目の割り勘を含む）で、
/// 標準からアクセシビリティサイズまで確かめる。
///
/// 部品だけを描くのではなく、ウィンドウに実際のホーム（ナビゲーション・帯・入力欄の中のスクロール）を置き、行と見える範囲が
/// 描かれた位置（`timelineFrameObserver`）で確かめる。下端に合わせる動きと LazyVStack の見積もりの揺れは、スクロールの中に
/// 並べた画面で起きるため（タイムラインを LazyVStack に戻すと、この置き方で AX1 の記録と、標準から AX5 まで（AX4 を除く）の
/// ふりかえりのカードが落ちることを確かめた）。
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

    @Test("開いたとき、いちばん新しい記録がタイムラインの下の端に見える", arguments: sizes)
    func newestEntryIsAtTheBottom(size: UIContentSizeCategory) async throws {
        let fixture = try TimelineFixture()
        try fixture.insertDemoLedger()
        fixture.markWeeklyRecapShown()
        let newest = try #require(try fixture.newestEntry())

        let frames = try await fixture.host(size: size, name: "entries")

        try Self.expectAtTheBottom(frames, key: .row(newest.persistentModelID), size: size)
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

    /// いちばん新しく記録したもの（タイムラインのいちばん下）。
    func newestEntry() throws -> Entry? {
        try context.fetch(Entry.timelineDescriptor(limit: 1)).first
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

    /// ホームを文字の大きさ `size` でウィンドウに置き、行の位置が落ち着くまで待って、描かれた位置を返す（落ち着かなければ投げる）。
    func host(size: UIContentSizeCategory, name: String) async throws -> [TimelineFrameKey: CGRect] {
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

    /// 見える範囲が描かれ、位置が 0.3 秒のあいだ変わらなくなるまで待つ（最大 5 秒）。下端に合わせる動きや、帯の高さが決まるまでの
    /// 並べ直しが済んでから確かめるため。
    ///
    /// 5 秒たっても落ち着かなければ `TimelineDidNotSettle` を投げて、そこで失敗にする。この不具合は見積もりが揺れて位置が動き続ける
    /// ものなので、落ち着かないまま確かめると、動いている途中にたまたま条件を満たした位置で通ったり、下の端に無いと別の理由で
    /// 落ちたりして、位置が落ち着かなかったこと自体が分からなくなるため。
    func waitUntilSettled(_ label: String) async throws {
        var last = frames
        var stableSince = Date.now
        let deadline = Date.now.addingTimeInterval(5)
        while Date.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
            if frames != last {
                last = frames
                stableSince = .now
            } else if frames[.viewport] != nil, Date.now.timeIntervalSince(stableSince) >= 0.3 {
                return
            }
        }
        throw TimelineDidNotSettle(label: label, viewport: frames[.viewport])
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
