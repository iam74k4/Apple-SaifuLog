import Foundation
import LocalAuthentication
import Observation
import SwiftUI
import UIKit

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
///   オンにできない。オフにするときも認証を求める（ロックの画面が何かの理由で外れたり、解除したまま置いた端末を別の人が
///   触ったりしたときに、黙ってロックを外させないため）。
/// - 設定は専用のファイル（`LaunchSettingsStore`）に置く。UserDefaults はロック中に裏で起こされると読めず、空の内容を覚えて
///   しまい、ロックがオフと読まれるため。起動したときに読めなければ（再起動して最初にロックを解く前）、読めるようになるまで
///   画面を隠しておき、読めたら決める（安全側に倒す）。
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

    @ObservationIgnored private let settings: LaunchSettingsStore
    @ObservationIgnored private let authenticator: any AppLockAuthenticating
    @ObservationIgnored private let isProtectedDataAvailable: @MainActor () -> Bool
    /// 次に前面に出たときに、解除を自動で求めるか（ロックして最初の 1 回だけ）。
    @ObservationIgnored private var promptsOnActive: Bool
    /// 起動したときに設定を読めず、まだオンかオフかを決めていないか。決めるまで画面を隠しておく。
    @ObservationIgnored private var isSettingPending: Bool

    /// - Parameters:
    ///   - settings: 設定の置き場所。アプリは `LaunchSettingsStore()`、テストと撮影用のデモは一時フォルダのファイル。
    ///   - authenticator: 認証（Face ID・Touch ID・パスコード）。テストで結果を決めたものに差し替える。
    ///   - isProtectedDataAvailable: 保護されたデータが読めるか（ロック中でないか）。テストで差し替える。ここでは呼ばない
    ///     （App を作る時点では UIApplication がまだ無いことがあるため）。
    init(
        settings: LaunchSettingsStore,
        authenticator: any AppLockAuthenticating = DeviceOwnerAuthenticator(),
        isProtectedDataAvailable: @escaping @MainActor () -> Bool = { UIApplication.shared.isProtectedDataAvailable }
    ) {
        self.settings = settings
        self.authenticator = authenticator
        self.isProtectedDataAvailable = isProtectedDataAvailable
        // ここでは UserDefaults から移さない（App を作る時点はロック中のことがあり、そのとき UserDefaults を読むと、空の内容を
        // 覚えてしまうため）。ファイルが読めた（ロック中でも、最初のロック解除の後なら読める）ときだけ決める。
        if let values = settings.load(migrating: false) {
            let enabled = values.appLockEnabled
            self.isEnabled = enabled
            // 起動したときは、オンならロックから始める（最初の画面が出る前に家計を見せない）。
            self.isLocked = enabled
            self.promptsOnActive = enabled
            self.isSettingPending = false
        } else {
            // 読めない（再起動して最初にロックを解く前）か、まだファイルが無い。オンかもしれないので、決めるまで隠しておく。
            // ロックの画面（解除のボタン）は出さず、隠すだけにする（オフの人に解除を求めないため）。
            self.isEnabled = false
            self.isLocked = false
            self.isCovered = true
            self.promptsOnActive = false
            self.isSettingPending = true
        }
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
        guard resolvePendingSetting() else {
            // まだ設定を読めない。決めるまで隠したまま（解除も求めない）。
            return nil
        }
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

    /// 起動したときに読めなかった設定を、保護されたデータが読めるようになっていれば読んで決める。決まっていれば true。
    ///
    /// 読めるようになってもファイルを読めないとき（ファイルの読み込みの失敗）は、オンとして扱う（解除すれば使える。オフとして
    /// 扱うと、オンの人の家計を Face ID なしで見せてしまうため）。設定の画面からオフに戻せる。
    private func resolvePendingSetting() -> Bool {
        guard isSettingPending else { return true }
        guard isProtectedDataAvailable() else { return false }
        isSettingPending = false
        let enabled = settings.load(migrating: true)?.appLockEnabled ?? true
        isEnabled = enabled
        isLocked = enabled
        isCovered = false
        promptsOnActive = enabled
        return true
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

    /// ロックのオンとオフを切り替える。オンにするときもオフにするときも、その場で認証できたときだけ切り替える。切り替えたら true。
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
        } else {
            guard await authenticator.authenticate(reason: String(localized: "アプリのロックをオフにします")) else {
                enableFailure = .disableNotAuthenticated
                return false
            }
        }
        // 書けなかったら切り替えない（画面ではオンなのに、次に開いたときにはオフ、を避ける）。
        do {
            try settings.update { $0.appLockEnabled = enabled }
        } catch {
            enableFailure = .notSaved
            return false
        }
        isEnabled = enabled
        if !enabled {
            isLocked = false
            isCovered = false
            promptsOnActive = false
        }
        return true
    }
}

extension AppLock {
    /// ロックを切り替えられなかった理由。
    enum EnableFailure: Equatable {
        /// 端末にパスコードを設定していない（解除できないので、オンにしない）。
        case passcodeNotSet
        /// オンにするときに認証できなかった（やめた・失敗した）。
        case notAuthenticated
        /// オフにするときに認証できなかった（やめた・失敗した）。
        case disableNotAuthenticated
        /// 設定を書けなかった（切り替えていない）。
        case notSaved
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
