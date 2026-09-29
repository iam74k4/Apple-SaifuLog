import Foundation

/// 無料で使える回数に上限のある機能。
///
/// rawValue は保存に使う（アプリの UserDefaults のキーを選ぶ）ので変えないこと。
public enum QuotaFeature: String, CaseIterable, Sendable, Codable {
    /// レシート・スクショの読み取り。
    case receiptScan
    /// 家計への質問。
    case question

    /// 無料で使える、暦の月あたりの回数。
    public var freeMonthlyLimit: Int {
        switch self {
        case .receiptScan: 5
        case .question: 10
        }
    }
}

/// 暦の月の見分け（紀元・年・月・閏月）。無料の回数を数える月。
///
/// 月の始まりの瞬間ではなく、暦の上の年と月で持つ。瞬間で持つと、同じ月のうちに時間帯を変えただけで
/// （東京の 9/1 0:00 はホノルルでは 8/31）別の月とみなし、使った回数を 0 に戻してしまうため。
/// 暦は画面と同じもの（利用者が選んだ暦と端末の時間帯）で、ホームの「今月」と同じ月になる。
/// 紀元を持つのは、和暦のように元号が変わると年が 1 に戻る暦があるため。閏月は中国暦などで同じ月の番号が 2 度あるため。
public struct QuotaMonth: Hashable, Codable, Sendable {
    public let era: Int
    public let year: Int
    public let month: Int
    public let isLeapMonth: Bool

    public init(containing date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.era, .year, .month], from: date)
        era = components.era ?? 0
        year = components.year ?? 0
        month = components.month ?? 0
        isLeapMonth = components.isLeapMonth ?? false
    }
}

/// 使える回数の見込み。
public enum QuotaAllowance: Hashable, Sendable {
    /// 回数の上限なし（プレミアムか体験中）。
    case unlimited
    /// この月にあと `remaining` 回（上限は `limit` 回）。
    case limited(remaining: Int, limit: Int)

    /// いま使えるか。
    public var canUse: Bool {
        switch self {
        case .unlimited: true
        case .limited(let remaining, _): remaining > 0
        }
    }
}

/// 1 つの機能の、暦の月ごとの使った回数。
///
/// 数えるのは無料のときだけ。プレミアムと体験中は上限が無く、使っても数えない（体験が月の途中で終わっても、
/// その月の無料の回数を体験中に使った分で減らさないため）。月が替わったら 0 から数える。
public struct UsageQuota: Hashable, Codable, Sendable {
    /// 最後に数えた月。まだ一度も数えていなければ nil。
    public private(set) var month: QuotaMonth?
    /// `month` に使った回数。
    public private(set) var count: Int

    public init(month: QuotaMonth? = nil, count: Int = 0) {
        self.month = month
        self.count = max(0, count)
    }

    /// その時点の月に使った回数。最後に数えた月と違えば 0（月が替わった）。
    ///
    /// 月が前に戻ったとき（時間帯を西へ変えて月の境目をまたいだ、時計を直した）も違う月として 0 にする。前に戻ったときだけ
    /// 数を残すと、時計を先へずらして使った後に直した人が、実際にその月が来るまで使えなくなるため（戻して増える回数は、
    /// 境目をまたいだ間の数回にとどまる）。
    public func count(at now: Date, calendar: Calendar) -> Int {
        // 保存した値が壊れて負の数になっていても、上限を超えて使えるようにはしない。
        month == QuotaMonth(containing: now, calendar: calendar) ? max(0, count) : 0
    }

    /// その時点で使える回数の見込み。
    public func allowance(for feature: QuotaFeature, status: PremiumStatus, now: Date, calendar: Calendar) -> QuotaAllowance {
        guard !status.unlocksPremium else { return .unlimited }
        let limit = feature.freeMonthlyLimit
        return .limited(remaining: max(0, limit - count(at: now, calendar: calendar)), limit: limit)
    }

    /// 1 回使ったことを数える。使えたら true。
    ///
    /// 上限まで使っていたら数えずに false を返す。プレミアムと体験中は数えずに true を返す。
    /// 読み取りや質問が終わってから呼ぶ（失敗やキャンセルで回数を減らさないため）。
    @discardableResult
    public mutating func recordUse(of feature: QuotaFeature, status: PremiumStatus, now: Date, calendar: Calendar) -> Bool {
        use(feature, status: status, now: now, calendar: calendar) != .limitReached
    }

    /// 1 回使ったことを数え、数えたかどうかと、数えた月を返す（取り消したときに戻すため。`refund(_:)`）。
    public mutating func use(_ feature: QuotaFeature, status: PremiumStatus, now: Date, calendar: Calendar) -> QuotaUse {
        guard !status.unlocksPremium else { return .unlimited }
        let current = QuotaMonth(containing: now, calendar: calendar)
        let used = count(at: now, calendar: calendar)
        guard used < feature.freeMonthlyLimit else { return .limitReached }
        month = current
        count = used + 1
        return .counted(current)
    }

    /// `use` で数えた 1 回を戻す（レシートから記録した直後に「取り消す」を押したとき）。
    ///
    /// 数えた月がいまも数えている月で、1 回以上数えているときだけ減らす。月が替わった後は、もう 0 から数えているので戻さない
    /// （戻すと、新しい月の回数を減らしてしまうため）。
    public mutating func refund(_ counted: QuotaMonth) {
        guard month == counted, count > 0 else { return }
        count -= 1
    }
}

/// 1 回使ったことを数えた結果。
public enum QuotaUse: Hashable, Sendable {
    /// 上限なし（プレミアムか体験中）で、数えなかった。
    case unlimited
    /// その月の 1 回として数えた。
    case counted(QuotaMonth)
    /// 上限まで使っていたので、数えなかった（使えない）。
    case limitReached
}
