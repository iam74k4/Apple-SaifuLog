import SaifuLogCore
import SwiftUI
import UIKit

/// 画面の色をまとめる場所。配色は「白 × 墨（モノクロ）」（docs/design.md §7）。
///
/// 画面側では色を直接書かず、ここのトークンを使う。値は `Palette` に 16 進で置き、SaifuLogTests が
/// そこから WCAG のコントラスト比を確かめる（値を変えるときは、テストが通るかで読めるかを確かめる）。
/// ライトとダークは iOS の設定に従う（アプリ内に外観の設定は置かない）。
///
/// 地はライトが白に近い灰色、ダークが黒で、色味を持たせない（アプリのアイコンの地と財布と同じ白と黒）。色はカテゴリ・収入・注意の
/// 意味のある色と設定の行の印にだけ使い、画面の操作の色は墨と白にする（2026-10-02 に「墨 × 山吹」から替えた。山吹は白地で 1.8:1 しか無く、
/// 送信ボタンや主ボタンの形が地から見分けにくかったため）。
///
/// 使い分け:
/// - 主の塗り（`accentFill`）は、ライトでは墨、ダークでは白にする（送信ボタン・主ボタン・選んだ額のボタン・予算の進捗バーなど）。
///   上の文字と記号は `onAccent`（ライトは白、ダークは墨）。どちらの外観でも地と 15:1 以上離れ、形がはっきり見える。
/// - 文字の強調（ボタンの文字など）は `accentText`。Assets の AccentColor で、アプリ全体の tint でもある（墨か白で、本文と同じ色）。
///   本文と色で見分けられないので、文字だけのボタンには記号を添えるか、ボタンの形（ガラス・枠）に入れる。
/// - トグルには tint を付けない（システムの色のまま）。画面の根元に `.tint` を掛けるとトグルまで染まるので、
///   全体の色は AccentColor だけで決める。
/// - `danger`（予算オーバーなど）は色だけで伝えない。色の見分けにくい人にも分かるよう、アイコンと文字を必ず添える。
enum Theme {
    /// 画面の背景。
    static let background = Palette.background.color
    /// アプリの返事のカード（記録しました・質問の回答・ふりかえり）など、背景の上に載せる面。
    static let surface = Palette.surface.color
    /// 本文の文字（墨）。
    static let ink = Palette.ink.color
    /// 補足の文字（日付・見出しなど）。
    static let inkSecondary = Palette.inkSecondary.color
    /// 主の塗り（ライトは墨、ダークは白。上の説明）。
    static let accentFill = Palette.accentFill.color
    /// 主の塗りの上に載せる文字と記号（ライトは白、ダークは墨）。
    static let onAccent = Palette.onAccent.color
    /// タイムラインの自分の吹き出し（送った文・質問）の面。墨の文字を載せる。背景とアプリの返事のカード（面）の
    /// どちらとも見分けられる灰色にする。
    static let userBubble = Palette.userBubble.color
    /// 文字の強調の色（Assets の AccentColor。値は `Palette.accentText` と同じにしてあり、テストで照合する）。
    static let accentText = Color.accentColor
    /// 注意の色（予算オーバーなど）。アイコンと文字を必ず添える。
    static let danger = Palette.danger.color
    /// 白い記号を載せる、注意の塗り（スワイプの「削除」「やめる」）。ダークの `danger` は明るく、白い記号が読めなくなるので、
    /// ダークでもライトの値で塗る（カテゴリの丸と同じ考え方）。
    static let dangerFill = Palette.dangerFill.color
    /// 進捗のバーの地（まだ使っていない分）。バーは数字に添える目安なので、地との差は控えめでよい。返事のカードの細い枠にも使う。
    static let track = Palette.track.color
    /// 収入の金額の色。収入は「+」の符号と「収入」の語でも示す（色だけに頼らない）。
    static let income = Palette.income.color
    /// カテゴリの丸に載せる記号の色。
    static let onCategory = Palette.onCategory.color

