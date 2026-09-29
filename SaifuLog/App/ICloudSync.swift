import CloudKit
import Foundation

/// この端末の iCloud のアカウントの状態（CloudKit の `CKAccountStatus`）。設定で iCloud 同期をオンにする前の確かめと、
/// オンのときの案内、診断画面に使う。
///
/// CloudKit の型をそのまま画面やテストに持ち込まず、ここで写し替える。`CKContainer` は iCloud の entitlement の無い
/// プロセス（署名なしのビルドで動かすアプリのテスト）で作ると落ちるので、状態を読むのは `current()` だけにし、
/// テストでは値を渡す。
enum ICloudAccountStatus: Equatable, Sendable {
    /// サインインしていて、このアプリの iCloud を使える。
    case available
    /// サインインしていない（iCloud Drive やこのアプリの iCloud をオフにしたときもこうなることがある）。
    case noAccount
    /// スクリーンタイムや機器の管理で、iCloud を使えないようにされている。
    case restricted
    /// いまは使えない（Apple アカウントの確認を求められているなど）。
    case temporarilyUnavailable
    /// 決められなかった。
    case couldNotDetermine
    /// 問い合わせが失敗した。エラーの説明文は端末の情報を含むことがあるので、ドメインと番号だけを持つ。
    case failed(domain: String, code: Int)

    init(_ status: CKAccountStatus) {
        switch status {
        case .available: self = .available
        case .noAccount: self = .noAccount
        case .restricted: self = .restricted
        case .temporarilyUnavailable: self = .temporarilyUnavailable
        case .couldNotDetermine: self = .couldNotDetermine
        // 新しい OS で足された状態は、使えるとはみなさない（同期をオンにさせない）。
        @unknown default: self = .couldNotDetermine
        }
    }

    /// 同期をオンにしてよいか。
    var isAvailable: Bool {
        self == .available
    }

    /// 診断画面に出す名前（訳さない）。
    var diagnosticName: String {
        switch self {
        case .available: "available"
        case .noAccount: "noAccount"
        case .restricted: "restricted"
        case .temporarilyUnavailable: "temporarilyUnavailable"
        case .couldNotDetermine: "couldNotDetermine"
        case .failed(let domain, let code): "error(\(domain) \(code))"
        }
    }

    /// 同期に使うコンテナで、いまの状態を問い合わせる。
    ///
    /// iCloud の entitlement が無いと `CKContainer` の生成で落ちる。署名して入れたアプリ（Xcode の Run・TestFlight・
    /// App Store）からだけ呼ぶ（アプリのテストでは差し替える）。
    static func current(containerIdentifier: String = ModelContainerFactory.iCloudContainerIdentifier) async -> ICloudAccountStatus {
        do {
            return ICloudAccountStatus(try await CKContainer(identifier: containerIdentifier).accountStatus())
        } catch {
            let error = error as NSError
            return .failed(domain: error.domain, code: error.code)
        }
    }
}

/// iCloud と同期する保存先を開けず、端末の中だけに戻したときの理由（起動や切り替えのときの知らせに出す）。
///
/// 理由を「サインインしていない」「容量が足りない」などに見分けることはしない。保存先を開く（`ModelContainer.init`）ときは
/// CloudKit につながず、アカウントも容量も確かめないので、そうした理由では開けなくならない（サインインしていなくても、
/// iCloud の entitlement が無くても開け、ログに出すだけ）。開けなくなるのは CloudKit の制約に合わないモデルのときで、
/// そのとき SwiftData は `SwiftDataError.loadIssueModelContainer` だけを投げ、Core Data の元のエラーを付けない
/// （どちらも署名なしのテストのプロセスで、シミュレータの iOS 26.4 で確かめた）。見分けても当たらないので、原因に近い
/// エラーのドメインと番号だけを残し、問い合わせに使えるようにする（説明文は端末のパスを含むことがあるので残さない）。
/// サインインしていないなど、開けても同期できない状態は、設定の画面が `ICloudAccountStatus` で確かめて案内する。
struct ICloudSyncFailure: Equatable, Sendable {
    let domain: String
    let code: Int

    init(domain: String, code: Int) {
        self.domain = domain
        self.code = code
    }

    /// 包まれた元のエラー（`NSUnderlyingErrorKey`）をたどり、いちばん奥（原因に近い）のエラーのドメインと番号を残す。
    init(error: any Error) {
        var innermost = error as NSError
        // 包み方が循環していても止まるよう、たどる数に上限を付ける。
        for _ in 0..<32 {
            guard let underlying = innermost.userInfo[NSUnderlyingErrorKey] as? NSError else { break }
            innermost = underlying
        }
        self.init(domain: innermost.domain, code: innermost.code)
    }
}

// MARK: - 利用者向けの文

extension ICloudSyncFailure {
    /// 端末の中だけに戻した理由の文（起動や切り替えのときの知らせに出す）。
    var reasonText: String {
        // 番号は文字にしてから埋め込む。数のまま埋め込むと、地域の書き方で桁区切りが入り（「134,060」）、
        // 問い合わせや検索に写したときに本当の番号と食い違うため。
        let codeText = String(code)
        return String(localized: "理由: \(domain) \(codeText)")
    }
}

extension ICloudAccountStatus {
    /// 同期をオンにできない（オンのまま同期できない）ときの案内。使えるときは nil。
    ///
    /// CKAccountStatus からは iCloud の空き容量は分からないので、容量のことは設定の注記で伝える。
    var guidanceText: String? {
        switch self {
        case .available:
            nil
        case .noAccount:
            String(localized: "iCloud にサインインしていません。iPhone の設定でサインインしてから、もう一度お試しください。サインインしているときは、設定の iCloud で iCloud Drive とこのアプリがオフになっていないかも確かめてください。")
        case .restricted:
            String(localized: "この iPhone では iCloud の利用が制限されています（スクリーンタイムや機器の管理の設定など）。")
        case .temporarilyUnavailable:
            String(localized: "いまは iCloud を使えません。iPhone の設定で、Apple アカウントの確認を求められていないかを確かめてください。")
        case .couldNotDetermine, .failed:
            String(localized: "iCloud の状態を確かめられませんでした。インターネットにつながっているかを確かめて、もう一度お試しください。")
        }
    }
}

extension ICloudAccountStatus {
    /// 同期がオンなのに iCloud を使えないときの、設定の節の中の案内。使えるときは nil。
    ///
    /// 保存先は開けていて、記録はこの端末に保存されている（同期だけが止まっている）ことを伝える。オンにしようとしたときの
    /// 案内（`guidanceText`）と違い、「もう一度お試しください」とは書かない（試すことが無いため）。
    var pausedText: String? {
        switch self {
        case .available:
            nil
        case .noAccount:
            String(localized: "iCloud にサインインしていないため、この iPhone の中だけに保存しています。iPhone の設定で iCloud にサインインしてください（サインインしているときは、設定の iCloud で iCloud Drive とこのアプリがオフになっていないかを確かめてください）。")
        case .restricted:
            String(localized: "この iPhone では iCloud の利用が制限されているため、この iPhone の中だけに保存しています。")
        case .temporarilyUnavailable:
            String(localized: "いまは iCloud を使えないため、この iPhone の中だけに保存しています。iPhone の設定で、Apple アカウントの確認を求められていないかを確かめてください。")
        case .couldNotDetermine, .failed:
            String(localized: "iCloud の状態を確かめられませんでした。インターネットにつながっているかを確かめてください。")
        }
    }
}
