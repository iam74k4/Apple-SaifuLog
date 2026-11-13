import PhotosUI
import SaifuLogCore
import SwiftData
import SwiftUI
import UIKit

/// ホーム。今月の合計、記録のタイムライン、入力欄を 1 画面に置く。
///
/// 記録も質問も同じ入力欄から行う。入口を分けると「どこに書けばいいか」を利用者に考えさせることになるため。
/// タイムラインは会話の形にする。送った文を右寄せの自分の吹き出しに、アプリの返事（記録しました・質問の答え）を左寄せの
/// カードに、送った順に出す（質問とその答えは保存しない）。記録の直後の「取り消す」は、その返事の見出しに出す。
///
/// 入力欄の左のカメラのボタンから、レシートを撮るか写真から選んで読み取り（④）、読み取り結果（⑤）のシートで確かめて記録する。
///
/// 会話を左へスワイプすると、カレンダーのページ（日ごとの支出・選んだ日の記録・今日あといくら使えるか。`LedgerCalendarView`）が
/// 出る。帯にカレンダーのボタンは置かない（スワイプで出るページと入口が重なるため）。
///
/// 状態と操作（送信・質問・レシート・取り消し・直す・削除・予算を決める画面と月のまとめと設定とプレミアムの出し入れ・
/// ページの切り替え）は `HomeModel` が持つ。ここは表示と、
/// 環境（文字の大きさ・前面かどうか）に合わせた出し方だけを受け持つ。
struct HomeView: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.scenePhase) private var scenePhase
    /// アプリのロック（アプリで 1 つ。`SaifuLogApp` が渡す）。ロック中は、Siri・ショートカットからの頼みを待たせる。
    @Environment(AppLock.self) private var appLock: AppLock?
    /// Siri・ショートカットからの頼みの受け箱（アプリで 1 つ）。
    private var quickActions: QuickActionInbox { .shared }

    @State private var model: HomeModel
    /// 写真の選択で選んだもの。読み取りに渡したら nil に戻す（写真はメモリの上で読み、保存しない）。
    @State private var photoItem: PhotosPickerItem?
    /// 入力欄にフォーカスがあるか（キーボードを出している間）。上の帯を低くして、タイムラインを広く見せる（`SummaryHeader.isCompact`）。
    @State private var isTyping = false
    #if DEBUG || INTERNAL_DIAGNOSTICS
    /// 診断画面を出しているか。社内テスト用のビルドと DEBUG だけの画面なので、App Store へ出すビルドにも入る
    /// `HomeModel` には持たせず、ここに置く。
    @State private var showsDiagnostics = false
    @Environment(\.modelContext) private var modelContext
    #endif

    init(model: HomeModel) {
        _model = State(initialValue: model)
    }

    #if DEBUG || INTERNAL_DIAGNOSTICS
    /// 帯に診断のボタンを出すか。撮影用のデモ（DEBUG のビルドだけ）では出さない。
    private var showsDiagnosticsButton: Bool {
        #if DEBUG
        ScreenshotDemo.current == nil
        #else
        true
        #endif
    }
    #endif

    var body: some View {
        NavigationStack {
            pages
                .toolbar(.hidden, for: .navigationBar)
                .alert(
                    model.storeFailure?.title ?? Text(verbatim: ""),
                    isPresented: showsStoreFailure,
                    presenting: model.storeFailure
                ) { _ in
                    Button("OK", role: .cancel) {}
                } message: { failure in
                    failure.message
                }
                // item で出す（閉じる間も中身を保つ。isPresented にして中身を budgetSetup から作ると、閉じる動きの
                // 途中で budgetSetup が nil になり、空のシートが下りていくため）。閉じると budgetSetup は nil に戻る。
                .sheet(item: $model.budgetSetup) { budgetSetup in
                    BudgetSetupSheet(model: budgetSetup)
                }
                // 「直す」も item で出す（上と同じ理由）。閉じると editing は nil に戻る。
                .sheet(item: $model.editing) { editing in
                    EditEntrySheet(model: editing)
                }
                // 返事の聞き返しから開く「カテゴリを作る」（上と同じく item で出す）。
                .sheet(item: $model.categoryEditor) { editor in
                    CategoryEditorSheet(model: editor)
                }
                // 返事の行の長押しの「毎月くり返す」で開く、くり返しの記録を作るシート。
                .sheet(item: $model.recurringEditor) { editor in
                    RecurringEditorSheet(model: editor)
                }
                // 月のまとめ（⑦）は横に進む。ホームへ戻ると monthlyReport は nil に戻る（item で出すのは、シートと同じく
                // 戻る動きの間も中身を保つため）。
                .navigationDestination(item: $model.monthlyReport) { report in
                    MonthlyReportView(model: report)
                }
                // 設定（⑧）も横に進む（ホームから行って戻るだけの画面なので、まとめと同じ出し方にする）。
                .navigationDestination(item: $model.settings) { settings in
                    SettingsView(model: settings)
                }
                // 無料体験が終わった後の最初の起動に、一度だけプレミアム（⑨）を出す（`HomeModel.presentPremiumIfTrialEnded`）。
                .sheet(item: $model.premiumSheet) { premium in
                    PremiumSheet(model: premium)
                }
                // ④ 撮影（書類カメラ）。閉じきってから読み取りのシートを出す（出し入れが重なると出ないことがあるため）。
                .fullScreenCover(isPresented: showsDocumentCamera, onDismiss: { model.receiptCaptureDidDismiss(calendar: calendar) }) {
                    DocumentCameraView(
                        finish: { model.finishDocumentCamera($0, skippedPageCount: $1) },
                        cancel: { model.receiptCapture = nil }
                    )
                    .ignoresSafeArea()
                }
                // 写真から選ぶ。PhotosPicker はアプリの外で動くので、写真のライブラリへのアクセスの許可は要らない。
                .photosPicker(isPresented: showsPhotoPicker, selection: $photoItem, matching: .images)
                .onChange(of: photoItem) { _, item in
                    guard let item else { return }
                    photoItem = nil
                    readPhoto(item)
                }
                // ⑤ 読み取り結果。item で出す（閉じる間も中身を保つ）。閉じきったら、撮り直しやプレミアムの案内を続ける。
                .sheet(item: $model.receiptResult, onDismiss: { model.receiptResultDidDismiss() }) { result in
                    ReceiptResultSheet(model: result)
                }
                // ホームが出たときと、購入の事実を読み終えたときに確かめる（前面に戻ったときは下の scenePhase）。
                // 状態の変化では出さない。アプリを開いたまま体験が終わる瞬間（`PurchaseManager` が描き直させる）に出すと、
                // 入力の途中でも遮るため。そのときは次に前面に戻ったときに出す（「体験が終わった後の最初の起動」）。
                .task(id: model.purchases.hasLoadedPurchases) {
                    model.presentPremiumIfTrialEnded()
                }
                // 体験を始めた・買った・返金されたら、月のまとめの AI の一言を決め直す（体験を始めて月のまとめに戻ったら一言が
                // 付くように）。
                .onChange(of: model.purchases.status.unlocksPremium) {
                    model.premiumStatusDidChange()
                }
                .onAppear {
                    // カレンダーのページに画面の暦を渡し、今月を読んでおく（左へスワイプしたときに、すぐ出せるように）。
                    model.calendarPage.configure(calendar: calendar)
                    // モデルは初回の案内より前に作っている（`AppRootView`）。案内の間に日付が変わっていても今日で数えるよう、読み直す。
                    model.refreshToday()
                    // 記録する日を過ぎたくり返しの記録を記録する（前面に戻ったとき・日付が変わったときは下）。
                    recordDueRecurringEntries()
                    // 起動の途中（案内の間・保存先を開く前）に受けた Siri・ショートカットの頼みを行う。
                    deliverQuickActions()
                }
                // Siri・ショートカットからの頼み（アプリを開いてから届く）と、待っていた頼みを行う時機（読み取りが終わったとき・
                // ロックを解いたとき）。
                .modifier(QuickActionDelivery(
                    pending: quickActions.pending, isParsing: model.isParsing, hidesContent: appLock?.hidesContent,
                    deliver: deliverQuickActions, contentDidShow: catchUpAfterShowingContent
                ))
                // ほかの画面やシートを閉じたら、待っていた Siri・ショートカットの頼みを行う。
                .onChange(of: model.isPresentingOtherScreen) { _, presenting in
                    if !presenting { deliverQuickActions() }
                }
                // 週の始まりの設定を変えると画面の暦が変わるので、カレンダーの並びを変えた後の暦で決め直す。
                .onChange(of: calendar) { _, calendar in
                    model.calendarPage.configure(calendar: calendar)
                }
                // ページが替わったら、VoiceOver に知らせ、新しいページの最初の要素から読ませる（スワイプでもボタンでも）。
                .onChange(of: model.page) {
                    VoiceOver.screenChanged()
                }
                // 保存先に書き込まれたら、カテゴリの一覧・カレンダー・聞き返しを読み直す（記録を足した・直した・消したとき）。
                .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
                    model.categories.reload()
                    model.calendarPage.reload()
                    model.refreshCategoryQuestions()
                }
                // iCloud で届いたほかの端末の変更でも読み直す（didSave にならないため。帯とタイムラインは @Query が追う）。
                // ほかの端末が同じ月のくり返しの記録を記録していたら片づける。
                .onReceive(StoreChanges.remote) { _ in
                    // ほかの端末で消された記録を、取り消す・聞き返しの対象から外す（消えた記録を指し続けないように）。
                    model.forgetRecordsDeletedElsewhere()
                    model.removeDuplicateRecurringEntries()
                    model.categories.reload()
                    model.calendarPage.reload()
                    model.refreshCategoryQuestions()
                }
                #if DEBUG || INTERNAL_DIAGNOSTICS
                .sheet(isPresented: $showsDiagnostics) {
                    DiagnosticsView(model: DiagnosticsModel(context: modelContext))
                }
                // 帯の右上に診断のボタンを出させる（渡さなければ出ない）。撮影用のデモでは渡さない（App Store の
                // スクリーンショットに、App Store 版には無い開発用のボタンを写さないため）。
                .environment(\.openDiagnostics, showsDiagnosticsButton ? OpenDiagnosticsAction { showsDiagnostics = true } : nil)
                #endif
                .confirmationDialog(
                    "この記録を削除しますか？",
                    isPresented: showsDeletionConfirmation,
                    titleVisibility: .visible,
                    presenting: model.pendingDeletion
                ) { pending in
                    Button("削除", role: .destructive) { model.delete(pending) }
                } message: { pending in
                    Text("\(pending.summary)の記録を削除します。この操作は取り消せません。")
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        model.refreshToday()
                        recordDueRecurringEntries()
                        deliverQuickActions()
                            // 状態が変わらなくても、前面に戻ったときには確かめる（ほかの画面を閉じた後で出せるように）。
                        model.presentPremiumIfTrialEnded()
                    default:
                        break
                    }
                }
                // 日付が変わったとき（0 時・時間帯の変更など）。前面に置いたまま月をまたいでも合計を切り替える。
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                    model.refreshToday()
                    recordDueRecurringEntries()
                }
        }
        // カテゴリの一覧（作ったカテゴリの名前・記号・色）を、ホームから開くすべての画面とシートに渡す。
        .environment(\.categoryCatalog, model.categories.catalog)
    }

    /// 会話（1 枚目）とカレンダー（2 枚目）。左右のスワイプで行き来し、カレンダーからは「会話」のボタンでも戻れる。
    /// VoiceOver では、帯の数字の要素の操作「カレンダー」でも開ける（ページを送るスワイプが見つけにくいため）。
    ///
    /// ナビゲーションの根元に置き、横に進む画面（月のまとめ・設定）とシートは、どちらのページからも同じものを出す。
    private var pages: some View {
        TabView(selection: $model.page) {
            timeline
                .tag(HomeModel.Page.conversation)
            LedgerCalendarView(
                model: model.calendarPage,
                showConversation: { withAnimation { model.page = .conversation } },
                edit: { model.presentEdit($0, calendar: calendar) },
                requestDelete: { model.requestDelete($0) },
                makeRecurring: { model.presentRecurringCreation(from: $0, calendar: calendar) },
                openReport: { model.presentMonthlyReport(calendar: calendar, month: $0) }
            )
            .tag(HomeModel.Page.calendar)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(Theme.background)
    }

    private var timeline: some View {
        timelineContent
            .background(Theme.background)
            // 帯と入力欄は safeAreaBar に置き、記録がその下を流れるようにする（iOS 26 のスクロール端の効果が、帯と入力欄の
            // 下で記録をぼかす）。帯は前は画面の背景の色で塗り、下端に細い線を引いていた（塗った帯の下では効果が隠れたため）。
            // 帯は数字の行が多く背が高いので、やわらかい効果（既定の .soft）では帯の下の方で記録が透け、目安や収入の行が
            // 読みにくくなった。上ははっきりした効果（.hard）にする。下（入力欄）は既定のまま。
            .scrollEdgeEffectStyle(.hard, for: .top)
            .safeAreaBar(edge: .top, spacing: 0) {
                header
                    // 合計は画面の上に常に出ている帯なので、文字の大きさに上限を設ける。最大の文字サイズの
                    // ままだと、下の入力欄と合わせて画面の半分以上を占め、タイムラインがほとんど見えなくなるため。
                    // 上限は入力欄（`InputBar`）と同じ AX1（前は AX5 で帯（上の安全領域を含む）が画面の 3 分の 1 を超えた）。
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            }
            .safeAreaBar(edge: .bottom, spacing: 0) {
                bottomBar
            }
    }

    private var timelineContent: some View {
            EntryTimeline(
                limit: model.timelineLimit,
                canShowMore: model.canShowMoreTimeline,
                today: model.today,
                questions: model.questions,
                pendingRecord: model.pendingRecord,
                // 控えた ID を渡す（ほかの端末で消された記録の値に、描くときに触れないため）。
                undoableEntryIDs: Set(model.justRecordedIDs),
                askingCategory: model.categoryQuestionIDs,
                showMore: { model.showMoreTimeline() },
                undo: { model.undoLastRecord() },
                edit: { model.presentEdit($0, calendar: calendar) },
                requestDelete: { model.requestDelete($0) },
                chooseCategory: { model.chooseCategory($1, for: $0) },
                createCategory: { model.presentCategoryCreation(for: $0) },
                makeRecurring: { model.presentRecurringCreation(from: $0, calendar: calendar) },
                fillDraft: { model.draft = $0 },
                openReport: { model.presentMonthlyReport(calendar: calendar, month: $0) },
                setBudget: { model.presentBudgetSetup() },
                openPremium: { model.presentPremium() },
                askFollowUp: { model.askFollowUp($0, calendar: calendar) }
            )
    }

    /// 上の帯（今月の合計と予算）。
    private var header: some View {
        MonthSummaryHeader(
            today: model.today,
            calendar: calendar,
            openReport: { model.presentMonthlyReport(calendar: calendar) },
            openSettings: { model.presentSettings() },
            openCalendar: { withAnimation { model.page = .calendar } },
            isCompact: isTyping
        )
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            InputBar(
                text: $model.draft,
                isSending: model.isParsing,
                send: { model.send(calendar: calendar) },
                scanReceipt: { model.requestReceiptScan(calendar: calendar) },
                showsReceiptChoice: $model.showsReceiptSourceChoice,
                canUseDocumentCamera: model.canUseDocumentCamera,
                chooseReceiptSource: { model.startReceiptCapture($0) },
                // 返事の見出しの「取り消す」と行の「直す」に加えて、入力欄の VoiceOver の操作にも出す（送信の後にフォーカスが
                // 入力欄に戻るので、返事のカードまで移らずに取り消し・直しができるように）。
                undo: undoAction,
                recorded: model.canUndo ? model.recordedItems : [],
                edit: { model.presentEdit($0, calendar: calendar) },
                focusRequest: model.inputFocusRequest,
                isOnScreen: model.page == .conversation,
                focusChanged: { isTyping = $0 }
            )
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    /// アプリのロックが家計の画面を隠しているか（ロック中・前面を離れている・起動したときに読めなかったロックの設定を
    /// 確かめている間）。
    private var hidesContent: Bool {
        appLock?.hidesContent == true
    }

    /// Siri・ショートカットからの頼みを受け取り、行えるなら行う。家計の画面を隠している間は受け取るだけにし、出してから行う
    /// （ロックの画面の下で記録したり、カメラを開いたりしないため）。
    private func deliverQuickActions() {
        if let action = quickActions.take() {
            model.receive(action)
        }
        guard scenePhase == .active, !hidesContent else { return }
        model.performPendingQuickAction(calendar: calendar)
    }

    /// 決めた日を過ぎたくり返しの記録を記録する。家計の画面を隠している間は行わず、出してから行う（`catchUpAfterShowingContent`）。
    /// 記録した内容（品目と金額）を VoiceOver に読み上げるので、ロックの画面の下で行うと、解除の前に金額が周りに聞こえるため。
    private func recordDueRecurringEntries() {
        guard !hidesContent else { return }
        model.recordDueRecurringEntries(calendar: calendar)
    }

    /// ロックを解いた（家計の画面を隠すのをやめた）ときに、待っていたものを前面に戻ったときと同じ順で行う。
    private func catchUpAfterShowingContent() {
        recordDueRecurringEntries()
        deliverQuickActions()
    }

    /// 入力欄の「直前の記録を取り消す」の操作。取り消せるものがあるときだけ渡す。
    private var undoAction: (() -> Void)? {
        guard model.canUndo else { return nil }
        return { model.undoLastRecord() }
    }

    private var showsDocumentCamera: Binding<Bool> {
        Binding(get: { model.receiptCapture == .camera }, set: { if !$0, model.receiptCapture == .camera { model.receiptCapture = nil } })
    }

    private var showsPhotoPicker: Binding<Bool> {
        Binding(get: { model.receiptCapture == .photos }, set: { if !$0, model.receiptCapture == .photos { model.receiptCapture = nil } })
    }

    /// 選んだ写真をメモリの上で読み、読み取りに渡す（ファイルにもアルバムにも保存しない）。⑤ は読み取り中で先に出し、
    /// 写真を読み込めなければ「写真を読み込めませんでした」を出す（`HomeModel.readReceiptPhoto`）。
    ///
    /// 読み込みと画像の縮小は、メインスレッドの外（@Sendable の閉包）で行う。
    private func readPhoto(_ item: PhotosPickerItem) {
        model.readReceiptPhoto(calendar: calendar) {
            guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
            return ReceiptImage(data: data)
        }
    }

    private var showsStoreFailure: Binding<Bool> {
        Binding(get: { model.storeFailure != nil }, set: { if !$0 { model.storeFailure = nil } })
    }

    private var showsDeletionConfirmation: Binding<Bool> {
        Binding(get: { model.pendingDeletion != nil }, set: { if !$0 { model.pendingDeletion = nil } })
    }
}

/// 保存先への書き込みの失敗を利用者に知らせる文。
extension HomeModel.StoreFailure {
    var title: Text {
        switch self {
        case .record: Text("記録できませんでした")
        case .undo: Text("取り消せませんでした")
        case .delete: Text("削除できませんでした")
        case .categoryChoice: Text("カテゴリを変えられませんでした")
        case .chatCommand: Text("変えられませんでした")
        }
    }

    var message: Text {
        switch self {
        case .record: Text("保存に失敗しました。もう一度送ってください。")
        case .undo, .delete, .categoryChoice, .chatCommand: Text("保存に失敗しました。もう一度お試しください。")
        }
    }
}

/// 記録のタイムライン。記録した日時の新しいものから `limit` 件を読み、古い順（新しいものが下）に会話の形で並べる。
///
/// 1 回の送信で記録したもの（ひとこと入力の複数件・レシートの品目）を 1 つの送信にまとめ（`EntrySend`。コアの `TimelineSend`）、
/// 送った文を右寄せの自分の吹き出しに、記録したものを左寄せの返事のカード（「記録しました」）に出す。この起動の間に送った質問と
/// その答えも、送った順に同じ流れへ差し込む。暦の日が替わるところには日付の見出しを置く（コアの `TimelineDay`）。
///
/// 全期間を読むと、記録が増えるほど開くのも描き直すのも遅くなる。読み込む件数は `limit` で区切り（送信ではなく記録の件数で数える）、
/// さかのぼりたいときは上の「前の記録を表示」で増やす（行はすべて測るので、件数を区切る意味は大きい。`TimelineScrollView`）。
/// 増やせるのは `HomeModel.timelineMaxLimit` まで（`TimelineOlderRecords`）。区切りで前の件が切れたいちばん古い送信は、読み込んだ
/// 件だけの返事になる。
private struct EntryTimeline: View {
    let limit: Int
    /// 「前の記録を表示」でさらに読み込めるか（読み込む件数が上限に届いていなければ）。
    let canShowMore: Bool
    let today: Date
    let questions: [QuestionExchange]
    /// 記録として送り、読み取っている文（読み取りが終わるまで、いちばん下に送った文と「読み取っています…」を出す）。
    let pendingRecord: HomeModel.PendingRecord?
    /// 直前の送信で記録したもの（まだ取り消せるもの）。これを含む送信の返事にだけ「取り消す」を出す。取り消せなければ空。
    let undoableEntryIDs: Set<PersistentIdentifier>
    /// カテゴリを聞き返している記録。その記録の行の下にカテゴリのボタンを出す。
    let askingCategory: Set<PersistentIdentifier>
    let showMore: () -> Void
    let undo: () -> Void
    let edit: (Entry) -> Void
    let requestDelete: (Entry) -> Void
    let chooseCategory: (Entry, EntryCategory) -> Void
    /// 聞き返した記録のために、カテゴリを作る画面を開く。
    let createCategory: (Entry) -> Void
    /// その記録の中身で、くり返しの記録を作る画面を開く（長押しの「毎月くり返す」）。
    let makeRecurring: (Entry) -> Void
    /// 記録が無いときの案内の入力の例を、入力欄に入れる。
    let fillDraft: (String) -> Void
    let openReport: (Date) -> Void
    let setBudget: () -> Void
    let openPremium: () -> Void
    /// 回答カードの「続けて聞く質問」を送る（いちばん新しい答えにだけ出す）。
    let askFollowUp: (QuestionFollowUp) -> Void

    @Environment(\.calendar) private var calendar
    @Query private var recentEntries: [Entry]

    init(
        limit: Int,
        canShowMore: Bool,
        today: Date,
        questions: [QuestionExchange],
        pendingRecord: HomeModel.PendingRecord?,
        undoableEntryIDs: Set<PersistentIdentifier>,
        askingCategory: Set<PersistentIdentifier>,
        showMore: @escaping () -> Void,
        undo: @escaping () -> Void,
        edit: @escaping (Entry) -> Void,
        requestDelete: @escaping (Entry) -> Void,
        chooseCategory: @escaping (Entry, EntryCategory) -> Void,
        createCategory: @escaping (Entry) -> Void,
        makeRecurring: @escaping (Entry) -> Void,
        fillDraft: @escaping (String) -> Void,
        openReport: @escaping (Date) -> Void,
        setBudget: @escaping () -> Void,
        openPremium: @escaping () -> Void,
        askFollowUp: @escaping (QuestionFollowUp) -> Void
    ) {
        self.limit = limit
        self.canShowMore = canShowMore
        self.today = today
        self.questions = questions
        self.pendingRecord = pendingRecord
        self.undoableEntryIDs = undoableEntryIDs
        self.askingCategory = askingCategory
        self.showMore = showMore
        self.undo = undo
        self.edit = edit
        self.requestDelete = requestDelete
        self.chooseCategory = chooseCategory
        self.createCategory = createCategory
        self.makeRecurring = makeRecurring
        self.fillDraft = fillDraft
        self.openReport = openReport
        self.setBudget = setBudget
        self.openPremium = openPremium
        self.askFollowUp = askFollowUp
        _recentEntries = Query(Entry.timelineDescriptor(limit: limit))
    }

    /// タイムラインのやりとりの 1 つ（送信か、読み取っている送信か、質問とその答え）。
    private enum Exchange {
        case send(EntrySend)
        case pendingRecord(HomeModel.PendingRecord)
        case question(QuestionExchange)

        /// 並べる日時。送信は送った日時（記録した日時）、質問は送った日時。日付の見出しもこの日で決める。
        var date: Date {
            switch self {
            case .send(let send): send.sentAt
            case .pendingRecord(let pending): pending.sentAt
            case .question(let exchange): exchange.askedAt
            }
        }
    }

    /// 画面に並べる 1 つ（日付の見出し・送った文の吹き出し・記録の返事・質問とその答え）。
    private enum Item: Identifiable {
        case day(Date)
        case sentText(EntrySend)
        case reply(EntrySend)
        case pendingRecord(HomeModel.PendingRecord)
        case question(QuestionExchange)

        var id: ItemID {
            switch self {
            case .day(let day): .day(day)
            case .sentText(let send): .sentText(send.id)
            case .reply(let send): .reply(send.id)
            case .pendingRecord(let pending): .pendingRecord(pending.id)
            case .question(let exchange): .question(exchange.id)
            }
        }
    }

    private enum ItemID: Hashable {
        case day(Date)
        case sentText(PersistentIdentifier)
        case reply(PersistentIdentifier)
        case pendingRecord(UUID)
        case question(UUID)
    }

    /// 送信と質問を送った順（古いものが上）に並べ、送信を吹き出しと返事に分け、日が替わるところに見出しを置く。
    private var items: [Item] {
        let sends = EntrySend.sends(from: Array(recentEntries.reversed()))
        let exchanges = (sends.map(Exchange.send) + questions.map(Exchange.question)
            + (pendingRecord.map { [Exchange.pendingRecord($0)] } ?? []))
            .sorted { $0.date < $1.date }
        let headers = Set(TimelineDay.headerIndices(for: exchanges.map(\.date), calendar: calendar))
        var items: [Item] = []
        for (index, exchange) in exchanges.enumerated() {
            if headers.contains(index) {
                items.append(.day(calendar.startOfDay(for: exchange.date)))
            }
            switch exchange {
            case .send(let send):
                // 元の文を持たない記録（古い版のものなど）は、送った文の吹き出しを出さずに返事だけにする。
                if !send.originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    items.append(.sentText(send))
                }
                items.append(.reply(send))
            case .pendingRecord(let pending):
                items.append(.pendingRecord(pending))
            case .question(let exchange):
                items.append(.question(exchange))
            }
        }
        return items
    }

    var body: some View {
        ScrollViewReader { proxy in
            TimelineScrollView {
                if recentEntries.isEmpty && questions.isEmpty && pendingRecord == nil {
                    EmptyTimelineView(fill: fillDraft)
                }
                // 読み込んだ件数が上限に届いていれば、まだ前の記録があるかもしれない。
                if recentEntries.count >= limit {
                    TimelineOlderRecords(canShowMore: canShowMore, showMore: showMore)
                }
                ForEach(items) { item in
                    switch item {
                    case .day(let day):
                        TimelineDayHeader(day: day, today: today)
                    case .sentText(let send):
                        SentTextBubble(send: send)
                    case .reply(let send):
                        // 直前の送信の返事にだけ、「取り消す」と今月の状況の一行と聞き返しを出す（同じ間。`ReplyStatusLine`）。
                        let isLatest = canUndo(send)
                        RecordedReplyCard(
                            send: send, today: today, canUndo: isLatest, showsStatus: isLatest,
                            askingCategory: isLatest ? askingCategory : [],
                            undo: undo, edit: edit, requestDelete: requestDelete, chooseCategory: chooseCategory,
                            createCategory: createCategory, makeRecurring: makeRecurring
                        )
                        // 送信のいちばん下（返事のカード）の位置を知らせる。
                        .reportsTimelineFrame(.row(send.id))
                    case .pendingRecord(let pending):
                        PendingRecordView(pending: pending)
                            .reportsTimelineFrame(.row(pending.id))
                    case .question(let exchange):
                        QuestionExchangeView(
                            exchange: exchange, openReport: openReport, setBudget: setBudget, openPremium: openPremium,
                            // 続けて聞く質問は、いちばん新しい答えにだけ出す（前の答えに並べると、タイムラインが候補で埋まるため）。
                            askFollowUp: exchange.id == questions.last?.id ? askFollowUp : nil
                        )
                        .reportsTimelineFrame(.row(exchange.id))
                    }
                }
            }
            // 送る先はどれも、いちばん下の行ではなく中身の下端で、動きを付けない（`scrollToTimelineBottom`）。
            // 記録を足した（いちばん新しい記録が替わった）ら、下端まで送る。
            .onChange(of: recentEntries.first?.persistentModelID) { _, id in
                guard id != nil else { return }
                proxy.scrollToTimelineBottom()
            }
            // 記録として送った文を読み取り始めたら、下端まで送る（送った文と「読み取っています…」が見えるように）。
            .onChange(of: pendingRecord?.id) { _, id in
                guard id != nil else { return }
                proxy.scrollToTimelineBottom()
            }
            // 質問を送ったときと、返事が届いた（カードが伸びた）ときに、下端まで送る。
            .onChange(of: questions.last) { _, exchange in
                guard exchange != nil else { return }
                proxy.scrollToTimelineBottom()
            }
        }
    }

    /// この送信の返事に「取り消す」を出すか（直前の送信で記録したもので、まだ取り消せるものを含む）。
    private func canUndo(_ send: EntrySend) -> Bool {
        !undoableEntryIDs.isEmpty && send.entries.contains { undoableEntryIDs.contains($0.persistentModelID) }
    }
}

