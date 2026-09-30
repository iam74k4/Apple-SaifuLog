import Foundation
import Observation
import SaifuLogCore
import SwiftData
import SwiftUI

/// ホームの状態と操作（送信・家計への質問・レシートの読み取り・声の入力・取り消し・直す・削除・予算を決める画面と月のまとめと設定と
/// プレミアムの出し入れ・先週のふりかえりのカード・「自分／家族」の切り替え）。
///
/// 家族と家計を共有しているとき（家計の共有が有効なビルドだけ）は、帯の「自分／家族」で記録先を切り替える。「家族」のときは、
/// 入力欄で記録したものを家計の保存先（`HouseholdHost`）に入れ、直す・取り消す・削除も家計の記録に効く。家計への質問・レシート・
/// 声の入力・月のまとめ・ふりかえりは v1 では「自分」だけ（docs/design.md §9 の家族との共有の決め事）。
///
/// 画面（`HomeView`）から切り離し、解析器・時計・読み上げを差し替えて SaifuLogTests で確かめられるようにしている。
/// 画面は、ここの値を表示し、操作をここへ渡すだけにする。
@MainActor
@Observable
final class HomeModel {
    /// タイムラインに一度に読み込む件数（さかのぼるときは「前の記録を表示」で同じ件数ずつ足す）。
    ///
    /// タイムラインは読み込んだ行をすべて測る（大きな文字で空に見えた不具合を直すため。`HomeView` の `TimelineScrollView`）ので、
    /// 開くときの手間が件数に比例する。テストのウィンドウにホームを置いて測ると（iPhone 17 Pro の iOS 26.4 のシミュレータ・標準の文字・
    /// 撮影用のデモの記録）、最初に並べ終えるまでが、行の組み立てを軽くした後（`EntryBubble`）で 100 件 0.3 秒ほど・
    /// 50 件 0.2 秒ほど（軽くする前は 100 件で 0.5 秒ほど、LazyVStack では 100〜500 件で 0.1 秒ほど）。開くときの待ちをさらに縮めるため、
    /// 1 日に 3〜6 件つける人で 1〜2 週間ほどが入る 50 件にする（実機での重さは docs/design.md §15 の 17 で確かめる）。
    static let timelinePageSize = 50
    /// タイムラインに読み込む件数の上限（「前の記録を表示」で足せるのはここまで）。
    ///
    /// 読み込んだ行は、開くときだけでなく、記録を足したり消したりしたとき・iCloud の同期で取り込んだとき・前面に戻って `today` を
    /// 読み直したときにも、すべて描き直す。その手間も件数に比例し、上と同じ測り方で `today` の読み直しが 100 件で 0.09 秒・300 件で
    /// 0.2 秒・500 件で 0.33 秒・1,000 件で 0.66 秒ほど、1 ページ足すのが 300 件から 0.2 秒・500 件から 0.34 秒ほどかかった（行の組み立てを
    /// 軽くする前の値。軽くした後は、300 件の描き直しが 0.09 秒ほど、50 件ずつ足すのが 300 件まで 0.07〜0.14 秒ほど）。
    /// 上限が無いと、何度も読み足した後は操作のたびに引っかかるので、0.2 秒ほどに収まる 300 件で止める。それより前の記録は、
    /// 月のまとめのカテゴリの一覧と設定の CSV の書き出しで見てもらう（上限に届いたら、タイムラインの上にそう案内する）。
    static let timelineMaxLimit = 300

    /// 入力欄の文。
    var draft = "" {
        didSet {
            // 入力欄を空にしたら（送った・消した）、声で入れた文ではなくなる。
            if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { draftSource = .text }
        }
    }
    /// 入力欄の文をどこから入れたか。声で入れた文（打ち直したものも含む）を送ったら、記録の入力元を「声」にする。
    private(set) var draftSource: EntrySource = .text
    /// よく使うひとことの候補（品目ごとにまとめたもの。入力欄の文に合わせて絞るのは画面。`QuickPhrases.suggestions`）。
    /// 記録を足す・直す・消す・取り込むたびに `refreshQuickPhrases()` で作り直す。
    private(set) var quickPhrases: [QuickPhrase] = []
    /// 送った文を読み取っている間（送信ボタンを押せなくし、読み取り中の印を出す）。
    private(set) var isParsing = false
    /// 直前の送信で記録したもの。その送信の返事に「取り消す」を出すため（時間では引っ込めない。次の文を送る・取り消す・
    /// その記録を直す・記録先を切り替えるまで残し、消した記録は外す）。
    private(set) var justRecorded: [Entry] = []
    /// 直前に家計へ記録したもの（「家族」のとき）。記録の直後に「取り消す」を出すため。
    private(set) var justRecordedHousehold: [HouseholdEntry] = []
    /// 記録先（「自分」か「家族」か）。家計に入っているときだけ「家族」を選べる（`showsLedgerSwitch`）。
    ///
    /// 切り替えたら「取り消す」を引っ込める（切り替えた後に、前の記録先の記録を取り消すと、どちらの記録が消えたか分からないため）。
    var ledgerScope: LedgerScope = .personal {
        didSet {
            guard ledgerScope != oldValue else { return }
            justRecorded = []
            justRecordedHousehold = []
            categoryQuestionIDs = []
        }
    }
    /// 直前の送信で記録したもののうち、返事でカテゴリを聞き返しているもの（「その他」になり、品目が辞書にも覚えにも当たらない支出。
    /// `CategoryMemory.asksCategory`）。「取り消す」と同じく、次の文を送る・取り消す・選ぶ・その記録を直す・消す・記録先を
    /// 切り替えるまで出す。聞き返すのは返事の中だけで、記録は止めない（一行入力の軽さを保つため。docs/design.md §3-2）。
    private(set) var categoryQuestionIDs: Set<PersistentIdentifier> = []
    /// 家計の記録の削除の確認を待っているもの。
    var pendingHouseholdDeletion: PendingHouseholdDeletion?
    /// 「家族」のときに、質問や読めない文を送った（家計には記録しない）ことの知らせ。
    var householdInputAlert: HouseholdInputAlert?
    var showsNoAmountAlert = false
    var storeFailure: StoreFailure?
    var pendingDeletion: PendingDeletion?
    /// 「予算を決める」のシートの状態と操作。シートを出していなければ nil（シートを閉じると画面が nil に戻す）。
    var budgetSetup: BudgetSetupModel?
    /// 「直す」のシートで直している記録の状態と操作。シートを出していなければ nil（シートを閉じると画面が nil に戻す）。
    var editing: EditEntryModel?
    /// 返事の聞き返しから開いた「カテゴリを作る」のシート。出していなければ nil（閉じると画面が nil に戻す）。
    var categoryEditor: CategoryEditorModel?
    /// 返事の行の長押しの「毎月くり返す」で開く、くり返しの記録を作るシート。出していなければ nil。
    var recurringEditor: RecurringEditorModel?
    /// Siri・ショートカットからの頼みのうち、まだ行っていないもの（読み取りの間・ほかの画面を出している間は待つ）。
    private(set) var pendingQuickAction: QuickAction?
    /// 入力欄にキーボードを出す頼みの数（増えるたびに、入力欄にフォーカスを入れる）。
    private(set) var inputFocusRequest = 0
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
    /// プレミアムの購入と状態（アプリで 1 つ）。カテゴリ別の予算（予算の画面の欄と月のまとめの進み）を出すかの判定と、設定・プレミアムのシートに渡す。
    let purchases: PurchaseManager
    /// 家計の共有（アプリで 1 つ）。無ければ（テスト・家計の共有が無効なビルド）「自分／家族」の切り替えを出さない。
    let household: HouseholdHost?
    /// いまのカテゴリの一覧（組み込みと作ったカテゴリ）。画面へは環境で渡し、記録に作ったカテゴリの名前を当てるのに使う。
    let categories: CategoryCatalogModel
    /// 今日。「今月」の範囲と、日付に年を添えるかの基準にする。
    ///
    /// 描画のたびに `.now` を読むだけだと、アプリを開いたまま（または裏に置いたまま）月をまたいだとき、
    /// 描き直しが起きずに前の月の合計が「今月」として出続ける。前面に戻ったときと日付が変わったときに
    /// `refreshToday()` で更新する。
    private(set) var today: Date
    /// タイムラインに読み込む件数。上の「前の記録を表示」で増やす（`timelineMaxLimit` まで）。
    private(set) var timelineLimit = HomeModel.timelinePageSize
    /// 「前の記録を表示」でさらに読み込めるか（読み込む件数が上限に届いていなければ）。
    var canShowMoreTimeline: Bool { timelineLimit < Self.timelineMaxLimit }
    /// この起動の間に送った質問とその返事。タイムラインに記録の送信（送った文と返事）と同じ流れ（送った順）で出す。
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
    /// 声の入力（マイクのボタン）。書き起こした文は入力欄へ入れるだけで、送らない（送信は利用者が押したときだけ）。
    let voice: VoiceInputModel

