// 診断画面は社内テスト用のビルド（release.yml の mode=testflight。make archive INTERNAL_BUILD=YES）と
// DEBUG のビルドにだけ入れる。App Store へ出すビルドに入っていないことは、release.mk がアーカイブの中身
// （下の buildMarker）で確かめる。
#if DEBUG || INTERNAL_DIAGNOSTICS
import Foundation

/// 診断画面に出し、まとめてコピーする値。
///
/// 家計の中身（金額・メモ・入力した文・予算の額）は持たず、件数と、端末・OS・保存先の状態だけを持つ。
/// コピーした文は不具合の相談などに貼り付けるので、個人のデータを混ぜない。端末の名前も持たない
/// （利用者の名前が入っていることがある）。保存先のパスも持たない（アプリの領域の ID が入るうえ、見比べる役にも立たない）。
struct DiagnosticsReport: Sendable {
    /// 診断画面が入ったビルドの印。release.mk の `RELEASE_INTERNAL_MARKER` と同じ値にする（変えるときは両方）。
    ///
    /// release.mk は、アーカイブのアプリの中にこの文字列があるかで診断画面が入っているかを見分け、App Store へ出す
    /// ビルド（INTERNAL_BUILD=NO）に入っていれば止める。社内テスト用のビルド（INTERNAL_BUILD=YES）で見つからなくても
    /// 止める（印を変えて release.mk を直し忘れたときに、「入っていない」の確かめが空振りしないように）。
    /// 16 バイト以上にしておく（15 バイトまでの文字列は、Swift がバイナリに文字列として置かないことがあるため）。
    /// コピーする文の先頭の行に使い、最適化で消されないようにしている。
    static let buildMarker = "SaifuLog-InternalDiagnostics-v1"

    /// 端末内 AI の区切りの ID。画面はこの区切りに「生成を試す」のボタンを足す。
    static let foundationModelsSectionID = "foundationModels"

    var sections: [Section]

    /// 画面の 1 つの区切り。
    struct Section: Identifiable, Sendable {
        var id: String
        var title: LocalizedStringResource
        var rows: [Row]
    }

    /// 1 つの項目。画面には `label` と `value`、コピーする文には `key: value` を出す。
    struct Row: Identifiable, Sendable {
        var id: String { key }
        /// コピーする文のキー。言語によらず同じにする（別の端末や言語の設定で取った診断と見比べやすいように）。
        var key: String
        var label: LocalizedStringResource
        /// 値も訳さない（機種の ID や保護クラスの名前など、そのまま検索できる形で出す）。
        var value: String
    }

    /// まとめてコピーする文。画面と同じ値を、1 行に 1 項目ずつ並べる。
    var text: String {
        let lines = sections.flatMap { section in section.rows.map { "\($0.key): \($0.value)" } }
        return ([Self.buildMarker] + lines).joined(separator: "\n")
    }

    /// キーの値（テストで使う）。
    func value(for key: String) -> String? {
        sections.lazy.flatMap(\.rows).first { $0.key == key }?.value
    }
}

// MARK: - 集める値

extension DiagnosticsReport {
    struct AppInfo: Equatable, Sendable {
        /// CFBundleShortVersionString。
        var version: String
        /// CFBundleVersion（TestFlight のビルド番号）。
        var build: String
        /// 社内テスト用か DEBUG か。
        var kind: String
    }

    struct DeviceInfo: Equatable, Sendable {
        /// 例: iOS 26.1。
        var os: String
        /// 例: Version 26.1 (Build 23B85)。同じ版でもビルドで挙動が違うことがあるので、ビルドまで残す。
        var osDetail: String
        /// 機種の ID（例: iPhone17,1）。販売名よりも、対応機種の表と突き合わせやすい。
        var model: String
    }

    struct FoundationModelsStatus: Equatable, Sendable {
        /// 例: available / unavailable(deviceNotEligible)。
        var availability: String
        var supportsJapanese: Bool
        /// 画像を入力できるか。iOS 26 では調べられない（nil）。
        var supportsVision: Bool?
    }

    /// 生成の試し（「生成を試す」）の状態と結果。
    ///
    /// 使えるか（availability）が available でも、生成が毎回失敗する端末がある（モデルの資産が無いシミュレータなど）。
    /// 使えるかの行だけでは見分けられないので、実際に 1 回生成して確かめる。
    enum GenerationProbe: Equatable, Sendable {
        /// まだ試していない。
        case notRun
        /// 試している。
        case running
        /// 生成できた。かかった時間（セッションを作ってから答えが返るまで）。
        case succeeded(latency: Duration)
        /// 生成が失敗した（エラーの型・ドメイン・番号だけ。説明文は持たない）。
        case failed(AIErrorSummary)
        /// 上限の時間までに返らなかった。
        case timedOut(Duration)

