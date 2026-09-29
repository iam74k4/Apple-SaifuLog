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
    /// iCloud と同期するか（設定の「iCloud で同期」）。既定はオフ（利用者が選んだときだけ同期する）。起動したときに
    /// `SaifuLogApp` が読んで保存先の開き方を決め、切り替えと、開けずに端末の中だけへ戻したときは `StoreHost` が書く。
    static let iCloudSyncEnabled = AppSetting(key: "iCloudSyncEnabled", defaultValue: false)
    /// 週の始まり（設定の画面で選ぶ）。既定は端末の設定（地域と iOS の設定）に合わせる。
    /// 画面の根元（`AppRootView`）が画面の暦の週の始まりに当てはめ、`ReportPeriod` の今週・先週の区切りに効かせる。
    static let weekStart = AppSetting(key: "weekStart", defaultValue: WeekStart.system)
    /// 無料体験が終わったときのプレミアムの案内（⑨）を出したか。体験が終わった後の最初の起動で一度だけ出し、
    /// しつこく出さない（`HomeModel.presentPremiumIfTrialEnded`）。プレミアムを買ったかどうかはここに置かない
    /// （購入の事実は StoreKit が持つ。覚えた値が App Store の記録と食い違うと、返金された購入でも使えてしまうため）。
    static let hasShownTrialEndedPremium = AppSetting(key: "hasShownTrialEndedPremium", defaultValue: false)
    /// レシートの読み取りを無料で使った回数（暦の月ごと。`QuotaStore`）。
    static let receiptScanQuota = AppSetting(key: "quota.receiptScan", defaultValue: UsageQuota())
    /// 家計への質問を無料で使った回数（暦の月ごと。`QuotaStore`）。
    static let questionQuota = AppSetting(key: "quota.question", defaultValue: UsageQuota())
    /// 先週のふりかえりのカードを最後に出した日時。週が替わって最初に開いたときだけ出すのに使う（`WeeklyRecap.isDue`・
    /// `HomeModel.showWeeklyRecapIfDue`）。まだ出したことが無ければ nil。
    ///
    /// 出した週の始まりではなく、出した瞬間を持つ。週の始まりの設定や時間帯を変えたときに、変えた後の暦で「今週もう出したか」を
    /// 決め直せるようにするため（週の始まりの日時で持つと、設定を変えただけで同じ週にもう一度出る）。家計の中身は含まない。
    static let weeklyRecapShownAt = AppSetting<Date?>(key: "weeklyRecap.shownAt", defaultValue: nil)

    /// 機能ごとの、無料で使った回数の設定。
    static func quota(for feature: QuotaFeature) -> AppSetting<UsageQuota> {
        switch feature {
        case .receiptScan: receiptScanQuota
        case .question: questionQuota
        }
    }

    /// すべての設定のキー。重なりが無いことをテストで確かめる。
    static var allKeys: [String] {
        [
            hasCompletedOnboarding.key, iCloudSyncEnabled.key, weekStart.key, hasShownTrialEndedPremium.key,
            receiptScanQuota.key, questionQuota.key, weeklyRecapShownAt.key,
        ]
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

    /// 日時の設定を読む。まだ書いていないか、日時でない値なら既定値（nil）。
    func date(for setting: AppSetting<Date?>) -> Date? {
        object(forKey: setting.key) as? Date ?? setting.defaultValue
    }

    /// 日時の設定を書く。nil なら消す。
    func set(_ date: Date?, for setting: AppSetting<Date?>) {
        set(date, forKey: setting.key)
    }

    /// 形のある設定（無料で使った回数など）を JSON で読む。まだ書いていないか、読めない値（壊れた値・新しい版で形を
    /// 変えた値を古い版で読んだときなど）なら既定値。
    func decodedValue<Value: Codable>(for setting: AppSetting<Value>) -> Value {
        guard let data = data(forKey: setting.key), let value = try? JSONDecoder().decode(Value.self, from: data) else {
            return setting.defaultValue
        }
        return value
    }

    /// 形のある設定を JSON で書く。
    func setEncoded<Value: Codable>(_ value: Value, for setting: AppSetting<Value>) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        set(data, forKey: setting.key)
    }
}
