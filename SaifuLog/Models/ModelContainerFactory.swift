import Foundation
import SwiftData

/// 記録の保存先（ModelContainer）を作る唯一の場所。アプリ・テスト・プレビューのすべてがここを通る。
///
/// 保存先の場所と iCloud の扱いは、SwiftData の既定に任せず明示する。既定のままだと、あとから entitlement を
/// 足しただけで動きが変わるため。iCloud の entitlement を足すと、利用者が有効にしていなくても同期が始まる
/// （`cloudKitDatabase` の既定は `.automatic`）。App Group を足すと、既定の保存先が共有のコンテナへ移り、
/// それまでの記録が読めなくなる（`groupContainer` の既定も `.automatic`）。
enum ModelContainerFactory {
    /// iCloud と同期するか。
    ///
    /// SwiftData の `ModelConfiguration.CloudKitDatabase` をそのまま受けず、使う値だけを並べる。
    /// `.automatic` を渡せないようにするため。iCloud 同期（利用者が設定で選ぶ。既定はオフ）を作るときに、
    /// 利用者の私用データベースのケースを足す。
    enum CloudKitDatabase: Hashable, Sendable {
        /// 端末の中だけに保存する。
        case none

        var configurationValue: ModelConfiguration.CloudKitDatabase {
            switch self {
            case .none: .none
            }
        }
    }

    /// 保存するモデル。モデルを足すときはここに並べる（アプリ・テスト・プレビューが同じ一覧を使う）。
    ///
    /// 足したモデルは、それまでの保存先を開いたときに SwiftData が自動で移行する（テーブルを足すだけで、
    /// 記録はそのまま読める。テストで確かめている）。既存のモデルの項目を変えるときは、自動の移行で済むかを
    /// 先に確かめる（iCloud 同期を入れた後は、CloudKit の制約で項目の削除や型の変更ができない）。
    static var modelTypes: [any PersistentModel.Type] {
        [Entry.self, Budget.self]
    }

    static var schema: Schema {
        Schema(modelTypes)
    }

    /// 記録の保存先のファイル。
    ///
    /// SwiftData の既定の場所（Application Support/default.store）と同じ。変えると、それまでの記録が
    /// 読めなくなる（新しい空の保存先が作られる）ので変えないこと。既定と同じ場所であることはテストで確かめている。
    static var storeURL: URL {
        URL.applicationSupportDirectory.appending(path: "default.store", directoryHint: .notDirectory)
    }

    /// 端末に保存する保存先を開く。開けなければ throw する（呼び出し側の `StoreHost` が再試行の画面を出す）。
    static func makeContainer(cloudKitDatabase: CloudKitDatabase = .none) throws -> ModelContainer {
        try makeContainer(url: storeURL, cloudKitDatabase: cloudKitDatabase)
    }

    /// `url` のファイルに保存する保存先を開く。テストで一時フォルダに開くために場所を受け取れるようにしている。
    static func makeContainer(url: URL, cloudKitDatabase: CloudKitDatabase) throws -> ModelContainer {
        // 保存先のフォルダ（Application Support）は、初回起動の時点ではまだ無い。無いまま開くと Core Data が
        // 「作れなかった」というエラーを何十行もログに出してから自分で作り直す（動作は正常）。そのノイズで
        // 本物のエラーを見落とさないよう、先に作っておく。失敗してもここでは止めない。本当に開けなければ
        // 下の ModelContainer が throw する。
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return try ModelContainer(for: schema, configurations: [configuration(url: url, cloudKitDatabase: cloudKitDatabase)])
    }

    static func configuration(url: URL, cloudKitDatabase: CloudKitDatabase) -> ModelConfiguration {
        ModelConfiguration(schema: schema, url: url, cloudKitDatabase: cloudKitDatabase.configurationValue)
    }

    /// メモリの上だけの保存先（テストとプレビュー用）。ファイルには書かないので、前の記録が残らない。
    ///
    /// iCloud はここでも明示的に切る。`ModelConfiguration(isStoredInMemoryOnly:)` の既定は `.automatic` で、
    /// iCloud の entitlement を足した時点で、テストやプレビューまで iCloud と同期しようとするため。
    static func makeInMemoryContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
