import SaifuLogCore
import SwiftUI
import UIKit

/// 画面の色をまとめる場所。配色は「墨 × 山吹」（docs/design.md §7）。
///
/// 画面側では色を直接書かず、ここのトークンを使う。値は `Palette` に 16 進で置き、SaifuLogTests が
/// そこから WCAG のコントラスト比を確かめる（値を変えるときは、テストが通るかで読めるかを確かめる）。
/// ライトとダークは iOS の設定に従う（アプリ内に外観の設定は置かない）。
///
/// 使い分け:
/// - 山吹（`accentFill`）は塗りにだけ使う（送信ボタン・主ボタン・選んだ額のボタン・予算の進捗バー・タイムラインの自分が送った文の
///   吹き出し）。
///   白地では 1.8:1 しかなく、ライトで文字や細いアイコンに使うと読めないため。塗りの上の文字と記号は
///   `onAccent`（墨）にする。白を載せると、ライトでもダークでも 2:1 に届かない。
/// - 文字の強調（ボタンの文字など）は `accentText`。Assets の AccentColor で、アプリ全体の tint でもある
///   （ライトは濃い琥珀、ダークは山吹）。
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
    /// 山吹。塗りにだけ使う（上の説明）。
    static let accentFill = Palette.accentFill.color
    /// 山吹の塗りの上に載せる文字と記号。
    static let onAccent = Palette.onAccent.color
    /// タイムラインの自分の吹き出し（送った文・質問）の面。墨の文字を載せる。背景とアプリの返事のカード（面）の
    /// どちらとも見分けられる灰色にする。
    static let userBubble = Palette.userBubble.color
    /// 文字の強調の色（Assets の AccentColor。値は `Palette.accentText` と同じにしてあり、テストで照合する）。
    static let accentText = Color.accentColor
    /// 注意の色（予算オーバーなど）。アイコンと文字を必ず添える。
    static let danger = Palette.danger.color
    /// 進捗のバーの地（まだ使っていない分）。バーは数字に添える目安なので、地との差は控えめでよい。返事のカードの細い枠にも使う。
    static let track = Palette.track.color
    /// 収入の金額の色。収入は「+」の符号と「収入」の語でも示す（色だけに頼らない）。
    static let income = Palette.income.color
    /// カテゴリの丸に載せる記号の色。
    static let onCategory = Palette.onCategory.color

    /// カテゴリの色。
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
    static let background = ColorPair(light: 0xF7F6F3, dark: 0x121418)
    static let surface = ColorPair(light: 0xFFFFFF, dark: 0x1C1F24)
    static let ink = ColorPair(light: 0x1F1D1A, dark: 0xF2F1EE)
    static let inkSecondary = ColorPair(light: 0x5F5B55, dark: 0xA8A6A1)
    static let accentFill = ColorPair(light: 0xF8B500, dark: 0xFFC62E)
    static let onAccent = ColorPair(light: 0x1F1D1A, dark: 0x1F1D1A)
    static let userBubble = ColorPair(light: 0xE8E5DE, dark: 0x2C3037)
    /// Assets の AccentColor と同じ値にする（二か所にあるので、テストで食い違いを止める）。
    static let accentText = ColorPair(light: 0x8A5A00, dark: 0xFFC62E)
    static let danger = ColorPair(light: 0xB3261E, dark: 0xFF8A80)
    static let track = ColorPair(light: 0xE4E1DA, dark: 0x2E3238)
    static let income = ColorPair(light: 0x2E7D4F, dark: 0x7FD1A0)
    /// カテゴリの丸と返事の行の印はダークでもライトの色で塗る（EntryBubble・RecordedReplyRow）ので、記号は両方とも白にする。
    static let onCategory = ColorPair(light: 0xFFFFFF, dark: 0xFFFFFF)

    /// カテゴリの色。
    ///
    /// ライトの値は塗り（丸）と記号の地に使い、白い記号を載せて 4:1 以上にしてある。白地の上の文字には使わない
    /// （食費と日用品は 4.5:1 に届かない）。ダークの値は暗い地の上で文字にも使える明るさ（4.5:1 以上）にしてある。
    /// システムの色（.orange や .teal）は明るく、白い記号とのコントラストが 3:1 に届かないため使わない。
    /// 光熱・通信は、山吹と見分けにくい琥珀をやめて青緑にした。
    static func category(_ category: EntryCategory) -> ColorPair {
        switch category {
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
