import Foundation
import Observation
import SaifuLogCore
import SwiftData
import SwiftUI

/// ホームの状態と操作（送信・家計への質問・レシートの読み取り・取り消し・直す・削除・予算を決める画面と月のまとめと設定と
/// プレミアムの出し入れ・先週のふりかえりのカード）。
///
/// 画面（`HomeView`）から切り離し、解析器・時計・読み上げを差し替えて SaifuLogTests で確かめられるようにしている。
/// 画面は、ここの値を表示し、操作をここへ渡すだけにする。
@MainActor
@Observable
final class HomeModel {
    /// タイムラインに一度に読み込む件数。
    static let timelinePageSize = 200

    /// 入力欄の文。
    var draft = ""
    /// 送った文を読み取っている間（送信ボタンを押せなくし、読み取り中の印を出す）。
    private(set) var isParsing = false
    /// 直前に記録したもの。記録の直後に「取り消す」を出すため。
    private(set) var justRecorded: [Entry] = []
    var showsNoAmountAlert = false
    var storeFailure: StoreFailure?
    var pendingDeletion: PendingDeletion?
    /// 「予算を決める」のシートの状態と操作。シートを出していなければ nil（シートを閉じると画面が nil に戻す）。
    var budgetSetup: BudgetSetupModel?
    /// 「直す」のシートで直している記録の状態と操作。シートを出していなければ nil（シートを閉じると画面が nil に戻す）。
    var editing: EditEntryModel?
    /// 「月のまとめ」（横に進む画面）の状態と操作。出していなければ nil（ホームへ戻ると画面が nil に戻す）。
    var monthlyReport: MonthlyReportModel?
    /// 「設定」（横に進む画面）の状態と操作。出していなければ nil（ホームへ戻ると画面が nil に戻す）。
    var settings: SettingsModel?
    /// 無料体験が終わった後の最初の起動に出す「プレミアム」のシート。出していなければ nil（閉じると画面が nil に戻す）。
    var premiumSheet: PremiumSheetModel?
    /// 先週のふりかえりのカード（タイムラインの中）。出していなければ nil（「閉じる」で nil にする）。
    private(set) var weeklyRecap: WeeklyRecapModel?
    /// 先週のふりかえりの内訳（カードから横に進む画面）。中身はカードと同じもの。出していなければ nil（ホームへ戻ると画面が nil に戻す）。
    var weeklyRecapDetail: WeeklyRecapModel?
    /// プレミアムの購入と状態（アプリで 1 つ）。カテゴリ別の予算を出すかの判定と、設定・プレミアムのシートに渡す。
    let purchases: PurchaseManager
    /// 今日。「今月」の範囲と、日付に年を添えるかの基準にする。
    ///
    /// 描画のたびに `.now` を読むだけだと、アプリを開いたまま（または裏に置いたまま）月をまたいだとき、
    /// 描き直しが起きずに前の月の合計が「今月」として出続ける。前面に戻ったときと日付が変わったときに
    /// `refreshToday()` で更新する。
    private(set) var today: Date
    /// タイムラインに読み込む件数。上の「前の記録を表示」で増やす。
    private(set) var timelineLimit = HomeModel.timelinePageSize
    /// この起動の間に送った質問とその返事。タイムラインに記録の吹き出しと同じ流れ（送った順）で出す。
    ///
    /// 質問は記録ではないので保存しない（アプリを開き直すと消える。docs/design.md §9 の質問の決め事）。
    private(set) var questions: [QuestionExchange] = []
    /// 無料で使える回数（家計への質問は月 10 回、レシートの読み取りは月 5 回。プレミアムと体験中は無制限）。
    let quotaStore: QuotaStore
    /// 「撮る」「写真から選ぶ」を選ばせる確認（カメラのボタンを押したとき）。
    var showsReceiptSourceChoice = false
    /// 出しているレシートの取り込み口（書類カメラか写真の選択）。出していなければ nil（閉じると画面が nil に戻す）。
    var receiptCapture: ReceiptCaptureSource?
    /// ⑤ 読み取り結果のシート。出していなければ nil（閉じると画面が nil に戻す）。
    var receiptResult: ReceiptResultModel?
    /// この端末で書類カメラを使えるか（使えなければ「撮る」を出さない）。
    let canUseDocumentCamera: Bool

