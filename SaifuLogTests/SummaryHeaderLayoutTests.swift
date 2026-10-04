import SaifuLogCore
import SwiftUI
import Testing
import UIKit
@testable import SaifuLog

/// ホームの上の帯の高さ。入力欄にキーボードを出している間（`isCompact`）は低い帯にして、タイムラインを広く見せる。
///
/// 以前は帯がキーボードを出している間も同じ高さで、キーボードと合わせてタイムラインが 230pt ほどしか残らず、送った記録の返事の
/// 「取り消す」やカテゴリの聞き返しが帯の下に隠れた（iPhone 17 Pro のシミュレータ）。
@MainActor
struct SummaryHeaderLayoutTests {
    /// 6.3 インチの iPhone（幅 402pt）。
    static let width: CGFloat = 402

    @Test(
        "キーボードを出している間の帯は 1 行（ボタンの高さ）に収まり、ふだんの帯より 60pt 以上低い",
        arguments: [DynamicTypeSize.large, .xxxLarge, .accessibility1]
    )
    func compactHeaderIsOneRow(size: DynamicTypeSize) throws {
        let regular = try Self.height(isCompact: false, size: size)
        let compact = try Self.height(isCompact: true, size: size)
        #expect(regular - compact >= 60, "ふだん \(regular)pt・低い帯 \(compact)pt")
        // 見出しの行（44pt）と上下の余白（4pt ずつ）。文字が大きくても 1 行に収める（ボタンは収まらなければ出さない）。
        #expect(compact <= 44 + 8 + 1, "低い帯 \(compact)pt")
    }

    @Test("予算を超えていても、予算が無くても、低い帯は 1 行に収まる")
    func compactHeaderIsOneRowInEveryState() throws {
        let over = try Self.height(isCompact: true, size: .large, spent: 180_000)
        let noBudget = try Self.height(isCompact: true, size: .large, budget: nil)
        #expect(over <= 44 + 8 + 1)
        #expect(noBudget <= 44 + 8 + 1)
    }

    /// 予算 ¥150,000・使った額 `spent` の今月の帯の高さ（予算が nil なら、予算を決めていない帯）。
    private static func height(
        isCompact: Bool, size: DynamicTypeSize, budget: Int? = 150_000, spent: Int = 4_530
    ) throws -> CGFloat {
        let month = try #require(ReportPeriod.thisMonth.interval(now: TestSupport.now, calendar: TestSupport.calendar))
        let status = BudgetStatus(budget: budget, spent: spent, now: TestSupport.now, month: month, calendar: TestSupport.calendar)
        let header = SummaryHeader(
            summary: MonthlySummary(expense: spent, income: 0),
            budget: status,
            editBudget: {},
            openReport: {},
            openSettings: {},
            pace: status == nil ? nil : SummaryHeader.Pace(amount: 130_000, beyond: spent - 130_000),
            isCompact: isCompact
        )
        .environment(\.dynamicTypeSize, size)
        .environment(\.locale, Locale(identifier: "ja_JP"))
        .environment(\.calendar, TestSupport.calendar)
        return UIHostingController(rootView: header)
            .sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
            .height
    }
}
