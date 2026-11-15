import Foundation
import SaifuLogCore
import Testing
@testable import SaifuLog

/// ホームの帯の数字をウィジェットに渡す（`WidgetPublisher`・`MonthSummaryHeader.widgetSnapshot`）。
@MainActor
struct WidgetPublisherTests {
    /// ウィジェットに描き直させた回数。
    final class ReloadCounter {
        var count = 0
    }

    static let september = DateInterval(start: TestSupport.date(2026, 9, 1), end: TestSupport.date(2026, 10, 1))

    static func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "WidgetSnapshot-\(UUID().uuidString).json")
    }

    /// 書いた数字はウィジェットが読めて、前と同じなら書かず（描き直しの回数を使わない）、変わったら書き直す。
    @Test func writesOnlyWhenFiguresChange() throws {
        let url = Self.temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let reloads = ReloadCounter()
        let publisher = WidgetPublisher(url: url, reload: { reloads.count += 1 })
        let first = WidgetSnapshot.figures(spent: 850, budget: 50_000, month: Self.september)

        publisher.publish(first)
        #expect(WidgetSnapshotFile.read(from: url) == first)
        #expect(reloads.count == 1)

        publisher.publish(first)
        #expect(reloads.count == 1)

        let second = WidgetSnapshot.figures(spent: 1_330, budget: 50_000, month: Self.september)
        publisher.publish(second)
        #expect(WidgetSnapshotFile.read(from: url) == second)
        #expect(reloads.count == 2)
    }

    /// アプリのロックをオンにしたら、前に書いた金額を残さない（ファイルは数字の無い形に置き換える）。
    @Test func appLockReplacesFiguresWithHidden() throws {
        let url = Self.temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let publisher = WidgetPublisher(url: url, reload: {})

        publisher.publish(.figures(spent: 850, budget: nil, month: Self.september))
        publisher.publish(.hidden)

        let written = try #require(WidgetSnapshotFile.read(from: url))
        #expect(written == .hidden)
        #expect(written.spent == 0)
        #expect(written.budget == nil)
    }

    /// App Group を使えないビルド（署名なしなど）では何もしない（落ちない・描き直させない）。
    @Test func doesNothingWithoutAppGroup() {
        let reloads = ReloadCounter()
        let publisher = WidgetPublisher(url: nil, reload: { reloads.count += 1 })

        publisher.publish(.figures(spent: 850, budget: nil, month: Self.september))

        #expect(reloads.count == 0)
    }

    /// 帯と同じ数字（今月使った額と全体の予算）を渡す。前の月の記録と収入は数えない。ロックがオンなら数字を渡さない。
    @Test func headerPassesSameFiguresAsBand() throws {
        let records = [
            TestSupport.entry(amount: 850, spentAt: TestSupport.date(2026, 9, 3)),
            TestSupport.entry(amount: 480, category: .cafe, memo: "カフェラテ", spentAt: TestSupport.date(2026, 9, 28, hour: 9)),
            // 前の月の記録は数えない。
            TestSupport.entry(amount: 9_999, spentAt: TestSupport.date(2026, 8, 31, hour: 20)),
        ]
        let income = Entry(
            amount: 250_000, isIncome: true, category: .other, memo: "給料", spentAt: TestSupport.date(2026, 9, 25),
            createdAt: TestSupport.now, source: .text, originalText: "給料 25万"
        )
        let budgets = [Budget(scope: .total, amount: 50_000, updatedAt: TestSupport.now)]
        let figures = MonthSummaryHeader.figures(
            records: records + [income], budgets: budgets, today: TestSupport.now, calendar: TestSupport.calendar
        )

        let snapshot = try #require(MonthSummaryHeader.widgetSnapshot(
            figures: figures, today: TestSupport.now, calendar: TestSupport.calendar, hidesFigures: false
        ))
        #expect(snapshot == .figures(spent: 1_330, budget: 50_000, month: Self.september))
        #expect(snapshot.spent == figures.summary.expense)

        #expect(MonthSummaryHeader.widgetSnapshot(
            figures: figures, today: TestSupport.now, calendar: TestSupport.calendar, hidesFigures: true
        ) == .hidden)
    }

    /// アプリの Info.plist に App Group の ID（ビルドの設定の値に置き換わったもの）と、ウィジェットを押したときの URL のスキームがあり、
    /// アプリの中にウィジェットの拡張が入っていて、拡張も同じ App Group を読む。
    @Test func appCarriesWidgetExtensionWithSameAppGroup() throws {
        let app = Bundle(for: Entry.self)
        let group = try #require(app.object(forInfoDictionaryKey: "SaifuLogAppGroup") as? String)
        let bundleID = try #require(app.bundleIdentifier)
        #expect(group == "group.\(bundleID)")

        let urlTypes = try #require(app.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]])
        #expect(urlTypes.flatMap { ($0["CFBundleURLSchemes"] as? [String]) ?? [] }.contains(WidgetLink.scheme))

        let pluginURL = try #require(app.builtInPlugInsURL).appending(path: "SaifuLogWidgets.appex")
        let widget = try #require(Bundle(url: pluginURL), "アプリにウィジェットの拡張が入っていません")
        #expect(widget.object(forInfoDictionaryKey: "SaifuLogAppGroup") as? String == group)
        let point = (widget.object(forInfoDictionaryKey: "NSExtension") as? [String: Any])?["NSExtensionPointIdentifier"] as? String
        #expect(point == "com.apple.widgetkit-extension")
    }

    /// ウィジェットを押したときの URL だけを、入力欄を開く頼みとして読む。
    @Test func readsOnlyRecordLink() throws {
        #expect(WidgetLink.isRecord(WidgetLink.record))
        #expect(WidgetLink.isRecord(try #require(URL(string: "SAIFULOG://record"))))
        #expect(!WidgetLink.isRecord(try #require(URL(string: "saifulog://delete"))))
        #expect(!WidgetLink.isRecord(try #require(URL(string: "https://record"))))
    }
}
