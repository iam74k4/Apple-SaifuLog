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

    /// 音声の書き起こしの問い合わせがまだ返っていないときの値（`init` の `speech` が nil のとき）。
    static let checking = "checking"

    struct SpeechStatus: Equatable, Sendable {
        /// この端末で SpeechTranscriber が使えるか。
        var isAvailable: Bool
        /// 日本語に当たる言語（例: ja_JP）。対応していなければ nil。
        var japaneseLocale: String?
        /// 日本語のモデルが端末に入っているか。
        var isJapaneseInstalled: Bool
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

    init(
        app: AppInfo,
        device: DeviceInfo,
        foundationModels: FoundationModelsStatus,
        speech: SpeechStatus?,
        storeFiles: [StoreFile],
        isProtectedDataAvailable: Bool,
        counts: RecordCounts
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
            Section(id: "foundationModels", title: "端末内 AI（Foundation Models）", rows: [
                Row(key: "fm.availability", label: "使えるか", value: foundationModels.availability),
                Row(key: "fm.japanese", label: "日本語に対応", value: String(foundationModels.supportsJapanese)),
                Row(
                    key: "fm.vision", label: "画像の入力（iOS 27 から）",
                    value: foundationModels.supportsVision.map(String.init) ?? "n/a (before iOS 27)"
                ),
            ]),
            // 音声の問い合わせは返るまで待たずに画面を出すので、返る前は 3 つとも checking にする。
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
            // iCloud の同期を作るまでは項目だけ置く（CKContainer.accountStatus は、iCloud の entitlement を足してから
            // でないと調べられない）。
            Section(id: "icloud", title: "iCloud", rows: [
                Row(key: "icloud.account", label: "アカウントの状態", value: "not implemented"),
            ]),
        ]
    }
}
#endif
