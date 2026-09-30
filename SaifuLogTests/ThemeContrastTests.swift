import SaifuLogCore
import SwiftUI
import Testing
import UIKit
@testable import SaifuLog

/// 配色（墨 × 山吹）のコントラスト比を WCAG 2.x の式で確かめる。
///
/// 色の値を変えたときに、文字や記号が読めなくなるのを CI で止めるため。基準は WCAG の AA:
/// 文字は 4.5:1 以上、大きい文字とアイコン（図形）は 3:1 以上。
struct ThemeContrastTests {
    /// 見た目のモード。
    enum Mode: String, CaseIterable, CustomTestStringConvertible {
        case light, dark

        var testDescription: String { rawValue }

        func value(of pair: ColorPair) -> UInt32 {
            self == .light ? pair.light : pair.dark
        }

        var traits: UITraitCollection {
            UITraitCollection(userInterfaceStyle: self == .light ? .light : .dark)
        }
    }

    /// 前景と背景の組。
    struct Combination: CustomTestStringConvertible, Sendable {
        let name: String
        let foreground: ColorPair
        let background: ColorPair

        var testDescription: String { name }
    }

    /// 本文の大きさで読ませる文字の組（4.5:1 以上）。
    static let textCombinations: [Combination] = [
        .init(name: "ink / background", foreground: Palette.ink, background: Palette.background),
        .init(name: "ink / surface", foreground: Palette.ink, background: Palette.surface),
        .init(name: "inkSecondary / background", foreground: Palette.inkSecondary, background: Palette.background),
        .init(name: "inkSecondary / surface", foreground: Palette.inkSecondary, background: Palette.surface),
        .init(name: "accentText / background", foreground: Palette.accentText, background: Palette.background),
        .init(name: "accentText / surface", foreground: Palette.accentText, background: Palette.surface),
        .init(name: "danger / background", foreground: Palette.danger, background: Palette.background),
        .init(name: "danger / surface", foreground: Palette.danger, background: Palette.surface),
        .init(name: "income / background", foreground: Palette.income, background: Palette.background),
        .init(name: "income / surface", foreground: Palette.income, background: Palette.surface),
        // 山吹の塗りの上の文字（主ボタンの文字など）。
        .init(name: "onAccent / accentFill", foreground: Palette.onAccent, background: Palette.accentFill),
        // タイムラインの自分の吹き出し（送った文・質問）の文字。
        .init(name: "ink / userBubble", foreground: Palette.ink, background: Palette.userBubble),
    ]

    @Test(arguments: textCombinations, Mode.allCases)
    func textMeetsAA(combination: Combination, mode: Mode) {
        let ratio = Self.contrastRatio(mode.value(of: combination.foreground), mode.value(of: combination.background))
        #expect(ratio >= 4.5, "\(combination.name)（\(mode)）が \(ratio):1")
    }

    /// 山吹の塗りの上の記号（送信ボタンの矢印、進捗バーの上の印）。文字と同じ組なので 3:1 は当然満たすが、
    /// 記号は細いので、ここでも確かめておく（白を載せないことの裏づけ）。
    @Test(arguments: Mode.allCases)
    func iconOnAccentFill(mode: Mode) {
        let onAccent = Self.contrastRatio(mode.value(of: Palette.onAccent), mode.value(of: Palette.accentFill))
        let white = Self.contrastRatio(0xFFFFFF, mode.value(of: Palette.accentFill))
        #expect(onAccent >= 3)
        // 白を載せると 3:1 に届かない。山吹の上の記号を墨にしている理由（Theme の説明）が崩れていないか。
        #expect(white < 3)
    }

    /// カテゴリの丸（ライトの色で塗る）に白い記号を載せたときに 4:1 以上。アイコンの基準の 3:1 より
    /// 余裕を持たせ、小さい記号でも見分けられるようにしている。
    @Test(arguments: EntryCategory.builtIns)
    func whiteSymbolOnCategory(category: EntryCategory) {
        let ratio = Self.contrastRatio(Palette.onCategory.light, Palette.category(category).light)
        #expect(ratio >= 4, "\(category) が \(ratio):1")
    }

    /// 作ったカテゴリに選べる色も、組み込みのカテゴリと同じ基準（白い記号で 4:1 以上）。
    @Test(arguments: Palette.customCategoryChoices.indices)
    func whiteSymbolOnCustomCategory(index: Int) {
        let ratio = Self.contrastRatio(Palette.onCategory.light, Palette.customCategoryChoices[index].light)
        #expect(ratio >= 4, "\(index) 番の色が \(ratio):1")
    }

    /// 収入の丸（記録の吹き出しの右の印）も同じ基準。
    @Test func whiteSymbolOnIncome() {
        #expect(Self.contrastRatio(Palette.onCategory.light, Palette.income.light) >= 4)
    }

    /// カテゴリの色を地の上に図形（グラフの棒など）として置いたときに 3:1 以上。ダークの値は文字にも使うので 4.5:1 以上。
    @Test(arguments: EntryCategory.builtIns)
    func categoryOnBackground(category: EntryCategory) {
        let pair = Palette.category(category)
        for background in [Palette.background, Palette.surface] {
            #expect(Self.contrastRatio(pair.light, background.light) >= 3, "\(category)（ライト）")
            #expect(Self.contrastRatio(pair.dark, background.dark) >= 4.5, "\(category)（ダーク）")
        }
    }