        /// 時間はミリ秒で、桁区切りを入れずに書く（言語の設定によらず同じ形にし、そのまま比べられるように）。
        var description: String {
            switch self {
            case .notRun: "not run"
            case .running: "running"
            case .succeeded(let latency): "ok (\(Self.milliseconds(latency)) ms)"
            case .failed(let error): error.description
            case .timedOut(let limit): "timeout (\(Self.milliseconds(limit)) ms)"
            }
        }

        static func milliseconds(_ duration: Duration) -> Int64 {
            let (seconds, attoseconds) = duration.components
            return seconds * 1_000 + attoseconds / 1_000_000_000_000_000
        }
    }

    /// 音声の書き起こしの問い合わせがまだ返っていないときの値（`init` の `speech` が nil のとき）。
    static let checking = "checking"

    struct SpeechStatus: Equatable, Sendable {
        /// この端末で SpeechTranscriber が使えるか。
        var isAvailable: Bool
        /// 日本語に当たる言語（例: ja_JP）。対応していなければ nil。
        var japaneseLocale: String?
        /// 日本語のモデルが端末に入っているか。
        var isJapaneseInstalled: Bool
        /// 声の入力で使っている経路（speechTranscriber / dictationTranscriber / none。`VoiceRoute`）。
        var route: String
        /// その経路のモデルの状態（installed / needsReservation / needsDownload / downloading。経路が無ければ none）。
        var model: String
    }

    /// 保存先のファイル 1 つの保護クラス。
    struct StoreFile: Equatable, Sendable {
        var name: String
        var protection: FileProtectionStatus
    }

    enum FileProtectionStatus: Equatable, Sendable {
        /// ファイルが無い（まだ作られていない、-wal / -shm が片づいた後など）。
        case missing
        /// 保護クラス（例: NSFileProtectionComplete）。
        case protected(String)
        /// ファイルはあるが、保護クラスを返さなかった。
        case unknown
        /// 読めなかった。エラーの説明文はパスを含むことがあるので、ドメインと番号だけを持つ。
        case failed(domain: String, code: Int)

        var description: String {
            switch self {
            case .missing: "missing"
            case .protected(let name): name
            case .unknown: "unknown"
            case .failed(let domain, let code): "error(\(domain) \(code))"
            }
        }
    }

    /// 記録と予算の件数。読めなければ nil。
    struct RecordCounts: Equatable, Sendable {
        var entries: Int?
        var budgetRows: Int?
    }

    /// iCloud 同期の状態。
    struct ICloudStatus: Equatable, Sendable {
        /// iCloud のアカウントの状態（`ICloudAccountStatus.diagnosticName`）。問い合わせが返るまでは nil（checking）。
        var account: String?
        /// いま開いている保存先の iCloud の扱い（none / private(コンテナ)）。
        var database: String
        /// 設定の「iCloud で同期」。開けずに端末の中だけへ戻したときは false になっている。
        var isSyncSettingOn: Bool
    }

    /// 家計の共有の状態（家計の中身・名前は持たない。件数と立場と保存先の保護クラスだけ）。
    struct HouseholdStatus: Equatable, Sendable {
        /// 家計の保存先を開けたか。
        var isStoreOpen: Bool
        /// 家計での立場（none / owner / participant）。
        var role: String
        /// 家計の記録の件数。読めなければ nil。
        var entries: Int?
        /// 自分の表示名を決めたか（名前そのものは出さない）。
        var hasMemberName: Bool
        /// 家計の保存先のファイル（本体・-wal・-shm）の保護クラス。
        var storeFiles: [StoreFile]
    }