/// タイムラインの上の端（読み込んだ件数が上限に届いていて、まだ前の記録があるかもしれないとき）。
///
/// 読み込む件数を増やせるうちは「前の記録を表示」を出す。上限（`HomeModel.timelineMaxLimit`）に届いたら、代わりにそれより前の
/// 記録の見方を案内する。タイムラインは読み込んだ行をすべて描き直すので、上限なしに読み足すと、記録を足すたび・前面に戻るたびに
/// 引っかかるようになるため（`TimelineScrollView`）。
private struct TimelineOlderRecords: View {
    let canShowMore: Bool
    let showMore: () -> Void

    var body: some View {
        if canShowMore {
            // 文字だけのボタンは本文と同じ墨になるので、記号を添えて押せると分かるようにする（docs/design.md §7）。
            Button(action: showMore) {
                Label("前の記録を表示", systemImage: "arrow.up")
            }
            .font(.subheadline)
            .frame(minHeight: 44)
        } else {
            Text("ホームに出せるのは、新しく記録した方から \(HomeModel.timelineMaxLimit) 件までです。それより前の記録は、月のまとめのカテゴリの一覧と、設定の「記録を書き出す」で見られます。")
            .font(.footnote)
            .foregroundStyle(Theme.inkSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }
}

/// タイムラインのスクロール。下端から開き、いちばん新しいものを入力欄のすぐ上に出す。
///
/// 行は LazyVStack ではなく、すべての行を測る並べ方（`TimelineStack`。VStack と同じ位置に置く）に並べる。LazyVStack は、まだ
/// 描いていない行の高さを、そのとき描いている行から見積もる。
/// タイムラインの行は高さがそろわない（送った文の吹き出し・品目の数だけ伸びる返事のカード・回答カード）ので、描く行が替わるたびに
/// 全体の高さの見積もりが大きく揺れる。下端に合わせる（`defaultScrollAnchor(.bottom)`）と、揺れるたびに位置も同じだけ動いて
/// 描く行がまた替わり、見える範囲に行が 1 つも無い位置で止まることがあった。開いたときにタイムラインが空に見えた不具合で、
/// 見える行が少なく見積もりが数行で決まる大きな文字で起きた（シミュレータで、見積もりが 1 万 pt ほど揺れ、行を描かないまま
/// 止まるのを確かめた。どの文字の大きさで起きるかは記録の中身と画面の幅で変わる）。途中で止まって、いちばん下の行が入力欄に
/// 隠れることもあった（当時あった先週のふりかえりのカード）。すべての行を測れば全体の高さが正しく、下端に正しく合う。
///
/// すべての行を測るぶん開くときの手間は件数に比例するので、読み込む件数を `HomeModel.timelinePageSize` で区切る。
/// 読み込んだ行は、記録の追加・削除や同期の取り込み、前面に戻ったときにもすべて描き直すので、「前の記録を表示」で読み足せる件数にも
/// 上限（`HomeModel.timelineMaxLimit`）を設ける。
///
/// 開いた後にいちばん新しいものを足したとき（送信の返事・質問）は、中身の本当の下端に置いた目印
/// （`TimelineBottomMarker`）まで、動きを付けずに送る（`ScrollViewProxy.scrollToTimelineBottom`）。
/// - 行の id で下端に合わせると、行の下の端が見える範囲の下の端にそろい、その下の余白（`padding()` の 16pt）が見える範囲の外に
///   隠れた（中身が画面より高いときだけ。開いたときと、当時あった「取り消す」のバナーが引っ込んだ後は余白が見えるので、送った
///   直後だけ行が入力欄に寄って見えた）。目印は `defaultScrollAnchor(.bottom)` と同じ位置を指すので、二つの合わせ方が食い違わない。
/// - 動きを付けると、送り先の位置が送り始めたときの見える範囲の高さで決まり、動いている間はその位置に向かい続ける。同じときに
///   見える範囲の高さが変わると（声の入力の知らせ。当時は送った記録と一緒に出た「取り消す」のバナーも）、`defaultScrollAnchor(.bottom)`
///   が下端に合わせ直す分が打ち消され、変わった分だけ下端からずれて止まった（シミュレータの iOS 26.4 で、送った記録が見える範囲の
///   下に 36〜129pt はみ出し、当時の声の入力の知らせと同時に出た当時のふりかえりのカードは AX1 と AX5 で 400pt 以上下に隠れた）。動きなしで
///   下端に着けば、その後の高さの変化は `defaultScrollAnchor(.bottom)` が下端に合わせ続ける。
private struct TimelineScrollView<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                TimelineStack(spacing: 12) {
                    content
                }
                .padding()
                // 行の間隔（12pt）の外に置き、高さも 0 にして、中身の高さを変えない。
                Color.clear
                    .frame(height: 0)
                    .id(TimelineBottomMarker.id)
                    .accessibilityHidden(true)
            }
        }
        .defaultScrollAnchor(.bottom)
        .scrollDismissesKeyboard(.interactively)
        // スクロールの枠は帯と入力欄の間（安全領域の中）に置かれるので、枠の位置が行の見える範囲になる。
        .reportsTimelineFrame(.viewport)
    }
}