    @ObservationIgnored private let store: EntryStore
    @ObservationIgnored private let budgetStore: BudgetStore
    /// 覚えたカテゴリ（修正の記憶）。読み取った記録に当て、返事で選んだカテゴリを覚える。
    @ObservationIgnored private let learnedCategories: LearnedCategoryStore
    /// くり返しの記録。記録する日を過ぎた月の分を記録する。
    @ObservationIgnored private let recurring: RecurringEntryStore
    /// くり返しの記録を記録するときの暦（時間帯と読み上げの日付）。画面から最後に渡された暦（設定の画面から足したときにも使う）。
    @ObservationIgnored private var recurringCalendar: Calendar = .autoupdatingCurrent
    @ObservationIgnored private let pendingWrites: PendingStoreWrites
    /// 保存先を開いたもの。設定の「iCloud で同期」の切り替え先として設定に渡す。無ければ設定に iCloud の節を出さない（テスト用）。
    @ObservationIgnored private let storeHost: StoreHost?
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
    /// 直前に家計へ記録したときに送った文。家計の記録は送った文を持たないので、取り消したときに入力欄へ戻すために取っておく。
    @ObservationIgnored private var householdRecordedText: String?

    /// - Parameters:
    ///   - budgetStore: 予算の読み書き。渡さなければ記録と同じ保存先（`store` の ModelContext）を使う。
    ///   - learnedCategories: 覚えたカテゴリの読み書き（修正の記憶）。渡さなければ記録と同じ保存先を使う。
    ///   - categories: カテゴリの一覧（作ったカテゴリ）。渡さなければ記録と同じ保存先から読む。
    ///   - recurring: くり返しの記録の読み書き。渡さなければ記録と同じ保存先を使う。
    ///   - pendingWrites: 解析を待ってから記録する処理を数える先（`StoreHost.pendingWrites`）。保存先を開き直すとき、
    ///     記録し終えるのを待ってもらうため。
    ///   - purchases: プレミアムの購入と状態。アプリは `SaifuLogApp` の 1 つを渡す。渡さなければ購入の無い状態（テスト用）。
    ///   - storeHost: 保存先を開いたもの（設定の「iCloud で同期」の切り替え先）。アプリは `SaifuLogApp` の 1 つを渡す。
    ///   - household: 家計の共有（「自分／家族」の切り替えと、家計への記録）。アプリは `SaifuLogApp` の 1 つを渡す。
    ///   - defaults: 設定の置き場所（体験の終わりの案内を出したか、無料で質問した回数）。アプリは `UserDefaults.standard`、
    ///     テストは使い捨ての領域。
    ///   - quotaStore: 無料で使った回数の読み書き。渡さなければ `defaults` と `now` で作る。
    ///   - makeParser: 送信のたびに解析器を選ぶ（AI の使える・使えないは途中から変わるため）。送った瞬間の日時と暦を渡し、
    ///     「昨日」「9/26」をその日時を基準に読ませる。テストで差し替える。
    ///   - makeAnswerer: 質問のたびに答え方（AI かキーワード辞書）を選ぶ。テストで差し替える。
    ///   - makeRemarkWriter: ふりかえり（先週のふりかえり・月のまとめ）の AI の一言を書くもの。AI が使えなければ nil。テストで差し替える。
    ///   - receiptReader: レシートの画像の読み取り（文字認識と AI）。テストで決めた文字や偽物の AI に差し替える。
    ///   - canUseDocumentCamera: 書類カメラを使えるか。テストで決める。
    ///   - voice: 声の入力。渡さなければ端末の書き起こし（SpeechAnalyzer）とマイクを使う。テストで書き起こしを差し替えたものを渡す。
    ///   - now: 記録の日時と「今日」の基準。テストで固定の日時にする。
    ///   - announce: VoiceOver に読み上げさせる。テストで読み上げる文を集める。
    init(
        store: EntryStore,
        budgetStore: BudgetStore? = nil,
        learnedCategories: LearnedCategoryStore? = nil,
        categories: CategoryCatalogModel? = nil,
        recurring: RecurringEntryStore? = nil,
        pendingWrites: PendingStoreWrites = PendingStoreWrites(),
        purchases: PurchaseManager? = nil,
        storeHost: StoreHost? = nil,
        household: HouseholdHost? = nil,
        defaults: UserDefaults = .standard,
        quotaStore: QuotaStore? = nil,
        makeParser: @escaping (Date, Calendar) -> any EntryParsing = { EntryParserFactory.makeParser(now: $0, calendar: $1) },
        makeAnswerer: @escaping () -> any QuestionAnswering = { QuestionAnswererFactory.makeAnswerer() },
        makeRemarkWriter: @escaping () -> (any RecapRemarkWriting)? = { RecapRemarkWriterFactory.makeWriter() },
        receiptReader: ReceiptReader = ReceiptReader(),
        canUseDocumentCamera: Bool = DocumentCameraView.isSupported,
        voice: VoiceInputModel? = nil,
        now: @escaping () -> Date = { .now },
        announce: @escaping @MainActor (String) -> Void = { VoiceOver.announce($0) }
    ) {
        self.store = store
        self.budgetStore = budgetStore ?? BudgetStore(context: store.context)
        self.learnedCategories = learnedCategories ?? LearnedCategoryStore(context: store.context, now: now)
        self.categories = categories ?? CategoryCatalogModel(store: CustomCategoryStore(context: store.context, now: now))
        self.recurring = recurring ?? RecurringEntryStore(context: store.context, now: now)
        self.pendingWrites = pendingWrites
        self.storeHost = storeHost
        self.household = household
        self.purchases = purchases ?? PurchaseManager(loadPurchases: { [] })
        self.defaults = defaults
        self.quotaStore = quotaStore ?? QuotaStore(defaults: defaults, now: now)
        self.makeParser = makeParser
        self.makeAnswerer = makeAnswerer
        self.makeRemarkWriter = makeRemarkWriter
        self.receiptReader = receiptReader
        self.canUseDocumentCamera = canUseDocumentCamera
        self.voice = voice ?? VoiceInputModel()
        self.now = now
        self.announce = announce
        self.today = now()
        self.voice.insertTranscript = { [weak self] text in self?.insertTranscript(text) }
        self.voice.isCoveredByOtherScreen = { [weak self] in self?.isPresentingOtherScreen ?? false }
    }

