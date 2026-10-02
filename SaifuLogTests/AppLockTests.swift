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

    /// 設定のファイル（`LaunchSettingsStore`）。
    @MainActor
    final class Settings {
        let store: LaunchSettingsStore

        init(lockEnabled: Bool) throws {
            store = try TestSupport.makeLaunchSettings(.init(appLockEnabled: lockEnabled))
        }

        var lockEnabled: Bool? { store.load(migrating: false)?.appLockEnabled }
    }

    /// 読めたり読めなかったりするファイル（再起動して最初にロックを解く前は読めない）。
    final class SwitchableFile: @unchecked Sendable {
        var readable = true
        var writable = true
        var data: Data?

        var access: LaunchSettingsStore.FileAccess {
            LaunchSettingsStore.FileAccess(
                read: { _ in
                    guard self.readable else { throw TestError() }
                    return self.data
                },
                write: { data, _ in
                    guard self.writable else { throw TestError() }
                    self.data = data
                }
            )
        }
    }

    /// 保護されたデータが読めるか（テストの途中で変える）。
    @MainActor
    final class ProtectedData {
        var isAvailable: Bool

        init(_ isAvailable: Bool) {
            self.isAvailable = isAvailable
        }
    }

    static func makeLock(
        _ settings: Settings, _ authenticator: StubAuthenticator, protectedDataAvailable: @escaping @MainActor () -> Bool = { true }
    ) -> AppLock {
        AppLock(settings: settings.store, authenticator: authenticator, isProtectedDataAvailable: protectedDataAvailable)
    }

    @Test func offByDefaultNeverLocks() async throws {
        let settings = try Settings(lockEnabled: false)
        let authenticator = StubAuthenticator()
        let lock = Self.makeLock(settings, authenticator)

        #expect(!lock.isEnabled)
        #expect(!lock.isLocked)
        #expect(lock.scenePhaseDidChange(to: .background) == nil)
        #expect(lock.scenePhaseDidChange(to: .active) == nil)
        #expect(!lock.hidesContent)
        #expect(authenticator.reasons.isEmpty)
    }

    /// オンなら、起動したときはロックから始め、前面に出たときに 1 回だけ解除を求める。
    @Test func locksAtLaunchAndUnlocksOnActive() async throws {
        let settings = try Settings(lockEnabled: true)
        let authenticator = StubAuthenticator()
        let lock = Self.makeLock(settings, authenticator)

        #expect(lock.isLocked)
        #expect(lock.hidesContent)

        await lock.scenePhaseDidChange(to: .active)?.value

        #expect(!lock.isLocked)
        #expect(!lock.hidesContent)
        #expect(authenticator.reasons.count == 1)
    }

    /// 裏に回るとロックし、戻ったときにまた解除を求める。
    @Test func locksWhenBackgrounded() async throws {
        let settings = try Settings(lockEnabled: true)
        let authenticator = StubAuthenticator()
        let lock = Self.makeLock(settings, authenticator)
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
        let settings = try Settings(lockEnabled: true)
        let authenticator = StubAuthenticator()
        let lock = Self.makeLock(settings, authenticator)
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
        let settings = try Settings(lockEnabled: true)
        let authenticator = StubAuthenticator()
        authenticator.succeeds = false
        let lock = Self.makeLock(settings, authenticator)

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
        let settings = try Settings(lockEnabled: false)
        let authenticator = StubAuthenticator()
        authenticator.succeeds = false
        let lock = Self.makeLock(settings, authenticator)

        #expect(await !lock.setEnabled(true))
        #expect(!lock.isEnabled)
        #expect(lock.enableFailure == .notAuthenticated)
        #expect(settings.lockEnabled == false)

        authenticator.succeeds = true
        #expect(await lock.setEnabled(true))
        #expect(lock.isEnabled)
        #expect(settings.lockEnabled == true)
        // オンにしたその場ではロックしない（解除したばかりの設定の画面のまま）。
        #expect(!lock.isLocked)
    }

    /// パスコードを設定していない端末ではオンにできない（解除できないロックにしない）。
    @Test func cannotEnableWithoutPasscode() async throws {
        let settings = try Settings(lockEnabled: false)
        let authenticator = StubAuthenticator()
        authenticator.method = .unavailable
        let lock = Self.makeLock(settings, authenticator)

        #expect(await !lock.setEnabled(true))
        #expect(lock.enableFailure == .passcodeNotSet)
        #expect(authenticator.reasons.isEmpty)
    }

    /// オフにするときも認証を求め、できたら隠す・ロックするのもやめる。
    @Test func disablingRequiresAuthenticationAndClearsLock() async throws {
        let settings = try Settings(lockEnabled: true)
        let authenticator = StubAuthenticator()
        let lock = Self.makeLock(settings, authenticator)
        await lock.scenePhaseDidChange(to: .active)?.value

        #expect(await lock.setEnabled(false))

        #expect(!lock.isEnabled)
        #expect(settings.lockEnabled == false)
        lock.scenePhaseDidChange(to: .background)
        #expect(!lock.hidesContent)
        // 解除の 1 回と、オフにするときの 1 回。
        #expect(authenticator.reasons.count == 2)
    }

    /// オフにするときに認証できなければ、オンのまま（設定も書かない）。
    @Test func disablingKeepsLockWhenNotAuthenticated() async throws {
        let settings = try Settings(lockEnabled: true)
        let authenticator = StubAuthenticator()
        let lock = Self.makeLock(settings, authenticator)
        await lock.scenePhaseDidChange(to: .active)?.value
        authenticator.succeeds = false

        #expect(await !lock.setEnabled(false))

        #expect(lock.isEnabled)
        #expect(lock.enableFailure == .disableNotAuthenticated)
        #expect(settings.lockEnabled == true)
        lock.scenePhaseDidChange(to: .background)
        #expect(lock.isLocked)
    }

    /// 設定を書けなければ切り替えない（画面ではオンなのに、次に開いたときはオフ、を避ける）。
    @Test func doesNotSwitchWhenSettingCannotBeSaved() async throws {
        let file = SwitchableFile()
        file.data = try JSONEncoder().encode(LaunchSettingsStore.Values(appLockEnabled: false))
        let store = LaunchSettingsStore(url: URL(filePath: "/unused"), files: file.access)
        let authenticator = StubAuthenticator()
        let lock = AppLock(settings: store, authenticator: authenticator, isProtectedDataAvailable: { true })
        file.writable = false

        #expect(await !lock.setEnabled(true))

        #expect(!lock.isEnabled)
        #expect(lock.enableFailure == .notSaved)
    }

    // MARK: - 起動したときに設定を読めない

    /// 再起動して最初にロックを解く前（ロック中に裏で起こされた）は設定を読めない。オンかもしれないので、読めるまで隠す。
    /// 解除は求めない（オフの人に解除を求めないため）。読めるようになって、オンなら、前面に出たときに解除を求める。
    @Test func coversUntilSettingIsReadableThenLocksWhenOn() async throws {
        let file = SwitchableFile()
        file.data = try JSONEncoder().encode(LaunchSettingsStore.Values(appLockEnabled: true))
        file.readable = false
        let store = LaunchSettingsStore(url: URL(filePath: "/unused"), files: file.access)
        let authenticator = StubAuthenticator()
        let protectedData = ProtectedData(false)
        let lock = AppLock(settings: store, authenticator: authenticator, isProtectedDataAvailable: { protectedData.isAvailable })

        #expect(lock.hidesContent)
        #expect(!lock.isLocked)
        #expect(lock.scenePhaseDidChange(to: .background) == nil)
        #expect(lock.hidesContent)
        #expect(authenticator.reasons.isEmpty)

        file.readable = true
        protectedData.isAvailable = true
        await lock.scenePhaseDidChange(to: .active)?.value

        #expect(lock.isEnabled)
        #expect(!lock.isLocked)
        #expect(authenticator.reasons.count == 1)
    }

    /// 読めるようになってオフなら、隠すのをやめる（解除は求めない）。
    @Test func uncoversWhenSettingTurnsOutOff() throws {
        let file = SwitchableFile()
        file.data = try JSONEncoder().encode(LaunchSettingsStore.Values(appLockEnabled: false))
        file.readable = false
        let store = LaunchSettingsStore(url: URL(filePath: "/unused"), files: file.access)
        let authenticator = StubAuthenticator()
        let protectedData = ProtectedData(false)
        let lock = AppLock(settings: store, authenticator: authenticator, isProtectedDataAvailable: { protectedData.isAvailable })
        #expect(lock.hidesContent)

        file.readable = true
        protectedData.isAvailable = true
        #expect(lock.scenePhaseDidChange(to: .active) == nil)

        #expect(!lock.isEnabled)
        #expect(!lock.hidesContent)
        #expect(authenticator.reasons.isEmpty)
    }

    /// 読めるようになってもファイルを読めなければ、オンとして扱う（解除すれば使える。オフとして扱うと、オンの人の家計を
    /// Face ID なしで見せてしまうため）。
    @Test func treatsUnreadableSettingAsOnOnceProtectedDataIsAvailable() async throws {
        let file = SwitchableFile()
        file.data = Data()
        file.readable = false
        let store = LaunchSettingsStore(url: URL(filePath: "/unused"), files: file.access)
        let authenticator = StubAuthenticator()
        let lock = AppLock(settings: store, authenticator: authenticator, isProtectedDataAvailable: { true })

        await lock.scenePhaseDidChange(to: .active)?.value

        #expect(lock.isEnabled)
        #expect(authenticator.reasons.count == 1)
    }

    /// この版より前に UserDefaults へ置いていた設定は、保護されたデータが読めるようになってから移す（作った時点では
    /// UserDefaults を読まない）。
    @Test func migratesFromUserDefaultsOnlyWhenProtectedDataIsAvailable() async throws {
        let suiteName = "AppLockTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, for: AppSettings.hasCompletedOnboarding)
        defaults.set(true, for: AppSettings.appLockEnabled)
        let url = URL.temporaryDirectory.appending(path: "\(suiteName).json", directoryHint: .notDirectory)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = LaunchSettingsStore(url: url, defaults: defaults)
        let authenticator = StubAuthenticator()
        let protectedData = ProtectedData(false)
        let lock = AppLock(settings: store, authenticator: authenticator, isProtectedDataAvailable: { protectedData.isAvailable })
        #expect(lock.hidesContent)
        #expect(store.read() == .missing)

        protectedData.isAvailable = true
        await lock.scenePhaseDidChange(to: .active)?.value

        #expect(lock.isEnabled)
        #expect(store.read() == .values(.init(appLockEnabled: true)))
        #expect(authenticator.reasons.count == 1)
    }
}
