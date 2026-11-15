import Foundation
import SaifuLogCore

/// テストのバンドルを指す目印（訳の lproj を探すため）。
final class WidgetTestBundle {}

/// ウィジェットのテストで使う、決まった日時と暦と訳。
enum WidgetFixture {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// 2026-09-28 12:00（日本時間）。
    static let now = date(2026, 9, 28, hour: 12)
    static let september = DateInterval(start: date(2026, 9, 1), end: date(2026, 10, 1))

    static let japanese = Locale(identifier: "ja_JP")
    static let english = Locale(identifier: "en_US")

    /// 言語の lproj（拡張と同じ String Catalog を、このテストのバンドルに入れてある。`project.yml`）。
    static func strings(_ language: String) -> Bundle {
        let bundle = Bundle(for: WidgetTestBundle.self)
        guard let path = bundle.path(forResource: language, ofType: "lproj"), let lproj = Bundle(path: path) else {
            // 開発言語（ja）は、訳を書いていない文の lproj を作らないことがある。そのときは文そのもの（キー）が出る。
            return bundle
        }
        return lproj
    }

    /// 9 月の予算の進み。
    static func budget(_ amount: Int, spent: Int) -> BudgetStatus {
        BudgetStatus(budget: amount, spent: spent, now: now, month: september, calendar: calendar)!
    }
}