    convenience init(
        context: ModelContext, pendingWrites: PendingStoreWrites = PendingStoreWrites(), purchases: PurchaseManager,
        storeHost: StoreHost? = nil, household: HouseholdHost? = nil
    ) {
        self.init(
            store: EntryStore(context: context), pendingWrites: pendingWrites, purchases: purchases, storeHost: storeHost,
            household: household
        )
    }

    /// ホームの上にほかの画面・シート・確認を出しているか。出している間は、体験の終わりの案内を重ねず、声の入力を止める
    /// （見えない入力欄に向けて聞き続けないように）。
    var isPresentingOtherScreen: Bool {
        budgetSetup != nil || editing != nil || categoryEditor != nil || recurringEditor != nil || monthlyReport != nil
            || settings != nil
            || premiumSheet != nil
            || weeklyRecapDetail != nil || receiptResult != nil || receiptCapture != nil || showsReceiptSourceChoice
    }

    /// 直前の記録を取り消せるか（返事の「取り消す」と入力欄の VoiceOver の操作を出すか）。いまの記録先の記録だけを数える。
    var canUndo: Bool {
        isHouseholdActive ? !justRecordedHousehold.isEmpty : !justRecorded.isEmpty
    }

    /// 入力欄の VoiceOver の「直す: …」の対象（いまの記録先の、直前に記録したもの）。
    var recordedItems: [RecordedItem] {
        if isHouseholdActive {
            justRecordedHousehold.map { RecordedItem(id: AnyHashable($0.id), summaryText: $0.summaryText) }
        } else {
            justRecorded.map {
                RecordedItem(id: AnyHashable($0.persistentModelID), summaryText: $0.summaryText(in: categories.catalog))
            }
        }
    }

    // MARK: - 自分／家族

    /// 帯に「自分／家族」の切り替えを出すか（家計に入っているときだけ）。
    var showsLedgerSwitch: Bool {
        household?.hasHousehold == true
    }

    /// いま「家族」（家計）に記録しているか。家計から抜けた・消えたときは「自分」に戻る。
    var isHouseholdActive: Bool {
        ledgerScope == .household && showsLedgerSwitch
    }

    /// 家計に入っているかが変わったとき（抜けた・消えた・入った）に呼ぶ。家計が無くなったら「自分」に戻す（次に家計に入ったときに、
    /// 前の「家族」のまま始まらないように）。
    func householdAvailabilityDidChange() {
        if !showsLedgerSwitch { ledgerScope = .personal }
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
        // 入力欄を空ける前に、どこから入れた文かを取っておく（空けると `draftSource` は text に戻る）。
        let source = draftSource
        // 送った時点で入力欄を空ける。解析（AI だと 1 秒以上かかることがある）を待ってから空けると、
        // 入力欄にとどまって打ち始めた次の入力まで、黙って消してしまうため。
        draft = ""
        return submit(text, source: source, calendar: calendar)
    }