    /// 組み込みのカテゴリの色（作ったカテゴリは「その他」の色。作ったカテゴリの色は `CategoryCatalog.color(for:)`）。
    static func color(for category: EntryCategory) -> Color {
        Palette.category(category).color
    }
}

/// ライトとダークの色の組（sRGB の 0xRRGGBB）。
struct ColorPair: Hashable, Sendable {
    let light: UInt32
    let dark: UInt32

    var color: Color {
        .dynamic(light: light, dark: dark)
    }
}

/// 色の値。画面は `Theme` から使い、ここはテスト（コントラスト比の検査）と `Theme` だけが読む。
enum Palette {
    /// 地。ライトは白に近い灰色（白い面のカードと見分けるため）、ダークは黒。どちらも色味を持たせない。
    static let background = ColorPair(light: 0xF5F5F5, dark: 0x000000)
    static let surface = ColorPair(light: 0xFFFFFF, dark: 0x1C1C1C)
    static let ink = ColorPair(light: 0x111111, dark: 0xF5F5F5)
    static let inkSecondary = ColorPair(light: 0x666666, dark: 0xA1A1A1)
    /// 主の塗りは墨と白（本文の文字と同じ値）。外観で入れ替わる。
    static let accentFill = ColorPair(light: 0x111111, dark: 0xF5F5F5)
    static let onAccent = ColorPair(light: 0xFFFFFF, dark: 0x111111)
    static let userBubble = ColorPair(light: 0xEBEBEB, dark: 0x2C2C2C)
    /// Assets の AccentColor と同じ値にする（二か所にあるので、テストで食い違いを止める）。
    static let accentText = ColorPair(light: 0x111111, dark: 0xF5F5F5)
    static let danger = ColorPair(light: 0xB3261E, dark: 0xFF8A80)
    static let dangerFill = ColorPair(light: 0xB3261E, dark: 0xB3261E)
    static let track = ColorPair(light: 0xE5E5E5, dark: 0x2E2E2E)
    static let income = ColorPair(light: 0x2E7D4F, dark: 0x7FD1A0)
    /// カテゴリの丸と返事の行の印はダークでもライトの色で塗る（EntryBubble・RecordedReplyRow）ので、記号は両方とも白にする。
    static let onCategory = ColorPair(light: 0xFFFFFF, dark: 0xFFFFFF)

    /// カテゴリの色。
    ///
    /// ライトの値は塗り（丸）と記号の地に使い、白い記号を載せて 4:1 以上にしてある。白地の上の文字には使わない
    /// （食費と日用品は 4.5:1 に届かない）。ダークの値は暗い地の上で文字にも使える明るさ（4.5:1 以上）にしてある。
    /// システムの色（.orange や .teal）は明るく、白い記号とのコントラストが 3:1 に届かないため使わない。
    /// 光熱・通信は、前の配色の差し色（山吹）と見分けにくい琥珀をやめて青緑にした。
    static func category(_ category: EntryCategory) -> ColorPair {
        switch category {
        case .custom: ColorPair(light: 0x6E6E73, dark: 0xAEAEB2) // 作ったカテゴリの色は `customCategory(_:)`。一覧に無いときは「その他」の鼠
        case .food: ColorPair(light: 0xD9482B, dark: 0xFF7A5C) // 朱
        case .daily: ColorPair(light: 0x3E8E41, dark: 0x7BCB7E) // 緑
        case .transport: ColorPair(light: 0x1E6FD9, dark: 0x5AA9FF) // 藍
        case .cafe: ColorPair(light: 0x8B5E3C, dark: 0xC9A27E) // 焦茶
        case .entertainment: ColorPair(light: 0x9B40C4, dark: 0xC38EF0) // 紫
        case .utilities: ColorPair(light: 0x0B7285, dark: 0x4FD0E0) // 青緑
        case .medical: ColorPair(light: 0xC2185B, dark: 0xFF7FB0) // 紅梅
        case .other: ColorPair(light: 0x6E6E73, dark: 0xAEAEB2) // 鼠
        }
    }

