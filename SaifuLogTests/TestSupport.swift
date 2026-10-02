import CoreGraphics
import Foundation
import SaifuLogCore
import SwiftData
import Synchronization
@testable import SaifuLog

/// テストで使う固定の日時と暦、メモリの上だけの保存先。
enum TestSupport {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    /// 2026-09-28 12:00（日本時間）。
    static let now = date(2026, 9, 28, hour: 12)

    static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// テストごとに新しい保存先を作る。前のテストの記録が残らないよう、ファイルには書かない。
    ///
    /// アプリと同じ `ModelContainerFactory` で作る（モデルの一覧と iCloud を切る設定をアプリと食い違わせないため）。
    /// SwiftData の `ModelConfiguration(isStoredInMemoryOnly:)` を直接使うと iCloud が既定の `.automatic` になり、
    /// iCloud の entitlement を足した時点で、テストが iCloud と同期しようとする。
    @MainActor
    static func makeContext() throws -> ModelContext {
        let container = try ModelContainerFactory.makeInMemoryContainer()
        // mainContext はコンテナが生きている間しか使えないので、コンテナごと保持させる。
        let context = container.mainContext
        retained.append(container)
        return context
    }

    @MainActor private static var retained: [ModelContainer] = []

    /// テストごとの、アプリのロックと iCloud 同期の設定（一時フォルダのファイルと、使い捨ての UserDefaults の領域）。
    /// `values` を渡すと、その値を書いた状態から始める（渡さなければ、まだ書いていない状態）。
    @MainActor
    static func makeLaunchSettings(
        _ values: LaunchSettingsStore.Values? = nil, files: LaunchSettingsStore.FileAccess = .live
    ) throws -> LaunchSettingsStore {
        let url = URL.temporaryDirectory.appending(
            path: "LaunchSettings-\(UUID().uuidString).json", directoryHint: .notDirectory
        )
        let suiteName = "TestSupport.LaunchSettings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = LaunchSettingsStore(url: url, defaults: defaults, files: files)
        if let values {
            try LaunchSettingsStore.FileAccess.live.write(try JSONEncoder().encode(values), url)
        }
        return store
    }

    static func entry(
        amount: Int = 850, category: EntryCategory = .food, memo: String = "ランチ",
        spentAt: Date = now, createdAt: Date = now
    ) -> Entry {
        Entry(
            amount: amount, isIncome: false, category: category, memo: memo,
            spentAt: spentAt, createdAt: createdAt, source: .text, originalText: "\(memo) \(amount)"
        )
    }
}

struct TestError: Error {}

/// 読み方を差し替えられる解析器（FallbackEntryParser に AI の代わりとして渡す、HomeModel に渡す）。
struct StubParser: EntryParsing {
    let body: @Sendable (String) async throws -> [ParsedEntry]

    init(_ body: @escaping @Sendable (String) async throws -> [ParsedEntry]) {
        self.body = body
    }

    func parse(_ text: String) async throws -> [ParsedEntry] {
        try await body(text)
    }
}

/// プレミアムの購入の事実を決めて渡す（StoreKit を使わない）。
extension TestSupport {
    /// 体験を始めた日時が `daysAgo` 日前（経過時間）の体験の購入。
    static func trial(startedDaysAgo daysAgo: Double, now: Date = now) -> PremiumPurchase {
        PremiumPurchase(product: .trial14, purchaseDate: now.addingTimeInterval(-daysAgo * TrialPeriod.secondsPerDay))
    }

    /// 決めた購入の事実を持つ PurchaseManager。購入の事実を読み終えた状態で返す（`load` が false なら読む前のまま）。
    /// 商品は読めない（価格も購入も StoreKit が要るため、購入の流れは `StoreKitPurchaseTests` で確かめる）。
    @MainActor
    static func purchases(
        _ records: [PremiumPurchase] = [],
        now: @escaping () -> Date = { TestSupport.now },
        sync: @escaping @MainActor () async throws -> Void = {},
        load: Bool = true
    ) async -> PurchaseManager {
        let verified = records.enumerated().map { VerifiedPurchase(transactionID: UInt64($0.offset), purchase: $0.element) }
        let manager = PurchaseManager(now: now, loadPurchases: { verified }, loadProducts: { _ in [] }, sync: sync)
        if load { await manager.refreshPurchases() }
        return manager
    }
}

/// 答え方を差し替えられる、家計への質問の答え手（HomeModel と FallbackQuestionAnswerer に渡す）。
struct StubAnswerer: QuestionAnswering {
    let body: @Sendable (String, QuestionLedger) async throws -> QuestionReply

    init(_ body: @escaping @Sendable (String, QuestionLedger) async throws -> QuestionReply) {
        self.body = body
    }

