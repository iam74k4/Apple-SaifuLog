import Foundation
import Testing
@testable import SaifuLog

/// アプリのロックと iCloud 同期の設定のファイル（`LaunchSettingsStore`）。読めない・まだ無い・壊れたときの扱いと、
/// この版より前に UserDefaults へ置いていた値を移す決まりを確かめる。ファイルの保護クラスはシミュレータでは効かないので、
/// 実機で確かめる（docs/design.md §15）。
@MainActor
struct LaunchSettingsStoreTests {
    typealias Values = LaunchSettingsStore.Values

    /// 使い捨ての UserDefaults の領域と、一時フォルダのファイル。
    @MainActor
    final class Place {
        let suiteName = "LaunchSettingsStoreTests.\(UUID().uuidString)"
        let defaults: UserDefaults
        let url: URL

        init() throws {
            defaults = try #require(UserDefaults(suiteName: suiteName))
            url = URL.temporaryDirectory.appending(path: "\(suiteName).json", directoryHint: .notDirectory)
        }

        func makeStore() -> LaunchSettingsStore {
            LaunchSettingsStore(url: url, defaults: defaults)
        }

        func cleanUp() {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: url)
        }
    }

    @Test func missingFileIsUndecidedUntilMigrating() throws {
        let place = try Place()
        defer { place.cleanUp() }
        let store = place.makeStore()

        #expect(store.read() == .missing)
        #expect(store.load(migrating: false) == nil)
    }

    @Test func writesAndReadsValues() throws {
        let place = try Place()
        defer { place.cleanUp() }
        let store = place.makeStore()

        try store.update { $0.appLockEnabled = true }
        try store.update { $0.iCloudSyncEnabled = true }

        // 片方を変えても、もう片方は残る。
        #expect(store.read() == .values(Values(appLockEnabled: true, iCloudSyncEnabled: true)))
        #expect(place.makeStore().load(migrating: false) == Values(appLockEnabled: true, iCloudSyncEnabled: true))
    }

    /// 読めない（再起動して最初にロックを解く前）ときは決めない。書くときも、読めない値を既定値で上書きしない。
    @Test func unreadableFileIsUndecidedAndNotOverwritten() throws {
        let store = LaunchSettingsStore(
            url: URL(filePath: "/unused"),
            files: LaunchSettingsStore.FileAccess(
                read: { _ in throw TestError() },
                write: { _, _ in Issue.record("読めないファイルを上書きしました") }
            )
        )

        #expect(store.read() == .unreadable)
        #expect(store.load(migrating: true) == nil)
        #expect(throws: LaunchSettingsStore.WriteError.self) {
            try store.update { $0.appLockEnabled = false }
        }
    }

    /// 壊れたファイルは、まだ書いていないものとして扱う（読み直しを待ち続けてロックの画面から抜けられなくならないように）。
    @Test func corruptedFileIsTreatedAsMissing() throws {
        let place = try Place()
        defer { place.cleanUp() }
        try Data("not json".utf8).write(to: place.url)
        let store = place.makeStore()

        #expect(store.read() == .missing)
        try store.update { $0.appLockEnabled = true }
        #expect(store.read() == .values(Values(appLockEnabled: true)))
    }

    /// 項目が足りないファイル（項目を足す前の版で書いた）は、足りない項目を既定値（オフ）で読む。
    @Test func readsOlderFileWithMissingKeys() throws {
        let place = try Place()
        defer { place.cleanUp() }
        try Data(#"{"appLockEnabled":true}"#.utf8).write(to: place.url)

        #expect(place.makeStore().read() == .values(Values(appLockEnabled: true, iCloudSyncEnabled: false)))
    }

    /// ファイルが無ければ、この版より前に UserDefaults へ置いていた値を移す。
    @Test func migratesFromUserDefaults() throws {
        let place = try Place()
        defer { place.cleanUp() }
        place.defaults.set(true, for: AppSettings.hasCompletedOnboarding)
        place.defaults.set(true, for: AppSettings.appLockEnabled)
        place.defaults.set(true, for: AppSettings.iCloudSyncEnabled)
        let store = place.makeStore()

        #expect(store.load(migrating: true) == Values(appLockEnabled: true, iCloudSyncEnabled: true))
        #expect(store.read() == .values(Values(appLockEnabled: true, iCloudSyncEnabled: true)))
    }

    /// UserDefaults が空に見える（初回の案内を終えたかの値も無い）ときは、既定のオフを返し、ファイルは書かない。
    @Test func doesNotWriteWhenUserDefaultsLooksEmpty() throws {
        let place = try Place()
        defer { place.cleanUp() }
        place.defaults.set(true, for: AppSettings.appLockEnabled)
        let store = place.makeStore()

        #expect(store.load(migrating: true) == Values())
        #expect(store.read() == .missing)
    }

    /// 移すのは保護されたデータが読めると確かめた後だけ（`migrating: true`）。作った時点の読み（`migrating: false`）では
    /// UserDefaults を読まない。
    @Test func doesNotMigrateWithoutBeingAsked() throws {
        let place = try Place()
        defer { place.cleanUp() }
        place.defaults.set(true, for: AppSettings.hasCompletedOnboarding)
        place.defaults.set(true, for: AppSettings.appLockEnabled)
        let store = place.makeStore()

        #expect(store.load(migrating: false) == nil)
        #expect(store.read() == .missing)
    }
}