    /// 文を送る（入力欄の文か、Siri・ショートカットから頼まれた文）。入力欄には触れない（送れなかったときに文を戻すのは、
    /// 入力欄が空のときだけ。`restoreDraft`）。
    ///
    /// - Parameter forcesQuestion: 記録か見分けずに質問として答える（Siri・ショートカットの「家計に質問」）。
    @discardableResult
    private func submit(
        _ text: String, source: EntrySource, forcesQuestion: Bool = false, calendar: Calendar
    ) -> Task<Void, Never> {
        // 送った瞬間の日時を 1 つ決め、解析（「昨日」「9/26」の基準）と保存（記録した日時・使った日時）の両方に使う。
        // 保存のときに時計を読み直すと、読み取りを待つ間に日付が変わったとき（23:59:59 に送って 0:00:01 に保存）、
        // 「9/26」と書いた記録が 1 日ずれて保存されるため。質問も、この日時で期間を区切る。
        let sentAt = now()
        // 前の記録の「取り消す」（返事の見出しと VoiceOver の操作）を引っ込める。読み取りの間も出したままだと、押したときに
        // 前の記録が消え、前の文が入力欄に戻る。それを送り直したり、いま送った文の記録だけが残ったりして、
        // 取り消したつもりのものと違う記録が残るため。質問を送ったときも同じにする（送るたびに引っ込める、と揃える）。
        justRecorded = []
        justRecordedHousehold = []
        categoryQuestionIDs = []
        if isHouseholdActive {
            return sendToHousehold(text, source: source, sentAt: sentAt, calendar: calendar)
        }
        if forcesQuestion {
            return ask(text, source: source, sentAt: sentAt, calendar: calendar)
        }
        switch InputIntentClassifier.classify(text, now: sentAt, calendar: calendar, catalog: categories.catalog) {
        case .record:
            return record(text, source: source, sentAt: sentAt, calendar: calendar)
        case .question:
            return ask(text, source: source, sentAt: sentAt, calendar: calendar)
        case .unclear:
            // 記録にはしない。書き直して送り直せるよう、送った文を入力欄に戻す。
            appendQuestion(text, askedAt: sentAt, state: .unclear)
            restoreDraft(text, source: source)
            announce(String(localized: "記録か質問か分かりませんでした"))
            return Task {}
        }
    }