    func answer(_ text: String, ledger: QuestionLedger, now: Date, calendar: Calendar) async throws -> QuestionReply {
        try await body(text, ledger)
    }
}

/// 書き方を差し替えられる、ふりかえりの AI の一言の書き手（HomeModel・RecapRemarkModel に渡す）。呼ばれた回数も数える。
struct StubRemarkWriter: RecapRemarkWriting {
    let calls = CallCounter()
    let body: @Sendable (String) async throws -> String

    init(_ body: @escaping @Sendable (String) async throws -> String) {
        self.body = body
    }

    func remark(from facts: String) async throws -> String {
        calls.increment()
        return try await body(facts)
    }
}

/// 開けるまで待たせる門。AI の一言の書き手を途中で止め、書いている間に数字の文が替わる場面を作る。
///
/// Task が取り消されても待ち続ける（取り消しで早く抜けると、古い書き手と新しい書き手の書き終える順をテストで決められないため）。
final class Gate: Sendable {
    private struct State {
        var isOpen = false
        var waiters: [CheckedContinuation<Void, Never>] = []
    }

    private let state = Mutex(State())

    /// 開くまで待つ（もう開いていればすぐ戻る）。
    func wait() async {
        await withCheckedContinuation { continuation in
            let isOpen = state.withLock { state in
                if !state.isOpen { state.waiters.append(continuation) }
                return state.isOpen
            }
            if isOpen { continuation.resume() }
        }
    }

    /// 開ける（待っているものをすべて進める）。
    func open() {
        let waiters = state.withLock { state in
            state.isOpen = true
            let waiters = state.waiters
            state.waiters = []
            return waiters
        }
        for waiter in waiters { waiter.resume() }
    }
}

/// レシートの読み取りの代わり。OCR が読んだことにする文字と、品名を整える AI を決めて渡す（シミュレータにはカメラも
/// Apple Intelligence も無いため）。
final class ReceiptStub: Sendable {
    private struct State {
        var lines: [ReceiptTextLine] = []
        var refiner: (any ReceiptItemRefining)?
        var recognizeCalls = 0
    }

    private let state = Mutex(State())

    /// OCR が読んだことにする行。
    var lines: [ReceiptTextLine] {
        get { state.withLock { $0.lines } }
        set { state.withLock { $0.lines = newValue } }
    }

    /// 品名を整える AI（nil なら AI の使えない端末）。
    var refiner: (any ReceiptItemRefining)? {
        get { state.withLock { $0.refiner } }
        set { state.withLock { $0.refiner = newValue } }
    }

    /// 文字認識を呼んだ回数。
    var recognizeCalls: Int {
        state.withLock { $0.recognizeCalls }
    }

    /// 決めた行を OCR として使う読み取り。
    var reader: ReceiptReader {
        ReceiptReader(
            recognize: { [self] _ in
                state.withLock { state in
                    state.recognizeCalls += 1
                    return state.lines
                }
            },
            makeRefiner: { [self] in refiner }
        )
    }

    /// 文字の行（位置なし）を決める。
    func setText(_ text: String) {
        lines = text.split(separator: "\n").map { ReceiptTextLine(String($0)) }
    }
}

/// 品名とカテゴリを整える AI の代わり。呼ばれた回数と、渡された画像を残す。
struct StubReceiptRefiner: ReceiptItemRefining {
    let usesImage: Bool
    let calls = CallCounter()
    /// 呼ばれるたびに渡された画像（渡されなければ nil）。iOS 27 の画像の経路で、画像を渡しているかを確かめる。
    let images = ReceivedReceiptImages()
    let body: @Sendable ([ReceiptItem]) throws -> [ReceiptItemSuggestion]

    init(usesImage: Bool = false, _ body: @escaping @Sendable ([ReceiptItem]) throws -> [ReceiptItemSuggestion]) {
        self.usesImage = usesImage
        self.body = body
    }

    func suggestions(for items: [ReceiptItem], storeName: String?, image: ReceiptImage?) async throws -> [ReceiptItemSuggestion] {
        calls.increment()
        images.append(image)
        return try body(items)
    }
}

/// 品名を整える AI の代わりに渡された画像の記録。
final class ReceivedReceiptImages: Sendable {
    private let value = Mutex<[ReceiptImage?]>([])

    func append(_ image: ReceiptImage?) {
        value.withLock { $0.append(image) }
    }

    var all: [ReceiptImage?] {
        value.withLock { $0 }
    }
}

extension TestSupport {
    /// 読み取りに渡す画像（中身は読まない。読み取りの代わりが決めた文字を返す）。幅と高さは 8。
    static let blankReceiptImage = blankImage(size: 8)

    /// 中身の無い正方形の画像（幅で見分ける）。
    static func blankImage(size: Int) -> ReceiptImage {
        let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return ReceiptImage(cgImage: context.makeImage()!)
    }
}
