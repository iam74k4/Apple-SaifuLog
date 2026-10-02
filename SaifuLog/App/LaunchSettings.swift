import Foundation

/// 起動の前提になる設定（アプリのロックと iCloud 同期）。UserDefaults ではなく、保護クラスを決めた専用のファイルに置く。
///
/// UserDefaults の元のファイルは、アプリの入れ物の既定の保護（エンタイトルメントの NSFileProtectionComplete）を継ぐので、
/// ロック中には読めない。Apple Pay の支払いの受け取り（アプリを開かないショートカットの操作）やサイレントプッシュで、
/// ロック中にアプリが裏で起こされたときに UserDefaults を読むと、空の内容が覚えられ、ロックを解いた後も同じプロセスでは
/// 空のまま返る（Apple の開発者フォーラム thread 15685 の Apple のエンジニアの説明）。ロックの設定が「オフ」と読まれると、
/// 次に開いたときに Face ID を求めずに家計を見せてしまう。iCloud 同期の設定も「オフ」と読まれ、その起動の間は同期しない。
/// Apple の勧めに従い、裏で起こされる経路で頼る設定は、保護を自分で決めたファイルに置く。
///
/// 保護は「最初のロック解除の後は読める」（completeUntilFirstUserAuthentication）。ロック中に裏で起こされても読めるように
/// するため。中身は 2 つのオン・オフだけで、家計の中身を含まない。再起動して最初にロックを解く前は読めないので、読めなければ
/// 分からないもの（nil）として返し、使う側が読めるようになってから読み直す（ファイルは UserDefaults と違い、読めなかった
/// 内容を覚えない）。
@MainActor
final class LaunchSettingsStore {
    /// 設定の値。項目を足すときは既定値を付ける（前の版で書いたファイルにはその項目が無いため）。
    struct Values: Codable, Equatable, Sendable {
        /// アプリのロック（設定の「Face ID でロック」）がオンか。
        var appLockEnabled = false
        /// iCloud と同期するか（設定の「iCloud で同期」）。
        var iCloudSyncEnabled = false

        init(appLockEnabled: Bool = false, iCloudSyncEnabled: Bool = false) {
            self.appLockEnabled = appLockEnabled
            self.iCloudSyncEnabled = iCloudSyncEnabled
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            appLockEnabled = try container.decodeIfPresent(Bool.self, forKey: .appLockEnabled) ?? false
            iCloudSyncEnabled = try container.decodeIfPresent(Bool.self, forKey: .iCloudSyncEnabled) ?? false
        }
    }

    /// ファイルを読んだ結果。
    enum ReadResult: Equatable {
        case values(Values)
        /// まだ書いていない（初めて開いた・この版より前は UserDefaults に置いていた）。
        case missing
        /// あるのに読めない（再起動して最初にロックを解く前）。
        case unreadable
    }

    /// 書けなかった。
    struct WriteError: Error {}

    /// ファイルの読み書き。テストで、読めない・書けない場面に差し替える。
    struct FileAccess: Sendable {
        /// 読む。ファイルが無ければ nil、あるのに読めなければ throw。
        var read: @Sendable (URL) throws -> Data?
        /// 書く（最初のロック解除の後は読める保護で）。
        var write: @Sendable (Data, URL) throws -> Void

        static let live = FileAccess(
            read: { url in
                guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
                return try Data(contentsOf: url)
            },
            write: { data, url in
                // 入れ物の Application Support は初回の起動の時点ではまだ無いことがある。保護を指定せずに作る（エンタイトル
                // メントの既定の保護が効く。ここで弱い保護を付けると、後からその中に作るファイルが継いでしまうため）。
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
        )
    }

    /// アプリの設定のファイル（Application Support/LaunchSettings.json）。変えると、それまでの設定が読めなくなる。
    static var standardURL: URL {
        URL.applicationSupportDirectory.appending(path: "LaunchSettings.json", directoryHint: .notDirectory)
    }

    private let url: URL
    /// この版より前に置いていた UserDefaults（移すときだけ読む）。
    private let defaults: UserDefaults
    private let files: FileAccess

    /// - Parameters:
    ///   - url: 設定のファイル。テストは一時フォルダの中。
    ///   - defaults: この版より前に設定を置いていた UserDefaults（ファイルがまだ無いときに、値を移すために読む）。
    ///   - files: ファイルの読み書き。テストで差し替える。
    init(url: URL = LaunchSettingsStore.standardURL, defaults: UserDefaults = .standard, files: FileAccess = .live) {
        self.url = url
        self.defaults = defaults
        self.files = files
    }

    /// ファイルを読む。
    ///
    /// 読めたのに中身を解けないとき（壊れた）は、まだ書いていないものとして扱う（読めないものとして扱うと、使う側がいつまでも
    /// 読み直しを待ち、ロックの画面から抜けられなくなるため）。次に設定を変えたときに書き直す。
    func read() -> ReadResult {
        let data: Data?
        do {
            data = try files.read(url)
        } catch {
            return .unreadable
        }
        guard let data, let values = try? JSONDecoder().decode(Values.self, from: data) else { return .missing }
        return .values(values)
    }

    /// 設定を読む。読めない・まだ決められないときは nil。
    ///
    /// - Parameter migrating: ファイルがまだ無いときに、この版より前に UserDefaults へ置いていた値を移すか。保護されたデータが
    ///   読めると確かめた後だけ true にする（ロック中に UserDefaults を読むと、空の内容が覚えられてしまうため）。
    func load(migrating: Bool) -> Values? {
        switch read() {
        case .values(let values):
            return values
        case .unreadable:
            return nil
        case .missing:
            guard migrating else { return nil }
            return migrateFromUserDefaults()
        }
    }

    /// 設定を変えて書く。いまの値が読めなければ（ロック中など）書かずに throw する（読めない値を既定値で上書きしないため）。
    @discardableResult
    func update(_ change: (inout Values) -> Void) throws -> Values {
        guard var values = load(migrating: true) else { throw WriteError() }
        change(&values)
        try files.write(try JSONEncoder().encode(values), url)
        return values
    }

    /// この版より前に UserDefaults へ置いていた値をファイルへ移す。
    ///
    /// UserDefaults が空に見えるとき（初回の案内を終えたかの値も無い）は、移さずに既定のオフを返す。初めて開いた端末（初回の
    /// 案内を終える前は、ロックも iCloud もオンにできない）か、どこかで読めないまま空の内容を覚えてしまったプロセスで、どちらも
    /// オフを書くと、後者では利用者の設定を消してしまうため。ファイルは、次に開いたときか、設定を変えたときに書く。
    private func migrateFromUserDefaults() -> Values {
        guard defaults.object(forKey: AppSettings.hasCompletedOnboarding.key) != nil else { return Values() }
        let values = Values(
            appLockEnabled: defaults.bool(for: AppSettings.appLockEnabled),
            iCloudSyncEnabled: defaults.bool(for: AppSettings.iCloudSyncEnabled)
        )
        // 書けなくても、この起動では移した値を使う（次に開いたときにまた移す）。
        try? files.write(try JSONEncoder().encode(values), url)
        return values
    }
}