/// タイムラインの行を上から並べる（`VStack(spacing:)` と同じ大きさと位置。幅の足りない行は真ん中に置く）。
///
/// VStack にしないのは、タイムラインを開くときの手間を減らすため（行はすべて測る。`TimelineScrollView`）。VStack は行を並べるときに
/// 揃えの位置を行の中まで問い合わせるが、タイムラインの行はどれも幅いっぱいに広がるか（吹き出し・カード・見出し）、真ん中に置く
/// もの（「前の記録を表示」）なので、問い合わせずに真ん中に置く。会話の形にして行が増えたとき（送った文の吹き出しと返事のカード）、
/// 撮影用のデモの 50 件で、ホームを開いて最初に並べ終えるまでが 0.28 秒から 0.23 秒ほどに縮んだ（iPhone 17 Pro の iOS 26.4 の
/// シミュレータ。docs/design.md §9）。
private struct TimelineStack: Layout {
    /// 行の間。
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        // 行には幅だけを提案する（高さは提案しない。行は自分の高さで並ぶ）。
        let childProposal = ProposedViewSize(width: proposal.width, height: nil)
        var width: CGFloat = 0
        var height: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(childProposal)
            width = max(width, size.width)
            height += size.height + (index == 0 ? 0 : spacing)
        }
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let childProposal = ProposedViewSize(width: bounds.width, height: nil)
        var y = bounds.minY
        for subview in subviews {
            let size = subview.sizeThatFits(childProposal)
            subview.place(at: CGPoint(x: bounds.midX, y: y), anchor: .top, proposal: childProposal)
            y += size.height + spacing
        }
    }

    /// 並べ方の中に独自の揃えは無いので、揃えを問われても中を測らずに既定の位置（nil）を返す。
    func explicitAlignment(
        of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void
    ) -> CGFloat? {
        nil
    }

    func explicitAlignment(
        of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void
    ) -> CGFloat? {
        nil
    }
}

