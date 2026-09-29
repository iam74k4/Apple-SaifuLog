#if DEBUG
import Foundation
import SaifuLogCore
import SwiftData

/// 撮影用のデモの家計。架空の一人暮らしの人の記録（食費・カフェ・日用品・交通・娯楽・光熱・通信・医療と給料）と、月の予算。
///
/// 記録は先月の 1 日からデモの「いま」（撮影の月の 15 日）まで、毎日つける。スクリーンショットに出るのは直近の 2 週間ほどだが、
/// 先月の分まで作るのは、月のまとめの前の月との差と、先週のふりかえりの前の週との差（前の週は先月にかかることがある）と、
/// 予算の目安（先月の支出）を出すため。
///
/// 金額は曜日と日付の決まった型から選ぶ（乱数を使わない）。同じ月に撮れば、日本語と英語で同じ記録になる。品目は日本語
/// （アプリは日本語の入力を読むので、英語の画面でも記録は日本語で書かれる）。店の名前や人の名前は入れない。
enum ScreenshotDemoLedger {
    /// デモの 1 件。
    struct Record: Equatable, Sendable {
        var amount: Int
        var isIncome: Bool
        var category: EntryCategory
        var memo: String
        var spentAt: Date
        var createdAt: Date
        var originalText: String
    }

    /// 月の全体の予算。月の支出（12 万円前後）より少し多くし、帯に「今月あと ¥…」が出て、予算の目安の提案（予算との差が
    /// 2 割以上のときだけ出る）が出ない額にする。
    static let monthlyBudget = 130_000
    /// 割り勘の記録の元の文（ようこその例と同じ書き方）。
    static let splitBillText = "昨日 焼肉12000 4人で割り勘"

    /// 記録を始めた日（先月の 1 日の 0 時）。
    static func startDate(now: Date, calendar: Calendar) -> Date? {
        ReportPeriod.lastMonth.interval(now: now, calendar: calendar)?.start
    }