    @ObservationIgnored private let store: EntryStore
    @ObservationIgnored private let budgetStore: BudgetStore
    @ObservationIgnored private let pendingWrites: PendingStoreWrites
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let makeParser: (Date, Calendar) -> any EntryParsing
    @ObservationIgnored private let makeAnswerer: () -> any QuestionAnswering
    @ObservationIgnored private let makeRemarkWriter: () -> (any RecapRemarkWriting)?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let announce: @MainActor (String) -> Void
    @ObservationIgnored private let receiptReader: ReceiptReader
    /// 書類カメラで撮った画像と、上限を超えて読み取らなかったページの数。カメラの画面が閉じきってから読み取りのシートを出すため、
    /// 閉じるまで持っておく。
    @ObservationIgnored private var capturedReceiptImages: (images: [ReceiptImage], skippedPageCount: Int)?
    /// ⑤ のシートを閉じた後に開く取り込み口（撮り直し）。
    @ObservationIgnored private var pendingReceiptRetake: ReceiptCaptureSource?
    /// ⑤ のシートを閉じた後にプレミアムの案内を出すか（記録しようとしたら無料の回数を使い切っていた）。
    @ObservationIgnored private var presentsPremiumAfterReceipt = false
    /// 直前にレシートから記録したときに数えた無料の 1 回（数えた月と、記録した記録）。取り消したら戻す。
    @ObservationIgnored private var receiptQuotaCharge: (month: QuotaMonth, ids: [PersistentIdentifier])?

    /// - Parameters:
    ///   - budgetStore: 予算の読み書き。渡さなければ記録と同じ保存先（`store` の ModelContext）を使う。
    ///   - pendingWrites: 解析を待ってから記録する処理を数える先（`StoreHost.pendingWrites`）。保存先を開き直すとき、
    ///     記録し終えるのを待ってもらうため。
    ///   - purchases: プレミアムの購入と状態。アプリは `SaifuLogApp` の 1 つを渡す。渡さなければ購入の無い状態（テスト用）。
    ///   - defaults: 設定の置き場所（体験の終わりの案内を出したか、無料で質問した回数）。アプリは `UserDefaults.standard`、
    ///     テストは使い捨ての領域。
    ///   - quotaStore: 無料で使った回数の読み書き。渡さなければ `defaults` と `now` で作る。
    ///   - makeParser: 送信のたびに解析器を選ぶ（AI の使える・使えないは途中から変わるため）。送った瞬間の日時と暦を渡し、
    ///     「昨日」「9/26」をその日時を基準に読ませる。テストで差し替える。
    ///   - makeAnswerer: 質問のたびに答え方（AI かキーワード辞書）を選ぶ。テストで差し替える。
    ///   - makeRemarkWriter: ふりかえり（先週のふりかえり・月のまとめ）の AI の一言を書くもの。AI が使えなければ nil。テストで差し替える。
    ///   - receiptReader: レシートの画像の読み取り（文字認識と AI）。テストで決めた文字や偽物の AI に差し替える。
    ///   - canUseDocumentCamera: 書類カメラを使えるか。テストで決める。
    ///   - now: 記録の日時と「今日」の基準。テストで固定の日時にする。
    ///   - announce: VoiceOver に読み上げさせる。テストで読み上げる文を集める。
    init(
        store: EntryStore,
        budgetStore: BudgetStore? = nil,
        pendingWrites: PendingStoreWrites = PendingStoreWrites(),
        purchases: PurchaseManager? = nil,
        defaults: UserDefaults = .standard,
        quotaStore: QuotaStore? = nil,
        makeParser: @escaping (Date, Calendar) -> any EntryParsing = { EntryParserFactory.makeParser(now: $0, calendar: $1) },
        makeAnswerer: @escaping () -> any QuestionAnswering = { QuestionAnswererFactory.makeAnswerer() },
        makeRemarkWriter: @escaping () -> (any RecapRemarkWriting)? = { RecapRemarkWriterFactory.makeWriter() },
        receiptReader: ReceiptReader = ReceiptReader(),
        canUseDocumentCamera: Bool = DocumentCameraView.isSupported,
        now: @escaping () -> Date = { .now },
        announce: @escaping @MainActor (String) -> Void = { VoiceOver.announce($0) }
    ) {
        self.store = store
        self.budgetStore = budgetStore ?? BudgetStore(context: store.context)
        self.pendingWrites = pendingWrites
        self.purchases = purchases ?? PurchaseManager(loadPurchases: { [] })
        self.defaults = defaults
        self.quotaStore = quotaStore ?? QuotaStore(defaults: defaults, now: now)
        self.makeParser = makeParser
        self.makeAnswerer = makeAnswerer
        self.makeRemarkWriter = makeRemarkWriter
        self.receiptReader = receiptReader
        self.canUseDocumentCamera = canUseDocumentCamera
        self.now = now
        self.announce = announce
        self.today = now()
    }

    convenience init(context: ModelContext, pendingWrites: PendingStoreWrites = PendingStoreWrites(), purchases: PurchaseManager) {
        self.init(store: EntryStore(context: context), pendingWrites: pendingWrites, purchases: purchases)
    }