/// タイムラインの中身の下端の目印の id（`TimelineScrollView`）。いちばん新しいものまで送るときの行き先。
///
/// いちばん新しいもの（送信の返事・質問）はいつもいちばん下に並ぶので、下端まで送れば見える。
private enum TimelineBottomMarker: Hashable {
    case id
}

private extension ScrollViewProxy {
    /// タイムラインの中身の下端（`TimelineBottomMarker`）まで、動きを付けずに送る（理由は `TimelineScrollView`）。
    ///
    /// 呼んだときの変更に動きが付いていても（`withAnimation` の中や、周りの `animation(_:value:)`）、送る位置の変化は動きにしない。
    func scrollToTimelineBottom() {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            scrollTo(TimelineBottomMarker.id, anchor: .bottom)
        }
    }
}

/// タイムラインの行と見える範囲のどれか（`timelineFrameObserver` に知らせるときの名前）。
enum TimelineFrameKey: Hashable {
    /// 行の見える範囲（帯と入力欄の間）。
    case viewport
    /// 行。送信の返事のカードは送信の `id`（送信のいちばん古い記録の `persistentModelID`）、質問は `id`。
    case row(AnyHashable)
}

/// タイムラインの行と見える範囲が描かれた位置（ウィンドウの座標）を受け取るもの。
struct TimelineFrameObserver {
    let report: @MainActor (TimelineFrameKey, CGRect) -> Void
}

