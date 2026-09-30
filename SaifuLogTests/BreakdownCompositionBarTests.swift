import CoreGraphics
import Testing
@testable import SaifuLog

/// 月のまとめのカテゴリ別の支出の帯（`BreakdownCompositionBar`）の幅の配り方。
struct BreakdownCompositionBarTests {
    /// 隙間を除いた幅を金額の比で配る。
    @Test func widthsFollowAmounts() {
        let widths = BreakdownCompositionBar.widths(for: [6_000, 3_000, 1_000], in: 204)

        // 隙間 2 つ（4pt）を除いた 200pt を 6:3:1 に配る。
        #expect(widths == [120, 60, 20])
    }

    /// 小さな割合のカテゴリにも最低の幅を残し、上げた分はほかから比で引く（合計は変えない）。
    @Test func smallItemsKeepMinimumWidth() {
        let widths = BreakdownCompositionBar.widths(for: [99_000, 1_000], in: 102)
        let available: CGFloat = 100

        #expect(widths[1] == BreakdownCompositionBar.minimumWidth)
        #expect(abs(widths.reduce(0, +) - available) < 0.001)
        #expect(widths[0] > widths[1])
    }

    /// 支出が無い・幅が無いときは 0 を配る。
    @Test func emptyCases() {
        #expect(BreakdownCompositionBar.widths(for: [0, 0], in: 100) == [0, 0])
        #expect(BreakdownCompositionBar.widths(for: [500], in: 0) == [0])
        #expect(BreakdownCompositionBar.widths(for: [], in: 100).isEmpty)
    }
}
