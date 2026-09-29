import Foundation
import Observation
import SaifuLogCore

/// 無料で使える回数（レシートの読み取り・家計への質問）を数えて、設定（UserDefaults）に残す。
///
/// 数え方（暦の月ごと・月が替わると 0・プレミアムと体験中は数えない）はコアの `UsageQuota` が決め、ここは読み書きだけ。
/// 回数は家計の中身ではないので、設定の置き場所（`AppSettings`。UserDefaults.standard）に置く。
/// 家計への質問（`HomeModel`。答えを出せたときだけ `recordUse` を呼ぶ）とレシートの読み取り（記録したときだけ `use` を呼び、
/// 記録の直後に取り消したら `refundUse` で戻す）で使う。どちらも、回答や記録が終わってから数える（失敗やキャンセルで回数を
/// 減らさないため）。
@MainActor
@Observable
final class QuotaStore {
    /// 機能ごとの、使った回数。
    private(set) var quotas: [QuotaFeature: UsageQuota]

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date

    /// - Parameters:
    ///   - defaults: 設定の置き場所。アプリは `UserDefaults.standard`（`AppSettings` の決まり）、テストは使い捨ての領域。
    ///   - now: 月の区切りの基準。テストで固定の日時にする。
    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = { .now }) {
        self.defaults = defaults
        self.now = now
        quotas = Dictionary(uniqueKeysWithValues: QuotaFeature.allCases.map { feature in
            (feature, defaults.decodedValue(for: AppSettings.quota(for: feature)))
        })
    }

    /// その機能を、この月にあと何回使えるか。
    /// - Parameter calendar: 月を区切る暦（画面の暦。ホームの「今月」と同じ月で数えるため）。
    func allowance(for feature: QuotaFeature, status: PremiumStatus, calendar: Calendar) -> QuotaAllowance {
        quota(for: feature).allowance(for: feature, status: status, now: now(), calendar: calendar)
    }

    /// 1 回使ったことを数えて残す。使えたら true（プレミアムと体験中は数えずに true）。上限まで使っていたら数えずに false。
    @discardableResult
    func recordUse(of feature: QuotaFeature, status: PremiumStatus, calendar: Calendar) -> Bool {
        var quota = quota(for: feature)
        let before = quota
        guard quota.recordUse(of: feature, status: status, now: now(), calendar: calendar) else { return false }
        if quota != before {
            quotas[feature] = quota
            defaults.setEncoded(quota, for: AppSettings.quota(for: feature))
        }
        return true
    }

    /// 1 回使ったことを数えて残し、数えたかどうかと数えた月を返す（取り消したときに `refundUse` で戻すため）。
    @discardableResult
    func use(_ feature: QuotaFeature, status: PremiumStatus, calendar: Calendar) -> QuotaUse {
        var quota = quota(for: feature)
        let use = quota.use(feature, status: status, now: now(), calendar: calendar)
        if case .counted = use { store(quota, for: feature) }
        return use
    }

    /// `use` で数えた 1 回を戻して残す（数えた月がいまも数えている月のときだけ。`UsageQuota.refund`）。
    func refundUse(of feature: QuotaFeature, month: QuotaMonth) {
        var quota = quota(for: feature)
        let before = quota
        quota.refund(month)
        if quota != before { store(quota, for: feature) }
    }

    private func store(_ quota: UsageQuota, for feature: QuotaFeature) {
        quotas[feature] = quota
        defaults.setEncoded(quota, for: AppSettings.quota(for: feature))
    }

    private func quota(for feature: QuotaFeature) -> UsageQuota {
        quotas[feature] ?? UsageQuota()
    }
}