    /// デモの記録（使った日時の古い順）。デモの「いま」より後の記録は作らない。
    static func records(now: Date, calendar: Calendar) -> [Record] {
        guard let start = startDate(now: now, calendar: calendar) else { return [] }
        let today = calendar.startOfDay(for: now)
        let splitDay = mostRecentSaturday(before: today, calendar: calendar)
        var records: [Record] = []
        var day = start
        var index = 0
        while day <= today {
            let items = items(
                weekday: calendar.component(.weekday, from: day),
                dayOfMonth: calendar.component(.day, from: day),
                index: index,
                isSplitBillDay: day == splitDay
            )
            for item in items {
                guard let spentAt = calendar.date(bySettingHour: item.hour, minute: item.minute, second: 0, of: day),
                      spentAt <= now
                else { continue }
                // 割り勘は翌朝に「昨日 …」と送った記録にする（記録した日時は翌日、使った日時は前の日）。
                let createdAt = item.recordedNextMorning
                    ? calendar.date(byAdding: DateComponents(day: 1, hour: -9, minute: -25), to: spentAt) ?? spentAt
                    : spentAt
                guard createdAt <= now else { continue }
                records.append(Record(
                    amount: item.amount, isIncome: item.isIncome, category: item.category, memo: item.memo,
                    spentAt: spentAt, createdAt: createdAt, originalText: item.originalText
                ))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = calendar.startOfDay(for: next)
            index += 1
        }
        return records
    }

    /// デモの記録と月の予算を保存先に入れる。予算は記録を始める前に決めたことにする（月のまとめで、先月にも予算の進みを出すため）。
    static func insert(into context: ModelContext, now: Date, calendar: Calendar) throws {
        for record in records(now: now, calendar: calendar) {
            context.insert(Entry(
                amount: record.amount, isIncome: record.isIncome, category: record.category, memo: record.memo,
                spentAt: record.spentAt, createdAt: record.createdAt, source: .text, originalText: record.originalText
            ))
        }
        let start = startDate(now: now, calendar: calendar) ?? now
        let decidedAt = calendar.date(byAdding: .day, value: -1, to: start) ?? start
        context.insert(Budget(scope: .total, amount: monthlyBudget, updatedAt: decidedAt))
        try context.save()
    }

    // MARK: - 1 日の記録の型

    /// 1 日の記録の 1 件（時刻と中身）。
    private struct Item {
        var hour: Int
        var minute: Int
        var memo: String
        var amount: Int
        var category: EntryCategory
        var isIncome = false
        /// 元の文。省けば「品目 金額」（ひとこと入力のいちばん素直な書き方）。
        var text: String?
        /// 翌朝にまとめて記録したか（割り勘）。
        var recordedNextMorning = false

        var originalText: String {
            text ?? "\(memo) \(amount)"
        }
    }

    /// その日の記録。曜日（1 が日曜）・日付・記録を始めてからの日数で決める。
    private static func items(weekday: Int, dayOfMonth: Int, index: Int, isSplitBillDay: Bool) -> [Item] {
        let week = index / 7
        var items: [Item] = []
        switch weekday {
        case 2...6:
            // 平日: 朝のコーヒー（水曜は飲まない）、昼のランチ、火曜と金曜の帰りにスーパー、水曜はドラッグストアかコンビニ、
            // 木曜はバス。
            if weekday != 4 {
                items.append(Item(hour: 8, minute: 50, memo: "コーヒー", amount: pick([420, 480, 450, 520], index), category: .cafe))
            }
            items.append(Item(
                hour: 12, minute: 15, memo: "ランチ", amount: pick([850, 980, 780, 1_100, 920, 880, 1_050], index), category: .food
            ))
            if weekday == 3 || weekday == 6 {
                items.append(Item(
                    hour: 19, minute: 10, memo: "スーパー", amount: pick([2_380, 3_140, 1_860, 2_760, 3_420], index), category: .food
                ))
            }
            if weekday == 4 {
                if week.isMultiple(of: 2) {
                    items.append(Item(
                        hour: 19, minute: 30, memo: "ドラッグストア", amount: pick([1_280, 2_150, 980], week / 2), category: .daily
                    ))
                } else {
                    items.append(Item(hour: 19, minute: 30, memo: "コンビニ", amount: pick([580, 720], week), category: .food))
                }
            }
            if weekday == 5 {
                items.append(Item(hour: 18, minute: 40, memo: "バス", amount: 230, category: .transport))
            }
        case 7:
            // 土曜: 昼のカフェ、1 週おきに映画、夜は外食（いちばん近い土曜は、友人との焼肉の割り勘）。
            items.append(Item(hour: 13, minute: 10, memo: "カフェラテ", amount: 620, category: .cafe))
            if !week.isMultiple(of: 2) {
                items.append(Item(hour: 16, minute: 0, memo: "映画", amount: 2_000, category: .entertainment))
            }
            if isSplitBillDay {
                items.append(Item(
                    hour: 19, minute: 30, memo: "焼肉（4人で割り勘・総額 ¥12,000・立替 ¥9,000）", amount: 3_000, category: .food,
                    text: splitBillText, recordedNextMorning: true
                ))
            } else {
                items.append(Item(hour: 19, minute: 30, memo: "夕食", amount: pick([3_800, 4_600, 3_200], week), category: .food))
            }
        default:
            // 日曜: まとめ買いのスーパーと、1 週おきに本屋か 100 円ショップ。
            items.append(Item(
                hour: 11, minute: 20, memo: "スーパー", amount: pick([4_280, 3_960, 4_650], week), category: .food
            ))
            if week.isMultiple(of: 2) {
                items.append(Item(hour: 15, minute: 30, memo: "本屋", amount: 1_540, category: .entertainment))
            } else {
                items.append(Item(hour: 15, minute: 30, memo: "100均", amount: 660, category: .daily))
            }
        }
        // 月に一度の支払いと給料。給料はデモの「いま」（15 日）より前の 10 日にする（帯の「今月の収入」と、月のまとめの収入と
        // 収支を、今月の分で写すため）。
        switch dayOfMonth {
        case 5: items.append(Item(hour: 20, minute: 0, memo: "スマホ代", amount: 2_980, category: .utilities))
        case 10:
            items.append(Item(
                hour: 9, minute: 0, memo: "給料", amount: 250_000, category: .other, isIncome: true, text: "給料 25万"
            ))
        case 12: items.append(Item(hour: 20, minute: 10, memo: "電気代", amount: 6_820, category: .utilities))
        case 18: items.append(Item(hour: 20, minute: 15, memo: "ガス代", amount: 3_960, category: .utilities))
        case 22: items.append(Item(hour: 17, minute: 30, memo: "薬局", amount: 1_320, category: .medical))
        default: break
        }
        return items
    }

    /// 決まった候補から、日数（か週）で順に選ぶ。
    private static func pick(_ values: [Int], _ index: Int) -> Int {
        values[index % values.count]
    }

    /// `day` より前のいちばん近い土曜日（0 時）。
    private static func mostRecentSaturday(before day: Date, calendar: Calendar) -> Date? {
        var cursor = day
        for _ in 0..<7 {
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { return nil }
            cursor = calendar.startOfDay(for: previous)
            if calendar.component(.weekday, from: cursor) == 7 { return cursor }
        }
        return nil
    }
}
#endif
