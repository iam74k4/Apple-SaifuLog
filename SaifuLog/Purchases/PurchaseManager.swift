import Foundation
import Observation
import SaifuLogCore
import StoreKit

/// プレミアムの購入・体験・復元と、いまの状態（`PremiumStatus`）を受け持つ（StoreKit 2）。
///
/// アプリの生涯で 1 つだけ作り（`SaifuLogApp`）、起動したらすぐ `start()` で Transaction.updates の購読を始める。
/// 購読を後回しにすると、返金・失効・ファミリー共有の取り消しや、承認待ち（Ask to Buy）の承認、ほかの端末での購入を
/// 取りこぼし、プレミアムの状態が古いままになるため。
///
/// 状態は購入の事実（`Transaction.currentEntitlements` の検証できたものと、`Transaction.all` の失効した体験。
/// `storedPurchases()`）と今の時刻から、コアの `PremiumStatus` が決める。購入の事実は StoreKit が端末に持っているので、
/// オフラインでも判断できる（アプリでは覚えておかない。覚えた値が App Store の記録と食い違うと、返金された購入で
/// プレミアムを使えてしまうため）。
///
/// 購入の情報は StoreKit（Apple）だけが扱い、アプリの外（開発者のサーバーなど）へは送らない（PRIVACY.md）。
@MainActor
@Observable
final class PurchaseManager {
    /// 判定に使う購入の事実（検証できた Transaction を写したもの）。
    private(set) var purchases: [VerifiedPurchase] = []
    /// 購入の事実を一度でも読み終えたか。読み終えるまでは、無料と見分けがつかない（体験の終わりの案内はこれを待つ）。
    private(set) var hasLoadedPurchases = false
    /// App Store の商品（価格の表示と購入に使う）。
    private(set) var products: [PremiumProduct: Product] = [:]
    /// 商品の読み込みの状態。
    private(set) var productsState: ProductsState = .notLoaded
    /// 購入の手続き中（ボタンを押せなくし、二重の購入を防ぐ）。
    private(set) var isPurchasing = false
    /// 購入の復元の途中。
    private(set) var isRestoring = false
    /// 時刻を読み直す合図。体験の残りの日数は時間とともに変わるので、前面に戻ったとき・日付が変わったとき・体験の
    /// 残りの日数が減る瞬間と終わる瞬間（`scheduleNextChange()`）に増やして、状態を出している画面を描き直させる
    /// （`status` がこれを読む）。
    private var clock = 0

    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let loadPurchases: @MainActor () async -> [VerifiedPurchase]
    @ObservationIgnored private let loadProducts: @MainActor ([String]) async throws -> [Product]
    @ObservationIgnored private let sync: @MainActor () async throws -> Void
    @ObservationIgnored private let sleepUntil: @MainActor (Date) async throws -> Void
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    /// 体験の残りの日数が次に減る瞬間（か終わる瞬間）に、画面を描き直させるための待ち。体験中でなければ nil。
    @ObservationIgnored private var nextChangeTask: Task<Void, Never>?
    /// 購入の事実を読み直した回数。後から始めた読み直しの結果だけを採る（前の読み直しが後から終わって、新しい状態を
    /// 古い状態で上書きしないように）。
    @ObservationIgnored private var refreshGeneration = 0

