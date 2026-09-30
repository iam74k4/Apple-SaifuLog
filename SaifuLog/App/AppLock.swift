import Foundation
import LocalAuthentication
import Observation
import SwiftUI

/// アプリのロック（設定の「Face ID でロック」。docs/design.md §9 の ⑧ の決め事）。
///
/// オンにすると、アプリを開くとき（起動したとき・裏から戻ったとき）に Face ID（Touch ID・パスコード）を求め、解除するまで
/// 家計の画面を出さない。アプリの切り替えの画面（iOS が撮る画面の写し）にも家計が写らないよう、前面を離れたら隠す。
///
/// 決め事:
/// - ロックするのは裏に回ったとき（`.background`）と起動したとき。コントロールセンターや通知を引き出したとき（`.inactive`）は
///   隠すだけでロックはしない（戻るたびに Face ID を求めると、すぐ戻っただけでも解除が要り、使いにくいため）。
/// - 解除は、ロックして最初に前面に出たときに 1 回だけ自動で求める。やめた・失敗したときは、ロックの画面の「ロックを解除」で
///   求め直す（自動で求め直すと、Face ID の画面を閉じるたびにまた出て、抜け出せなくなるため）。
/// - 認証は iOS の `deviceOwnerAuthentication`（生体認証が使えなければ端末のパスコード）。アプリは認証の結果だけを受け取り、
///   顔や指紋のデータは受け取らない（iOS の仕組み）。
/// - オンにするときは、その場で 1 回認証してから切り替える（解除できない設定にしないため）。パスコードを設定していない端末では
///   オンにできない。オフにするのは、解除した後の設定の画面からだけなので、認証を求めない。
/// - 設定は UserDefaults（`AppSettings.appLockEnabled`）。家計の中身ではないため。
@MainActor
@Observable
final class AppLock {
    /// 解除するまで家計の画面を出さない状態か。
    private(set) var isLocked: Bool
    /// 前面を離れていて、家計の画面を隠しているか（アプリの切り替えの画面に写さないため）。ロック中も隠す。
    private(set) var isCovered = false
    /// 認証の途中か（ロックの画面のボタンを押せなくする）。
    private(set) var isAuthenticating = false
    /// ロックがオンか（設定の「Face ID でロック」）。
    private(set) var isEnabled: Bool
    /// オンにできなかった理由（設定の画面がアラートで知らせる）。
    var enableFailure: EnableFailure?

    /// 家計の画面を出さないか（ロック中か、前面を離れて隠しているか）。
    var hidesContent: Bool { isLocked || isCovered }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let authenticator: any AppLockAuthenticating
    /// 次に前面に出たときに、解除を自動で求めるか（ロックして最初の 1 回だけ）。
    @ObservationIgnored private var promptsOnActive: Bool

    /// - Parameters:
    ///   - defaults: 設定の置き場所。アプリは `UserDefaults.standard`、テストと撮影用のデモは別の領域。
    ///   - authenticator: 認証（Face ID・Touch ID・パスコード）。テストで結果を決めたものに差し替える。
    init(defaults: UserDefaults = .standard, authenticator: any AppLockAuthenticating = DeviceOwnerAuthenticator()) {
        self.defaults = defaults
        self.authenticator = authenticator
        let enabled = defaults.bool(for: AppSettings.appLockEnabled)
        self.isEnabled = enabled
        // 起動したときは、オンならロックから始める（最初の画面が出る前に家計を見せない）。
        self.isLocked = enabled
        self.promptsOnActive = enabled
    }

    /// 端末で使える認証の種類（設定の行の名前「Face ID でロック」などに使う）。
    var method: AppLockMethod {
        authenticator.method
    }

    // MARK: - 前面・裏

    /// 場面の状態が変わった（`ScenePhase`）。前面を離れたら隠し、裏に回ったらロックし、前面に出たらロックの解除を求める。
    /// 解除を求めたときは、認証を待つ Task を返す（テストで使う）。
    ///
    /// 隠す・ロックするのはその場で行う（待たない）。iOS がアプリの切り替えの画面の写しを撮るまでに、隠した画面を描き終えるため。
    @discardableResult
    func scenePhaseDidChange(to phase: ScenePhase) -> Task<Void, Never>? {
        guard isEnabled else {
            isLocked = false
            isCovered = false
            return nil
        }
        switch phase {
        case .background:
            isLocked = true
            isCovered = true
            promptsOnActive = true
        case .inactive:
            // 認証の画面（Face ID）を出している間も inactive になる。隠したままでよい（ロック中は隠しているため）。
            isCovered = true
        case .active:
            isCovered = false
            if isLocked, promptsOnActive {
                promptsOnActive = false
                return Task { await unlock() }
            }
        @unknown default:
            break
        }
        return nil
    }

    // MARK: - 解除

    /// ロックを解除する（認証を求める）。やめた・失敗したときはロックのまま（ロックの画面から求め直せる）。
    func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        if await authenticator.authenticate(reason: String(localized: "記録を表示するためにロックを解除します")) {
            isLocked = false
            isCovered = false
        }
    }

    // MARK: - 設定

    /// ロックのオンとオフを切り替える。オンにするときは、その場で認証できたときだけ切り替える。切り替えたら true。
    @discardableResult
    func setEnabled(_ enabled: Bool) async -> Bool {
        guard enabled != isEnabled else { return true }
        if enabled {
            guard authenticator.method != .unavailable else {
                enableFailure = .passcodeNotSet
                return false
            }
            guard await authenticator.authenticate(reason: String(localized: "アプリのロックをオンにします")) else {
                enableFailure = .notAuthenticated
                return false
            }
        }
        isEnabled = enabled
        defaults.set(enabled, for: AppSettings.appLockEnabled)
        if !enabled {
            isLocked = false
            isCovered = false
            promptsOnActive = false
        }
        return true
    }
}

extension AppLock {
    /// ロックをオンにできなかった理由。
    enum EnableFailure: Equatable {
        /// 端末にパスコードを設定していない（解除できないので、オンにしない）。
        case passcodeNotSet
        /// 認証できなかった（やめた・失敗した）。
        case notAuthenticated
    }
}

/// 端末で使える、ロックの解除の方法。
enum AppLockMethod: Equatable, Sendable {
    case faceID
    case touchID
    case opticID
    /// 生体認証が無い（使えない）端末で、パスコードで解除する。
    case passcode
    /// 端末にパスコードを設定していない（ロックを使えない）。
    case unavailable
}

/// ロックの解除の認証。テストで差し替える。
@MainActor
protocol AppLockAuthenticating {
    /// 端末で使える解除の方法。
    var method: AppLockMethod { get }
    /// 認証を求める。認証できたら true（やめた・失敗した・使えないときは false）。
    func authenticate(reason: String) async -> Bool
}

/// iOS の端末の持ち主の認証（Face ID・Touch ID、使えなければパスコード。`LAPolicy.deviceOwnerAuthentication`）。
struct DeviceOwnerAuthenticator: AppLockAuthenticating {
    var method: AppLockMethod {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return .unavailable }
        // 生体認証が使えるかは、生体認証だけの方針で調べたときに決まる（`biometryType` はその後で読む）。
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        case .none: return .passcode
        @unknown default: return .passcode
        }
    }

    func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        // 解除の画面の「キャンセル」の文字は iOS の既定のまま。パスコードへの切り替えは iOS が出す。
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}
