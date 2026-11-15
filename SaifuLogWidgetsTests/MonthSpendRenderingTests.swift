import SaifuLogCore
import SwiftUI
import Testing
import UIKit

/// ウィジェットの中身（`MonthSpendContent`）を、大きさ × 状態 × 文字の大きさで描いてみる。WidgetKit の外でも落ちずに描け、
/// 何かが描かれる（空の画にならない）ことを確かめる（並べ方の崩れは、実機とシミュレータで見る）。
@MainActor
struct MonthSpendRenderingTests {
    typealias Fixture = WidgetFixture

    /// 大きさごとのおおよその枠（iPhone の 6.1 インチ前後）。
    static func size(of layout: MonthSpendLayout) -> CGSize {
        switch layout {
        case .small: CGSize(width: 170, height: 170)
        case .rectangular: CGSize(width: 172, height: 76)
        case .circular: CGSize(width: 76, height: 76)
        case .inline: CGSize(width: 234, height: 26)
        }
    }

    static let displays: [WidgetDisplay?] = [
        .figures(spent: 32_480, budget: Fixture.budget(50_000, spent: 32_480)),
        .figures(spent: 1_253_000, budget: Fixture.budget(50_000, spent: 1_253_000)),
        .figures(spent: 42_380, budget: nil),
        .hidden,
        nil,
    ]

    @Test("どの大きさ・状態・文字の大きさでも描ける", arguments: MonthSpendLayout.allCases, [DynamicTypeSize.large, .accessibility5])
    func renders(layout: MonthSpendLayout, typeSize: DynamicTypeSize) throws {
        for display in Self.displays {
            for language in ["ja", "en"] {
                let presentation = MonthSpendPresentation(
                    display: display, layout: layout, bundle: Fixture.strings(language),
                    locale: language == "ja" ? Fixture.japanese : Fixture.english
                )
                let size = Self.size(of: layout)
                let renderer = ImageRenderer(
                    content: MonthSpendContent(presentation: presentation, layout: layout)
                        .frame(width: size.width, height: size.height)
                        .environment(\.dynamicTypeSize, typeSize)
                )
                renderer.scale = 2
                let image = try #require(renderer.uiImage, "描けません: \(layout) \(String(describing: display)) \(language)")
                #expect(image.size.width > 0 && image.size.height > 0)
            }
        }
    }
}
