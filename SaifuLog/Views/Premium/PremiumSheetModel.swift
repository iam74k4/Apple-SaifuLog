import Foundation
import Observation
import SaifuLogCore
import StoreKit

/// 「プレミアム」（⑨）のシートの状態と操作。
///
/// 購入・体験・復元そのものはアプリで 1 つの `PurchaseManager` が受け持ち、ここはシートに出す値と、結果の知らせ方
/// （アラート・VoiceOver の読み上げ）だけを持つ。結果の知らせ方をシートごとに持つのは、設定の画面の「購入の復元」と
/// 同じ PurchaseManager を使っても、知らせるのは操作した画面だけにするため。
@MainActor
@Observable
final class PremiumSheetModel: Identifiable {
    let purchases: PurchaseManager
    /// 出しているアラート。
    var alert: PurchaseAlert?
    /// 手続き中の商品（押したボタンにだけ進行中の印を出す）。
    private(set) var inFlight: PremiumProduct?
    #if DEBUG
    /// シートを下の端（14 日間の無料体験の説明とボタン）まで送った状態で開くか。撮影用のデモ（`ScreenshotDemo`）が、体験の
    /// 課金アイテムの審査用のスクリーンショットを撮るときだけ使う（DEBUG のビルドだけ）。
    var screenshotScrollsToBottom = false
    #endif

    @ObservationIgnored private let announce: @MainActor (String) -> Void

    /// - Parameter announce: VoiceOver に読み上げさせる。テストで読み上げる文を集める。
    init(purchases: PurchaseManager, announce: @escaping @MainActor (String) -> Void = { VoiceOver.announce($0) }) {
        self.purchases = purchases
        self.announce = announce
    }

    var status: PremiumStatus { purchases.status }

    /// 購入か復元の途中（ボタンを押せなくし、シートを下へのスワイプで閉じさせない）。
    var isBusy: Bool { purchases.isPurchasing || purchases.isRestoring }

    /// App Store の価格の表示（「¥1,800」）。読めていなければ nil（`PurchaseManager.displayPrice(for:)`）。
    var premiumPrice: String? { purchases.displayPrice(for: .premium) }

    /// 体験の案内とボタンを出すか（まだ体験していない無料のときだけ）。
    var showsTrial: Bool { status.canStartTrial }

    /// 体験を始められるか。
    var canStartTrial: Bool { showsTrial && purchases.isOffered(.trial14) && !isBusy }

    /// プレミアムを買えるか。
    var canPurchase: Bool { status.canPurchase && purchases.isOffered(.premium) && !isBusy }

    /// 価格を読む（シートを開いたとき・「もう一度読み込む」）。
    func loadProducts() async {
        await purchases.loadProductsIfNeeded()
    }

    /// プレミアムを買う。
    func buyPremium(using purchaser: @escaping PurchaseManager.Purchaser) async {
        await buy(.premium, using: purchaser)
    }

    /// 無料体験を始める（価格 0 の体験の商品を買う）。
    func startTrial(using purchaser: @escaping PurchaseManager.Purchaser) async {
        await buy(.trial14, using: purchaser)
    }

    /// 購入の復元。
    func restore() async {
        let outcome = await purchases.restore()
        alert = PurchaseAlert(outcome)
    }

    private func buy(_ kind: PremiumProduct, using purchaser: @escaping PurchaseManager.Purchaser) async {
        guard inFlight == nil else { return }
        // ボタンを出さない状態では手続きに進まない（体験は 1 回だけ、プレミアムは持っていれば買わない）。
        switch kind {
        case .premium: guard status.canPurchase else { return }
        case .trial14: guard status.canStartTrial else { return }
        }
        inFlight = kind
        defer { inFlight = nil }
        let outcome = await purchases.purchase(kind, using: purchaser)
        finish(outcome, kind: kind)
    }

    /// 購入の結果を知らせる。
    func finish(_ outcome: PurchaseOutcome, kind: PremiumProduct) {
        if outcome == .purchased {
            // 画面の文が替わるだけでは VoiceOver の利用者に伝わらないので、読み上げる。
            switch kind {
            case .premium: announce(String(localized: "プレミアムを購入しました"))
            case .trial14: announce(String(localized: "14日間の無料体験を始めました"))
            }
        }
        alert = PurchaseAlert(outcome)
    }
}

/// 購入・復元の結果のアラート。利用者がやめたときと、途中で受け付けなかったときは出さない。
enum PurchaseAlert: Identifiable, Hashable {
    /// 承認待ち（Ask to Buy など）。
    case pending
    case purchaseFailed(PurchaseFailure)
    case restored
    case nothingToRestore
    case restoreFailed(PurchaseFailure)

    var id: Self { self }

    /// 購入の結果。成功はシートの文が替わるので、アラートは出さない。
    init?(_ outcome: PurchaseOutcome) {
        switch outcome {
        case .purchased, .cancelled, .busy: return nil
        case .pending: self = .pending
        case .failed(let failure): self = .purchaseFailed(failure)
        }
    }

    /// 復元の結果。
    init?(_ outcome: RestoreOutcome) {
        switch outcome {
        case .cancelled, .busy: return nil
        case .restored: self = .restored
        case .nothingToRestore: self = .nothingToRestore
        case .failed(let failure): self = .restoreFailed(failure)
        }
    }
}