    /// 直前の記録を取り消せるか（「取り消す」のバナーと入力欄の VoiceOver の操作を出すか）。
    var canUndo: Bool {
        !justRecorded.isEmpty
    }

    /// 「取り消す」のバナーを時間で引っ込めてよいか（画面の 8 秒のタイマーを動かすか）。
    ///
    /// 「直す」のシートを出している間は数えない。シートの下でもホームは表示されたままなので、数え続けると、
    /// 直すのに 8 秒以上かけてやめたときには「取り消す」が消えていて、直すのをやめても取り消せる、という約束を破るため。
    /// 保存の失敗のアラート（「取り消せませんでした」など）を出している間も数えない。アラートを読んでいる間に
    /// バナーが消えると、「もう一度お試しください」に従えないため。どちらも閉じたら数え直す（閉じた直後にも押せるように）。
    var autoHidesUndo: Bool {
        canUndo && editing == nil && storeFailure == nil
    }

    // MARK: - 送信

    /// 入力欄の文を送る。記録なら読み取って保存し、質問なら答える（保存しない）。読み取りや答えを待つための Task を返す
    /// （テストで使う）。空の文や、読み取り中の送信は受け付けない（nil を返す）。
    ///
    /// 記録か質問かはコア（`InputIntentClassifier`）が決める。誤って記録にならないことを優先し、決められないものは記録しない。
    @discardableResult
    func send(calendar: Calendar) -> Task<Void, Never>? {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isParsing else { return nil }
        // 送った瞬間の日時を 1 つ決め、解析（「昨日」「9/26」の基準）と保存（記録した日時・使った日時）の両方に使う。
        // 保存のときに時計を読み直すと、読み取りを待つ間に日付が変わったとき（23:59:59 に送って 0:00:01 に保存）、
        // 「9/26」と書いた記録が 1 日ずれて保存されるため。質問も、この日時で期間を区切る。
        let sentAt = now()
        // 送った時点で入力欄を空ける。解析（AI だと 1 秒以上かかることがある）を待ってから空けると、
        // 入力欄にとどまって打ち始めた次の入力まで、黙って消してしまうため。
        draft = ""
        // 前の記録の「取り消す」（バナーと VoiceOver の操作）を引っ込める。読み取りの間も出したままだと、押したときに
        // 前の記録が消え、前の文が入力欄に戻る。それを送り直したり、いま送った文の記録だけが残ったりして、
        // 取り消したつもりのものと違う記録が残るため。質問を送ったときも同じにする（送るたびに引っ込める、と揃える）。
        justRecorded = []
        switch InputIntentClassifier.classify(text, now: sentAt, calendar: calendar) {
        case .record:
            return record(text, sentAt: sentAt, calendar: calendar)
        case .question:
            return ask(text, sentAt: sentAt, calendar: calendar)
        case .unclear:
            // 記録にはしない。書き直して送り直せるよう、送った文を入力欄に戻す。
            appendQuestion(text, askedAt: sentAt, state: .unclear)
            restoreDraft(text)
            announce(String(localized: "記録か質問か分かりませんでした"))
            return Task {}
        }
    }

    /// 記録として読み取って保存する。
    private func record(_ text: String, sentAt: Date, calendar: Calendar) -> Task<Void, Never> {
        isParsing = true
        let parser = makeParser(sentAt, calendar)
        // 解析の間に保存先が開き直されないよう、Task を作る前に数える（Task は画面のツリーを畳んだ後も動き続け、
        // この後で前の保存先に書き込むため）。
        pendingWrites.begin()
        return Task {
            defer {
                isParsing = false
                pendingWrites.end()
            }
            let parsed = (try? await parser.parse(text)) ?? []
            guard !parsed.isEmpty else {
                // 送った文を入力欄に戻し、その場で直せるようにする。
                restoreDraft(text)
                showsNoAmountAlert = true
                return
            }
            let recorded = Entry.records(from: parsed, originalText: text, source: .text, now: sentAt, calendar: calendar)
            do {
                try store.insert(recorded)
            } catch {
                // 保存できなかった。記録したことにはせず、送った文を戻して送り直せるようにする。
                restoreDraft(text)
                storeFailure = .record
                return
            }
            justRecorded = recorded
            announceRecorded(recorded, today: sentAt, calendar: calendar)
        }
    }

    // MARK: - 質問

