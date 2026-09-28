import Foundation

/// App Store Connect に登録した課金アイテム。
///
/// rawValue は App Store Connect の製品 ID。一度出したら変えない（変えると、買った人がプレミアムを使えなくなる）。
/// Bundle ID の接頭辞（`ORG_PREFIX`）から組み立てないのは、製品 ID が App Store Connect に登録した値で決まっていて、
/// 手元で別のチームのビルドをしても変わらないため。
public enum PremiumProduct: String, CaseIterable, Sendable {
    /// プレミアム。買い切りの非消耗型（¥1,800・ファミリー共有あり）。
    case premium = "com.iam74k4.SaifuLog.premium"
    /// 14 日間の無料体験。価格 0 の非消耗型（ファミリー共有なし）。審査ガイドライン 3.1.1 が認める
    /// 「非サブスクのアプリが価格 0 の非消耗型で期間限定の体験を出す」形で、購入した日時から 14 日を体験の期間にする。
    case trial14 = "com.iam74k4.SaifuLog.trial14"
}

/// プレミアムを持っている理由。自分で買ったか、家族がファミリー共有で分けてくれたか。
public enum PremiumOwnership: Sendable, Hashable {
    case purchased
    case familyShared
}

/// 購入の事実の 1 件。StoreKit の Transaction から、プレミアムかどうかを決めるのに要る値だけを写したもの。
///
/// コアに StoreKit を持ち込まずに判定をテストするための境目。アプリは検証できた Transaction だけをこれにする
/// （検証できないものを数えると、改ざんした購入の記録でプレミアムを開けられるため）。
public struct PremiumPurchase: Sendable, Hashable {
    public var product: PremiumProduct
    public var ownership: PremiumOwnership
    public var purchaseDate: Date
    /// 返金・ファミリー共有の取り消しなどで失効した日時。失効していなければ nil。
    public var revocationDate: Date?

    public init(product: PremiumProduct, ownership: PremiumOwnership = .purchased, purchaseDate: Date, revocationDate: Date? = nil) {
        self.product = product
        self.ownership = ownership
        self.purchaseDate = purchaseDate
        self.revocationDate = revocationDate
    }

    public var isRevoked: Bool { revocationDate != nil }
}

/// 14 日間の無料体験の期間。
///
/// 端末の暦の日付ではなく、経過時間（14 × 24 時間）で数える。暦の日付で数えると、時間帯を変えたり
/// 夏時間が切り替わったりしたときに体験の長さが変わり、端末の時間帯を変えるだけで延ばせてしまうため。
/// 始まりは trial14 の購入日時（App Store の記録）で、端末に覚えた日時ではない（再インストールでやり直せないように）。
public struct TrialPeriod: Sendable, Hashable {
    /// 体験の日数。
    public static let dayCount = 14
    /// 1 日の長さ（経過時間）。
    public static let secondsPerDay: TimeInterval = 24 * 60 * 60
    /// 体験の長さ（経過時間）。
    public static let duration: TimeInterval = Double(dayCount) * secondsPerDay

    /// 始まり（trial14 の購入日時）。
    public let start: Date

    public init(start: Date) {
        self.start = start
    }

    /// 終わる瞬間。この瞬間からは体験の外（始まりは含み、終わりは含まない）。
    public var end: Date { start.addingTimeInterval(Self.duration) }

    /// その時点で体験中か。端末の時計が購入日時より前にずれていても、終わる前なら体験中とみなす
    /// （時計のずれで、始めたばかりの体験が使えなくならないように）。
    public func isActive(at now: Date) -> Bool {
        now < end
    }

    /// 画面に出す残りの日数。終わっていれば 0。
    ///
    /// 残りの時間を 1 日単位で切り上げる（残り 1 秒でも「あと 1 日」、始めた直後から 24 時間は「あと 14 日」）。
    /// 切り捨てると、まだ使える最後の 1 日に「あと 0 日」と出し、始めた直後に「あと 13 日」と出して、14 日間という
    /// 案内と食い違うため。端末の時計が購入日時より前にずれていても 14 を超えない。
    public func daysRemaining(at now: Date) -> Int {
        let remaining = end.timeIntervalSince(now)
        guard remaining > 0 else { return 0 }
        return min(Self.dayCount, Int((remaining / Self.secondsPerDay).rounded(.up)))
    }

