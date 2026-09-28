import Foundation
import SaifuLogCore
import Testing
@testable import SaifuLog

/// アプリ自身の設定（UserDefaults）のキーと既定値、プライバシーマニフェストとの整合。
struct AppSettingsTests {
    @Test func keysAreUnique() {
        #expect(Set(AppSettings.allKeys).count == AppSettings.allKeys.count)
    }

    /// キーの文字列は保存に使うので変えない（変えると、利用者の設定が既定値に戻る）。
    @Test func keysAreStable() {
        #expect(AppSettings.hasCompletedOnboarding.key == "hasCompletedOnboarding")
        #expect(AppSettings.iCloudSyncEnabled.key == "iCloudSyncEnabled")
        #expect(AppSettings.weekStart.key == "weekStart")
        #expect(AppSettings.hasShownTrialEndedPremium.key == "hasShownTrialEndedPremium")
        #expect(AppSettings.receiptScanQuota.key == "quota.receiptScan")
        #expect(AppSettings.questionQuota.key == "quota.question")
        #expect(AppSettings.quota(for: .receiptScan).key == "quota.receiptScan")
        #expect(AppSettings.quota(for: .question).key == "quota.question")
    }

    /// 初回の案内はまだ終えていない、iCloud 同期はオフ（利用者が選んだときだけ同期する）、週の始まりは端末の設定に
    /// 合わせる、が既定。
    @Test func defaults() {
        #expect(AppSettings.hasCompletedOnboarding.defaultValue == false)
        #expect(AppSettings.iCloudSyncEnabled.defaultValue == false)
        #expect(AppSettings.weekStart.defaultValue == .system)
        #expect(AppSettings.hasShownTrialEndedPremium.defaultValue == false)
        #expect(AppSettings.receiptScanQuota.defaultValue == UsageQuota())
        #expect(AppSettings.questionQuota.defaultValue == UsageQuota())
    }

    /// 形のある設定（無料で使った回数）は JSON で書き、読めない値は既定値で読む。
    @Test func readsCodableSetting() throws {
        let suiteName = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var quota = UsageQuota()
        quota.recordUse(of: .question, status: .free, now: TestSupport.now, calendar: TestSupport.calendar)

        #expect(defaults.decodedValue(for: AppSettings.questionQuota) == UsageQuota())

        defaults.setEncoded(quota, for: AppSettings.questionQuota)
        #expect(defaults.decodedValue(for: AppSettings.questionQuota) == quota)

        defaults.set("broken", forKey: AppSettings.questionQuota.key)
        #expect(defaults.decodedValue(for: AppSettings.questionQuota) == UsageQuota())
    }

    /// 選択肢の設定は rawValue で書き、知らない値は既定値で読む。
    @Test func readsChoiceSettingByRawValue() throws {
        let suiteName = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(defaults.value(for: AppSettings.weekStart) == .system)

        defaults.set(WeekStart.monday, for: AppSettings.weekStart)
        #expect(defaults.string(forKey: "weekStart") == "monday")
        #expect(defaults.value(for: AppSettings.weekStart) == .monday)

        defaults.set("friday", forKey: "weekStart")
        #expect(defaults.value(for: AppSettings.weekStart) == .system)
    }

    /// まだ書いていない設定は既定値で読み、書いたらその値で読む。
    @Test func readsDefaultUntilWritten() throws {
        let suiteName = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(defaults.bool(for: AppSettings.iCloudSyncEnabled) == false)

        defaults.set(true, for: AppSettings.iCloudSyncEnabled)
        #expect(defaults.bool(for: AppSettings.iCloudSyncEnabled) == true)
        #expect(defaults.bool(for: AppSettings.hasCompletedOnboarding) == false)
    }

    /// 設定を UserDefaults に置くので、プライバシーマニフェストに利用理由（CA92.1: アプリ自身だけが読み書きする）が
    /// 書かれていること。消すと、App Store Connect への提出で、UserDefaults を使う理由の宣言が無いと指摘される。
    @Test func privacyManifestDeclaresUserDefaultsReason() throws {
        let url = try #require(Bundle(for: Entry.self).url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let plist = try #require(
            try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any]
        )
        let accessedTypes = try #require(plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let userDefaults = try #require(accessedTypes.first {
            $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults"
        })

        #expect(userDefaults["NSPrivacyAccessedAPITypeReasons"] as? [String] == ["CA92.1"])
    }
}
