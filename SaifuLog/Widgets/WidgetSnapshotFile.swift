import Foundation
import SaifuLogCore

/// ウィジェットに渡す今月の数字（`WidgetSnapshot`）のファイル。アプリが書き、ウィジェットの拡張が読む（このファイルは両方の
/// ターゲットに入れる。`project.yml`）。
///
/// 置き場所は App Group の共有の領域（グループの ID は Info.plist の `SaifuLogAppGroup`。値は `Config/Base.xcconfig` の
/// `APP_GROUP_ID` から入る。ID を二か所に書かない）。UserDefaults の共有の領域は使わない（理由の申告が要る API を増やさないため。
/// `PrivacyInfo.xcprivacy`）。
///
/// 保護は「最初のロック解除の後は読める」にする。ロック画面のウィジェットは端末のロック中に描かれ、保存先と同じ Complete では
/// 読めないため。そのぶん、置くのは月・使った額・予算だけにする（`WidgetSnapshot`）。ロック画面では、数字はロック中に隠す
/// （ウィジェットの `privacySensitive`）。
enum WidgetSnapshotFile {
    static let fileName = "WidgetSnapshot.json"

    /// Info.plist に書いた App Group の ID。
    static var appGroupID: String? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "SaifuLogAppGroup") as? String, !id.isEmpty else { return nil }
        return id
    }

    /// ファイルの場所。App Group を使えない（エンタイトルメントが無い・署名なしのビルドなど）ときは nil。
    static var defaultURL: URL? {
        guard let appGroupID,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        else { return nil }
        return container.appending(path: fileName, directoryHint: .notDirectory)
    }

    /// 読む。無い・読めない・形が違うときは nil。
    static func read(from url: URL) -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return WidgetSnapshot.decode(data)
    }

    /// 書く（書きかけを読ませないよう、まとめて置き換える）。
    static func write(_ snapshot: WidgetSnapshot, to url: URL) throws {
        try snapshot.encoded().write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