    /// 家計への質問に答える。数字はコアが計算し（AI には計算させない）、答えは保存しない。
    ///
    /// 無料の回数（月 10 回）を使い切っていれば、答えずにプレミアムの案内を出す（記録は無料で無制限のまま）。数えるのは
    /// 答えを出せたときだけ（読めなかった質問・失敗は数えない）。プレミアムと体験中は数えない（`UsageQuota`）。
    /// 保存先には書き込まない（読むだけ）ので、`pendingWrites` には数えない。
    private func ask(_ text: String, sentAt: Date, calendar: Calendar) -> Task<Void, Never> {
        let id = appendQuestion(text, askedAt: sentAt, state: .answering)
        let ledger: QuestionLedger
        do {
            ledger = try QuestionLedger.load(from: store.context, now: sentAt, calendar: calendar)
        } catch {
            setQuestionState(.loadFailed, for: id)
            restoreDraft(text)
            announce(String(localized: "記録を読み込めませんでした"))
            return Task {}
        }
        isParsing = true
        return Task {
            defer { isParsing = false }
            // 購入の事実を読み終える前は、プレミアムでも無料に見える。起動の直後に送った質問で、買った人に「使い切りました」を
            // 出したり、プレミアムや体験中の人の質問を無料の回数として数えたりしないよう、読み終えるのを待ってから決める
            // （体験の終わりの案内と同じく、読み終える前の状態では決めない）。
            if !purchases.hasLoadedPurchases {
                await purchases.refreshPurchases()
            }
            guard quotaStore.allowance(for: .question, status: purchases.status, calendar: calendar).canUse else {
                setQuestionState(.limitReached, for: id)
                // プレミアムを買ったあとに送り直せるよう、送った文を入力欄に戻す。
                restoreDraft(text)
                announce(String(localized: "今月の無料の質問を使い切りました"))
                return
            }
            let answerer = makeAnswerer()
            let reply = (try? await answerer.answer(text, ledger: ledger, now: sentAt, calendar: calendar)) ?? .unreadable
            switch reply {
            case .answered(let answer, let remark):
                // 答えを出せたときだけ数える。答えの後に状態を読み直す（答えを待つ間に体験を始めたり買ったりしていれば数えない）。
                let status = purchases.status
                quotaStore.recordUse(of: .question, status: status, calendar: calendar)
                let freeQuestionsLeft = freeQuestionsLeftToShow(status: status, calendar: calendar)
                setQuestionState(.answered(answer, remark: remark, freeQuestionsLeft: freeQuestionsLeft), for: id)
                // 画面にカードが出るだけでは VoiceOver の利用者に伝わらないので、答えを読み上げる。残りの回数が少ないときの
                // 知らせも、カードの小さな行だけでは気づけないので一緒に読む。
                announce(QuestionTexts.spoken(answer, remark: remark, freeQuestionsLeft: freeQuestionsLeft, calendar: calendar))
            case .unreadable:
                setQuestionState(.unreadable, for: id)
                // 書き直して送り直せるよう、送った文を入力欄に戻す（記録の「金額が見つかりませんでした」と同じ）。
                restoreDraft(text)
                announce(String(localized: "質問を読めませんでした"))
            }
        }
    }

    /// 回答カードに出す、今月の無料の質問の残り。残りが少ない（3 回以下の）ときだけ（プレミアムと体験中は出さない）。
    private func freeQuestionsLeftToShow(status: PremiumStatus, calendar: Calendar) -> Int? {
        guard case .limited(let remaining, _) = quotaStore.allowance(for: .question, status: status, calendar: calendar),
              remaining <= Self.fewFreeQuestionsLeft
        else { return nil }
        return remaining
    }

    /// 回答カードに無料の残りの回数を出し始める回数。
    static let fewFreeQuestionsLeft = 3

    @discardableResult
    private func appendQuestion(_ text: String, askedAt: Date, state: QuestionExchange.State) -> UUID {
        let exchange = QuestionExchange(text: text, askedAt: askedAt, state: state)
        questions.append(exchange)
        return exchange.id
    }

    private func setQuestionState(_ state: QuestionExchange.State, for id: UUID) {
        guard let index = questions.firstIndex(where: { $0.id == id }) else { return }
        questions[index].state = state
    }

    /// 送った文を入力欄に戻す。ただし解析の間に次の入力を打ち始めていたら、そちらを上書きしない。
    private func restoreDraft(_ text: String) {
        if draft.isEmpty { draft = text }
    }

    /// 何円をどのカテゴリに記録したかを VoiceOver に読み上げさせる。
    ///
    /// 「記録しました / 取り消す」のバナーは、画面に出ても VoiceOver では読まれない。読み上げないと、
    /// VoiceOver の利用者は記録できたかも、AI がどう読んだかも分からず、読み違いにその場で気づけない。
    /// 今日でない日付に記録したときは日付も読む（「昨日」の読み違いや、未来の日付に気づけるように）。
    /// 今日かどうかは、記録の日付を決めたのと同じ送った瞬間（`today`）で見る。
    private func announceRecorded(_ recorded: [Entry], today: Date, calendar: Calendar) {
        let items = recorded.map { entry in
            var item = "\(entry.kindText) \(YenFormatter.string(from: entry.amount))"
            if !calendar.isDate(entry.spentAt, inSameDayAs: today) {
                let format: Date.FormatStyle = entry.showsYear(today: today, calendar: calendar)
                    ? .dateTime.year().month().day() : .dateTime.month().day()
                item += " \(entry.spentAt.formatted(format))"
            }
            return item
        }
        announce(String(localized: "記録しました: \(items.formatted(.list(type: .and)))"))
    }