    /// - Parameters:
    ///   - now: 体験の残りの判定に使う時刻。テストで固定する。
    ///   - loadPurchases: 購入の事実を読む。既定は `storedPurchases()`（`Transaction.currentEntitlements` と、
    ///     `Transaction.all` の失効した体験）。StoreKit を使わないテストで差し替える。
    ///   - loadProducts: App Store の商品を読む。既定は `Product.products(for:)`。
    ///   - sync: 購入の復元（App Store と購入の記録を同期する）。既定は `AppStore.sync()`。
    ///   - sleepUntil: その瞬間（`now` の時刻）まで待つ。体験の残りの日数が減る瞬間に描き直させるのに使う。取り消されたら
    ///     投げる。既定は `now` との差だけ `Task.sleep` する。テストで時計と一緒に差し替える。
    init(
        now: @escaping () -> Date = { .now },
        loadPurchases: @escaping @MainActor () async -> [VerifiedPurchase] = PurchaseManager.storedPurchases,
        loadProducts: @escaping @MainActor ([String]) async throws -> [Product] = { try await Product.products(for: $0) },
        sync: @escaping @MainActor () async throws -> Void = { try await AppStore.sync() },
        sleepUntil: (@MainActor (Date) async throws -> Void)? = nil
    ) {
        self.now = now
        self.loadPurchases = loadPurchases
        self.loadProducts = loadProducts
        self.sync = sync
        self.sleepUntil = sleepUntil ?? { date in
            try await Task.sleep(for: .seconds(max(0, date.timeIntervalSince(now()))))
        }
    }

    /// いまのプレミアムの状態。読むたびに今の時刻で決める（体験は時間で終わるため）。
    var status: PremiumStatus {
        _ = clock
        return PremiumStatus(purchases: purchases.map(\.purchase), now: now())
    }

    // MARK: - 起動と購読