    /// 画面に出す残りの日数が次に減る瞬間（残りが 1 日なら、終わる瞬間）。終わっていれば nil。
    ///
    /// 残りの日数は購入の時刻から 24 時間ごとに減るので、0 時には変わらない。アプリは画面を開いたままでもこの瞬間に
    /// 描き直す（日付が変わったときに描き直すだけでは、「あと N 日」が古いまま残り、体験が終わっても体験中と出るため）。
    public func nextChange(after now: Date) -> Date? {
        Self.nextChange(end: end, daysRemaining: daysRemaining(at: now))
    }

    /// 残りの日数が `daysRemaining` のときに、次にそれが変わる瞬間。残りの日数は終わる瞬間までの時間の切り上げなので、
    /// 残りの時間が (daysRemaining - 1) 日ちょうどになった瞬間に 1 減る。
    static func nextChange(end: Date, daysRemaining: Int) -> Date? {
        guard daysRemaining > 0 else { return nil }
        return end.addingTimeInterval(-Double(daysRemaining - 1) * secondsPerDay)
    }
}

/// プレミアムの状態。購入の事実と今の時刻から決める（`init(purchases:now:)`）。
public enum PremiumStatus: Sendable, Hashable {
    /// 無料で、体験もまだしていない（体験を始められる）。
    case free
    /// 無料体験中。`daysRemaining` は画面に出す残りの日数（`TrialPeriod.daysRemaining`）、`endsAt` は終わる瞬間。
    case trial(daysRemaining: Int, endsAt: Date)
    /// 無料体験が終わった（プレミアムは買っていない）。体験は 1 つの Apple アカウントにつき 1 回。
    case trialEnded(endedAt: Date)
    /// プレミアム（買った・ファミリー共有）。
    case premium(PremiumOwnership)

    /// 購入の事実から状態を決める。
    ///
    /// - 失効していないプレミアムがあれば、プレミアム。自分で買ったものとファミリー共有の両方があれば、自分で買ったものを採る
    ///   （家族が共有をやめても使い続けられるのは、自分で買ったほうのため）。
    /// - 失効したプレミアムは数えない（返金やファミリー共有の取り消しの後は、体験か無料に戻る）。
    /// - プレミアムが無く、体験（trial14）を買っていれば、最初に買った日時から 14 日（経過時間）が体験。終わる瞬間からは
    ///   体験の終わり。体験の購入が失効していたら、体験は終わったものとする（体験は 1 回だけで、やり直しにはしない）。
    ///   このためアプリは、いま持っている購入（失効したものを含まない）に、失効した体験の購入を足して渡す
    ///   （`PurchaseManager.storedPurchases`）。
    /// - どれも無ければ無料。
    public init(purchases: some Sequence<PremiumPurchase>, now: Date) {
        let purchases = Array(purchases)
        let owned = purchases.filter { $0.product == .premium && !$0.isRevoked }
        if owned.contains(where: { $0.ownership == .purchased }) {
            self = .premium(.purchased)
            return
        }
        if !owned.isEmpty {
            self = .premium(.familyShared)
            return
        }
        guard let trial = purchases.filter({ $0.product == .trial14 }).min(by: { $0.purchaseDate < $1.purchaseDate }) else {
            self = .free
            return
        }
        let period = TrialPeriod(start: trial.purchaseDate)
        if let revoked = trial.revocationDate {
            self = .trialEnded(endedAt: min(revoked, period.end))
        } else if period.isActive(at: now) {
            self = .trial(daysRemaining: period.daysRemaining(at: now), endsAt: period.end)
        } else {
            self = .trialEnded(endedAt: period.end)
        }
    }

    /// プレミアムの機能を使えるか（プレミアムか体験中）。
    public var unlocksPremium: Bool {
        switch self {
        case .premium, .trial: true
        case .free, .trialEnded: false
        }
    }

    /// 時間がたつだけで状態が次に変わる瞬間（体験中の、残りの日数が減るか体験が終わる瞬間）。体験中でなければ nil
    /// （無料・体験の終わり・プレミアムは、購入の事実が変わらない限り変わらない）。
    public var nextChange: Date? {
        guard case .trial(let daysRemaining, let endsAt) = self else { return nil }
        return TrialPeriod.nextChange(end: endsAt, daysRemaining: daysRemaining)
    }

    /// 無料体験を始められるか（まだ体験していない無料のときだけ）。
    public var canStartTrial: Bool {
        self == .free
    }

    /// プレミアムを買えるか（買っていない・共有されていないとき。体験中も買える）。
    public var canPurchase: Bool {
        if case .premium = self { return false }
        return true
    }
}
