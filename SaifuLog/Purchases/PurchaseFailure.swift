import Foundation
import StoreKit

/// 購入・復元・商品の読み込みの失敗を、利用者に伝える種類に分けたもの。
///
/// StoreKit のエラーはそのまま出しても利用者には分からない（「StoreKitError error 1」など）ので、何をすればよいかが
/// 分かる文に替える（文は画面の側。`PurchaseAlert`）。
enum PurchaseFailure: Hashable, Sendable {
    /// App Store に接続できなかった（オフラインなど）。
    case network
    /// この国や地域では買えない、または商品を読めていない。
    case productUnavailable
    /// この端末では購入が制限されている（スクリーンタイムの App 内課金の制限など）。
    case notAllowed
    /// App Store の購入の記録を検証できなかった。
    case unverified
    /// 利用者がやめた（知らせない。呼び出し側で `cancelled` にする）。
    case cancelled
    /// そのほか。
    case unknown

    init(_ error: any Error) {
        switch error {
        case let error as StoreKitError:
            switch error {
            case .userCancelled: self = .cancelled
            case .networkError: self = .network
            case .notAvailableInStorefront: self = .productUnavailable
            default: self = .unknown
            }
        case let error as Product.PurchaseError:
            switch error {
            case .purchaseNotAllowed: self = .notAllowed
            case .productUnavailable: self = .productUnavailable
            default: self = .unknown
            }
        case is VerificationResult<Transaction>.VerificationError:
            self = .unverified
        case is URLError:
            self = .network
        default:
            self = .unknown
        }
    }
}