    /// 作ったカテゴリに選べる色（`CustomCategory.colorIndex` の位置）。組み込みのカテゴリの色と同じ基準にする（ライトは白い記号を
    /// 載せて 4:1 以上・地の上の図形として 3:1 以上、ダークは暗い地の上で 4.5:1 以上。`ThemeContrastTests`）。
    /// 並びを変えると、作ったカテゴリの色が変わってしまうので、足すときは後ろに足す。
    static let customCategoryChoices: [ColorPair] = [
        ColorPair(light: 0x3949AB, dark: 0x9FA8FF), // 群青
        ColorPair(light: 0xA8323E, dark: 0xFF8A95), // 蘇芳
        ColorPair(light: 0x1B7F5A, dark: 0x5FD3A5), // 常盤
        ColorPair(light: 0xA85400, dark: 0xFFB066), // 柿
        ColorPair(light: 0x6A4CB0, dark: 0xB9A2FF), // 桔梗
        ColorPair(light: 0x283E6B, dark: 0x8FB0E6), // 鉄紺
        ColorPair(light: 0x5E6420, dark: 0xCDD27F), // 海松
        ColorPair(light: 0xAD2F6B, dark: 0xFF8FC0), // 薔薇
        ColorPair(light: 0x7A4B3A, dark: 0xD7A995), // 栗
        ColorPair(light: 0x45413C, dark: 0xCFCAC3), // 墨
    ]

    /// 作ったカテゴリの色（番号が範囲の外なら 0 番。新しい版の端末で足した色が iCloud で届いたときなど）。
    static func customCategory(_ index: Int) -> ColorPair {
        customCategoryChoices.indices.contains(index) ? customCategoryChoices[index] : customCategoryChoices[0]
    }
}

extension CategoryCatalog {
    /// カテゴリの色の組（作ったカテゴリは選んだ色、組み込みは `Palette.category`）。
    func colorPair(for category: EntryCategory) -> ColorPair {
        info(for: category).map { Palette.customCategory($0.colorIndex) } ?? Palette.category(category)
    }

    /// カテゴリの色。
    func color(for category: EntryCategory) -> Color {
        colorPair(for: category).color
    }

    /// カテゴリの記号（SF Symbols）。
    func symbolName(for category: EntryCategory) -> String {
        info(for: category)?.symbolName ?? category.symbolName
    }

    /// 画面に出す名前（組み込みは訳した名前、作ったカテゴリは利用者が決めた名前のまま）。
    func label(for category: EntryCategory) -> Text {
        if let info = info(for: category) { return Text(verbatim: info.name) }
        return Text(category.label)
    }

    /// 画面の言語の名前の文字列（読み上げと、文字列を組み立てるところで使う）。
    func localizedName(for category: EntryCategory) -> String {
        info(for: category)?.name ?? String(localized: category.label)
    }
}

extension EnvironmentValues {
    /// カテゴリの一覧（作ったカテゴリの名前・記号・色を引く）。ホーム（`HomeView`）が渡す。渡されていなければ組み込みの 8 種だけ。
    @Entry var categoryCatalog: CategoryCatalog = .builtIn
}

extension Color {
    /// ライトとダークで値を切り替える色。
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension EntryCategory {
    /// 画面に出す名前。コアの `displayName` は AI への指示と解析に使う日本語で固定なので、
    /// 表示用は String Catalog で英語に訳せるよう別に持つ。
    var label: LocalizedStringResource {
        switch self {
        // 作ったカテゴリの名前は `CategoryCatalog.label(for:)` で引く（ここは一覧に無いときの「その他」）。
        case .custom: "その他"
        case .food: "食費"
        case .daily: "日用品"
        case .transport: "交通"
        case .cafe: "カフェ"
        case .entertainment: "娯楽"
        case .utilities: "光熱・通信"
        case .medical: "医療"
        case .other: "その他"
        }
    }
}
