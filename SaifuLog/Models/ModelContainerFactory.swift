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
    /// `.automatic` を渡せないようにするため（entitlement を足しただけで、利用者が選んでいないのに同期が始まる）。
    enum CloudKitDatabase: Hashable, Sendable {
        /// 端末の中だけに保存する（既定）。
        case none
        /// 利用者自身の iCloud の私用データベースと同期する（設定の「iCloud で同期」をオンにしたときだけ）。
        /// 開発者は中身を読めない。家族との共有（共有データベース）には使わない。
        case `private`

        /// 設定の「iCloud で同期」（`AppSettings.iCloudSyncEnabled`）に当たる値。
        init(syncEnabled: Bool) {
            self = syncEnabled ? .private : .none
        }

        /// iCloud と同期するか。
        var isSyncEnabled: Bool {
            self == .private
        }

        /// 診断画面とログに出す名前（訳さない）。
        var diagnosticName: String {
            switch self {
            case .none: "none"
            case .private: "private"
            }
        }

        var configurationValue: ModelConfiguration.CloudKitDatabase {
            switch self {
            case .none: .none
            case .private: .private(ModelContainerFactory.iCloudContainerIdentifier)
            }
        }
    }

    /// iCloud 同期に使う CloudKit のコンテナ。
    ///
    /// エンタイトルメント（project.yml の icloud-container-identifiers）は Config/Base.xcconfig の
    /// `ICLOUD_CONTAINER_ID = iCloud.$(APP_BUNDLE_ID)` を使う。Swift からはビルドの設定を読めないので、同じ決まり
    /// （「iCloud.」と Bundle ID）でここでも組み立てる。ID を文字で書き写すと、`ORG_PREFIX` を上書きして自分のチームで
    /// 入れたときに、entitlement のコンテナと食い違って同期できないため。決まりを変えるときは両方を直す。
    /// アプリの拡張（ウィジェットなど）から使うときは、拡張の Bundle ID ではなくアプリの Bundle ID から組み立てること。
    static var iCloudContainerIdentifier: String {
        iCloudContainerIdentifier(bundleIdentifier: Bundle.main.bundleIdentifier)
    }

    /// Bundle ID から CloudKit のコンテナの ID を組み立てる（読めなければ作者の Bundle ID を使う）。
    static func iCloudContainerIdentifier(bundleIdentifier: String?) -> String {
        "iCloud." + (bundleIdentifier ?? "com.iam74k4.SaifuLog")
    }

    /// 保存するモデル。モデルを足すときはここに並べる（アプリ・テスト・プレビューが同じ一覧を使う）。
    ///
    /// 足したモデルは、それまでの保存先を開いたときに SwiftData が自動で移行する（テーブルを足すだけで、
    /// 記録はそのまま読める。テストで確かめている）。既存のモデルの項目を変えるときは、自動の移行で済むかを
    /// 先に確かめる。iCloud 同期を出した後は、CloudKit の制約（すべての項目に既定値か optional、一意制約なし、
    /// 関係は optional で逆向きあり。テストで確かめている）を守り、項目の削除・名前や型の変更をしない
    /// （Production に出した CloudKit のスキーマは、足すことしかできないため）。
    /// 項目は足すときから `@Attribute(.allowsCloudEncryption)` を付けて暗号化フィールドにする（テストで確かめている）。
    /// CloudKit は、一度スキーマに載った項目を暗号化フィールドに変えられないため。暗号化の指定は Core Data のモデルの版
    /// （バージョンハッシュ）に入らないので、指定を足しても端末の保存先は移行なしでそのまま開ける（どちらもテストで確かめている）。
    static var modelTypes: [any PersistentModel.Type] {
        [Entry.self, Budget.self, LearnedCategory.self]
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

    /// 端末に保存する保存先を開く。開けなければ throw する（呼び出し側の `StoreHost` が再試行の画面を出すか、
    /// iCloud と同期する保存先なら端末の中だけに戻して開き直す）。
    ///
    /// iCloud 同期のオンとオフで、同じファイル（`storeURL`）を使う。オンにした時点でこの端末にある記録が iCloud に
    /// 上がり、オフに戻してもこの端末の記録はそのまま残る（別のファイルにすると、切り替えのたびに記録が見えなくなるか、
    /// 写し替えが要る）。docs/design.md §5-3。
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

    // MARK: - 家計の保存先（家族・パートナーとの共有）

    /// 家計の保存先に置くモデル。自分の記録（`modelTypes`）とは別の保存先にする（docs/design.md §5-5）。
    ///
    /// SwiftData の CloudKit 同期は共有データベース（CKShare）を扱えないので、家計は CKSyncEngine が専用のゾーンと同期する。
    /// 同じ保存先に入れると、自分の記録の iCloud 同期（`.private`）が家計の記録まで自分の私用データベースに上げてしまうため、
    /// ファイルごと分ける。
    static var householdModelTypes: [any PersistentModel.Type] {
        [Household.self, HouseholdEntry.self, HouseholdSyncState.self]
    }

    static var householdSchema: Schema {
        Schema(householdModelTypes)
    }

    /// 家計の保存先のファイル（Application Support/household.store）。変えると、それまでの家計の記録と同期の状態が読めなくなる。
    ///
    /// 保護クラスは、自分の記録と同じくエンタイトルメントの既定（NSFileProtectionComplete）が効く（アプリが作るファイルの既定の
    /// クラスのため）。ロック中は開けないので、開くのは自分の記録の保存先を開けた後（`HouseholdHost.start`）。
    static var householdStoreURL: URL {
        URL.applicationSupportDirectory.appending(path: "household.store", directoryHint: .notDirectory)
    }

    /// 家計の保存先を開く。iCloud との同期は SwiftData に任せない（`cloudKitDatabase` はいつも `.none`。CKSyncEngine が同期する）。
    static func makeHouseholdContainer(url: URL = householdStoreURL) throws -> ModelContainer {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return try ModelContainer(for: householdSchema, configurations: [householdConfiguration(url: url)])
    }

    static func householdConfiguration(url: URL) -> ModelConfiguration {
        ModelConfiguration(schema: householdSchema, url: url, cloudKitDatabase: .none)
    }

    /// メモリの上だけの家計の保存先（テストとプレビュー用）。
    static func makeInMemoryHouseholdContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: householdSchema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: householdSchema, configurations: [configuration])
    }
}
