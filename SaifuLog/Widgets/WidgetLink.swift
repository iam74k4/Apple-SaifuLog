import Foundation

/// ウィジェットを押したときにアプリへ渡す URL（このファイルはアプリとウィジェットの拡張の両方に入れる。`project.yml`）。
///
/// 押すと、会話の入力欄にキーボードを出してアプリを開く（ウィジェットで今月の額を見てから、そのまま記録できるように）。
/// 形は「saifulog://record」だけ。スキームは `SaifuLog/Info.plist` の CFBundleURLTypes。ほかのアプリから開かれても、入力欄を
/// 開くだけで、何も記録しない。
enum WidgetLink {
    static let scheme = "saifulog"
    static let recordHost = "record"

    static let record = URL(string: "\(scheme)://\(recordHost)")!

    static func isRecord(_ url: URL) -> Bool {
        url.scheme?.lowercased() == scheme && url.host()?.lowercased() == recordHost
    }
}