    init(
        app: AppInfo,
        device: DeviceInfo,
        foundationModels: FoundationModelsStatus,
        speech: SpeechStatus?,
        storeFiles: [StoreFile],
        isProtectedDataAvailable: Bool,
        counts: RecordCounts,
        iCloud: ICloudStatus,
        household: HouseholdStatus? = nil,
        aiFallbacks: AIFallbackLog.Snapshot = AIFallbackLog.Snapshot(),
        generationProbe: GenerationProbe = .notRun
    ) {
        sections = [
            Section(id: "app", title: "アプリ", rows: [
                Row(key: "app.version", label: "版", value: app.version),
                Row(key: "app.build", label: "ビルド番号", value: app.build),
                Row(key: "app.buildKind", label: "ビルドの種類", value: app.kind),
            ]),
            Section(id: "device", title: "端末", rows: [
                Row(key: "os", label: "OS", value: device.os),
                Row(key: "os.detail", label: "OS の詳細", value: device.osDetail),
                Row(key: "device.model", label: "機種", value: device.model),
            ]),
            Section(id: Self.foundationModelsSectionID, title: "端末内 AI（Foundation Models）", rows: [
                Row(key: "fm.availability", label: "使えるか", value: foundationModels.availability),
                Row(key: "fm.japanese", label: "日本語に対応", value: String(foundationModels.supportsJapanese)),
                Row(
                    key: "fm.vision", label: "画像の入力（iOS 27 から）",
                    value: foundationModels.supportsVision.map(String.init) ?? "n/a (before iOS 27)"
                ),
                Row(key: "fm.generation", label: "生成の試し", value: generationProbe.description),
            ] + Self.fallbackRows(aiFallbacks)),
            // 音声の問い合わせは返るまで待たずに画面を出すので、返る前はすべて checking にする。
            Section(id: "speech", title: "音声の書き起こし（SpeechTranscriber）", rows: [
                Row(key: "speech.available", label: "使えるか", value: speech.map { String($0.isAvailable) } ?? Self.checking),
                Row(
                    key: "speech.japaneseLocale", label: "日本語の言語",
                    value: speech.map { $0.japaneseLocale ?? "none" } ?? Self.checking
                ),
                Row(
                    key: "speech.japaneseInstalled", label: "日本語のモデルが入っているか",
                    value: speech.map { String($0.isJapaneseInstalled) } ?? Self.checking
                ),
                // SpeechTranscriber が日本語に対応しない端末では DictationTranscriber に切り替えるので、どちらを使っているかも出す。
                Row(key: "speech.route", label: "使っている経路", value: speech.map(\.route) ?? Self.checking),
                Row(key: "speech.model", label: "経路のモデルの状態", value: speech.map(\.model) ?? Self.checking),
            ]),
            Section(
                id: "store", title: "保存先",
                rows: storeFiles.map { file in
                    Row(key: "store.\(file.name)", label: "\(file.name) の保護クラス", value: file.protection.description)
                } + [
                    Row(
                        key: "store.protectedDataAvailable", label: "保護されたデータを読めるか",
                        value: String(isProtectedDataAvailable)
                    ),
                ]
            ),
            Section(id: "records", title: "記録", rows: [
                Row(key: "records.entries", label: "記録の件数", value: counts.entries.map(String.init) ?? "error"),
                Row(key: "records.budgetRows", label: "予算の行数", value: counts.budgetRows.map(String.init) ?? "error"),
            ]),
            // 同期がオンなのにそろわないときに、アカウント・開いた保存先・設定のどこが食い違っているかを見比べる。
            // コンテナの ID はアプリのもので、利用者の情報ではない。
            Section(id: "icloud", title: "iCloud", rows: [
                Row(key: "icloud.account", label: "アカウントの状態", value: iCloud.account ?? Self.checking),
                Row(key: "icloud.database", label: "いまの保存先の同期", value: iCloud.database),
                Row(key: "icloud.syncSetting", label: "設定の「iCloud で同期」", value: String(iCloud.isSyncSettingOn)),
            ]),
        ]
        // 家計の共有（有効なビルドで、家計の受け持ちを渡されたときだけ）。家計の保存先の保護クラスを実機で確かめるのにも使う。
        if let household {
            sections.append(Section(
                id: "household", title: "家族と共有",
                rows: [
                    Row(key: "household.store", label: "家計の保存先", value: household.isStoreOpen ? "open" : "unavailable"),
                    Row(key: "household.role", label: "家計での立場", value: household.role),
                    Row(key: "household.entries", label: "家計の記録の件数", value: household.entries.map(String.init) ?? "error"),
                    Row(key: "household.memberName", label: "表示名を決めたか", value: String(household.hasMemberName)),
                ] + household.storeFiles.map { file in
                    Row(key: "household.file.\(file.name)", label: "\(file.name) の保護クラス", value: file.protection.description)
                }
            ))
        }
    }

    /// 起動してから AI の結果を使わなかった回数と、最後の失敗の行。AI が失敗しても利用者には辞書の結果だけを見せるので、
    /// 「使える」と出るのに毎回失敗している端末を、ここで見分ける（`AIFallbackLog`）。失敗が無ければ、最後の失敗の機能と
    /// 日時の行は出さない。
    static func fallbackRows(_ snapshot: AIFallbackLog.Snapshot) -> [Row] {
        // 機能ごとの回数は、0 回の機能も決まった順で並べる（別の端末や日の診断と見比べやすいように）。
        let byFeature = AIFeature.allCases.map { "\($0.rawValue) \(snapshot.fallbacks[$0] ?? 0)" }.joined(separator: ", ")
        var rows = [
            Row(key: "fm.fallbacks", label: "AI の結果を使わなかった回数（起動から）", value: "\(snapshot.totalFallbacks) (\(byFeature))"),
            Row(key: "fm.lastError", label: "最後のエラー", value: snapshot.lastError?.error.description ?? "none"),
        ]
        if let lastError = snapshot.lastError {
            rows += [
                Row(key: "fm.lastError.feature", label: "最後のエラーの機能", value: lastError.feature.rawValue),
                Row(key: "fm.lastError.at", label: "最後のエラーの日時", value: lastError.date.formatted(.iso8601)),
            ]
        }
        return rows
    }
}
#endif