    /// 記録として読み取って保存する。
    ///
    /// - Parameter source: 送った文をどこから入れたか（声で入れた文なら、記録の入力元を「声」にする）。
    private func record(_ text: String, source: EntrySource, sentAt: Date, calendar: Calendar) -> Task<Void, Never> {
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
                restoreDraft(text, source: source)
                showsNoAmountAlert = true
                return
            }
            // 作ったカテゴリの名前と覚えたカテゴリを、AI と辞書のどちらで読んだ記録にも当てる（修正の記憶）。覚えを読めなくても
            // 記録は止めない。
            let catalog = categories.catalog
            let memory = (try? learnedCategories.memory()) ?? CategoryMemory()
            let recorded = Entry.records(
                from: memory.applying(to: parsed, catalog: catalog), originalText: text, source: source, now: sentAt,
                calendar: calendar
            )
            do {
                try store.insert(recorded)
            } catch {
                // 保存できなかった。記録したことにはせず、送った文を戻して送り直せるようにする。
                restoreDraft(text, source: source)
                storeFailure = .record
                return
            }
            justRecorded = recorded
            categoryQuestionIDs = Set(
                recorded.filter {
                    memory.asksCategory(
                        memo: $0.memo, amount: $0.amount, category: $0.category, isIncome: $0.isIncome, catalog: catalog
                    )
                }
                .map(\.persistentModelID)
            )
            // 返事のカテゴリのボタンは画面に出るだけでは VoiceOver の利用者に伝わらないので、聞き返すときは選べることも読み上げる。
            announceRecorded(recorded, today: sentAt, calendar: calendar, asksCategory: !categoryQuestionIDs.isEmpty)
        }
    }

    // MARK: - 家族（家計）への記録

    /// 「家族」のときの送信。記録なら家計の記録として保存する。質問と、記録か質問か分からない文は、家計には記録せず、送った文を
    /// 入力欄に戻して知らせる（家計への質問は v1 では出さない。答えを自分の記録で出すと、家族の記録の答えと取り違えるため）。
    private func sendToHousehold(_ text: String, source: EntrySource, sentAt: Date, calendar: Calendar) -> Task<Void, Never> {
        switch InputIntentClassifier.classify(text, now: sentAt, calendar: calendar, catalog: categories.catalog) {
        case .record:
            return recordToHousehold(text, source: source, sentAt: sentAt, calendar: calendar)
        case .question:
            restoreDraft(text, source: source)
            householdInputAlert = .question
            announce(String(localized: "家族の家計では、まだ質問できません"))
        case .unclear:
            restoreDraft(text, source: source)
            householdInputAlert = .unclear
            announce(String(localized: "記録か質問か分かりませんでした"))
        }
        return Task {}
    }

    /// 家計の記録として読み取って保存する（記録した人は、家計の自分の表示名）。
    ///
    /// 家計の保存先は自分の記録の保存先とは別で、iCloud 同期の切り替えで開き直さないので、`pendingWrites` には数えない。
    private func recordToHousehold(_ text: String, source: EntrySource, sentAt: Date, calendar: Calendar) -> Task<Void, Never> {
        isParsing = true
        let parser = makeParser(sentAt, calendar)
        return Task {
            defer { isParsing = false }
            let parsed = (try? await parser.parse(text)) ?? []
            guard !parsed.isEmpty else {
                restoreDraft(text, source: source)
                showsNoAmountAlert = true
                return
            }
            // 読み取りを待つ間に「自分」へ切り替えた・家計から抜けた・家計が消えたときは、どちらにも記録しない（家計に書くつもりの
            // 文を自分の記録にしないため）。送った文を入力欄に戻し、いまの記録先で送り直せるようにする。
            guard let household, isHouseholdActive else {
                restoreDraft(text, source: source)
                return
            }
            let recorded: [HouseholdEntry]
            do {
                // 覚えたカテゴリは家計の記録にも当てる（書いた人の言葉の覚えなので）。聞き返しは「自分」の返事だけ。作ったカテゴリは
                // 自分の一覧にしかなく、家族の端末では名前が分からないので、家計の記録では「その他」にする。
                let memory = (try? learnedCategories.memory()) ?? CategoryMemory()
                let entries = memory.applying(to: parsed, catalog: categories.catalog).map { entry in
                    var shared = entry
                    if shared.category.isCustom { shared.category = .other }
                    return shared
                }
                recorded = try household.record(entries, sentAt: sentAt, calendar: calendar)
            } catch {
                restoreDraft(text, source: source)
                storeFailure = .record
                return
            }
            justRecordedHousehold = recorded
            householdRecordedText = text
            announceRecorded(
                recorded.map { (kind: $0.kindText, amount: $0.amount, spentAt: $0.spentAt) }, toHousehold: true,
                today: sentAt, calendar: calendar
            )
        }
    }

    // MARK: - 質問

    /// 家計への質問に答える。数字はコアが計算し（AI には計算させない）、答えは保存しない。
    ///
    /// 無料の回数（月 10 回）を使い切っていれば、答えずにプレミアムの案内を出す（記録は無料で無制限のまま）。数えるのは
    /// 答えを出せたときだけ（読めなかった質問・失敗は数えない）。プレミアムと体験中は数えない（`UsageQuota`）。
    /// 保存先には書き込まない（読むだけ）ので、`pendingWrites` には数えない。
    private func ask(_ text: String, source: EntrySource, sentAt: Date, calendar: Calendar) -> Task<Void, Never> {
        let id = appendQuestion(text, askedAt: sentAt, state: .answering)
        let ledger: QuestionLedger
        do {
            ledger = try QuestionLedger.load(from: store.context, now: sentAt, calendar: calendar)
        } catch {
            setQuestionState(.loadFailed, for: id)
            restoreDraft(text, source: source)
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
                restoreDraft(text, source: source)
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
                announce(QuestionTexts.spoken(
                    answer, remark: remark, freeQuestionsLeft: freeQuestionsLeft, calendar: calendar,
                    catalog: categories.catalog
                ))
            case .unreadable:
                setQuestionState(.unreadable, for: id)
                // 書き直して送り直せるよう、送った文を入力欄に戻す（記録の「金額が見つかりませんでした」と同じ）。
                restoreDraft(text, source: source)
                announce(String(localized: "質問を読めませんでした"))
            }
        }
    }

    /// 回答カードの「続けて聞く質問」を送る（ふつうの質問と同じ流れ。入力欄の文には触れない）。読み取りの間と「家族」のときは
    /// 受け付けない（nil を返す）。送った文は、打った質問と同じく自分の吹き出しに出る。
    @discardableResult
    func askFollowUp(_ followUp: QuestionFollowUp, calendar: Calendar) -> Task<Void, Never>? {
        guard !isParsing, !isHouseholdActive else { return nil }
        // 送信と同じく、前の記録の「取り消す」と聞き返しを引っ込める。
        justRecorded = []
        justRecordedHousehold = []
        categoryQuestionIDs = []
        return ask(followUp.text, source: .text, sentAt: now(), calendar: calendar)
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
    ///
    /// - Parameter source: 戻す文をどこから入れたか（声で入れた文を戻したら、送り直したときも入力元を「声」にする）。
    private func restoreDraft(_ text: String, source: EntrySource = .text) {
        guard draft.isEmpty else { return }
        draft = text
        if !text.isEmpty { draftSource = source }
    }

    // MARK: - 声の入力

    /// 書き起こした文を入力欄へ入れる（打ちかけの文があれば、その後ろに足す）。送信はしない。
    ///
    /// 書き起こしは読み違えることがあるので、利用者が入力欄で見て直してから送信ボタンを押したときだけ、記録や質問として扱う。
    /// 声の入力は無料で、回数も数えない（記録と同じく、いちばん使う入力の方法に上限を付けないため。docs/design.md §6）。
    private func insertTranscript(_ text: String) {
        let updated = VoiceTranscript.draft(appending: text, to: draft)
        guard updated != draft else { return }
        draft = updated
        draftSource = .voice
    }

    /// 何円をどのカテゴリに記録したかを VoiceOver に読み上げさせる。
    ///
    /// タイムラインに返事のカード（「記録しました」）が出ても、VoiceOver では読まれない（フォーカスは入力欄に戻る）。読み上げないと、
    /// VoiceOver の利用者は記録できたかも、AI がどう読んだかも分からず、読み違いにその場で気づけない。
    /// 今日でない日付に記録したときは日付も読む（「昨日」の読み違いや、未来の日付に気づけるように）。
    /// 今日かどうかは、記録の日付を決めたのと同じ送った瞬間（`today`）で見る。
    private func announceRecorded(_ recorded: [Entry], today: Date, calendar: Calendar, asksCategory: Bool = false) {
        announceRecorded(
            recorded.map { (kind: $0.kindText(in: categories.catalog), amount: $0.amount, spentAt: $0.spentAt) },
            toHousehold: false, today: today, calendar: calendar, asksCategory: asksCategory
        )
    }

    /// 記録の読み上げ（自分の記録と家計の記録で共通）。家計に記録したときは、家計に記録したことが分かる文にする
    /// （「自分／家族」を取り違えて記録したことに、読み上げで気づけるように）。
    private func announceRecorded(
        _ recorded: [(kind: String, amount: Int, spentAt: Date)], toHousehold: Bool, today: Date, calendar: Calendar,
        asksCategory: Bool = false
    ) {
        let items = recorded.map { entry in
            var item = "\(entry.kind) \(YenFormatter.string(from: entry.amount))"
            if !calendar.isDate(entry.spentAt, inSameDayAs: today) {
                let format: Date.FormatStyle = calendar.isDate(entry.spentAt, equalTo: today, toGranularity: .year)
                    ? .dateTime.month().day() : .dateTime.year().month().day()
                item += " \(entry.spentAt.formatted(format))"
            }
            return item
        }
        let list = items.formatted(.list(type: .and))
        if toHousehold {
            announce(String(localized: "家族の家計に記録しました: \(list)"))
        } else if asksCategory {
            announce(String(localized: "記録しました: \(list)。カテゴリを選べます"))
        } else {
            announce(String(localized: "記録しました: \(list)"))
        }
    }

    // MARK: - レシート

    /// カメラのボタン（入力欄の左）。無料の回数が残っていれば「撮る」「写真から選ぶ」を選ばせ、使い切っていればプレミアム（⑨）の
    /// 案内を出す（プレミアムと体験中は無制限）。選ばせるまでを待つ Task を返す（テストで使う）。
    ///
    /// 購入の事実を読み終える前は、プレミアムでも無料に見えるので、読み終えるのを待ってから決める（家計への質問と同じ）。
    @discardableResult
    func requestReceiptScan(calendar: Calendar) -> Task<Void, Never> {
        // レシートは v1 では「自分」だけ（「家族」のときはカメラのボタンを出さない）。
        guard !isHouseholdActive else { return Task {} }
        return Task {
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
            retake: { [weak self] in self?.retakeReceipt(source) },
            catalog: { [weak self] in self?.categories.catalog ?? .builtIn }
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

    /// ⑤ から記録する。記録したら ⑤ を閉じ、タイムラインにレシートの送信と返事（「取り消す」つき）を出し、無料の 1 回を数える。
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
    /// くり返しの記録も入力欄に何も戻さない。取り消した月の分はもう記録しない（記録した月は覚えたまま。`RecurringEntryStore`）。
    func undoLastRecord() {
        if isHouseholdActive {
            undoLastHouseholdRecord()
            return
        }
        let targets = justRecorded
        guard !targets.isEmpty else { return }
        // 消した記録の値は、保存した後には読めない。読み上げと入力欄に戻す文は先に取っておく。
        let items = targets.map { "\($0.kindText(in: categories.catalog)) \(YenFormatter.string(from: $0.amount))" }
        let originalText = targets.first?.originalText ?? ""
        // レシートとくり返しの記録は打った文ではないので、入力欄に戻さない。
        let restoresDraft = !targets.contains { $0.source == .receipt || $0.source == .recurring }
        let restoredSource: EntrySource = targets.allSatisfy { $0.source == .voice } ? .voice : .text
        let ids = targets.map(\.persistentModelID)
        do {
            try store.delete(targets)
        } catch {
            // 「取り消す」は残し、もう一度押せるようにする。
            storeFailure = .undo
            return
        }
        justRecorded = []
        categoryQuestionIDs = []
        if let charge = receiptQuotaCharge, charge.ids == ids {
            quotaStore.refundUse(of: .receiptScan, month: charge.month)
        }
        receiptQuotaCharge = nil
        if restoresDraft { restoreDraft(originalText, source: restoredSource) }
        announce(String(localized: "取り消しました: \(items.formatted(.list(type: .and)))"))
    }

    /// 直前に家計へ記録したものを取り消す（「家族」のとき）。送った文を入力欄に戻す。
    private func undoLastHouseholdRecord() {
        let targets = justRecordedHousehold
        guard let household, !targets.isEmpty else { return }
        let items = targets.map { "\($0.kindText) \(YenFormatter.string(from: $0.amount))" }
        do {
            try household.delete(targets)
        } catch {
            storeFailure = .undo
            return
        }
        justRecordedHousehold = []
        // 自分の記録と同じく、送った文を入力欄に戻して、その場で直して送り直せるようにする。
        if let text = householdRecordedText { restoreDraft(text) }
        householdRecordedText = nil
        announce(String(localized: "取り消しました: \(items.formatted(.list(type: .and)))"))
    }

    // MARK: - 削除

    /// 削除の確認を出す。確認の文は先に作っておく（消した後の記録の値は読めないため）。
    func requestDelete(_ entry: Entry) {
        pendingDeletion = PendingDeletion(entry: entry, summary: entry.summaryText(in: categories.catalog))
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
        forgetJustRecorded(id)
        announce(String(localized: "削除しました: \(pending.summary)"))
    }

    // MARK: - 家計の記録の直す・削除

    /// 家計の記録の削除の確認を出す。
    func requestHouseholdDelete(_ entry: HouseholdEntry) {
        pendingHouseholdDeletion = PendingHouseholdDeletion(entry: entry, summary: entry.summaryText)
    }

    /// 確認のあとで家計の記録を削除する（ほかの参加者の記録も消せる。家族の全員が読み書きできる共有のため）。
    func deleteHouseholdEntry(_ pending: PendingHouseholdDeletion) {
        pendingHouseholdDeletion = nil
        guard let household else { return }
        let id = pending.entry.id
        do {
            try household.delete([pending.entry])
        } catch {
            storeFailure = .delete
            return
        }
        justRecordedHousehold.removeAll { $0.id == id }
        announce(String(localized: "削除しました: \(pending.summary)"))
    }

    /// 家計の記録の「直す」のシートを出す（ほかの参加者の記録も直せる）。
    func presentHouseholdEdit(_ entry: HouseholdEntry, calendar: Calendar) {
        guard let household else { return }
        let id = entry.id
        let target = household.editTarget(
            for: entry,
            didSave: { [weak self] in
                // 直前に記録したものを直したら「取り消す」を引っ込める（自分の記録と同じ）。
                if self?.justRecordedHousehold.contains(where: { $0.id == id }) == true { self?.justRecordedHousehold = [] }
            },
            didDelete: { [weak self] in self?.justRecordedHousehold.removeAll { $0.id == id } }
        )
        editing = EditEntryModel(target: target, calendar: calendar, now: now, announce: announce)
    }

    /// 入力欄の VoiceOver の「直す: …」から、直前に記録したものを直す。
    func presentEdit(_ item: RecordedItem, calendar: Calendar) {
        if isHouseholdActive {
            guard let entry = justRecordedHousehold.first(where: { AnyHashable($0.id) == item.id }) else { return }
            presentHouseholdEdit(entry, calendar: calendar)
        } else {
            guard let entry = justRecorded.first(where: { AnyHashable($0.persistentModelID) == item.id }) else { return }
            presentEdit(entry, calendar: calendar)
        }
    }

    // MARK: - 直す

    /// 「直す」のシートを出す（返事の行のタップ・長押しのメニュー・VoiceOver の操作から）。
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
            didDelete: { [weak self] id in self?.forgetJustRecorded(id) },
            catalog: categories.catalog
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
        // 直すでカテゴリを選んだ（直すで変えたカテゴリは、そこで覚える）ので、返事で聞き返すのをやめる。
        categoryQuestionIDs.remove(id)
    }

    /// 消した記録を、「取り消す」と聞き返しの対象から外す（消えた記録を取り消したり、選んだりしないように）。
    private func forgetJustRecorded(_ id: PersistentIdentifier) {
        justRecorded.removeAll { $0.persistentModelID == id }
        categoryQuestionIDs.remove(id)
    }

    // MARK: - カテゴリの聞き返し

    /// 返事で聞き返したカテゴリを選ぶ（「その他のまま」は `.other`）。記録のカテゴリを直し、品目とカテゴリの組を覚えて、
    /// 次から同じ品目の記録をそのカテゴリにする（修正の記憶。docs/design.md §3-2）。
    ///
    /// 「取り消す」は残す（取り消すと送った文が入力欄に戻り、送り直すと覚えたカテゴリで記録されるので、選んだことと食い違わない）。
    /// 記録を直せなければ、聞き返しを残して知らせる（もう一度選べるように）。覚えられなくても、記録のカテゴリは直っているので
    /// 失敗にはしない（次に同じ品目を送ったときに、また聞き返す）。
    func chooseCategory(_ category: EntryCategory, for entry: Entry) {
        let id = entry.persistentModelID
        guard categoryQuestionIDs.contains(id) else { return }
        if entry.category != category {
            var edits = EntryEdits(entry)
            edits.category = category
            do {
                try store.update(entry, with: edits)
            } catch {
                storeFailure = .categoryChoice
                return
            }
        }
        let item = CategoryMemory.item(ofMemo: entry.memo, amount: entry.amount, isIncome: entry.isIncome)
        let remembered = (try? learnedCategories.remember(item: item, category: category)) ?? false
        categoryQuestionIDs.remove(id)
        let name = categories.catalog.localizedName(for: category)
        announce(
            remembered
                ? String(localized: "\(name)にしました。次から「\(item)」は\(name)にします")
                : String(localized: "\(name)にしました")
        )
    }

    /// 返事の聞き返しの「＋ カテゴリを作る」。作ったら、そのカテゴリを聞き返した記録のカテゴリにして覚える（`chooseCategory`）。
    func presentCategoryCreation(for entry: Entry) {
        guard categoryQuestionIDs.contains(entry.persistentModelID) else { return }
        categoryEditor = CategoryEditorModel(
            mode: .create,
            store: CustomCategoryStore(context: store.context, now: now),
            catalog: categories.catalog,
            announce: announce,
            didSave: { [weak self] category in
                // 一覧を先に読み直す（選んだカテゴリの名前を読み上げ、返事の行に出すため）。
                self?.categories.reload()
                self?.chooseCategory(category, for: entry)
            }
        )
    }

    // MARK: - Siri・ショートカット

    /// Siri・ショートカットからの頼みを受け取る（`QuickActionInbox` から）。前に待っていた頼みがあれば、新しいほうにする。
    func receive(_ action: QuickAction) {
        pendingQuickAction = action
    }

    /// 待っている頼みを、行えるなら行う。行ったら、その処理を待つ Task を返す（テストで使う）。行えなければ nil（待ち続ける）。
    /// ホームが出たとき・頼みを受け取ったとき・読み取りが終わったとき・ほかの画面を閉じたとき・ロックを解いたときに呼ぶ。
    ///
    /// 記録と質問は読み取りの間だけ待つ（ほかの画面を出していても行い、答えや返事はタイムラインに出す）。入力欄・レシート・
    /// 声は、ほかの画面を出している間も待つ（画面の下で入力欄やカメラを開かないため）。記録と質問の文が空なら、入力欄を開く。
    @discardableResult
    func performPendingQuickAction(calendar: Calendar) -> Task<Void, Never>? {
        guard let action = pendingQuickAction, !isParsing else { return nil }
        switch action {
        case .record(let text), .ask(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                guard !isPresentingOtherScreen else { return nil }
                pendingQuickAction = nil
                inputFocusRequest += 1
                return Task {}
            }
            pendingQuickAction = nil
            let isQuestion = if case .ask = action { true } else { false }
            return submit(trimmed, source: .text, forcesQuestion: isQuestion, calendar: calendar)
        case .compose:
            guard !isPresentingOtherScreen else { return nil }
            pendingQuickAction = nil
            inputFocusRequest += 1
            return Task {}
        case .receipt:
            guard !isPresentingOtherScreen else { return nil }
            pendingQuickAction = nil
            return requestReceiptScan(calendar: calendar)
        case .voice:
            guard !isPresentingOtherScreen else { return nil }
            pendingQuickAction = nil
            return voice.isActive ? Task {} : (voice.toggle() ?? Task {})
        }
    }

    // MARK: - くり返しの記録

    /// 記録する日を過ぎたくり返しの記録を記録し、返事のカード（「くり返しの記録」）と読み上げで知らせる（ホームが出たとき・
    /// 前面に戻ったとき・日付が変わったとき・くり返しの記録を足したり直したりしたとき）。
    ///
    /// 記録したものは直前の送信と同じく「取り消す」の対象にする（取り消すと、その月の分はもう記録しない）。書き込めなければ
    /// 何もしない（記録した月を覚えていないので、次に開いたときにもう一度記録する）。
    func recordDueRecurringEntries(calendar: Calendar) {
        recurringCalendar = calendar
        removeDuplicateRecurringEntries()
        let recordedAt = now()
        guard let recorded = try? recurring.recordDue(now: recordedAt, timeZone: calendar.timeZone), !recorded.isEmpty else {
            return
        }
        justRecorded = recorded
        categoryQuestionIDs = []
        receiptQuotaCharge = nil
        let items = recorded.map { entry in
            var item = "\(entry.kindText(in: categories.catalog)) \(YenFormatter.string(from: entry.amount))"
            if !calendar.isDate(entry.spentAt, inSameDayAs: recordedAt) {
                item += " \(entry.spentAt.formatted(.dateTime.month().day()))"
            }
            return item
        }
        announce(String(localized: "くり返しの記録をしました: \(items.formatted(.list(type: .and)))"))
    }

    /// iCloud で同期しているほかの端末が同じ月の分を記録していたら、片づける（`RecurringEntryStore.removeDuplicateOccurrences`）。
    /// iCloud でほかの端末の変更が届いたときと、くり返しの記録を記録する前に呼ぶ。
    func removeDuplicateRecurringEntries() {
        guard let removed = try? recurring.removeDuplicateOccurrences() else { return }
        removed.forEach(forgetJustRecorded)
    }

    /// 返事の行の長押しの「毎月くり返す」。その記録の金額・品目・カテゴリ・使った日を入れて、くり返しの記録を作るシートを出す。
    /// その記録の月の分はもう記録してあるので、次の月から記録する。
    func presentRecurringCreation(from entry: Entry, calendar: Calendar) {
        guard entry.source != .recurring else { return }
        let item = CategoryMemory.item(ofMemo: entry.memo, amount: entry.amount, isIncome: entry.isIncome)
        let day = calendar.component(.day, from: entry.spentAt)
        let recordedMonth = RecurringMonth(containing: entry.spentAt, timeZone: calendar.timeZone)
        recurringEditor = RecurringEditorModel(
            creating: RecurringDraft(
                amount: entry.amount, memo: item, isIncome: entry.isIncome, category: entry.category, dayOfMonth: day
            ),
            notBefore: recordedMonth.adding(months: 1),
            store: recurring,
            timeZone: calendar.timeZone,
            now: now,
            announce: announce,
            didChange: { [weak self] in self?.recordDueRecurringEntries(calendar: calendar) }
        )
    }

    // MARK: - 予算

    /// 「予算を決める」のシートを出す。いまの予算を入力欄に入れて開く（予算を変えるときも同じ画面）。
    ///
    /// 予算の保存は同期的に書き込む（送信のように、あとで書き込む処理ではない）ので、`pendingWrites` には数えない。
    func presentBudgetSetup() {
        // カテゴリ別の予算はプレミアムと体験中だけ出す（開く時点の状態で決める）。
        budgetSetup = BudgetSetupModel(
            store: budgetStore, showsCategoryBudgets: purchases.status.unlocksPremium, catalog: categories.catalog,
            announce: announce
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
            // カテゴリ別の予算の進み（プレミアムと体験中だけ）。
            purchases: purchases,
            now: now,
            announce: announce,
            didSave: { [weak self] entry in self?.finishEditing(entry) },
            didDelete: { [weak self] id in self?.forgetJustRecorded(id) }
        )
    }

    // MARK: - 設定

    /// 「設定」へ進む（帯の右上の歯車を押したとき）。
    ///
    /// 設定から開く「予算を決める」も、ホームの帯から開くときと同じ保存先と読み上げを使う。保存先を開いたもの
    /// （`storeHost`）も渡す。渡さないと、設定の「iCloud で同期」の節が黙って消える（テストで確かめている）。
    func presentSettings() {
        settings = SettingsModel(
            context: store.context, budgetStore: budgetStore, categories: categories, purchases: purchases, storeHost: storeHost,
            householdHost: household, defaults: defaults, now: now, announce: announce,
            // 足した・直したくり返しの記録の、記録する日を過ぎた分をすぐ記録する（ホームに戻ると返事のカードが出ている）。
            recurringDidChange: { [weak self] in
                guard let self else { return }
                recordDueRecurringEntries(calendar: recurringCalendar)
            }
        )
    }

    /// iCloud 同期を切り替えて保存先を開き直した直後なら、設定の画面を開いた状態にする（`AppRootView` がホームのモデルを
    /// 作ったときに呼ぶ）。
    ///
    /// 切り替えは設定の画面から始まるが、開き直すと画面のツリーを畳むのでホームに戻ってしまう。どうなったか（オンかオフか、
    /// 戻したならその理由）を切り替えた画面で見せるため。画面の側ではなくここに置くのは、テストで確かめられるようにするため。
    func restoreSettingsAfterStoreSwitch() {
        if storeHost?.consumeSettingsRestoration() == true {
            presentSettings()
        }
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
        // 声の入力の間とその案内を出している間も出さない（話している途中を遮らないため）。マイクの許可の確認（iOS の確認）を
        // 出している間も待機ではないので出さない（許可された後に、このシートの下でマイクを開かないように）。
        guard !isPresentingOtherScreen, voice.phase == .idle, !voice.showsPermissionAlert, voice.downloadConfirmation == nil
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
            didDelete: { [weak self] id in self?.forgetJustRecorded(id) }
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

    /// タイムラインにさらに前の記録を読み込む（上限の `timelineMaxLimit` を超えては読み込まない）。
    func showMoreTimeline() {
        timelineLimit = min(timelineLimit + Self.timelinePageSize, Self.timelineMaxLimit)
    }

    // MARK: - よく使うひとこと

    /// よく使うひとことの候補に読む期間（日）。いまの暮らしで使う品目と額を出すため、古い記録は読まない。
    static let quickPhraseWindowDays = 90

    /// よく使うひとことの候補を作り直す（ホームが出たとき・保存先に書き込んだとき・iCloud で取り込んだとき・前面に戻ったとき）。
    /// 読めなければ前の候補のまま（候補は入力の手助けで、無くても記録できるため）。
    func refreshQuickPhrases() {
        // 期間はおおよそでよいので、暦ではなく秒数で区切る。
        let start = now().addingTimeInterval(-Double(Self.quickPhraseWindowDays) * 86_400)
        guard let records = try? store.context.fetch(Entry.quickPhraseDescriptor(since: start)) else { return }
        quickPhrases = QuickPhrases.phrases(from: records)
    }

    /// よく使うひとことを選んだ。その文（「ランチ 850」）を入力欄に入れる（送るのは利用者。額を直してから送れるように）。
    func pickQuickPhrase(_ phrase: QuickPhrase) {
        draft = phrase.draft
        draftSource = .text
    }

    // MARK: - 型

    /// 削除の確認を待っている記録。確認の文は先に作っておく（消した後の記録の値は読めないため）。
    struct PendingDeletion {
        let entry: Entry
        let summary: String
    }

    /// 削除の確認を待っている家計の記録。
    struct PendingHouseholdDeletion {
        let entry: HouseholdEntry
        let summary: String
    }

    /// 記録先。
    enum LedgerScope: Hashable {
        /// 自分の記録（default.store）。
        case personal
        /// 家族と共有している家計（household.store）。
        case household
    }

    /// 「家族」のときに家計へ記録しなかった理由。
    enum HouseholdInputAlert: Equatable {
        /// 質問を送った（家計への質問は v1 では出さない）。
        case question
        /// 記録か質問か分からなかった。
        case unclear
    }

    /// 保存先への書き込みの失敗。利用者に知らせ、記録したつもり・消したつもりにさせない。
    enum StoreFailure: Equatable {
        case record
        case undo
        case delete
        /// 返事で選んだカテゴリを書き込めなかった。
        case categoryChoice
    }
}

/// 記録の直後の「直す」の対象の 1 件（自分の記録か家計の記録か）。
///
/// 入力欄の VoiceOver の操作（「直す: ランチ ¥850」）は、どちらの保存先の記録かを知らなくてよいので、見出しと ID だけを持つ。
/// どの記録を直すかは、ID から `HomeModel` が決める。
struct RecordedItem: Identifiable {
    let id: AnyHashable
    /// 「ランチ ¥850」
    let summaryText: String
}