    /// Transaction.updates の購読を始め、購入の事実を読む。起動したらすぐ呼ぶ。2 回目からは何もしない。
    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                await self.handle(update)
            }
        }
        Task { await refreshPurchases() }
    }

    /// 購読をやめる（テストの後片づけ）。
    func stop() {
        updatesTask?.cancel()
        updatesTask = nil
        nextChangeTask?.cancel()
        nextChangeTask = nil
    }

    /// 前面に戻ったとき・日付が変わったときに呼ぶ。体験の残りの日数と終わりを、今の時刻で出し直させる。
    /// 時計が変わった（時刻を合わせ直した）かもしれないので、次に起きる瞬間も決め直す。
    func clockDidChange() {
        clock &+= 1
        scheduleNextChange()
    }

    /// 体験中なら、残りの日数が次に減る瞬間（残り 1 日なら終わる瞬間）に起きて描き直させる。前の待ちは取り消す。
    ///
    /// 残りの日数は購入の時刻から 24 時間ごとに減り、0 時には変わらない。前面に戻ったときと日付が変わったときに描き直す
    /// だけでは、アプリを開いたままその瞬間を過ぎると、設定の「体験中 あと N 日」やシートの文が古いまま残り、体験が
    /// 終わっても体験中と出る（カテゴリ別の予算を出すかは開く時点の状態で決めるので、表示と食い違う）ため。
    /// 裏にいる間は動かないが、前面に戻ったときに `clockDidChange()` で決め直す。
    private func scheduleNextChange() {
        nextChangeTask?.cancel()
        nextChangeTask = nil
        guard let next = status.nextChange else { return }
        nextChangeTask = Task { [weak self, sleepUntil] in
            do {
                try await sleepUntil(next)
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            self.clockDidChange()
        }
    }

    /// App Store の外で起きた購入の変化（返金・失効・ファミリー共有の取り消し・承認待ちの承認・ほかの端末での購入）。
    private func handle(_ update: VerificationResult<Transaction>) async {
        // 検証できないものは数えず、終えもしない（改ざんされた記録でプレミアムを開けられないように）。
        guard case .verified(let transaction) = update else { return }
        await transaction.finish()
        await refreshPurchases(applying: Self.forcedUpdate(VerifiedPurchase(transaction)))
    }

    /// Transaction.updates から届いた Transaction のうち、読み直した購入の事実に上書きしてでも反映するもの。
    ///
    /// 失効（返金・ファミリー共有の取り消し）だけ。端末の記録の側がまだ古くても、失効は確実に反映したいため。
    /// 付与（失効していない Transaction）は、読み直した `Transaction.currentEntitlements` に任せ、届いただけでは開けない。
    /// 届くのが遅れた古い Transaction（すでに消えた・取り消された購入）で、持っていないプレミアムが開いてしまわないように
    /// （SKTestSession で、前のテストの購入が記録を消した後に届いて起きた）。承認待ちの承認やほかの端末での購入は、
    /// `finish()` の後の読み直しで currentEntitlements に入っている。
    static func forcedUpdate(_ update: VerifiedPurchase?) -> VerifiedPurchase? {
        guard let update, update.purchase.isRevoked else { return nil }
        return update
    }

    /// 購入の事実を読み直す。
    ///
    /// - Parameter update: いま届いた Transaction。読み直した購入の事実に、同じ Transaction があれば置き換え、無ければ足す。
    ///   失効が届いた直後に、端末の記録の側がまだ古くても、失効を確実に反映するため（失効したものは `PremiumStatus` が数えない）。
    func refreshPurchases(applying update: VerifiedPurchase? = nil) async {
        refreshGeneration &+= 1
        let generation = refreshGeneration
        var loaded = await loadPurchases()
        guard generation == refreshGeneration else { return }
        if let update {
            loaded.removeAll { $0.transactionID == update.transactionID }
            loaded.append(update)
        }
        purchases = loaded
        hasLoadedPurchases = true
        scheduleNextChange()
    }

    /// 端末の購入の記録から、判定に使う購入の事実を読む（検証できたものだけ）。
    ///
    /// いま持っている購入（`Transaction.currentEntitlements`）に、`Transaction.all` の失効した体験を足す
    /// （`mergingRevokedTrials`）。端末に持っている記録を読むので、オフラインでも読める。
    static func storedPurchases() async -> [VerifiedPurchase] {
        var entitlements: [VerifiedPurchase] = []
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement, let purchase = VerifiedPurchase(transaction) else { continue }
            entitlements.append(purchase)
        }
        var history: [VerifiedPurchase] = []
        for await record in Transaction.all {
            guard case .verified(let transaction) = record, let purchase = VerifiedPurchase(transaction) else { continue }
            history.append(purchase)
        }
        return mergingRevokedTrials(entitlements: entitlements, history: history)
    }

    /// いま持っている購入に、購入の履歴のうち失効した体験（trial14）を足す。
    ///
    /// `Transaction.currentEntitlements` は返金・失効したものを返さない。それだけで決めると、体験の購入が返金された後の
    /// 起動や復元で「体験していない無料」に戻り、体験のボタンがまた出て、買い直した体験で 14 日をやり直せてしまう
    /// （返金された非消耗型は買い直せる。体験は 1 つの Apple アカウントにつき 1 回）。失効したプレミアムは足さない
    /// （数えないので、足しても状態は変わらない）。
    static func mergingRevokedTrials(entitlements: [VerifiedPurchase], history: [VerifiedPurchase]) -> [VerifiedPurchase] {
        var result = entitlements
        var seen = Set(entitlements.map(\.transactionID))
        for record in history where record.purchase.product == .trial14 && record.purchase.isRevoked {
            if seen.insert(record.transactionID).inserted {
                result.append(record)
            }
        }
        return result
    }

    // MARK: - 商品

    /// App Store の商品（価格など）を読む。読み込み中なら何もしない。
    func loadProductsIfNeeded() async {
        guard productsState != .loading, productsState != .loaded else { return }
        productsState = .loading
        do {
            let loaded = try await loadProducts(PremiumProduct.allCases.map(\.rawValue))
            var byProduct: [PremiumProduct: Product] = [:]
            for product in loaded {
                if let kind = PremiumProduct(rawValue: product.id) { byProduct[kind] = product }
            }
            products = byProduct
            // プレミアムが無ければ買えないので、読めなかったことにする（体験だけがあっても出さない）。
            productsState = byProduct[.premium] == nil ? .failed : .loaded
        } catch {
            productsState = .failed
        }
    }

    // MARK: - 購入

    /// 購入の手続き（StoreKit に頼む部分）。画面は SwiftUI の PurchaseAction（シートを出す場面を StoreKit に教える）を渡し、
    /// テストは `Product.purchase()` を渡す。
    typealias Purchaser = @MainActor (Product) async throws -> Product.PurchaseResult

    /// プレミアムか体験を買う。
    ///
    /// 検証できた成功（`.success(.verified)`）だけを受け入れ、Transaction を終えて状態を読み直す。検証できないもの
    /// （`.unverified`）は受け入れない。承認待ち（Ask to Buy など）は案内だけを返し、承認されたら Transaction.updates から
    /// 届く。利用者がやめたときは何もしない。購入や復元の途中は受け付けない（二重の購入を防ぐ）。
    func purchase(_ kind: PremiumProduct, using purchaser: Purchaser = { try await $0.purchase() }) async -> PurchaseOutcome {
        guard !isPurchasing, !isRestoring else { return .busy }
        guard let product = products[kind] else { return .failed(.productUnavailable) }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await purchaser(product)
            switch result {
            case .success(.verified(let transaction)):
                await transaction.finish()
                await refreshPurchases(applying: VerifiedPurchase(transaction))
                return .purchased
            case .success(.unverified):
                // 終えない（Apple の手順どおり。検証できたときに届けなおされる）。プレミアムも開けない。
                return .failed(.unverified)
            case .pending:
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .failed(.unknown)
            }
        } catch {
            let failure = PurchaseFailure(error)
            return failure == .cancelled ? .cancelled : .failed(failure)
        }
    }

    // MARK: - 復元

    /// 購入の復元。App Store と購入の記録を同期してから、購入の事実を読み直す。
    ///
    /// StoreKit 2 は購入の記録を自動で同期するので、ふだんは要らない。機種変更の直後などに、プレミアムが出ないときのための操作。
    /// 同期は Apple ID の確認を求めることがある（利用者がやめたら何もしない）。
    func restore() async -> RestoreOutcome {
        guard !isPurchasing, !isRestoring else { return .busy }
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await sync()
        } catch {
            let failure = PurchaseFailure(error)
            return failure == .cancelled ? .cancelled : .failed(failure)
        }
        await refreshPurchases()
        if case .premium = status { return .restored }
        return .nothingToRestore
    }

    // MARK: - 型

    enum ProductsState: Equatable {
        case notLoaded
        case loading
        case loaded
        case failed
    }
}

