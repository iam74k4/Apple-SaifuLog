import SaifuLogCore
import SwiftUI
import UIKit

/// 画面の色をまとめる場所。
///
/// 配色は 3 案（和紙 × 藍 / ミント / 夜 × アプリコット）で検討中で、まだ決まっていない。
/// 決まったらここと Assets の AccentColor を差し替えるだけで済むよう、画面側では色を直接書かない
/// （Assets の AppIcon は白地に黒い財布のライト・ダーク・色付きの 3 枚で、配色には依存しない）。
/// ライトとダークは iOS の設定に従う（アプリ内に外観の設定は置かない）。
enum Theme {
    /// 画面の背景。
    static let background = Color(uiColor: .systemGroupedBackground)
    /// 記録の吹き出しの背景。
    static let bubble = Color(uiColor: .secondarySystemGroupedBackground)
    /// 強調の色（Assets の AccentColor。仮に藍）。
    static let accent = Color.accentColor
    /// 収入の金額の色。
    static let income = Color.dynamic(light: 0x2E7D4F, dark: 0x7FD1A0)

    /// カテゴリの色。どの配色案でも共通にする（配色を変えても見分け方が変わらないように）。
    /// 食費（朱系）と日用品（緑系）以外はまだ決まっていないので、システムの色に近い色相を仮に当てている。
    ///
    /// ライトの値は白い記号を載せても 4:1 以上、ダークの値は暗い地の上で 4.5:1 以上になるようにしている。
    /// システムの色（.orange や .teal）は明るく、白い記号とのコントラストが 3:1 に届かないため使わない。
    static func color(for category: EntryCategory) -> Color {
        switch category {
        case .food: .dynamic(light: 0xD9482B, dark: 0xFF7A5C)
        case .daily: .dynamic(light: 0x3E8E41, dark: 0x7BCB7E)
        case .transport: .dynamic(light: 0x1E6FD9, dark: 0x5AA9FF)
        case .cafe: .dynamic(light: 0x8B5E3C, dark: 0xC9A27E)
        case .entertainment: .dynamic(light: 0x9B40C4, dark: 0xC38EF0)
        case .utilities: .dynamic(light: 0xB45309, dark: 0xFFA24D)
        case .medical: .dynamic(light: 0x0B7285, dark: 0x4FD0E0)
        case .other: .dynamic(light: 0x6E6E73, dark: 0xAEAEB2)
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
