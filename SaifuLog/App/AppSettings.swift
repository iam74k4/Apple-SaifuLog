import Foundation
import SaifuLogCore
import SwiftUI

/// アプリ自身の設定（UserDefaults）の 1 項目。キーと既定値を組にして持つ。
///
/// キーの文字列を画面ごとに書くと、綴りの違いで別の設定として読み書きしたり、既定値が画面ごとに
/// 食い違ったりするため、`AppSettings` に並べたものだけを使う。
struct AppSetting<Value: Sendable>: Sendable {
    /// 保存に使うキー。一度出したら変えないこと（変えると、利用者の設定が既定値に戻る）。
    let key: String
    let defaultValue: Value
}

/// アプリ自身の設定の一覧。
///
/// 保存先は `UserDefaults.standard`（このアプリ専用の領域）だけにする。プライバシーマニフェスト
/// （PrivacyInfo.xcprivacy）に書いた UserDefaults の利用理由 CA92.1（アプリ自身だけが読み書きする）は、
/// この使い方に限られるため。App Group の共有の領域（ウィジェットなどと共有する）に置くなら、先に
/// マニフェストへ理由 1C8F.1 を足し、PRIVACY.md も見直す。
/// 家計の記録そのもの（金額やメモ）はここに置かない。SwiftData の保存先に置き、データ保護を効かせる。
enum AppSettings {
    /// 初回の案内（ようこそ・予算を決める）を終えたか。予算を決めずに「あとで」で進んでも終えたことになる。
    /// 案内を出す前の版から使っていて記録がある端末は、案内を出さずに true にする（`OnboardingModel.needsOnboarding`）。
    static let hasCompletedOnboarding = AppSetting(key: "hasCompletedOnboarding", defaultValue: false)
    /// iCloud と同期するか。既定はオフ（利用者が選んだときだけ同期する）。iCloud 同期を作るときに使う。
    static let iCloudSyncEnabled = AppSetting(key: "iCloudSyncEnabled", defaultValue: false)
    /// 週の始まり（設定の画面で選ぶ）。既定は端末の設定（地域と iOS の設定）に合わせる。
    /// 画面の根元（`AppRootView`）が画面の暦の週の始まりに当てはめ、`ReportPeriod` の今週・先週の区切りに効かせる。
    static let weekStart = AppSetting(key: "weekStart", defaultValue: WeekStart.system)

    /// すべての設定のキー。重なりが無いことをテストで確かめる。
    static var allKeys: [String] {
        [hasCompletedOnboarding.key, iCloudSyncEnabled.key, weekStart.key]
    }
}

extension AppStorage where Value == Bool {
    /// 画面から設定を読み書きする。`@AppStorage(AppSettings.hasCompletedOnboarding) private var hasCompletedOnboarding`
    init(_ setting: AppSetting<Bool>, store: UserDefaults? = nil) {
        self.init(wrappedValue: setting.defaultValue, setting.key, store: store)
    }
}

extension AppStorage {
    /// 選択肢の設定（`WeekStart` など、文字列の rawValue で保存するもの）を画面から読み書きする。
    init(_ setting: AppSetting<Value>, store: UserDefaults? = nil) where Value: RawRepresentable, Value.RawValue == String {
        self.init(wrappedValue: setting.defaultValue, setting.key, store: store)
    }
}

extension UserDefaults {
    /// 画面の外（保存先を開くときなど）から設定を読む。まだ書いていなければ既定値。
    func bool(for setting: AppSetting<Bool>) -> Bool {
        object(forKey: setting.key) as? Bool ?? setting.defaultValue
    }

    func set(_ value: Bool, for setting: AppSetting<Bool>) {
        set(value, forKey: setting.key)
    }

    /// 選択肢の設定を読む。まだ書いていないか、知らない値（新しい版で足した選択肢を古い版で読んだときなど）なら既定値。
    func value<Value: RawRepresentable>(for setting: AppSetting<Value>) -> Value where Value.RawValue == String {
        string(forKey: setting.key).flatMap(Value.init(rawValue:)) ?? setting.defaultValue
    }

    /// 選択肢の設定を書く（rawValue で保存する。`@AppStorage` と同じ形なので、画面の `@AppStorage` にも伝わる）。
    func set<Value: RawRepresentable>(_ value: Value, for setting: AppSetting<Value>) where Value.RawValue == String {
        set(value.rawValue, forKey: setting.key)
    }
}