/// 検証できた Transaction から、判定に要る値だけを写したもの。
struct VerifiedPurchase: Sendable, Hashable {
    let transactionID: UInt64
    let purchase: PremiumPurchase

    init(transactionID: UInt64, purchase: PremiumPurchase) {
        self.transactionID = transactionID
        self.purchase = purchase
    }

    /// プレミアムと体験でない Transaction は nil。
    init?(_ transaction: Transaction) {
        guard let product = PremiumProduct(rawValue: transaction.productID) else { return nil }
        self.init(
            transactionID: transaction.id,
            purchase: PremiumPurchase(
                product: product,
                ownership: transaction.ownershipType == .familyShared ? .familyShared : .purchased,
                purchaseDate: transaction.purchaseDate,
                revocationDate: transaction.revocationDate
            )
        )
    }
}

/// 購入の結果。
enum PurchaseOutcome: Equatable {
    /// 検証でき、状態に反映した。
    case purchased
    /// 承認待ち（保護者の承認・支払いの確認など）。承認されたら Transaction.updates から反映する。
    case pending
    /// 利用者がやめた（何も知らせない）。
    case cancelled
    /// 購入や復元の途中で、受け付けなかった。
    case busy
    case failed(PurchaseFailure)
}

/// 購入の復元の結果。
enum RestoreOutcome: Equatable {
    /// プレミアムを復元できた。
    case restored
    /// この Apple アカウントにプレミアムの購入が無かった（体験の記録だけのときも含む）。
    case nothingToRestore
    case cancelled
    case busy
    case failed(PurchaseFailure)
}