extension EnvironmentValues {
    /// タイムラインの行と見える範囲が描かれた位置を知らせる先。テストだけが渡し、アプリでは nil（行に何も付けない）。
    ///
    /// 大きな文字でタイムラインが空に見えた不具合（`TimelineScrollView`）の再発を、実際のホーム（ナビゲーションと帯と入力欄の
    /// 中のスクロール）のまま、いちばん新しい行が見える範囲の下端に描かれたかで確かめるため（`HomeTimelineLayoutTests`）。
    @Entry var timelineFrameObserver: TimelineFrameObserver? = nil
}

private extension View {
    /// 描かれた位置を `timelineFrameObserver` に知らせる（受け取る先が無ければ何も付けない）。
    func reportsTimelineFrame(_ key: TimelineFrameKey) -> some View {
        modifier(TimelineFrameReporter(key: key))
    }
}

private struct TimelineFrameReporter: ViewModifier {
    let key: TimelineFrameKey
    @Environment(\.timelineFrameObserver) private var observer

    func body(content: Content) -> some View {
        if let observer {
            content
                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frame in
                    observer.report(key, frame)
                }
                // 描かなくなった行は位置を消す（`.null`）。いまの並べ方（`TimelineStack`）では起きないが、遅延して描くスタックに
                // 戻したときに、見える範囲を外れて描いていない行を、前に描いた位置のまま「見えている」と数えないように。
                .onDisappear {
                    observer.report(key, .null)
                }
        } else {
            content
        }
    }
}