    // MARK: - レシート

    /// カメラのボタン（入力欄の左）。無料の回数が残っていれば「撮る」「写真から選ぶ」を選ばせ、使い切っていればプレミアム（⑨）の
    /// 案内を出す（プレミアムと体験中は無制限）。選ばせるまでを待つ Task を返す（テストで使う）。
    ///
    /// 購入の事実を読み終える前は、プレミアムでも無料に見えるので、読み終えるのを待ってから決める（家計への質問と同じ）。
    @discardableResult
    func requestReceiptScan(calendar: Calendar) -> Task<Void, Never> {
        Task {
            if !purchases.hasLoadedPurchases {
                await purchases.refreshPurchases()
            }
            guard quotaStore.allowance(for: .receiptScan, status: purchases.status, calendar: calendar).canUse else {
                announce(String(localized: "今月の無料のレシートの読み取りを使い切りました"))
                presentPremium()
                return
            }
            showsReceiptSourceChoice = true
        }
    }

    /// 選んだ取り込み口（書類カメラか写真の選択）を開く。
    func startReceiptCapture(_ source: ReceiptCaptureSource) {
        guard source != .camera || canUseDocumentCamera else { return }
        receiptCapture = source
    }

    /// 書類カメラで撮り終えた。画像を持っておき、カメラの画面を閉じる（閉じきったら `receiptCaptureDidDismiss` で読み取る）。
    ///
    /// - Parameter skippedPageCount: 上限（`DocumentCameraView.maximumPages`）を超えて読み取らなかったページの数。⑤ に知らせる。
    func finishDocumentCamera(_ images: [ReceiptImage], skippedPageCount: Int = 0) {
        capturedReceiptImages = (images, skippedPageCount)
        receiptCapture = nil
    }

    /// 取り込み口の画面が閉じきった（書類カメラ）。撮った画像があれば読み取りのシートを出す。
    ///
    /// カメラの画面が閉じる途中でシートを出すと、画面の出し入れが重なって出ないことがあるため、閉じきってから出す。
    /// 読み取りを待つ Task を返す（テストで使う）。撮った画像が無ければ nil。
    @discardableResult
    func receiptCaptureDidDismiss(calendar: Calendar) -> Task<Void, Never>? {
        guard let captured = capturedReceiptImages else { return nil }
        capturedReceiptImages = nil
        return readReceipt(captured.images, source: .camera, skippedPageCount: captured.skippedPageCount, calendar: calendar)
    }

    /// 画像を読み取る。⑤ のシートを読み取り中で出し、読み終えたら結果を入れる。読み終えるまでを待つ Task を返す（テストで使う）。
    ///
    /// 読み取りでは無料の回数を数えない（数えるのは記録したときだけ。`recordReceipt`）。保存先には書き込まない（記録は利用者が
    /// 「記録する」を押したときにその場で書き込む）ので、`pendingWrites` には数えない。
    ///
    /// - Parameter skippedPageCount: 書類カメラで上限を超えて読み取らなかったページの数。
    @discardableResult
    func readReceipt(
        _ images: [ReceiptImage], source: ReceiptCaptureSource, skippedPageCount: Int = 0, calendar: Calendar
    ) -> Task<Void, Never> {
        startReceiptReading(source: source, skippedPageCount: skippedPageCount, calendar: calendar) { images }
    }

    /// 選んだ写真を読み取る。⑤ を読み取り中で先に出してから、写真を読み込む（`loadImage`）。読み込めなければ（写真のデータを
    /// 読めない・iCloud から取り出せない）、「写真を読み込めませんでした」を出す。読み終えるまでを待つ Task を返す（テストで使う）。
    ///
    /// 先に出すのは、iCloud にだけある写真は取り出すのに時間がかかり、その間に何も出ないと、選んだことが伝わらないため。
    @discardableResult
    func readReceiptPhoto(
        calendar: Calendar, loadImage: @escaping @Sendable () async -> ReceiptImage?
    ) -> Task<Void, Never> {
        startReceiptReading(source: .photos, skippedPageCount: 0, calendar: calendar) {
            await loadImage().map { [$0] } ?? []
        }
    }