    /// 作ったカテゴリに選べる色も、地の上で組み込みのカテゴリと同じ基準。
    @Test(arguments: Palette.customCategoryChoices.indices)
    func customCategoryOnBackground(index: Int) {
        let pair = Palette.customCategoryChoices[index]
        for background in [Palette.background, Palette.surface] {
            #expect(Self.contrastRatio(pair.light, background.light) >= 3, "\(index) 番の色（ライト）")
            #expect(Self.contrastRatio(pair.dark, background.dark) >= 4.5, "\(index) 番の色（ダーク）")
        }
    }

    /// 作ったカテゴリは選んだ色で塗り、一覧に無い（ほかの端末で消した）カテゴリと範囲の外の色の番号は、決めた色に落ちる。
    @Test func customCategoryColorsFollowCatalog() {
        let catalog = CategoryCatalog(customs: [
            CustomCategoryInfo(id: "a", name: "衣服", symbolName: "tshirt", colorIndex: 3),
            CustomCategoryInfo(id: "b", name: "住居", symbolName: "house", colorIndex: 99),
        ])

        #expect(catalog.colorPair(for: .custom("a")) == Palette.customCategoryChoices[3])
        #expect(catalog.colorPair(for: .custom("b")) == Palette.customCategoryChoices[0])
        #expect(catalog.colorPair(for: .custom("gone")) == Palette.category(.other))
        #expect(catalog.colorPair(for: .food) == Palette.category(.food))
        #expect(catalog.symbolName(for: .custom("a")) == "tshirt")
        #expect(catalog.symbolName(for: .custom("gone")) == EntryCategory.other.symbolName)
    }

    /// 画面が使う色（Theme）が、検査している値（Palette）と同じ色になるか。
    @Test(arguments: Mode.allCases)
    func themeResolvesToPalette(mode: Mode) {
        let tokens: [(String, Color, ColorPair)] = [
            ("background", Theme.background, Palette.background),
            ("surface", Theme.surface, Palette.surface),
            ("ink", Theme.ink, Palette.ink),
            ("inkSecondary", Theme.inkSecondary, Palette.inkSecondary),
            ("accentFill", Theme.accentFill, Palette.accentFill),
            ("onAccent", Theme.onAccent, Palette.onAccent),
            ("userBubble", Theme.userBubble, Palette.userBubble),
            ("danger", Theme.danger, Palette.danger),
            ("track", Theme.track, Palette.track),
            ("income", Theme.income, Palette.income),
            ("onCategory", Theme.onCategory, Palette.onCategory),
        ] + EntryCategory.builtIns.map { ("\($0)", Theme.color(for: $0), Palette.category($0)) }
            + Palette.customCategoryChoices.indices.map { ("custom \($0)", Palette.customCategory($0).color, Palette.customCategoryChoices[$0]) }

        for (name, color, pair) in tokens {
            let resolved = UIColor(color).resolvedColor(with: mode.traits)
            #expect(Self.rgb(of: resolved) == mode.value(of: pair), "\(name)（\(mode)）")
        }
    }

    /// Assets の AccentColor（アプリ全体の tint）が Palette.accentText と同じ値か。
    /// 値が二か所にあるので、片方だけを変えるとコントラストの検査が実際の色を見なくなるため。
    @Test(arguments: Mode.allCases)
    func accentColorAssetMatchesPalette(mode: Mode) throws {
        let asset = try #require(UIColor(named: "AccentColor", in: Bundle(for: Entry.self), compatibleWith: mode.traits))
        #expect(Self.rgb(of: asset.resolvedColor(with: mode.traits)) == mode.value(of: Palette.accentText))
    }

    /// 式そのものの確かめ。WCAG の説明にある値（白と黒で 21:1、同じ色で 1:1）と、
    /// 白地で 4.5:1 をわずかに超える灰色（#767676）。
    @Test func contrastFormula() {
        #expect(abs(Self.contrastRatio(0xFFFFFF, 0x000000) - 21) < 0.001)
        #expect(abs(Self.contrastRatio(0x777777, 0x777777) - 1) < 0.001)
        #expect(Self.contrastRatio(0x767676, 0xFFFFFF) >= 4.5)
        #expect(Self.contrastRatio(0x777777, 0xFFFFFF) < 4.5)
        // 前景と背景を入れ替えても同じ。
        #expect(Self.contrastRatio(0x1F1D1A, 0xF8B500) == Self.contrastRatio(0xF8B500, 0x1F1D1A))
    }

    // MARK: - WCAG 2.x のコントラスト比

    /// 2 色のコントラスト比（1〜21）。
    static func contrastRatio(_ a: UInt32, _ b: UInt32) -> Double {
        let la = relativeLuminance(a)
        let lb = relativeLuminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// sRGB の 0xRRGGBB の相対輝度。
    static func relativeLuminance(_ rgb: UInt32) -> Double {
        func linear(_ component: UInt32) -> Double {
            let c = Double(component) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let r = linear((rgb >> 16) & 0xFF)
        let g = linear((rgb >> 8) & 0xFF)
        let b = linear(rgb & 0xFF)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    /// UIColor を 0xRRGGBB に丸める。
    static func rgb(of color: UIColor) -> UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        func byte(_ value: CGFloat) -> UInt32 { UInt32((min(max(value, 0), 1) * 255).rounded()) }
        return byte(r) << 16 | byte(g) << 8 | byte(b)
    }
}