/// 記録が 1 件も無いときの案内。入力の例を見せて、何を書けばよいかを伝える。質問も同じ入力欄からできることを添える。
///
/// 例は押すと入力欄に入る（送るのは利用者）。初めての記録を、打たずに試せるようにするため。
private struct EmptyTimelineView: View {
    /// 例を入力欄に入れる。
    let fill: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ひとことで記録")
                .font(.title2.bold())
            Text("下の入力欄に、こんなふうに送るだけで記録できます。")
                .foregroundStyle(Theme.inkSecondary)
            examples(Self.recordExamples)
            Text("同じ入力欄で、家計について聞くこともできます。")
                .foregroundStyle(Theme.inkSecondary)
                .padding(.top, 4)
            examples(Self.questionExamples)
        }
        .foregroundStyle(Theme.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 24)
    }

    private func examples(_ texts: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(texts, id: \.self) { example in
                Button {
                    fill(example)
                } label: {
                    HStack(spacing: 8) {
                        Text(verbatim: example)
                            .foregroundStyle(Theme.ink)
                        // 押すと入力欄に入ることを示す印（入力欄へ上げる矢印）。
                        Image(systemName: "arrow.down.left")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.inkSecondary)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(minHeight: 44)
                    .background(Theme.surface, in: .rect(cornerRadius: 12))
                    .contentShape(.rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityHint("入力欄に入れます")
            }
        }
    }

    /// 入力の例は日本語のまま見せる（解析が日本語の入力を前提にしているため、訳さない）。
    private static let recordExamples = ["ランチ 850", "昨日 焼肉12000 4人で割り勘", "給料 25万"]
    /// 質問の例（ようこその 3 つ目の例と同じ）。
    private static let questionExamples = ["今月カフェいくら?"]
}

#Preview {
    // プレビューも、アプリとテストと同じ作り方の保存先（iCloud を切った、メモリの上だけのもの）を使う。
    if let container = try? ModelContainerFactory.makeInMemoryContainer() {
        HomeView(model: HomeModel(context: container.mainContext, purchases: PurchaseManager(loadPurchases: { [] })))
            .modelContainer(container)
    }
}

/// Siri・ショートカットからの頼みを受け渡す時機（頼みが届いたとき・読み取りが終わったとき・ロックを解いたとき）。ホームの画面の
/// 修飾子が長くなり、型の確かめが終わらなくなったので分けた。
private struct QuickActionDelivery: ViewModifier {
    let pending: QuickAction?
    let isParsing: Bool
    let hidesContent: Bool?
    let deliver: () -> Void
    /// 家計の画面を隠すのをやめた（ロックを解いた）とき。
    let contentDidShow: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: pending) { deliver() }
            .onChange(of: isParsing) { deliver() }
            .onChange(of: hidesContent) { _, hides in
                if hides == true { deliver() } else { contentDidShow() }
            }
    }
}