    private func startReceiptReading(
        source: ReceiptCaptureSource,
        skippedPageCount: Int,
        calendar: Calendar,
        images loadImages: @escaping @Sendable () async -> [ReceiptImage]
    ) -> Task<Void, Never> {
        receiptCapture = nil
        let readAt = now()
        let result = ReceiptResultModel(
            source: source,
            readAt: readAt,
            calendar: calendar,
            firstSkippedPage: skippedPageCount > 0 ? DocumentCameraView.maximumPages + 1 : nil,
            announce: announce,
            record: { [weak self] submission in self?.recordReceipt(submission, calendar: calendar) ?? .failed },
            retake: { [weak self] in self?.retakeReceipt(source) }
        )
        receiptResult = result
        let reader = receiptReader
        return Task { [weak self] in
            let images = await loadImages()
            // 画像を読み込む間にシートを閉じていたら、文字を読まない。
            guard self?.receiptResult === result else { return }
            let reading = await reader.read(images, now: readAt, calendar: calendar)
            // 読み取りの間にシートを閉じていたら（撮り直しを含む）、結果を入れない（閉じたシートの読み上げが割り込まないように）。
            guard let self, receiptResult === result else { return }
            result.load(reading)
        }
    }

    /// ⑤ から記録する。記録したら ⑤ を閉じ、記録の吹き出しと「取り消す」を出し、無料の 1 回を数える。
    ///
    /// 数えるのは記録したときだけ（読み取っただけ・読めなかった・閉じたは数えない）。記録の直後に「取り消す」を押したら戻す。
    /// 記録しようとした時点で使い切っていれば（読み取りの間に月が替わった・時計を動かしたなど）、記録せずにプレミアムの案内を出す。
    func recordReceipt(_ submission: ReceiptResultModel.Submission, calendar: Calendar) -> ReceiptResultModel.RecordOutcome {
        let status = purchases.status
        guard quotaStore.allowance(for: .receiptScan, status: status, calendar: calendar).canUse else {
            presentsPremiumAfterReceipt = true
            receiptResult = nil
            return .limitReached
        }
        let recordedAt = now()
        let recorded = Entry.records(fromReceipt: submission, now: recordedAt, calendar: calendar)
        guard !recorded.isEmpty else { return .failed }
        do {
            try store.insert(recorded)
        } catch {
            return .failed
        }
        if case .counted(let month) = quotaStore.use(.receiptScan, status: status, calendar: calendar) {
            receiptQuotaCharge = (month, recorded.map(\.persistentModelID))
        } else {
            receiptQuotaCharge = nil
        }
        justRecorded = recorded
        receiptResult = nil
        announceRecorded(recorded, today: recordedAt, calendar: calendar)
        return .recorded
    }

    /// 撮り直す。⑤ を閉じ、閉じきったら同じ取り込み口をもう一度開く（`receiptResultDidDismiss`）。
    func retakeReceipt(_ source: ReceiptCaptureSource) {
        pendingReceiptRetake = source
        receiptResult = nil
    }

    /// ⑤ のシートが閉じきった。撮り直しなら取り込み口を開き、使い切っていたならプレミアムの案内を出す。
    func receiptResultDidDismiss() {
        if presentsPremiumAfterReceipt {
            presentsPremiumAfterReceipt = false
            pendingReceiptRetake = nil
            presentPremium()
            return
        }
        if let source = pendingReceiptRetake {
            pendingReceiptRetake = nil
            startReceiptCapture(source)
        }
    }

    // MARK: - 取り消し

    /// 直前の記録を取り消す。元の文を入力欄に戻し、その場で直して送り直せるようにする。
    ///
    /// レシートから記録したものは、入力欄に何も戻さない（元の文は「レシート: 店名 合計 ¥…」の要約で、送り直すと合計の 1 件を
    /// ひとこと入力として記録してしまうため）。その回に数えた無料の 1 回は戻す（取り消した記録は数えない決め事。docs/design.md §6）。
    func undoLastRecord() {
        let targets = justRecorded
        guard !targets.isEmpty else { return }
        // 消した記録の値は、保存した後には読めない。読み上げと入力欄に戻す文は先に取っておく。
        let items = targets.map { "\($0.kindText) \(YenFormatter.string(from: $0.amount))" }
        let originalText = targets.first?.originalText ?? ""
        let isReceipt = targets.allSatisfy { $0.source == .receipt }
        let ids = targets.map(\.persistentModelID)
        do {
            try store.delete(targets)
        } catch {
            // バナーは残し、もう一度押せるようにする。
            storeFailure = .undo
            return
        }
        justRecorded = []
        if let charge = receiptQuotaCharge, charge.ids == ids {
            quotaStore.refundUse(of: .receiptScan, month: charge.month)
        }
        receiptQuotaCharge = nil
        if !isReceipt { restoreDraft(originalText) }
        announce(String(localized: "取り消しました: \(items.formatted(.list(type: .and)))"))
    }

