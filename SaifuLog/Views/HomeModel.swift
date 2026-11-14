import Foundation
import Observation
import SaifuLogCore
import SwiftData
import SwiftUI

/// ホームの状態と操作（送信・家計への質問・チャットで頼む操作・レシートの読み取り・取り消し・直す・削除・予算を決める
/// 画面と月のまとめと設定の出し入れ・会話とカレンダーのページの切り替え）。
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
    var draft = ""

    /// 記録の無いホームの入力の例を押した。例の文を入力欄に入れ、入力欄にフォーカスを移す（VoiceOver のフォーカスも。文が入った
    /// ことと、そのまま送れることが分かるように。前は文が入るだけで、VoiceOver では何が起きたか分からなかった）。
    func fillDraft(_ text: String) {
        draft = text
        inputFocusRequest += 1
    }
    /// 送った文を読み取っている間（送信ボタンを押せなくし、読み取り中の印を出す）。
    private(set) var isParsing = false {
        didSet {
            // 読み取りの間に待たせたくり返しの記録を、読み取りが終わったら記録する（`recordDueRecurringEntries`）。
            guard oldValue, !isParsing, holdsRecurringEntries else { return }
            holdsRecurringEntries = false
            recordDueRecurringEntries(calendar: recurringCalendar)
        }
    }
    /// 記録として送り、読み取っている文。読み取りが終わるまで、タイムラインのいちばん下に送った文の吹き出しと「読み取っています…」
    /// を出す（質問の「計算しています…」と同じ）。読み取りは AI だと 1 秒以上かかることがあり、その間に何も出ないと、送った文が
    /// 入力欄から消えただけに見え、送れたのか分からないため。記録したら記録した送信に替わり、読めなければ消えて文が入力欄に戻る。
    private(set) var pendingRecord: PendingRecord?
    /// 直前の送信で記録したもの。その送信の返事に「取り消す」を出すため（時間では引っ込めない。次の文を送る・取り消す・
    /// その記録を直す・記録先を切り替えるまで残し、消した記録は外す）。
    private(set) var justRecorded: [Entry] = [] {
        didSet {
            // 別の送信の記録に替わったら（記録した・引っ込めた）、引っ込めた「取り消す」を戻す。消えた記録を外しただけなら、そのまま。
            if justRecorded.isEmpty || justRecorded.contains(where: { entry in !oldValue.contains { $0 === entry } }) {
                undoWithdrawn = false
            }
            snapshotJustRecorded()
        }
    }
    /// 直前の送信の「取り消す」を引っ込めたか（チャットで金額を直したとき）。直前の記録そのものは、今月の状況の一行・聞き返し・
    /// チャットで直す相手として残す（`justRecorded` を空にすると、金額を直した直後に「それ日用品」で直せず、聞き返しのボタンも
    /// 消えるため）。取り消すと直す前の文が入力欄に戻り、直した内容と食い違うので、「取り消す」だけを引っ込める。
    private(set) var undoWithdrawn = false
    /// `justRecorded` の ID（同じ並び）。記録した時点で控えておく。ほかの端末（iCloud）で消された記録は、SwiftData が値を空にし、
    /// 値を読むとアプリが落ちうるので、画面を描くときや、消えたかを確かめるときは記録ではなくこちらを使う。
    private(set) var justRecordedIDs: [PersistentIdentifier] = []
    /// 入力欄の VoiceOver の「直す: …」の対象（`justRecorded` の要約。記録した時点で作っておく。理由は `justRecordedIDs` と同じ）。
    private var justRecordedItems: [RecordedItem] = []
    /// いま出しているホームのページ。開いたときは会話（記録が先）。左右のスワイプのほか、カレンダーの「会話」のボタンと、
    /// VoiceOver の帯の操作「カレンダー」で切り替える。
    var page: Page = .conversation
    /// カレンダーのページ（docs/design.md §9 の ⑩）の状態と操作。
    let calendarPage: LedgerCalendarModel
    /// カテゴリを聞き返している記録（`Entry.needsCategoryReview`）。直前の返事の行の下にカテゴリのボタンを出す。保存先から
    /// 読み直すので、開き直した後も聞き返しが残る。
    private(set) var categoryQuestionIDs: Set<PersistentIdentifier> = []
    var storeFailure: StoreFailure?
    var pendingDeletion: PendingDeletion?
    /// 端末内 AI が選んだチャットの操作で、行う前の確認を待っているもの（確認のアラートを出す）。
    var pendingCommand: PendingCommand?
    /// 「予算を決める」のシートの状態と操作。シートを出していなければ nil（シートを閉じると画面が nil に戻す）。
    var budgetSetup: BudgetSetupModel? {
        didSet {
            // 予算を変えたかもしれない。返事の一言は予算の残りを書いていることがあるので、変わっていれば外す。
            if budgetSetup == nil, oldValue != nil { discardReplyRemarkIfBudgetChanged() }
        }
    }
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
    /// 月のまとめの AI の一言。月のまとめを開き直しても同じものを使う（書いた一言を月の数字ごとに覚えておき、数字の
    /// 変わらない月で AI を呼び直さないため）。初めて開いたときに作る。
    @ObservationIgnored private var monthlyRemark: RecapRemarkModel?
    /// 「設定」（横に進む画面）の状態と操作。出していなければ nil（ホームへ戻ると画面が nil に戻す）。
    var settings: SettingsModel? {
        didSet {
            // 閉じた（作り直した）設定の、途中の書き出しとアカウントの確かめをやめる（`SettingsModel.close`）。
            if let oldValue, oldValue !== settings { oldValue.close() }
            // 設定の「予算」で予算を変えたかもしれない（上の `budgetSetup` と同じ）。
            if settings == nil, oldValue != nil { discardReplyRemarkIfBudgetChanged() }
        }
    }
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
    /// 覚えたカテゴリ（修正の記憶）。読み取った記録に当て、返事で選んだカテゴリを覚える。
    @ObservationIgnored private let learnedCategories: LearnedCategoryStore
    /// くり返しの記録。記録する日を過ぎた月の分を記録する。
    @ObservationIgnored private let recurring: RecurringEntryStore
    /// くり返しの記録を記録するときの暦（時間帯と読み上げの日付）。画面から最後に渡された暦（設定の画面から足したときにも使う）。
    @ObservationIgnored private var recurringCalendar: Calendar = .autoupdatingCurrent
    /// 読み取りの間・家計の画面を隠している間に、記録する日を過ぎたくり返しの記録を待たせたか。
    @ObservationIgnored private var holdsRecurringEntries = false
    /// 家計の画面を隠しているか（アプリのロックの画面を出している間。`HomeView` が `AppLock.hidesContent` を渡す）。隠している
    /// 間は、くり返しの記録を記録せず、記録の返事の一言も読み上げない（ロックの画面の下で金額が周りに聞こえないように）。
    @ObservationIgnored var hidesContent = false
    @ObservationIgnored private let pendingWrites: PendingStoreWrites
    /// 保存先を開いたもの。設定の「iCloud で同期」の切り替え先として設定に渡す。無ければ設定に iCloud の節を出さない（テスト用）。
    @ObservationIgnored private let storeHost: StoreHost?
    @ObservationIgnored private let makeParser: (Date, Calendar) -> any EntryParsing
    @ObservationIgnored private let makeCategoryRefiner: () -> CategoryRefiner?
    @ObservationIgnored private let makeCommandInterpreter: () -> ChatCommandInterpreter?
    @ObservationIgnored private let makeAnswerer: () -> any QuestionAnswering
    @ObservationIgnored private let makeRemarkWriter: () -> (any RecapRemarkWriting)?
    @ObservationIgnored private let makeRecordRemarkWriter: () -> (any RecapRemarkWriting)?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let announce: @MainActor (String) -> Void
    @ObservationIgnored private let announceAside: @MainActor (String) -> Void
    @ObservationIgnored private let receiptReader: ReceiptReader
    /// 書類カメラで撮った画像と、上限を超えて読み取らなかったページの数。カメラの画面が閉じきってから読み取りのシートを出すため、
    /// 閉じるまで持っておく。
    @ObservationIgnored private var capturedReceiptImages: (images: [ReceiptImage], skippedPageCount: Int)?
    /// ⑤ のシートを閉じた後に開く取り込み口（撮り直し）。
    @ObservationIgnored private var pendingReceiptRetake: ReceiptCaptureSource?

    /// - Parameters:
    ///   - budgetStore: 予算の読み書き。渡さなければ記録と同じ保存先（`store` の ModelContext）を使う。
    ///   - learnedCategories: 覚えたカテゴリの読み書き（修正の記憶）。渡さなければ記録と同じ保存先を使う。
    ///   - categories: カテゴリの一覧（作ったカテゴリ）。渡さなければ記録と同じ保存先から読む。
    ///   - recurring: くり返しの記録の読み書き。渡さなければ記録と同じ保存先を使う。
    ///   - pendingWrites: 解析を待ってから記録する処理を数える先（`StoreHost.pendingWrites`）。保存先を開き直すとき、
    ///     記録し終えるのを待ってもらうため。
    ///   - storeHost: 保存先を開いたもの（設定の「iCloud で同期」の切り替え先）。アプリは `SaifuLogApp` の 1 つを渡す。
    ///   - makeParser: 送信のたびに解析器を選ぶ（AI の使える・使えないは途中から変わるため）。送った瞬間の日時と暦を渡し、
    ///     「昨日」「9/26」をその日時を基準に読ませる。テストで差し替える。
    ///   - makeCategoryRefiner: 記録のたびに、辞書で決まらなかった品目のカテゴリを AI に聞き直すものを選ぶ（AI が使えなければ nil）。
    ///     テストで差し替える（決まった答えを返す代わりか nil）。
    ///   - makeCommandInterpreter: 決まりで読めなかったチャットの文の操作の種類を AI に選ばせるもの（AI が使えなければ nil）。
    ///     テストで差し替える。
    ///   - makeAnswerer: 質問のたびに答え方（AI かキーワード辞書）を選ぶ。テストで差し替える。
    ///   - makeRemarkWriter: 月のまとめの AI の一言を書くもの。AI が使えなければ nil。テストで差し替える。
    ///   - makeRecordRemarkWriter: 記録の返事に添える AI の一言を書くもの。AI が使えなければ nil。テストで差し替える。
    ///   - receiptReader: レシートの画像の読み取り（文字認識と AI）。テストで決めた文字や偽物の AI に差し替える。
    ///   - canUseDocumentCamera: 書類カメラを使えるか。テストで決める。
    ///   - now: 記録の日時と「今日」の基準。テストで固定の日時にする。
    ///   - announce: VoiceOver に読み上げさせる。テストで読み上げる文を集める。
    ///   - announceAside: VoiceOver に、いまの読み上げを遮らずに読み上げさせる（記録の返事の一言）。テストで読み上げる文を集める。
    init(
        store: EntryStore,
        budgetStore: BudgetStore? = nil,
        learnedCategories: LearnedCategoryStore? = nil,
        categories: CategoryCatalogModel? = nil,
        recurring: RecurringEntryStore? = nil,
        pendingWrites: PendingStoreWrites = PendingStoreWrites(),
        storeHost: StoreHost? = nil,
        makeParser: @escaping (Date, Calendar) -> any EntryParsing = { EntryParserFactory.makeParser(now: $0, calendar: $1) },
        makeCategoryRefiner: @escaping () -> CategoryRefiner? = { CategoryRefiner.forDevice() },
        makeCommandInterpreter: @escaping () -> ChatCommandInterpreter? = { ChatCommandInterpreter.forDevice() },
        makeAnswerer: @escaping () -> any QuestionAnswering = { QuestionAnswererFactory.makeAnswerer() },
        makeRemarkWriter: @escaping () -> (any RecapRemarkWriting)? = { RecapRemarkWriterFactory.makeWriter() },
        makeRecordRemarkWriter: @escaping () -> (any RecapRemarkWriting)? = { RecordRemarkWriterFactory.makeWriter() },
        receiptReader: ReceiptReader = ReceiptReader(),
        canUseDocumentCamera: Bool = DocumentCameraView.isSupported,
        now: @escaping () -> Date = { .now },
        announce: @escaping @MainActor (String) -> Void = { VoiceOver.announce($0) },
        announceAside: @escaping @MainActor (String) -> Void = { VoiceOver.announceAside($0) }
    ) {
        let budgetStore = budgetStore ?? BudgetStore(context: store.context)
        let recurring = recurring ?? RecurringEntryStore(context: store.context, now: now)
        self.store = store
        self.budgetStore = budgetStore
        self.learnedCategories = learnedCategories ?? LearnedCategoryStore(context: store.context, now: now)
        self.categories = categories ?? CategoryCatalogModel(store: CustomCategoryStore(context: store.context, now: now))
        self.recurring = recurring
        self.calendarPage = LedgerCalendarModel(store: store, now: now, announce: announce)
        self.pendingWrites = pendingWrites
        self.storeHost = storeHost
        self.makeParser = makeParser
        self.makeCategoryRefiner = makeCategoryRefiner
        self.makeCommandInterpreter = makeCommandInterpreter
        self.makeAnswerer = makeAnswerer
        self.makeRemarkWriter = makeRemarkWriter
        self.makeRecordRemarkWriter = makeRecordRemarkWriter
        self.receiptReader = receiptReader
        self.canUseDocumentCamera = canUseDocumentCamera
        self.now = now
        self.announce = announce
        self.announceAside = announceAside
        self.today = now()
        refreshCategoryQuestions()
    }

    convenience init(
        context: ModelContext, pendingWrites: PendingStoreWrites = PendingStoreWrites(), storeHost: StoreHost? = nil
    ) {
        self.init(store: EntryStore(context: context), pendingWrites: pendingWrites, storeHost: storeHost)
    }

    /// ホームの上にほかの画面・シート・確認・知らせを出しているか（出している間は、Siri・ショートカットの頼みと、AI が選んだ
    /// 操作の確認を待たせる。削除の確認と保存の失敗の知らせも数える。数えないと、確認の下で記録して返事を出してしまうため）。
    var isPresentingOtherScreen: Bool {
        budgetSetup != nil || editing != nil || categoryEditor != nil || recurringEditor != nil || monthlyReport != nil
            || settings != nil || pendingCommand != nil || pendingDeletion != nil || storeFailure != nil
            || receiptResult != nil || receiptCapture != nil || showsReceiptSourceChoice
    }

    /// 直前の記録を取り消せるか（返事の「取り消す」と入力欄の VoiceOver の操作を出すか）。
    var canUndo: Bool {
        !justRecorded.isEmpty && !undoWithdrawn
    }

    /// 入力欄の VoiceOver の「直す: …」の対象（直前に記録したもの）。
    var recordedItems: [RecordedItem] {
        justRecordedItems
    }

    /// `justRecorded` の ID と要約を控える（記録を入れ替えたとき・カテゴリを選んだとき）。消えた記録を外した後に呼ぶので、
    /// ここで読む記録はどれもまだ保存先にある。
    private func snapshotJustRecorded() {
        justRecordedIDs = justRecorded.map(\.persistentModelID)
        justRecordedItems = justRecorded.map {
            RecordedItem(id: AnyHashable($0.persistentModelID), summaryText: $0.summaryText(in: categories.catalog))
        }
        // 一言は直前の送信の返事にだけ添える。次の送信・取り消し・直すで直前の記録が替わったら外す。
        if let replyRemark, !replyRemark.entryIDs.isSubset(of: Set(justRecordedIDs)) {
            self.replyRemark = nil
        }
    }

    // MARK: - 記録の返事の一言

    /// 直前の送信の返事に添える、端末内 AI の一言（Apple Intelligence。数字はコアの `RecordFacts` が計算した文だけを渡し、
    /// `RecapRemark.checked` の照合に通ったものだけ）。保存しない（開き直すと消える）。
    struct ReplyRemark: Equatable {
        /// 一言を書いた送信の記録。
        let entryIDs: Set<PersistentIdentifier>
        let text: String
        /// 一言を書いたときの月の予算（決めていなければ nil）。予算を変えたら、一言の予算の残りが食い違うので外す。
        var budget: Int?
        /// 一言を書かせた数字の文（`RecordFacts`）と、その基準の日時。ほかの端末の変更が届いたときに作り直して比べる。
        var facts: String = ""
        var sentAt: Date = .distantPast
    }

    /// 記録の返事の一言を書かせる数字の文（`RecordFacts`）と、そのときの月の予算。
    ///
    /// 今月（`sentAt` の月）に使った支出だけを書く。「昨日 ランチ 850」を月の 1 日に送ると、いま記録した支出が今月の数字に
    /// 入らず、記録した額と食い違う一言（「今月はまだ使っていません」）が照合に通ってしまうため。今月の支出が無ければ nil
    /// （一言を書かせない）。
    private func recordFacts(for recorded: [Entry], sentAt: Date, calendar: Calendar) -> (text: String, budget: Int?)? {
        guard let month = ReportPeriod.thisMonth.interval(now: sentAt, calendar: calendar) else { return nil }
        let expenses = recorded.filter { !$0.isIncome && $0.spentAt >= month.start && $0.spentAt < month.end }
        guard !expenses.isEmpty else { return nil }
        let items = expenses.map {
            RecordFacts.Item(
                item: CategoryMemory.item(ofMemo: $0.memo, amount: $0.amount, isIncome: false), amount: $0.amount, category: $0.category
            )
        }
        let monthRecords = (try? store.context.fetch(Entry.monthDescriptor(containing: sentAt, calendar: calendar))) ?? []
        let budget = currentBudget()
        guard let text = RecordFacts.text(
            recorded: items, monthRecords: monthRecords, budget: budget, now: sentAt, calendar: calendar, catalog: categories.catalog
        ) else { return nil }
        return (text, budget)
    }

    /// いま出している一言。無ければ nil（AI が使えない端末・照合に通らない・まだ書いている間）。
    private(set) var replyRemark: ReplyRemark?
    /// 一言を書かせている処理（テストで待つ）。
    @ObservationIgnored private(set) var replyRemarkTask: Task<Void, Never>?

    /// 記録した直後に、返事の一言を端末内 AI に書かせる。返事は先に出し、一言は後から足す（待つ間も次の文を打てる。書き込みは
    /// しないので `pendingWrites` には数えない）。上限（`AITimeouts.recordRemark`）までに返らない・失敗した・照合に通らない・その間に
    /// 直前の記録が替わったときは出さない（返事の今月の状況の一行は、いつも定型の文で出ている）。
    private func requestReplyRemark(for recorded: [Entry], sentAt: Date, calendar: Calendar) {
        replyRemarkTask?.cancel()
        replyRemark = nil
        guard let made = recordFacts(for: recorded, sentAt: sentAt, calendar: calendar),
              let writer = makeRecordRemarkWriter() else { return }
        let facts = made.text
        let budget = made.budget
        let ids = Set(recorded.map(\.persistentModelID))
        let timeout = AITimeouts.recordRemark
        let report = AIFallbackLog.shared.reporter(for: .recordRemark)
        replyRemarkTask = Task {
            let sentence: String
            do {
                sentence = try await withDeadline(timeout) { try await writer.remark(from: facts) }
            } catch is CancellationError {
                return
            } catch is DeadlineExceeded {
                report(.timedOut(timeout))
                return
            } catch {
                report(.failed(error))
                return
            }
            guard !Task.isCancelled, ids.isSubset(of: Set(justRecordedIDs)) else { return }
            // 書かせている間に数字が変わっていれば（予算の画面で予算を変えた・ほかの端末の記録が届いた）、出さない（一言は書かせた
            // ときの数字で書いているので、いまの帯や返事の数字と食い違うため）。
            guard recordFacts(for: recorded, sentAt: sentAt, calendar: calendar)?.text == facts else { return }
            guard let checked = RecapRemark.checked(sentence, facts: facts) else {
                report(.noResult)
                return
            }
            replyRemark = ReplyRemark(entryIDs: ids, text: checked, budget: budget, facts: facts, sentAt: sentAt)
            // 一言は記録の読み上げ（「記録しました: …」）の後に届く。その読み上げや次の入力を遮らないよう、控えめに読み上げる。
            // 家計の画面を隠している間（ロックの画面の下）は読み上げない。
            if !hidesContent { announceAside(checked) }
        }
    }

    /// 返事の一言を外す（書いている途中なら、書かせるのもやめる）。一言は書いたときの今月の数字で書いているので、送信・記録を
    /// 消す・直す・予算を決める・ほかの端末の変更が届くと食い違いうる。
    func discardReplyRemark() {
        replyRemarkTask?.cancel()
        replyRemark = nil
    }

    /// ほかの端末の変更が届いたときに、出している一言の数字が変わっていれば外す（`StoreChanges.remote`）。
    ///
    /// iCloud と同期する保存先では、この端末自身の保存の後にも同期の知らせが届く。知らせのたびに外すと、同期をオンにした端末では
    /// 一言がほとんど出なくなるので、数字の文（`RecordFacts`）を作り直して、変わったときだけ外す。書いている途中の一言は、
    /// 届いたときに同じように確かめる（`requestReplyRemark`）。
    func reviewReplyRemarkAfterRemoteChange(calendar: Calendar) {
        guard let replyRemark else { return }
        let recorded = zip(justRecorded, justRecordedIDs).filter { replyRemark.entryIDs.contains($0.1) }.map(\.0)
        guard recorded.count == replyRemark.entryIDs.count,
              recordFacts(for: recorded, sentAt: replyRemark.sentAt, calendar: calendar)?.text == replyRemark.facts
        else {
            discardReplyRemark()
            return
        }
    }

    /// 予算が一言を書いたときと変わっていれば、一言を外す（予算の画面と設定から戻ったとき）。
    private func discardReplyRemarkIfBudgetChanged() {
        guard let replyRemark, replyRemark.budget != currentBudget() else { return }
        discardReplyRemark()
    }

    /// いまの月の全体の予算（決めていない・読めなければ nil）。
    private func currentBudget() -> Int? {
        (try? budgetStore.plan())?.total
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
        let source = EntrySource.text
        // 送った時点で入力欄を空ける。解析（AI だと 1 秒以上かかることがある）を待ってから空けると、
        // 入力欄にとどまって打ち始めた次の入力まで、黙って消してしまうため。
        draft = ""
        return submit(text, source: source, calendar: calendar)
    }

    /// 文を送る（入力欄の文か、Siri・ショートカットから頼まれた文）。入力欄には触れない（送れなかったときに文を戻すのは、
    /// 入力欄が空のときだけ。`restoreDraft`）。
    ///
    /// - Parameters:
    ///   - forcesQuestion: 記録か見分けずに質問として答える（Siri・ショートカットの「家計に質問」）。
    ///   - confirmsCommands: 決まりで読んだチャットの操作も、行う前に確かめる（Siri・ショートカットの「ひとことで記録」）。声で
    ///     頼んだ文は聞き取りの誤りがあり、記録のつもりの頼みで直前の記録を黙って消したり書き換えたりしないため。
    @discardableResult
    private func submit(
        _ text: String, source: EntrySource, forcesQuestion: Bool = false, confirmsCommands: Bool = false, calendar: Calendar
    ) -> Task<Void, Never> {
        // 送った瞬間の日時を 1 つ決め、解析（「昨日」「9/26」の基準）と保存（記録した日時・使った日時）の両方に使う。
        // 保存のときに時計を読み直すと、読み取りを待つ間に日付が変わったとき（23:59:59 に送って 0:00:01 に保存）、
        // 「9/26」と書いた記録が 1 日ずれて保存されるため。質問も、この日時で期間を区切る。
        let sentAt = now()
        // 一言は直前の送信の返事に添えたもの。次の文を送ったら、記録にならない文でも外す（会話の流れの中で、前の返事の数字の
        // 一言が後から読まれて食い違わないように）。
        discardReplyRemark()
        // チャットの操作の相手（直前の送信）を、送った時点で控える。AI を待つ間に直前の送信が替わっても（取り消した・
        // くり返しの記録を記録した）、送った文が指していた記録だけを相手にするため。
        let targets = commandTargets()
        // チャットで頼む操作（「それ日用品」「さっきのを900に直して」「さっきの消して」「今月の予算を5万にして」）なら、記録にも
        // 質問にもせずに行う。直す相手が無ければ、そう案内する（ふつうの送信として読むと、「さっきの消して」が「金額が見つかり
        // ませんでした」になり、何がいけないのか分からないため）。
        if !forcesQuestion,
           let command = ChatCommandReader.command(in: text, now: sentAt, calendar: calendar, catalog: categories.catalog) {
            perform(command, text: text, sentAt: sentAt, targets: targets, confirms: confirmsCommands)
            return Task {}
        }
        let intent = forcesQuestion
            ? .question
            : InputIntentClassifier.classify(text, now: sentAt, calendar: calendar, catalog: categories.catalog)
        switch intent {
        case .record:
            // 金額の無い文だったときに直前の送信へ戻し、チャットの操作だったときの相手にするため、引っ込める前の送信を控える。
            let previous = latestSend()
            retractLastReply()
            return record(text, source: source, sentAt: sentAt, calendar: calendar, previous: previous, targets: targets)
        case .question:
            retractLastReply()
            return ask(text, source: source, sentAt: sentAt, calendar: calendar)
        case .unclear, .correction:
            // 決まりで読めなかった文。AI が使える端末では、どの操作を頼んでいるかを AI に選ばせ、値を文から読めれば行う。
            if let interpreter = makeCommandInterpreter() {
                return interpretCommand(
                    text, intent: intent, source: source, sentAt: sentAt, calendar: calendar, interpreter: interpreter, targets: targets
                )
            }
            showUndecided(intent, text: text, source: source, sentAt: sentAt)
            return Task {}
        }
    }

    /// 記録にも質問にも操作にもできなかった文の案内を出し、送った文を入力欄に戻す（数えない）。
    ///
    /// - 記録か質問か決められない文（`unclear`）: 書き直して送り直せるようにする。
    /// - 前の記録を直そうとする文（`correction`。直した先の金額が読めなかった）: 新しい記録にはしない（記録すると、直したつもりの
    ///   支出が二重に記録されるため）。直し方を案内する。
    ///
    /// どちらも前の記録の「取り消す」と聞き返しは引っ込めない（記録も答えもしていないので、前の返事はまだ直前の返事のまま。
    /// 案内が「取り消す」で取り消して送り直す方法を勧めるため）。
    private func showUndecided(_ intent: InputIntent, text: String, source: EntrySource, sentAt: Date) {
        let correction = intent == .correction
        appendQuestion(text, askedAt: sentAt, state: correction ? .correction : .unclear)
        restoreDraft(text)
        announce(correction ? String(localized: "記録は直していません") : String(localized: "記録か質問か分かりませんでした"))
    }

    /// 決まりで読めなかった文の操作の種類を端末内 AI に選ばせ（`ChatCommandInterpreter`）、値を文から読めれば確認を出す。読めなければ
    /// これまでどおり案内を出す。AI を待つ間は、記録の読み取りと同じく送った文と「読み取っています…」を出し、次の文を送れなくする。
    ///
    /// AI の選んだ操作は、確認を出してから行う（決まりで読んだ操作はすぐ行う）。AI の読み違いで、記録や予算を黙って書き換えないため。
    private func interpretCommand(
        _ text: String, intent: InputIntent, source: EntrySource, sentAt: Date, calendar: Calendar, interpreter: ChatCommandInterpreter,
        targets: CommandTargets
    ) -> Task<Void, Never> {
        isParsing = true
        pendingRecord = PendingRecord(text: text, source: source, sentAt: sentAt)
        pendingWrites.begin()
        return Task {
            defer {
                isParsing = false
                pendingRecord = nil
                pendingWrites.end()
            }
            switch await interpretedCommand(text, sentAt: sentAt, calendar: calendar, interpreter: interpreter) {
            case .cancelled:
                // 取り消された（読み取りの取り消しと同じ）。何もせず、送った文だけを入力欄に戻す。
                restoreDraft(text)
                return
            case .command(let command):
                perform(command, text: text, sentAt: sentAt, targets: targets, confirms: true)
                return
            case .nothing:
                break
            }
            showUndecided(intent, text: text, source: source, sentAt: sentAt)
        }
    }

    /// 端末内 AI に選ばせた操作（`interpretedCommand`）。
    private enum InterpretedCommand {
        /// 種類を選べ、値を文から読めた。
        case command(ChatCommand)
        /// AI が使えない・どれでもない・値を文から読めない。
        case nothing
        /// 呼び出した Task が取り消された。
        case cancelled
    }

    /// 文の操作の種類を端末内 AI に選ばせ、値を文から読む（`ChatCommandReader.command(kind:in:now:calendar:catalog:)`）。
    ///
    /// - Parameter interpreter: 使う AI。渡さなければ、いまの端末で使えるもの（無ければ `.nothing`）。
    private func interpretedCommand(
        _ text: String, sentAt: Date, calendar: Calendar, interpreter: ChatCommandInterpreter? = nil
    ) async -> InterpretedCommand {
        guard let interpreter = interpreter ?? makeCommandInterpreter() else { return .nothing }
        let kind: ChatCommandKind
        do {
            kind = try await interpreter.kind(of: text)
        } catch {
            return .cancelled
        }
        guard let command = ChatCommandReader.command(kind: kind, in: text, now: sentAt, calendar: calendar, catalog: categories.catalog)
        else { return .nothing }
        return .command(command)
    }

    /// 前の送信の「取り消す」を引っ込める。カテゴリの聞き返しは記録（`Entry.needsCategoryReview`）に残し、開き直しても出す。
    ///
    /// 読み取りの間も出したままだと、押したときに前の記録が消え、前の文が入力欄に戻る。それを送り直したり、いま送った文の
    /// 記録だけが残ったりして、取り消したつもりのものと違う記録が残るため。質問を送ったときも同じにする（答えるたびに引っ込める、
    /// と揃える）。記録も答えもしない文（記録か質問か決められない文・前の記録を直そうとする文）では引っ込めない。
    private func retractLastReply() {
        justRecorded = []
    }

    /// 直前の送信の控え（引っ込める前のもの）。記録として送った文に金額が無かったとき、直前の送信に戻すため。
    private struct LatestSend {
        let entries: [Entry]
        let ids: [PersistentIdentifier]
        let undoWithdrawn: Bool
    }

    private func latestSend() -> LatestSend {
        LatestSend(entries: justRecorded, ids: justRecordedIDs, undoWithdrawn: undoWithdrawn)
    }

    /// 記録として送った文で何も記録しなかったとき、引っ込めた直前の送信を戻す（「取り消す」と聞き返しを、送る前のとおりに出す）。
    /// ほかの端末で消された記録は外す。その間にほかの送信が直前の送信になっていれば（くり返しの記録など）、そちらのままにする。
    private func restoreLatestSend(_ previous: LatestSend) {
        guard justRecorded.isEmpty else { return }
        justRecorded = zip(previous.entries, previous.ids).filter { store.exists($0.1) }.map(\.0)
        undoWithdrawn = previous.undoWithdrawn && !justRecorded.isEmpty
    }

    /// 送った文を記録として読み取る。取り消されたら nil を返す。
    ///
    /// 取り消しは読めなかったのではないので、呼び出し側は「金額が見つかりませんでした」を出さない。AI の失敗と時間切れは解析器
    /// （`FallbackEntryParser`）がルールベースで読み直すので、ここで投げられるのはルールベースも投げたときだけで、読めなかった
    /// （0 件）として扱う。取り消された後に投げられたものは、取り消しによるものとみなす（解析器が取り消しを別のエラーで伝えても、
    /// 読めなかったことにしないため）。
    private func parse(_ text: String, with parser: any EntryParsing) async -> [ParsedEntry]? {
        do {
            return try await parser.parse(text)
        } catch {
            if error is CancellationError || Task.isCancelled { return nil }
            return []
        }
    }

    /// 記録として読み取って保存する。
    ///
    /// - Parameters:
    ///   - source: 送った文をどこから入れたか（記録の入力元にする）。
    ///   - previous: 送る前の直前の送信（「取り消す」を引っ込める前のもの）。何も記録しなかったときに戻す。
    ///   - targets: 送った時点のチャットの操作の相手。金額の無い文を端末内 AI がチャットの操作と読んだとき、直す相手にする。
    private func record(
        _ text: String, source: EntrySource, sentAt: Date, calendar: Calendar, previous: LatestSend, targets: CommandTargets
    ) -> Task<Void, Never> {
        isParsing = true
        pendingRecord = PendingRecord(text: text, source: source, sentAt: sentAt)
        let parser = makeParser(sentAt, calendar)
        // 解析の間に保存先が開き直されないよう、Task を作る前に数える（Task は画面のツリーを畳んだ後も動き続け、
        // この後で前の保存先に書き込むため）。
        pendingWrites.begin()
        return Task {
            defer {
                isParsing = false
                // 記録したときは、保存と同じ描き直しで記録した送信に替わる（吹き出しが同じ位置に残り、下のカードだけが替わる）。
                pendingRecord = nil
                pendingWrites.end()
            }
            guard let parsed = await parse(text, with: parser) else {
                // 取り消された。読めなかったのではないので知らせず、送った文だけを入力欄に戻す（送り直せるように）。
                restoreLatestSend(previous)
                restoreDraft(text)
                return
            }
            guard !parsed.isEmpty else {
                // 何も記録していないので、直前の送信は送る前のまま（「取り消す」と聞き返しを戻す）。
                restoreLatestSend(previous)
                // 金額の無い文は、チャットで頼む操作かもしれない（「あれはやっぱりなかったことにしたい」）。AI が使える端末では、
                // 決まりで読めなかった文と同じく AI に種類を選ばせ、値を文から読めれば確認を出す。
                switch await interpretedCommand(text, sentAt: sentAt, calendar: calendar) {
                case .cancelled:
                    restoreDraft(text)
                    return
                case .command(let command):
                    perform(command, text: text, sentAt: sentAt, targets: targets, confirms: true)
                    return
                case .nothing:
                    break
                }
                // 送った文と案内をタイムラインに出し、文を入力欄に戻して、その場で金額を足して送り直せるようにする（キーボードは
                // 出したまま）。
                appendQuestion(text, askedAt: sentAt, state: .noAmount)
                restoreDraft(text)
                announce(String(localized: "金額が見つかりませんでした"))
                return
            }
            // 作ったカテゴリの名前・覚えたカテゴリ・過去の記録のいつものカテゴリ・店の名前の辞書を、AI と辞書のどちらで読んだ
            // 記録にも当てる（`CategoryResolver`）。覚えや過去の記録を読めなくても、記録は止めない。
            let catalog = categories.catalog
            let memory = (try? learnedCategories.memory()) ?? CategoryMemory()
            let resolutions = CategoryResolver.resolve(parsed, memory: memory, history: categoryHistory(), catalog: catalog)
            var entries = resolutions.map(\.entry)
            // それでも「その他」のまま、返事で聞き返すことになる品目は、先に AI に聞き直す（AI が使える端末だけ。辞書に無い品目でも、
            // AI がカテゴリを選べれば聞き返さずに済む。選べなければ、これまでどおり返事で聞き返す）。作ったカテゴリがあれば、
            // 作ったカテゴリに当たるかも聞く（`CategoryRefinement`）。
            if let refiner = makeCategoryRefiner() {
                do {
                    entries = try await refiner.refine(resolutions, catalog: catalog)
                } catch {
                    // 取り消された（読み取りの取り消しと同じ）。記録せず、送った文だけを入力欄に戻す。
                    restoreLatestSend(previous)
                    restoreDraft(text)
                    return
                }
            }
            let recorded = Entry.records(
                from: entries, originalText: text, source: source, now: sentAt, calendar: calendar
            )
            for (entry, resolution) in zip(recorded, resolutions) {
                // AI に聞き直して決まった記録は聞き返さない。
                entry.needsCategoryReview = resolution.asksCategory && entry.category == .other
            }
            do {
                try store.insert(recorded)
            } catch {
                // 保存できなかった。記録したことにはせず、送った文を戻して送り直せるようにする。
                restoreLatestSend(previous)
                restoreDraft(text)
                storeFailure = .record
                return
            }
            justRecorded = recorded
            refreshCategoryQuestions()
            // 返事のカテゴリのボタンは画面に出るだけでは VoiceOver の利用者に伝わらないので、聞き返すときは選べることも読み上げる。
            announceRecorded(
                recorded, today: sentAt, calendar: calendar, asksCategory: recorded.contains(where: \.needsCategoryReview)
            )
            requestReplyRemark(for: recorded, sentAt: sentAt, calendar: calendar)
        }
    }

    /// 過去の記録のいつものカテゴリ（`CategoryHistory`）。読めなければ空（記録は止めない）。
    private func categoryHistory() -> CategoryHistory {
        guard let entries = try? store.context.fetch(Entry.categoryHistoryDescriptor()) else { return CategoryHistory() }
        return CategoryHistory(records: entries.map { entry in
            CategoryHistory.Record(
                item: CategoryMemory.item(ofMemo: entry.memo, amount: entry.amount, isIncome: entry.isIncome),
                category: entry.category
            )
        })
    }

    // MARK: - 質問

    /// 家計への質問に答える。数字はコアが計算し（AI には計算させない）、答えは保存しない。
    /// 保存先には書き込まない（読むだけ）ので、`pendingWrites` には数えない。
    private func ask(_ text: String, source: EntrySource, sentAt: Date, calendar: Calendar) -> Task<Void, Never> {
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
            let answerer = makeAnswerer()
            let reply = (try? await answerer.answer(text, ledger: ledger, now: sentAt, calendar: calendar)) ?? .unreadable
            switch reply {
            case .answered(let answer, let remark):
                setQuestionState(.answered(answer, remark: remark), for: id)
                // 画面にカードが出るだけでは VoiceOver の利用者に伝わらないので、答えを読み上げる。
                announce(QuestionTexts.spoken(answer, remark: remark, calendar: calendar, catalog: categories.catalog))
            case .unreadable:
                setQuestionState(.unreadable, for: id)
                // 書き直して送り直せるよう、送った文を入力欄に戻す（記録の「金額が見つかりませんでした」と同じ）。
                restoreDraft(text)
                announce(String(localized: "質問を読めませんでした"))
            }
        }
    }

    /// 回答カードの「続けて聞く質問」を送る（ふつうの質問と同じ流れ。入力欄の文には触れない）。読み取りの間は受け付けない
    /// （nil を返す）。送った文は、打った質問と同じく自分の吹き出しに出る。
    @discardableResult
    func askFollowUp(_ followUp: QuestionFollowUp, calendar: Calendar) -> Task<Void, Never>? {
        guard !isParsing else { return nil }
        // 送信と同じく、前の記録の「取り消す」と聞き返しを引っ込める。
        retractLastReply()
        return ask(followUp.text, source: .text, sentAt: now(), calendar: calendar)
    }

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
        guard draft.isEmpty else { return }
        draft = text
    }

    /// 何円をどのカテゴリに記録したかを VoiceOver に読み上げさせる。
    ///
    /// タイムラインに返事のカード（「記録しました」）が出ても、VoiceOver では読まれない（フォーカスは入力欄に戻る）。読み上げないと、
    /// VoiceOver の利用者は記録できたかも、AI がどう読んだかも分からず、読み違いにその場で気づけない。
    /// 今日でない日付に記録したときは日付も読む（「昨日」の読み違いや、未来の日付に気づけるように）。
    /// 今日かどうかは、記録の日付を決めたのと同じ送った瞬間（`today`）で見る。
    private func announceRecorded(
        _ recorded: [Entry], today: Date, calendar: Calendar, asksCategory: Bool = false
    ) {
        let items = recorded.map { entry in
            var item = "\(entry.kindText(in: categories.catalog)) \(YenFormatter.string(from: entry.amount))"
            if !calendar.isDate(entry.spentAt, inSameDayAs: today) {
                let format: Date.FormatStyle = calendar.isDate(entry.spentAt, equalTo: today, toGranularity: .year)
                    ? .dateTime.month().day() : .dateTime.year().month().day()
                item += " \(entry.spentAt.formatted(format))"
            }
            return item
        }
        let list = items.formatted(.list(type: .and))
        if asksCategory {
            announce(String(localized: "記録しました: \(list)。カテゴリを選べます"))
        } else {
            announce(String(localized: "記録しました: \(list)"))
        }
    }

    // MARK: - レシート

    /// カメラのボタン（入力欄の左）。「撮る」「写真から選ぶ」を選ばせる。
    func requestReceiptScan() {
        showsReceiptSourceChoice = true
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
    /// 保存先には書き込まない（記録は利用者が「記録する」を押したときにその場で書き込む）ので、`pendingWrites` には数えない。
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

    /// ⑤ から記録する。記録したら ⑤ を閉じ、タイムラインにレシートの送信と返事（「取り消す」つき）を出す。
    func recordReceipt(_ submission: ReceiptResultModel.Submission, calendar: Calendar) -> ReceiptResultModel.RecordOutcome {
        let recordedAt = now()
        let recorded = Entry.records(fromReceipt: submission, now: recordedAt, calendar: calendar)
        guard !recorded.isEmpty else { return .failed }
        do {
            try store.insert(recorded)
        } catch {
            return .failed
        }
        justRecorded = recorded
        refreshCategoryQuestions()
        receiptResult = nil
        announceRecorded(recorded, today: recordedAt, calendar: calendar)
        return .recorded
    }

    /// 撮り直す。⑤ を閉じ、閉じきったら同じ取り込み口をもう一度開く（`receiptResultDidDismiss`）。
    func retakeReceipt(_ source: ReceiptCaptureSource) {
        pendingReceiptRetake = source
        receiptResult = nil
    }

    /// ⑤ のシートが閉じきった。撮り直しなら取り込み口を開く。
    func receiptResultDidDismiss() {
        if let source = pendingReceiptRetake {
            pendingReceiptRetake = nil
            startReceiptCapture(source)
        }
    }

    // MARK: - 取り消し

    /// 直前の記録を取り消す。元の文を入力欄に戻し、その場で直して送り直せるようにする。
    ///
    /// レシートから記録したものは、入力欄に何も戻さない（元の文は「レシート: 店名 合計 ¥…」の要約で、送り直すと合計の 1 件を
    /// ひとこと入力として記録してしまうため）。
    /// くり返しの記録も入力欄に何も戻さない。取り消した月の分はもう記録しない（記録した月は覚えたまま。`RecurringEntryStore`）。
    func undoLastRecord() {
        // チャットで金額を直した後は「取り消す」を引っ込めている（直した内容と、入力欄に戻す直す前の文が食い違うため）。
        guard canUndo else { return }
        undoPersonalRecords(restoringDraft: true)
    }

    /// 直前に記録したもの（自分の記録）を消す。消せたら、消した記録の要約（「ランチ ¥850」）を返す。
    ///
    /// - Parameter restoringDraft: 元の文を入力欄に戻すか。
    @discardableResult
    private func undoPersonalRecords(restoringDraft: Bool) -> [String]? {
        // ほかの端末で消されたものは先に外す（消えた記録の値を読まないように）。
        forgetRecordsDeletedElsewhere()
        let targets = justRecorded
        guard !targets.isEmpty else { return nil }
        // 消した記録の値は、保存した後には読めない。読み上げと入力欄に戻す文は先に取っておく。
        let items = targets.map { "\($0.kindText(in: categories.catalog)) \(YenFormatter.string(from: $0.amount))" }
        let originalText = targets.first?.originalText ?? ""
        // レシート・くり返しの記録・Apple Pay の支払い（前の版で記録したもの）は打った文ではないので、入力欄に戻さない。
        let restoresDraft = restoringDraft && !targets.contains { [.receipt, .recurring, .wallet].contains($0.source) }
        do {
            try store.delete(targets)
        } catch {
            // 「取り消す」は残し、もう一度押せるようにする。
            storeFailure = .undo
            return nil
        }
        justRecorded = []
        refreshCategoryQuestions()
        if restoresDraft { restoreDraft(originalText) }
        announce(String(localized: "取り消しました: \(items.formatted(.list(type: .and)))"))
        return items
    }

    // MARK: - 削除

    /// 削除の確認を出す。確認の文は先に作っておく（消した後の記録の値は読めないため）。
    func requestDelete(_ entry: Entry) {
        pendingDeletion = PendingDeletion(
            entry: entry, id: entry.persistentModelID, summary: entry.summaryText(in: categories.catalog)
        )
    }

    /// 確認のあとで記録を削除する。確認の間にほかの端末で消されていたら、消えたものとして扱う（記録の値には触れない）。
    func delete(_ pending: PendingDeletion) {
        pendingDeletion = nil
        let id = pending.id
        guard store.exists(id) else {
            forgetJustRecorded(id)
            announce(String(localized: "削除しました: \(pending.summary)"))
            return
        }
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

    /// 入力欄の VoiceOver の「直す: …」から、直前に記録したものを直す。
    func presentEdit(_ item: RecordedItem, calendar: Calendar) {
        guard let index = justRecordedIDs.firstIndex(where: { AnyHashable($0) == item.id }) else { return }
        // ほかの端末で消されていたら開かない（シートは開いた時点の記録の値を読むため）。操作の一覧からも外す。
        guard store.exists(justRecordedIDs[index]) else {
            forgetRecordsDeletedElsewhere()
            return
        }
        presentEdit(justRecorded[index], calendar: calendar)
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
        if justRecordedIDs.contains(id) {
            justRecorded = []
        }
        // 直したのが前の記録でも今月の数字が変わりうるので、返事の一言は外す。
        discardReplyRemark()
        // 直すでカテゴリを選んだ（直すで変えたカテゴリは、そこで覚える）ので、返事で聞き返すのをやめる。
        categoryQuestionIDs.remove(id)
        refreshCategoryQuestions()
    }

    /// 消した記録を、「取り消す」と聞き返しの対象から外す（消えた記録を取り消したり、選んだりしないように）。
    private func forgetJustRecorded(_ id: PersistentIdentifier) {
        forgetJustRecorded([id])
    }

    /// 消えた記録をまとめて外す。控えた ID で見分け、消えた記録の値には触れない（1 件ずつ外すと、外すたびに残りの要約を
    /// 作り直し、まだ外していない消えた記録の値を読むことになるため）。
    private func forgetJustRecorded(_ ids: Set<PersistentIdentifier>) {
        guard !ids.isEmpty else { return }
        // 記録が消えると今月の数字が変わるので、返事の一言は外す。
        discardReplyRemark()
        let kept = zip(justRecorded, justRecordedIDs).filter { !ids.contains($0.1) }.map(\.0)
        if kept.count != justRecorded.count { justRecorded = kept }
        categoryQuestionIDs.subtract(ids)
        refreshCategoryQuestions()
    }

    /// ほかの端末（iCloud）で消された記録を、「取り消す」・聞き返し・削除の確認の対象から外す（`StoreChanges.remote` のたび。
    /// 取り消す・直すの前にも）。
    ///
    /// 消えた記録を持ち続けると、取り消す・直すときに消えた記録の値を読み、アプリが落ちうる（SwiftData は、届いた削除で
    /// 読み込み済みの記録の値を空にする。Apple の開発者フォーラム thread 762022）。ID だけで確かめる（`EntryStore.exists`）。
    func forgetRecordsDeletedElsewhere() {
        var ids = Set(justRecordedIDs).union(categoryQuestionIDs)
        if let pendingDeletion { ids.insert(pendingDeletion.id) }
        let gone = ids.filter { !store.exists($0) }
        guard !gone.isEmpty else { return }
        forgetJustRecorded(gone)
        if let pendingDeletion, gone.contains(pendingDeletion.id) { self.pendingDeletion = nil }
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
        var edits = EntryEdits(entry)
        edits.category = category
        do {
            // 「その他のまま」も、選んだ事実を保存して再び聞き返さない。
            try store.update(entry, with: edits)
        } catch {
            storeFailure = .categoryChoice
            return
        }
        let item = CategoryMemory.item(ofMemo: entry.memo, amount: entry.amount, isIncome: entry.isIncome)
        let remembered = (try? learnedCategories.remember(item: item, category: category)) ?? false
        categoryQuestionIDs.remove(id)
        refreshCategoryQuestions()
        // 入力欄の VoiceOver の「直す: …」の文を、選んだカテゴリで作り直す。
        snapshotJustRecorded()
        // 一言はカテゴリを選ぶ前の数字で書いたので外す。
        discardReplyRemark()
        let name = categories.catalog.localizedName(for: category)
        announce(
            remembered
                ? String(localized: "\(name)にしました。次から「\(item)」は\(name)にします")
                : String(localized: "\(name)にしました")
        )
    }

    // MARK: - チャットで頼む操作

    /// チャットの操作を行う。直す相手が無ければ、そう案内する（`noTarget`）。
    ///
    /// - Parameters:
    ///   - targets: 操作の相手（文を送った時点の直前の送信。`commandTargets`）。
    ///   - confirms: 行う前に確認を出すか（端末内 AI が選んだ操作）。決まりで読んだ操作はすぐ行う（2 件以上かレシートの記録を
    ///     消すときだけは確かめる。`needsConfirmation`）。
    private func perform(_ command: ChatCommand, text: String, sentAt: Date, targets: CommandTargets, confirms: Bool) {
        func reply(_ state: QuestionExchange.State) {
            appendQuestion(text, askedAt: sentAt, state: state)
        }
        guard confirms || needsConfirmation(command, targets: targets) else {
            execute(command, text: text, targets: targets, reply: reply)
            return
        }
        // AI の答えを待つ間に、ほかの画面や確認を開いていたら、確認を出さずにやめて文を入力欄に戻す。開いている画面の上や後に
        // 確認を出すと、確認が出ないまま待ち続けたり、直す画面で直した後に直す前の内容で確かめたりするため。
        if isPresentingOtherScreen {
            reply(.commandCancelled)
            restoreDraft(text)
            return
        }
        guard let question = commandQuestion(for: command, text: text, targets: targets, reply: reply) else { return }
        let exchangeID = appendQuestion(text, askedAt: sentAt, state: .commandAsked(question))
        pendingCommand = PendingCommand(command: command, question: question, text: text, targets: targets, exchangeID: exchangeID)
    }

    /// 決まりで読んだ操作でも、行う前に確かめるか。直前の送信の記録を 2 件以上か、レシートの記録を消すとき（1 文で品目がすべて
    /// 消え、レシートの画像は保存していないので戻せないため）。1 件の記録を消すときは、すぐ消す（送った文を見返せば分かり、
    /// 長押しの削除と同じ手間にしないため）。
    private func needsConfirmation(_ command: ChatCommand, targets: CommandTargets) -> Bool {
        guard case .removeLast = command else { return false }
        let records = liveRecords(in: targets)
        return records.count >= 2 || records.contains { $0.entry.source == .receipt }
    }

    /// 端末内 AI が選んだ操作の確認の内容。直す相手が無い・割り勘の金額を直そうとしたなど、確認するまでもなく行えなければ、
    /// その案内を `reply` に出して nil を返す。
    private func commandQuestion(
        for command: ChatCommand, text: String, targets: CommandTargets, reply: (QuestionExchange.State) -> Void
    ) -> CommandQuestion? {
        let catalog = categories.catalog
        switch command {
        case .recategorize(let category):
            guard let target = editTarget(in: targets) else {
                showNoTarget(text: text, reply: reply)
                return nil
            }
            return .recategorize(summary: target.entry.summaryText(in: catalog), category: catalog.localizedName(for: category))
        case .changeAmount(let amount):
            guard let target = editTarget(in: targets) else {
                showNoTarget(text: text, reply: reply)
                return nil
            }
            guard !isSplit(target.entry) else {
                showSplitNotChanged(text: text, reply: reply)
                return nil
            }
            return .changeAmount(summary: target.entry.summaryText(in: catalog), amount: amount)
        case .removeLast:
            let records = liveRecords(in: targets)
            guard !records.isEmpty else {
                showNoTarget(text: text, reply: reply)
                return nil
            }
            return .remove(summary: records.map { $0.entry.summaryText(in: catalog) }.formatted(.list(type: .and)))
        case .setMonthlyBudget(let amount):
            return .setMonthlyBudget(amount: amount)
        }
    }

    /// 確認で「変える」「削除」「決める」を押した。確認を出した返事のカードを、行った結果に書き換える。
    ///
    /// 確認の間に相手の記録が消えていれば（ほかの端末で消された・取り消した）、行わずに案内する。
    func confirmCommand(_ pending: PendingCommand) {
        guard isAsking(pending) else { return }
        if pendingCommand?.id == pending.id { pendingCommand = nil }
        execute(pending.command, text: pending.text, targets: pending.targets) { state in
            self.setQuestionState(state, for: pending.exchangeID)
        }
    }

    /// 確認で「キャンセル」を押した。何も変えず、送った文を入力欄に戻す（AI の読み違いなら、書き直して送れるように）。
    func cancelCommand(_ pending: PendingCommand) {
        guard isAsking(pending) else { return }
        if pendingCommand?.id == pending.id { pendingCommand = nil }
        setQuestionState(.commandCancelled, for: pending.exchangeID)
        restoreDraft(pending.text)
        announce(String(localized: "何も変えていません"))
    }

    /// まだ確認を待っているか（同じ確認を 2 度行わないため。ボタンと閉じる動きのどちらが先でも、1 度だけ行う）。
    private func isAsking(_ pending: PendingCommand) -> Bool {
        questions.first { $0.id == pending.exchangeID }?.state == .commandAsked(pending.question)
    }

    /// 操作を行い、結果の返事を `reply` に出す。
    private func execute(
        _ command: ChatCommand, text: String, targets: CommandTargets, reply: (QuestionExchange.State) -> Void
    ) {
        switch command {
        case .recategorize(let category):
            guard let target = editTarget(in: targets) else { return showNoTarget(text: text, reply: reply) }
            // カテゴリの名前だけの文（「交通」）は、直すが覚えない（`CategoryCorrection.isNameOnly`）。
            let remembers = !CategoryCorrection.isNameOnly(text, catalog: categories.catalog)
            recategorize(target.entry, to: category, text: text, remembers: remembers, reply: reply)
        case .changeAmount(let amount):
            guard let target = editTarget(in: targets) else { return showNoTarget(text: text, reply: reply) }
            changeAmount(target.entry, to: amount, text: text, reply: reply)
        case .removeLast:
            let records = liveRecords(in: targets)
            guard !records.isEmpty else { return showNoTarget(text: text, reply: reply) }
            remove(records, text: text, reply: reply)
        case .setMonthlyBudget(let amount):
            setMonthlyBudget(amount, text: text, reply: reply)
        }
    }

    /// チャットの操作の相手（送った時点の直前の送信）を控える。くり返しの記録は相手にしない（打った文の記録ではなく、
    /// 「さっきの」が指すものと違うことがあるため。返事のカードの「取り消す」と長押しで直せる）。
    private func commandTargets() -> CommandTargets {
        forgetRecordsDeletedElsewhere()
        return CommandTargets(records: zip(justRecorded, justRecordedIDs)
            .filter { $0.0.source != .recurring }
            .map { CommandTargets.Record(entry: $0.0, id: $0.1, isIncome: $0.0.isIncome) })
    }

    /// 控えた相手のうち、まだ保存先にあるもの（ほかの端末で消された記録の値には触れない）。
    private func liveRecords(in targets: CommandTargets) -> [CommandTargets.Record] {
        targets.records.filter { store.exists($0.id) }
    }

    /// カテゴリと金額を直す相手。直前の送信の支出が 1 件ならそれ、複数なら聞き返している記録が 1 件のときだけそれ。決められなければ
    /// nil（どの記録か分からないまま書き換えない）。収入は直さない（カテゴリを持たず、金額を直す文の「さっきの」は支出を指すことが
    /// 多いため）。
    private func editTarget(in targets: CommandTargets) -> CommandTargets.Record? {
        let expenses = liveRecords(in: targets).filter { !$0.isIncome }
        if expenses.count == 1 { return expenses[0] }
        let asking = expenses.filter { categoryQuestionIDs.contains($0.id) }
        return asking.count == 1 ? asking[0] : nil
    }

    /// 割り勘の記録か（1 人分の額を記録し、メモに割り勘の説明を書いたもの。`EntryMemoNote`）。
    private func isSplit(_ entry: Entry) -> Bool {
        EntryMemoNote(memo: entry.memo, amount: entry.amount, isIncome: entry.isIncome) != nil
    }

    /// 直す相手が無いことを案内し、送った文を入力欄に戻す。
    private func showNoTarget(text: String, reply: (QuestionExchange.State) -> Void) {
        reply(.noTarget)
        restoreDraft(text)
        announce(String(localized: "直せる直前の記録がありません"))
    }

    /// 割り勘の記録の金額はチャットでは直さないことを案内し、送った文を入力欄に戻す。
    private func showSplitNotChanged(text: String, reply: (QuestionExchange.State) -> Void) {
        reply(.splitNotChanged)
        restoreDraft(text)
        announce(String(localized: "割り勘の記録の金額は直していません"))
    }

    /// 直前の記録のカテゴリをチャットの文で直し、品目とカテゴリの組を覚える（返事の聞き返しで選んだときと同じ。修正の記憶）。
    /// 返事（「日用品にしました」）をタイムラインに出す。「取り消す」は残す（直したのはカテゴリだけなので、取り消せば
    /// 記録ごと消え、送った文が入力欄に戻る。返事で選んだときと同じ）。
    ///
    /// 書き込めなければ、送った文を入力欄に戻して知らせる（もう一度送れるように）。
    private func recategorize(
        _ entry: Entry, to category: EntryCategory, text: String, remembers: Bool, reply: (QuestionExchange.State) -> Void
    ) {
        let id = entry.persistentModelID
        var edits = EntryEdits(entry)
        edits.category = category
        do {
            try store.update(entry, with: edits)
        } catch {
            restoreDraft(text)
            storeFailure = .categoryChoice
            return
        }
        let item = CategoryMemory.item(ofMemo: entry.memo, amount: entry.amount, isIncome: entry.isIncome)
        let remembered = remembers && ((try? learnedCategories.remember(item: item, category: category)) ?? false)
        categoryQuestionIDs.remove(id)
        refreshCategoryQuestions()
        snapshotJustRecorded()
        // 一言はカテゴリを変える前の数字で書いたので外す。
        discardReplyRemark()
        let name = categories.catalog.localizedName(for: category)
        reply(.recategorized(item: item, category: name, remembered: remembered))
        announce(
            remembered
                ? String(localized: "\(name)にしました。次から「\(item)」は\(name)にします")
                : String(localized: "\(name)にしました")
        )
    }

    /// 直前の記録の金額をチャットの文で直す（「さっきのを900に直して」）。返事（「金額を直しました」）をタイムラインに出す。
    ///
    /// 割り勘の記録は直さない（1 人分の額を記録しているので、書いた金額が 1 人分か合計か決められないため。⑥ で直してもらう）。
    /// 「取り消す」だけを引っ込める（取り消すと、直す前の文が入力欄に戻り、直した内容と食い違うため。⑥ で直したときと同じ）。
    /// 直前の記録は、聞き返し・チャットで直す相手として残す（金額を直しても、カテゴリはまだ決まっていないため）。書き込めなければ、
    /// 送った文を入力欄に戻して知らせる。
    private func changeAmount(_ entry: Entry, to amount: Int, text: String, reply: (QuestionExchange.State) -> Void) {
        guard !isSplit(entry) else { return showSplitNotChanged(text: text, reply: reply) }
        let previous = entry.amount
        let item = CategoryMemory.item(ofMemo: entry.memo, amount: entry.amount, isIncome: entry.isIncome)
        var edits = EntryEdits(entry)
        edits.amount = amount
        edits.memo = item
        do {
            try store.update(entry, with: edits, resolvesCategory: false)
        } catch {
            restoreDraft(text)
            storeFailure = .amountChange
            return
        }
        if justRecordedIDs.contains(entry.persistentModelID) {
            undoWithdrawn = true
            snapshotJustRecorded()
        }
        // 一言は直す前の金額で書いたので外す。
        discardReplyRemark()
        reply(.amountChanged(item: item, from: previous, to: amount))
        announce(String(localized: "金額を\(YenFormatter.string(from: amount))に直しました"))
    }

    /// 直前の送信の記録をチャットの文で消す（「さっきの消して」。返事の「取り消す」と同じく、その送信の記録をすべて消す）。
    /// 送った文は入力欄に戻さない（消したいと書いたので）。消せなければ、「取り消す」の失敗と同じく知らせ、送った文を戻す。
    private func remove(_ records: [CommandTargets.Record], text: String, reply: (QuestionExchange.State) -> Void) {
        // 消した記録の値は、保存した後には読めない。返事と読み上げの文は先に作る。
        let catalog = categories.catalog
        let summary = records.map { $0.entry.summaryText(in: catalog) }.formatted(.list(type: .and))
        let items = records.map { "\($0.entry.kindText(in: catalog)) \(YenFormatter.string(from: $0.entry.amount))" }
        let ids = records.map(\.id)
        do {
            try store.delete(records.map(\.entry))
        } catch {
            restoreDraft(text)
            storeFailure = .undo
            return
        }
        forgetJustRecorded(Set(ids))
        reply(.removed(summary: summary))
        announce(String(localized: "削除しました: \(items.formatted(.list(type: .and)))"))
    }

    /// 月の全体の予算をチャットの文で決める（「今月の予算を5万にして」。② 予算を決めると同じ保存）。返事を出す。
    /// 書き込めなければ、送った文を入力欄に戻して知らせる。
    private func setMonthlyBudget(_ amount: Int, text: String, reply: (QuestionExchange.State) -> Void) {
        do {
            try budgetStore.setAmount(amount, for: .total)
        } catch {
            restoreDraft(text)
            storeFailure = .budgetChange
            return
        }
        // 一言は前の予算の残りで書いていることがあるので外す。
        discardReplyRemark()
        reply(.budgetSet(amount: amount))
        announce(String(localized: "月の予算を\(YenFormatter.string(from: amount))にしました"))
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
    /// カレンダーのページを出していたら、会話のページに戻す（返事を会話のページに出すため）。
    func receive(_ action: QuickAction) {
        pendingQuickAction = action
        page = .conversation
        closeScreensForQuickAction()
    }

    /// 頼みを受けたら、横に進んだ画面（設定・月のまとめ）を閉じて会話に戻す（答えや返事は会話に出るので、閉じないと見えない
    /// まま終わる）。その上にシートや確認を出しているときは閉じない（書きかけを黙って捨てないため。閉じるまで頼みを待たせる）。
    private func closeScreensForQuickAction() {
        if let monthlyReport, monthlyReport.editing == nil {
            self.monthlyReport = nil
        }
        if let settings, !settings.isPresentingSheet {
            self.settings = nil
        }
    }

    /// 待っている頼みを、行えるなら行う。行ったら、その処理を待つ Task を返す（テストで使う）。行えなければ nil（待ち続ける）。
    /// ホームが出たとき・頼みを受け取ったとき・読み取りが終わったとき・ほかの画面を閉じたとき・ロックを解いたときに呼ぶ。
    ///
    /// 読み取りの間と、ほかの画面（シート・確認・閉じられなかった設定など）を出している間は待つ（画面の下で記録したり答えたり
    /// すると、返事が見えないまま終わるため）。文が空なら入力欄を開く。
    @discardableResult
    func performPendingQuickAction(calendar: Calendar) -> Task<Void, Never>? {
        guard let action = pendingQuickAction, !isParsing, !isPresentingOtherScreen else { return nil }
        switch action {
        case .record(let text), .ask(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                pendingQuickAction = nil
                inputFocusRequest += 1
                return Task {}
            }
            pendingQuickAction = nil
            let isQuestion = if case .ask = action { true } else { false }
            return submit(trimmed, source: .text, forcesQuestion: isQuestion, confirmsCommands: !isQuestion, calendar: calendar)
        }
    }

    // MARK: - カテゴリの聞き返しの読み直し

    /// カテゴリを聞き返している記録を保存先から読み直す（記録を足した・直した・消したとき、ほかの端末の変更が届いたとき、
    /// 開いたとき）。読めなければ、いまの聞き返しのまま（記録は止めない）。
    func refreshCategoryQuestions() {
        guard let entries = try? store.context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.needsCategoryReview }))
        else { return }
        categoryQuestionIDs = Set(entries.map(\.persistentModelID))
    }

    // MARK: - くり返しの記録

    /// 記録する日を過ぎたくり返しの記録を記録し、返事のカード（「くり返しの記録」）と読み上げで知らせる（ホームが出たとき・
    /// 前面に戻ったとき・日付が変わったとき・くり返しの記録を足したり直したりしたとき）。
    ///
    /// 記録したものは直前の送信と同じく「取り消す」の対象にする（取り消すと、その月の分はもう記録しない）。書き込めなければ
    /// 何もしない（記録した月を覚えていないので、次に開いたときにもう一度記録する）。
    ///
    /// 送った文を読み取っている間（AI の判断を待つ間も）は記録せず、読み取りが終わってから記録する（`isParsing`）。記録すると
    /// 直前の送信がくり返しの記録に替わり、読み取りの後で、送った文の記録の「取り消す」やチャットの操作の相手と食い違うため。
    ///
    /// 家計の画面を隠している間も記録せずに待たせる（`hidesContent`）。読み取りが裏で終わったときに、ロックの画面の下で記録して
    /// 金額を読み上げないように。画面を出したら `HomeView` がもう一度呼ぶ。
    func recordDueRecurringEntries(calendar: Calendar) {
        recurringCalendar = calendar
        guard !isParsing, !hidesContent else {
            holdsRecurringEntries = true
            return
        }
        removeDuplicateRecurringEntries()
        let recordedAt = now()
        guard let recorded = try? recurring.recordDue(now: recordedAt, timeZone: calendar.timeZone), !recorded.isEmpty else {
            return
        }
        justRecorded = recorded
        refreshCategoryQuestions()
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
        forgetJustRecorded(Set(removed))
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
        budgetSetup = BudgetSetupModel(store: budgetStore, announce: announce)
    }

    // MARK: - 月のまとめ

    /// 「月のまとめ」へ進む（帯の今月の合計を押したとき）。今月を開く。
    ///
    /// まとめの記録の一覧からも「直す」を開けるので、ホームから開いたときと同じく、直したら「取り消す」を引っ込め、
    /// 消したら「取り消す」の対象から外す（戻ったあとで、消えた記録や直す前の文を取り消しで扱わないように）。
    /// - Parameters:
    ///   - calendar: 月の区切りの暦（ホームの画面の暦。帯の今月と同じ月でまとめるため）。
    ///   - month: 開く月に入る日時（質問の回答カードから先月を開くとき）。nil なら今月。
    ///
    /// 設定を出している間（戻る動きの途中を含む）は開かない。月のまとめと設定はホームの別々の行き先（`navigationDestination`）で、
    /// 両方が立つと、違う画面が開いたり二重に積まれたりするため（押した側は、戻りきってから押し直せば開く）。
    func presentMonthlyReport(calendar: Calendar, month: Date? = nil) {
        guard settings == nil else { return }
        let remark = monthlyRemark ?? RecapRemarkModel(makeWriter: makeRemarkWriter)
        monthlyRemark = remark
        monthlyReport = MonthlyReportModel(
            store: store,
            calendar: calendar,
            month: month,
            remark: remark,
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
    ///
    /// 月のまとめを出している間（戻る動きの途中を含む）は開かない（`presentMonthlyReport` と同じ理由）。
    func presentSettings() {
        guard monthlyReport == nil else { return }
        settings = SettingsModel(
            context: store.context, budgetStore: budgetStore, categories: categories, storeHost: storeHost,
            now: now, announce: announce,
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

    // MARK: - 日付とタイムライン

    /// 「今日」を読み直す。前面に戻ったときと、日付が変わったとき（0 時・時間帯の変更など）に呼ぶ。
    func refreshToday() {
        today = now()
        calendarPage.refreshToday()
    }

    /// タイムラインにさらに前の記録を読み込む（上限の `timelineMaxLimit` を超えては読み込まない）。
    func showMoreTimeline() {
        timelineLimit = min(timelineLimit + Self.timelinePageSize, Self.timelineMaxLimit)
    }

    // MARK: - 型

    /// チャットの操作の相手（文を送った時点の直前の送信の記録。くり返しの記録は除く）。
    ///
    /// 記録と一緒に、控えた時点の ID と収入かも持つ（ほかの端末で消された記録の値に触れずに、消えたかと直す相手を決めるため）。
    struct CommandTargets {
        struct Record {
            let entry: Entry
            let id: PersistentIdentifier
            let isIncome: Bool
        }

        let records: [Record]
    }

    /// 端末内 AI が選んだチャットの操作で、確認を待っているもの。
    struct PendingCommand: Identifiable {
        let id = UUID()
        let command: ChatCommand
        /// 確認の内容（確認のアラートと返事のカードに出す）。
        let question: CommandQuestion
        /// 送った文（やめたときに入力欄へ戻す）。
        let text: String
        /// 操作の相手（文を送った時点の直前の送信）。
        let targets: CommandTargets
        /// 確認を出した返事のカード（行った結果か、やめたことに書き換える）。
        let exchangeID: UUID
    }

    /// 削除の確認を待っている記録。確認の文は先に作っておく（消した後の記録の値は読めないため）。
    struct PendingDeletion {
        let entry: Entry
        /// 確認を出した時点で控えた ID（確認の間にほかの端末で消されたかを、記録の値に触れずに確かめるため）。
        let id: PersistentIdentifier
        let summary: String
    }

    /// 記録として送り、読み取っている文（`pendingRecord`）。
    struct PendingRecord: Identifiable, Equatable {
        let id = UUID()
        let text: String
        /// どこから入れた文か（吹き出しに添える印を、記録した後の吹き出しと同じにする）。
        let source: EntrySource
        /// 送った瞬間の日時（タイムラインの並びと日付の見出しに使う。記録した日時と同じ値）。
        let sentAt: Date
    }

    /// ホームのページ。
    enum Page: Hashable {
        /// 会話（記録と質問のタイムラインと入力欄）。
        case conversation
        /// カレンダー（月の日ごとの支出・選んだ日の記録・今日あと）。
        case calendar
    }

    /// 保存先への書き込みの失敗。利用者に知らせ、記録したつもり・消したつもりにさせない。
    enum StoreFailure: Equatable {
        case record
        case undo
        case delete
        /// 返事で選んだカテゴリを書き込めなかった。
        case categoryChoice
        /// チャットで頼んだ金額の直しを書き込めなかった。
        case amountChange
        /// チャットで頼んだ月の予算を書き込めなかった。
        case budgetChange
    }
}

/// 記録の直後の「直す」の対象の 1 件。
///
/// 入力欄の VoiceOver の操作（「直す: ランチ ¥850」）は記録の値を読まずに描けるよう、見出しと ID だけを持つ。
/// どの記録を直すかは、ID から `HomeModel` が決める。
struct RecordedItem: Identifiable {
    let id: AnyHashable
    /// 「ランチ ¥850」
    let summaryText: String
}
