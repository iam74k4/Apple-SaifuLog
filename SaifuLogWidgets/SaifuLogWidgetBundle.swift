import SwiftUI
import WidgetKit

/// ウィジェットの拡張の入口。ウィジェットは「今月使った額」の 1 つだけ（ホームの帯と同じ数字。`MonthSpendWidget`）。
@main
struct SaifuLogWidgetBundle: WidgetBundle {
    var body: some Widget {
        MonthSpendWidget()
    }
}