    /// 「取り消す」のバナーを引っ込める（時間切れ・「閉じる」の操作）。記録はそのまま残る。
    func dismissUndo() {
        justRecorded = []
    }

    // MARK: - 削除

    /// 削除の確認を出す。確認の文は先に作っておく（消した後の記録の値は読めないため）。
    func requestDelete(_ entry: Entry) {
        pendingDeletion = PendingDeletion(entry: entry, summary: entry.summaryText)
    }

    /// 確認のあとで記録を削除する。
    func delete(_ pending: PendingDeletion) {
        pendingDeletion = nil
        let id = pending.entry.persistentModelID
        do {
            try store.delete([pending.entry])
        } catch {
            storeFailure = .delete
            return
        }
        // 直前に記録したものを消したら、「取り消す」の対象からも外す（消えた記録を取り消そうとしないように）。
        justRecorded.removeAll { $0.persistentModelID == id }
        announce(String(localized: "削除しました: \(pending.summary)"))
    }

    // MARK: - 直す

    /// 「直す」のシートを出す（吹き出しのタップ・長押しのメニュー・「取り消す」のバナー・VoiceOver の操作から）。
    ///
    /// 直した内容の保存は同期的に書き込む（送信のように、あとで書き込む処理ではない）ので、`pendingWrites` には数えない。
    /// - Parameter calendar: 日付の区切りの基準（画面の暦）。今日より先かの判定と、日付を直したかの判定に使う。
    func presentEdit(_ entry: Entry, calendar: Calendar) {
        editing = EditEntryModel(
            entry: entry,
            store: store,
            calendar: calendar,
            now: now,
            announce: announce,
            didSave: { [weak self] entry in self?.finishEditing(entry) },
            didDelete: { [weak self] id in self?.justRecorded.removeAll { $0.persistentModelID == id } }
        )
    }

    /// 直前に記録したものを直したら、「取り消す」を引っ込める。
    ///
    /// 取り消すと、直す前の送った文を入力欄に戻すことになり、直した内容と食い違うため（送り直すと、直す前の読み方で
    /// 記録し直すことになる）。直した後も消したければ、長押しの「削除」か、直すシートの「この記録を削除」から消せる。
    private func finishEditing(_ entry: Entry) {
        let id = entry.persistentModelID
        if justRecorded.contains(where: { $0.persistentModelID == id }) {
            justRecorded = []
        }
    }

    // MARK: - 予算

    /// 「予算を決める」のシートを出す。いまの予算を入力欄に入れて開く（予算を変えるときも同じ画面）。
    ///
    /// 予算の保存は同期的に書き込む（送信のように、あとで書き込む処理ではない）ので、`pendingWrites` には数えない。
    func presentBudgetSetup() {
        // カテゴリ別の予算はプレミアムと体験中だけ出す（開く時点の状態で決める）。
        budgetSetup = BudgetSetupModel(
            store: budgetStore, showsCategoryBudgets: purchases.status.unlocksPremium, announce: announce
        )
    }

    // MARK: - 月のまとめ

    /// 「月のまとめ」へ進む（帯の今月の合計を押したとき）。今月を開く。
    ///
    /// まとめの記録の一覧からも「直す」を開けるので、ホームから開いたときと同じく、直したら「取り消す」を引っ込め、
    /// 消したら「取り消す」の対象から外す（戻ったあとで、消えた記録や直す前の文を取り消しで扱わないように）。
    /// - Parameters:
    ///   - calendar: 月の区切りの暦（ホームの画面の暦。帯の今月と同じ月でまとめるため）。
    ///   - month: 開く月に入る日時（質問の回答カードから先月を開くとき）。nil なら今月。
    func presentMonthlyReport(calendar: Calendar, month: Date? = nil) {
        monthlyReport = MonthlyReportModel(
            store: store,
            calendar: calendar,
            month: month,
            remark: RecapRemarkModel(purchases: purchases, makeWriter: makeRemarkWriter),
            now: now,
            announce: announce,
            didSave: { [weak self] entry in self?.finishEditing(entry) },
            didDelete: { [weak self] id in self?.justRecorded.removeAll { $0.persistentModelID == id } }
        )
    }

    // MARK: - 設定

    /// 「設定」へ進む（帯の右上の歯車を押したとき）。
    ///
    /// 設定から開く「予算を決める」も、ホームの帯から開くときと同じ保存先と読み上げを使う。
    func presentSettings() {
        settings = SettingsModel(
            context: store.context, budgetStore: budgetStore, purchases: purchases, defaults: defaults, now: now, announce: announce
        )
    }

    // MARK: - プレミアム

    /// 「プレミアム」のシートを出す（無料の質問やレシートの読み取りを使い切ったときの案内から）。
    func presentPremium() {
        premiumSheet = PremiumSheetModel(purchases: purchases, announce: announce)
    }

