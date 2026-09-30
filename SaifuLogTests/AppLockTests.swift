import Foundation
import SwiftUI
import Testing
@testable import SaifuLog

/// アプリのロック（`AppLock`）。起動したとき・裏に回ったとき・前面に出たときの状態の移り方と、オンにするときの認証を、
/// 結果を決めた認証（`StubAuthenticator`）で確かめる。Face ID の画面そのものはシミュレータでは試せないので、確かめない。
@MainActor
struct AppLockTests {
    /// 結果を決めた認証。呼ばれた回数と理由を残す。
    @MainActor
    final class StubAuthenticator: AppLockAuthenticating {
        var method: AppLockMethod = .faceID
        var succeeds = true
        private(set) var reasons: [String] = []

        func authenticate(reason: String) async -> Bool {
            reasons.append(reason)
            return succeeds
        }
    }

    final class Defaults {
        let suiteName = "AppLockTests.\(UUID().uuidString)"
        let defaults: UserDefaults

        init(lockEnabled: Bool) throws {
            defaults = try #require(UserDefaults(suiteName: suiteName))
            defaults.set(lockEnabled, for: AppSettings.appLockEnabled)
        }

        deinit {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
    }

    @Test func offByDefaultNeverLocks() async throws {
        let store = try Defaults(lockEnabled: false)
        let authenticator = StubAuthenticator()
        let lock = AppLock(defaults: store.defaults, authenticator: authenticator)

        #expect(!lock.isEnabled)
        #expect(!lock.isLocked)
        #expect(lock.scenePhaseDidChange(to: .background) == nil)
        #expect(lock.scenePhaseDidChange(to: .active) == nil)
        #expect(!lock.hidesContent)
        #expect(authenticator.reasons.isEmpty)
    }

    /// オンなら、起動したときはロックから始め、前面に出たときに 1 回だけ解除を求める。
    @Test func locksAtLaunchAndUnlocksOnActive() async throws {
        let store = try Defaults(lockEnabled: true)
        let authenticator = StubAuthenticator()
        let lock = AppLock(defaults: store.defaults, authenticator: authenticator)

        #expect(lock.isLocked)
        #expect(lock.hidesContent)

        await lock.scenePhaseDidChange(to: .active)?.value

        #expect(!lock.isLocked)
        #expect(!lock.hidesContent)
        #expect(authenticator.reasons.count == 1)
    }

    /// 裏に回るとロックし、戻ったときにまた解除を求める。
    @Test func locksWhenBackgrounded() async throws {
        let store = try Defaults(lockEnabled: true)
        let authenticator = StubAuthenticator()
        let lock = AppLock(defaults: store.defaults, authenticator: authenticator)
        await lock.scenePhaseDidChange(to: .active)?.value

        lock.scenePhaseDidChange(to: .inactive)
        lock.scenePhaseDidChange(to: .background)

        #expect(lock.isLocked)
        #expect(lock.hidesContent)
        await lock.scenePhaseDidChange(to: .active)?.value
        #expect(!lock.isLocked)
        #expect(authenticator.reasons.count == 2)
    }

    /// コントロールセンターや通知を引き出したとき（inactive）は隠すだけで、ロックしない（戻っても解除を求めない）。
    @Test func inactiveOnlyCovers() async throws {
        let store = try Defaults(lockEnabled: true)
        let authenticator = StubAuthenticator()
        let lock = AppLock(defaults: store.defaults, authenticator: authenticator)
        await lock.scenePhaseDidChange(to: .active)?.value

        lock.scenePhaseDidChange(to: .inactive)
        #expect(lock.hidesContent)
        #expect(!lock.isLocked)

        #expect(lock.scenePhaseDidChange(to: .active) == nil)
        #expect(!lock.hidesContent)
        #expect(authenticator.reasons.count == 1)
    }

    /// やめた・失敗したときはロックのまま、自動では求め直さない（Face ID の画面を閉じるたびにまた出て、抜け出せなくならないように）。
    /// ロックの画面の「ロックを解除」で求め直せる。
    @Test func failedUnlockStaysLockedWithoutRetryLoop() async throws {
        let store = try Defaults(lockEnabled: true)
        let authenticator = StubAuthenticator()
        authenticator.succeeds = false
        let lock = AppLock(defaults: store.defaults, authenticator: authenticator)

        await lock.scenePhaseDidChange(to: .active)?.value
        #expect(lock.isLocked)
        // 認証の画面を閉じると、inactive から active に戻る。そのときは求め直さない。
        lock.scenePhaseDidChange(to: .inactive)
        #expect(lock.scenePhaseDidChange(to: .active) == nil)
        #expect(authenticator.reasons.count == 1)

        authenticator.succeeds = true
        await lock.unlock()
        #expect(!lock.isLocked)
        #expect(authenticator.reasons.count == 2)
    }

    /// オンにするときは、その場で認証できたときだけ切り替えて設定に書く。
    @Test func enablingRequiresAuthentication() async throws {
        let store = try Defaults(lockEnabled: false)
        let authenticator = StubAuthenticator()
        authenticator.succeeds = false
        let lock = AppLock(defaults: store.defaults, authenticator: authenticator)

        #expect(await !lock.setEnabled(true))
        #expect(!lock.isEnabled)
        #expect(lock.enableFailure == .notAuthenticated)
        #expect(!store.defaults.bool(for: AppSettings.appLockEnabled))

        authenticator.succeeds = true
        #expect(await lock.setEnabled(true))
        #expect(lock.isEnabled)
        #expect(store.defaults.bool(for: AppSettings.appLockEnabled))
        // オンにしたその場ではロックしない（解除したばかりの設定の画面のまま）。
        #expect(!lock.isLocked)
    }

    /// パスコードを設定していない端末ではオンにできない（解除できないロックにしない）。
    @Test func cannotEnableWithoutPasscode() async throws {
        let store = try Defaults(lockEnabled: false)
        let authenticator = StubAuthenticator()
        authenticator.method = .unavailable
        let lock = AppLock(defaults: store.defaults, authenticator: authenticator)

        #expect(await !lock.setEnabled(true))
        #expect(lock.enableFailure == .passcodeNotSet)
        #expect(authenticator.reasons.isEmpty)
    }

    /// オフにするのは認証を求めず、隠す・ロックするのもやめる。
    @Test func disablingClearsLock() async throws {
        let store = try Defaults(lockEnabled: true)
        let authenticator = StubAuthenticator()
        let lock = AppLock(defaults: store.defaults, authenticator: authenticator)
        await lock.scenePhaseDidChange(to: .active)?.value

        #expect(await lock.setEnabled(false))

        #expect(!lock.isEnabled)
        #expect(!store.defaults.bool(for: AppSettings.appLockEnabled))
        lock.scenePhaseDidChange(to: .background)
        #expect(!lock.hidesContent)
        #expect(authenticator.reasons.count == 1)
    }
}