    /// 無料体験が終わった後の最初の起動で、一度だけ「プレミアム」のシートを出す。
    ///
    /// 出したことは設定に書き、二度と出さない（しつこく出さない）。購入の事実を読み終えるまでは出さない（読み終える前は
    /// 無料と見分けがつかないため）。ほかのシートや画面を出しているときは出さず、次に呼ばれたときに出す（重ねて出すと、
    /// 利用者の操作を遮るため）。ホームが出たとき・前面に戻ったとき・プレミアムの状態が変わったときに呼ぶ。
    func presentPremiumIfTrialEnded() {
        guard purchases.hasLoadedPurchases, case .trialEnded = purchases.status else { return }
        guard !defaults.bool(for: AppSettings.hasShownTrialEndedPremium) else { return }
        guard budgetSetup == nil, editing == nil, monthlyReport == nil, settings == nil, premiumSheet == nil,
              weeklyRecapDetail == nil, receiptResult == nil, receiptCapture == nil, !showsReceiptSourceChoice
        else { return }
        premiumSheet = PremiumSheetModel(purchases: purchases, announce: announce)
        defaults.set(true, for: AppSettings.hasShownTrialEndedPremium)
    }

    // MARK: - 先週のふりかえり

    /// 週が替わって最初に開いたときだけ、先週のふりかえりのカードを出す（`WeeklyRecap.isDue`）。出したら、出した日時を設定に
    /// 書く（同じ週にはもう出さない。閉じなくても、次に開き直したときには出さない）。
    ///
    /// ホームが出たとき・前面に戻ったとき・日付が変わったとき・画面の暦（週の始まりの設定）が変わったときに呼ぶ。出している
    /// カードは、暦が変わったら変えた後の週で数え直し、開いたまま週が替わったら新しい週のカードに替える。
    /// 保存先は読むだけで書き込まないので、`pendingWrites` には数えない。
    /// - Parameter calendar: 週の区切りの暦（ホームの画面の暦。週の始まりは設定のとおり）。
    func showWeeklyRecapIfDue(calendar: Calendar) {
        let now = now()
        weeklyRecap?.update(calendar: calendar)
        let earliest = try? store.context.fetch(Entry.earliestDescriptor).first?.spentAt
        guard WeeklyRecap.isDue(
            lastShownAt: defaults.date(for: AppSettings.weeklyRecapShownAt), earliestRecordAt: earliest, now: now, calendar: calendar
        ) else { return }
        defaults.set(now, for: AppSettings.weeklyRecapShownAt)
        weeklyRecap = WeeklyRecapModel(
            store: store,
            calendar: calendar,
            shownAt: now,
            remark: RecapRemarkModel(purchases: purchases, makeWriter: makeRemarkWriter),
            now: self.now,
            announce: announce,
            didSave: { [weak self] entry in self?.finishEditing(entry) },
            didDelete: { [weak self] id in self?.justRecorded.removeAll { $0.persistentModelID == id } }
        )
    }

    /// 先週のふりかえりのカードを閉じる（「閉じる」の操作）。同じ週にはもう出さない（出した日時は出したときに書いてある）。
    func dismissWeeklyRecap() {
        guard weeklyRecap != nil else { return }
        weeklyRecap = nil
        // カードが消えると VoiceOver のフォーカスの行き先が無くなるので、閉じたことを読み上げる。
        announce(String(localized: "先週のふりかえりを閉じました"))
    }

    /// 先週のふりかえりの内訳へ進む（カードを押したとき）。
    func presentWeeklyRecapDetail() {
        weeklyRecapDetail = weeklyRecap
    }

    /// プレミアムの状態が変わったとき（体験を始めた・買った・返金された）に、ふりかえりの AI の一言を決め直す。
    func premiumStatusDidChange() {
        weeklyRecap?.remark.refresh()
    }

    // MARK: - 日付とタイムライン

    /// 「今日」を読み直す。前面に戻ったときと、日付が変わったとき（0 時・時間帯の変更など）に呼ぶ。
    func refreshToday() {
        today = now()
        // 体験の残りの日数と終わりも、今の時刻で出し直す。
        purchases.clockDidChange()
    }

    /// タイムラインにさらに前の記録を読み込む。
    func showMoreTimeline() {
        timelineLimit += Self.timelinePageSize
    }

    // MARK: - 型

    /// 削除の確認を待っている記録。確認の文は先に作っておく（消した後の記録の値は読めないため）。
    struct PendingDeletion {
        let entry: Entry
        let summary: String
    }

    /// 保存先への書き込みの失敗。利用者に知らせ、記録したつもり・消したつもりにさせない。
    enum StoreFailure: Equatable {
        case record
        case undo
        case delete
    }
}
