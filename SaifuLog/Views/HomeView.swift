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
/// 週が替わって最初に開いたときは、先週のふりかえりのカードも同じタイムラインに出す（アプリからの返事として、出した時点の位置に）。
///
/// 入力欄の左のカメラのボタンから、レシートを撮るか写真から選んで読み取り（④）、読み取り結果（⑤）のシートで確かめて記録する。
///
/// 入力欄の右のマイクのボタンから、話した内容を端末の中で書き起こして入力欄に入れる（送信は利用者が押したときだけ）。
///
/// 家族と家計を共有しているとき（家計の共有が有効なビルドだけ）は、帯の「自分／家族」で記録先を切り替える。「家族」のときは、
/// タイムラインに家計の記録（記録した人の名前つき）を、帯に家族の今月の合計を出し、カメラとマイクのボタンは出さない
/// （レシートと声は v1 では「自分」だけ）。
///
/// 状態と操作（送信・質問・レシート・取り消し・直す・削除・予算を決める画面と月のまとめと設定とプレミアムの出し入れ・
/// 先週のふりかえり）は `HomeModel` が持つ。ここは表示と、
/// 環境（文字の大きさ・前面かどうか）に合わせた出し方だけを受け持つ。
struct HomeView: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    @State private var model: HomeModel
    /// 写真の選択で選んだもの。読み取りに渡したら nil に戻す（写真はメモリの上で読み、保存しない）。
    @State private var photoItem: PhotosPickerItem?
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
            timeline
                .toolbar(.hidden, for: .navigationBar)
                .alert("金額が見つかりませんでした", isPresented: $model.showsNoAmountAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("「ランチ 850」のように、金額の数字を入れてください。")
                }
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
                // 月のまとめ（⑦）は横に進む。ホームへ戻ると monthlyReport は nil に戻る（item で出すのは、シートと同じく
                // 戻る動きの間も中身を保つため）。
                .navigationDestination(item: $model.monthlyReport) { report in
                    MonthlyReportView(model: report)
                }
                // 設定（⑧）も横に進む（ホームから行って戻るだけの画面なので、まとめと同じ出し方にする）。
                .navigationDestination(item: $model.settings) { settings in
                    SettingsView(model: settings)
                }
                // 先週のふりかえりの内訳も横に進む（まとめと同じ出し方）。
                .navigationDestination(item: $model.weeklyRecapDetail) { recap in
                    WeeklyRecapView(model: recap)
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
                // 声の入力でマイクの許可が無い・断られたとき。許可は iOS の設定でしか変えられないので、設定を開くボタンを出す。
                .alert("マイクを使えません", isPresented: showsMicrophonePermissionAlert) {
                    Button("設定を開く") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    Button("キャンセル", role: .cancel) {}
                } message: {
                    Text("声で入力するには、設定でサイフログのマイクの使用を許可してください。")
                }
                // 書き起こしのモデルが無いとき。大きなファイルを Apple からダウンロードするので、始める前に確かめる。
                .alert(
                    "日本語の音声モデルをダウンロードしますか？",
                    isPresented: showsDownloadConfirmation,
                    presenting: model.voice.downloadConfirmation
                ) { _ in
                    Button("ダウンロード") { model.voice.confirmDownload() }
                    Button("キャンセル", role: .cancel) { model.voice.declineDownload() }
                } message: { confirmation in
                    if confirmation.onExpensiveNetwork {
                        Text("声を文字にするための日本語のモデルを、Apple からこの iPhone にダウンロードします。声や記録は送りません。いまはモバイル回線か低データモードです。大きなファイルなので、Wi‑Fi でのダウンロードをおすすめします。")
                    } else {
                        Text("声を文字にするための日本語のモデルを、Apple からこの iPhone にダウンロードします。声や記録は送りません。")
                    }
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
                // 体験を始めた・買った・返金されたら、ふりかえりの AI の一言を決め直す（体験を始めてホームに戻ったら一言が付くように）。
                .onChange(of: model.purchases.status.unlocksPremium) {
                    model.premiumStatusDidChange()
                }
                // 週が替わって最初に開いたときだけ、先週のふりかえりのカードを出す（前面に戻ったとき・日付が変わったときは下）。
                .onAppear {
                    // モデルは初回の案内より前に作っている（`AppRootView`）。案内の間に日付が変わっていても今日で数えるよう、読み直す。
                    model.refreshToday()
                    model.showWeeklyRecapIfDue(calendar: calendar)
                }
                // この端末で声の入力を使えるか（マイクのボタンを出すか）を調べる。前面に戻ったときにも調べ直す（下の scenePhase）。
                .task {
                    await model.voice.refreshAvailability()
                }
                // ほかの画面やシートを出したら、声の入力を止める（聞き取れた分は入力欄に入れる）。見えない入力欄に向けて
                // 聞き続けないように。
                .onChange(of: model.isPresentingOtherScreen) { _, presenting in
                    if presenting { model.voice.stop(.user) }
                }
                // 週の始まりの設定を変えると画面の暦が変わるので、変えた後の週で決め直す。
                .onChange(of: calendar) { _, calendar in
                    model.showWeeklyRecapIfDue(calendar: calendar)
                }
                // 保存先に書き込まれたら、ふりかえりのカード（と内訳）の数字を読み直す（先週の日付で記録したり、直したりしたとき）。
                .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
                    model.weeklyRecap?.reload()
                }
                // iCloud で届いたほかの端末の変更でも読み直す（didSave にならないため。帯とタイムラインは @Query が追う）。
                .onReceive(StoreChanges.remote) { _ in
                    model.weeklyRecap?.reload()
                }
                #if DEBUG || INTERNAL_DIAGNOSTICS
                .sheet(isPresented: $showsDiagnostics) {
                    DiagnosticsView(model: DiagnosticsModel(context: modelContext, household: model.household))
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
                // 家計の記録の削除。家族の端末からも消えることを添える。
                .confirmationDialog(
                    "この記録を削除しますか？",
                    isPresented: showsHouseholdDeletionConfirmation,
                    titleVisibility: .visible,
                    presenting: model.pendingHouseholdDeletion
                ) { pending in
                    Button("削除", role: .destructive) { model.deleteHouseholdEntry(pending) }
                } message: { pending in
                    Text("\(pending.summary)の家計の記録を削除します。家族の端末からも消えます。この操作は取り消せません。")
                }
                // 「家族」のときに質問や読めない文を送った（家計には記録しない）。送った文は入力欄に戻っている。
                .alert(
                    householdInputAlertTitle,
                    isPresented: showsHouseholdInputAlert,
                    presenting: model.householdInputAlert
                ) { _ in
                    Button("OK", role: .cancel) {}
                } message: { alert in
                    switch alert {
                    case .question:
                        Text("家族の家計への質問は、まだできません。帯の「自分」に切り替えると、自分の記録について聞けます。")
                    case .unclear:
                        Text("「ランチ 850」のように、品目と金額を入れてください。")
                    }
                }
                // 家計の共有の知らせ（招待を受け入れた・家計が消えたなど）。ほかの画面を出している間は、閉じてから出す
                // （設定の画面を出している間は、設定の画面が出す）。
                .alert(
                    model.household?.notice?.title ?? Text(verbatim: ""),
                    isPresented: showsHouseholdNotice,
                    presenting: model.household?.notice
                ) { _ in
                    Button("OK", role: .cancel) {}
                } message: { notice in
                    notice.message
                }
                // 家計から抜けた・消えたら「自分」に戻す。
                .onChange(of: model.showsLedgerSwitch) {
                    model.householdAvailabilityDidChange()
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        model.refreshToday()
                        // 状態が変わらなくても、前面に戻ったときには確かめる（ほかの画面を閉じた後で出せるように）。
                        model.presentPremiumIfTrialEnded()
                        model.showWeeklyRecapIfDue(calendar: calendar)
                        Task { await model.voice.refreshAvailability() }
                    case .background:
                        // 裏に回ったら、聞き取れた分を入力欄へ入れて止める（裏ではマイクを使い続けない）。
                        model.voice.stop(.background)
                    default:
                        break
                    }
                }
                // 日付が変わったとき（0 時・時間帯の変更など）。前面に置いたまま月をまたいでも合計を切り替える。
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                    model.refreshToday()
                    model.showWeeklyRecapIfDue(calendar: calendar)
                }
        }
        // 保存先の開き直しなどでホームの画面が片づけられるときは、声の入力をやめる（マイクを開いたままにしない）。
        .onDisappear {
            model.voice.cancel()
        }
    }

    private var timeline: some View {
        timelineContent
            .background(Theme.background)
            .safeAreaInset(edge: .top, spacing: 0) {
                header
                    // 合計は画面の上に常に出ている帯なので、文字の大きさに上限を設ける。最大の文字サイズの
                    // ままだと、下の入力欄と合わせて画面の半分以上を占め、タイムラインがほとんど見えなくなるため。
                    // 上限は入力欄（`InputBar`）と同じ AX1。AX2 では「1日あたり ¥… ・のこり N 日」が 2 行に分かれ、
                    // AX5 で帯（上の安全領域を含む）が画面の 3 分の 1 を超えた。AX1 なら 1 行に収まり、帯が 50pt ほど
                    // 低くなる（iPhone 17 Pro のシミュレータ）。
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBar
            }
    }

    /// 「家族」のときの家計の保存先といまの家計（家計に入っていて、「家族」を選んでいるときだけ）。
    private var activeHousehold: (container: ModelContainer, zoneName: String)? {
        guard model.isHouseholdActive, let host = model.household, let container = host.container,
              let zoneName = host.currentHousehold?.zoneName
        else { return nil }
        return (container, zoneName)
    }

    @ViewBuilder
    private var timelineContent: some View {
        if let household = activeHousehold {
            // 家計の記録は家計の保存先から読む（自分の記録の保存先とは別）。
            HouseholdTimeline(
                zoneName: household.zoneName,
                limit: model.timelineLimit,
                canShowMore: model.canShowMoreTimeline,
                today: model.today,
                undoableEntryIDs: Set(model.justRecordedHousehold.map(\.id)),
                showMore: { model.showMoreTimeline() },
                undo: { model.undoLastRecord() },
                edit: { model.presentHouseholdEdit($0, calendar: calendar) },
                requestDelete: { model.requestHouseholdDelete($0) }
            )
            .modelContainer(household.container)
        } else {
            EntryTimeline(
                limit: model.timelineLimit,
                canShowMore: model.canShowMoreTimeline,
                today: model.today,
                questions: model.questions,
                weeklyRecap: model.weeklyRecap,
                undoableEntryIDs: Set(model.justRecorded.map(\.persistentModelID)),
                showMore: { model.showMoreTimeline() },
                undo: { model.undoLastRecord() },
                edit: { model.presentEdit($0, calendar: calendar) },
                requestDelete: { model.requestDelete($0) },
                openReport: { model.presentMonthlyReport(calendar: calendar, month: $0) },
                setBudget: { model.presentBudgetSetup() },
                openPremium: { model.presentPremium() },
                openWeeklyRecap: { model.presentWeeklyRecapDetail() },
                // 閉じたときは、上の行がカードのあった所へ下りてくる動きを付ける（出したときは付けない。`TimelineScrollView`）。
                dismissWeeklyRecap: { withAnimation { model.dismissWeeklyRecap() } }
            )
        }
    }

    /// 上の帯。「家族」のときは家族の今月の合計（予算は v1 では「自分」だけなので出さない。まとめへも進まない）。
    @ViewBuilder
    private var header: some View {
        if let household = activeHousehold {
            HouseholdSummaryHeader(
                zoneName: household.zoneName,
                today: model.today,
                calendar: calendar,
                ledgerScope: $model.ledgerScope,
                openSettings: { model.presentSettings() }
            )
            .modelContainer(household.container)
        } else {
            MonthSummaryHeader(
                today: model.today,
                calendar: calendar,
                editBudget: { model.presentBudgetSetup() },
                openReport: { model.presentMonthlyReport(calendar: calendar) },
                openSettings: { model.presentSettings() },
                ledgerScope: model.showsLedgerSwitch ? $model.ledgerScope : nil
            )
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if let notice = model.voice.notice {
                VoiceNoticeView(notice: notice)
                    .transition(.opacity)
                    // 少しの間だけ出す。次の知らせに替わったら数え直す。
                    .task(id: notice) {
                        try? await Task.sleep(for: .seconds(5))
                        if !Task.isCancelled, model.voice.notice == notice { model.voice.notice = nil }
                    }
            }
            InputBar(
                text: $model.draft,
                isSending: model.isParsing,
                send: { model.send(calendar: calendar) },
                // レシートと声の入力は v1 では「自分」だけ（「家族」のときはボタンを出さない）。
                scanReceipt: model.isHouseholdActive ? nil : { model.requestReceiptScan(calendar: calendar) },
                showsReceiptChoice: $model.showsReceiptSourceChoice,
                canUseDocumentCamera: model.canUseDocumentCamera,
                chooseReceiptSource: { model.startReceiptCapture($0) },
                // 返事の見出しの「取り消す」と行の「直す」に加えて、入力欄の VoiceOver の操作にも出す（送信の後にフォーカスが
                // 入力欄に戻るので、返事のカードまで移らずに取り消し・直しができるように）。
                undo: undoAction,
                recorded: model.canUndo ? model.recordedItems : [],
                edit: { model.presentEdit($0, calendar: calendar) },
                voice: model.isHouseholdActive ? nil : model.voice,
                targetsHousehold: model.isHouseholdActive
            )
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .animation(.default, value: model.voice.notice)
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

    private var showsMicrophonePermissionAlert: Binding<Bool> {
        Binding(get: { model.voice.showsPermissionAlert }, set: { model.voice.showsPermissionAlert = $0 })
    }

    private var showsDownloadConfirmation: Binding<Bool> {
        Binding(get: { model.voice.downloadConfirmation != nil }, set: { if !$0 { model.voice.downloadConfirmation = nil } })
    }

    private var showsStoreFailure: Binding<Bool> {
        Binding(get: { model.storeFailure != nil }, set: { if !$0 { model.storeFailure = nil } })
    }

    private var showsDeletionConfirmation: Binding<Bool> {
        Binding(get: { model.pendingDeletion != nil }, set: { if !$0 { model.pendingDeletion = nil } })
    }

    private var showsHouseholdDeletionConfirmation: Binding<Bool> {
        Binding(get: { model.pendingHouseholdDeletion != nil }, set: { if !$0 { model.pendingHouseholdDeletion = nil } })
    }

    private var showsHouseholdInputAlert: Binding<Bool> {
        Binding(get: { model.householdInputAlert != nil }, set: { if !$0 { model.householdInputAlert = nil } })
    }

    private var householdInputAlertTitle: Text {
        switch model.householdInputAlert {
        case .question: Text("家族の家計では質問できません")
        case .unclear, nil: Text("記録として読めませんでした")
        }
    }

    /// 家計の共有の知らせを、ホームで出してよいか（ほかの画面を出している間は出せないので、閉じてから出す）。
    private var showsHouseholdNotice: Binding<Bool> {
        Binding(
            get: { model.household?.notice != nil && !model.isPresentingOtherScreen },
            set: { if !$0 { model.household?.notice = nil } }
        )
    }
}

/// 保存先への書き込みの失敗を利用者に知らせる文。
private extension HomeModel.StoreFailure {
    var title: Text {
        switch self {
        case .record: Text("記録できませんでした")
        case .undo: Text("取り消せませんでした")
        case .delete: Text("削除できませんでした")
        }
    }

    var message: Text {
        switch self {
        case .record: Text("保存に失敗しました。もう一度送ってください。")
        case .undo, .delete: Text("保存に失敗しました。もう一度お試しください。")
        }
    }
}

/// 記録のタイムライン。記録した日時の新しいものから `limit` 件を読み、古い順（新しいものが下）に会話の形で並べる。
///
/// 1 回の送信で記録したもの（ひとこと入力の複数件・レシートの品目）を 1 つの送信にまとめ（`EntrySend`。コアの `TimelineSend`）、
/// 送った文を右寄せの自分の吹き出しに、記録したものを左寄せの返事のカード（「記録しました」）に出す。この起動の間に送った質問と
/// その答えも、送った順に同じ流れへ差し込む。先週のふりかえりのカードは、出した日時の位置に差し込む（出したときはいちばん下で、
/// 開いたときに見える。その後に記録すると、その上に流れていく）。暦の日が替わるところには日付の見出しを置く（コアの `TimelineDay`）。
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
    let weeklyRecap: WeeklyRecapModel?
    /// 直前の送信で記録したもの（まだ取り消せるもの）。これを含む送信の返事にだけ「取り消す」を出す。取り消せなければ空。
    let undoableEntryIDs: Set<PersistentIdentifier>
    let showMore: () -> Void
    let undo: () -> Void
    let edit: (Entry) -> Void
    let requestDelete: (Entry) -> Void
    let openReport: (Date) -> Void
    let setBudget: () -> Void
    let openPremium: () -> Void
    let openWeeklyRecap: () -> Void
    let dismissWeeklyRecap: () -> Void

    @Environment(\.calendar) private var calendar
    @Query private var recentEntries: [Entry]

    init(
        limit: Int,
        canShowMore: Bool,
        today: Date,
        questions: [QuestionExchange],
        weeklyRecap: WeeklyRecapModel?,
        undoableEntryIDs: Set<PersistentIdentifier>,
        showMore: @escaping () -> Void,
        undo: @escaping () -> Void,
        edit: @escaping (Entry) -> Void,
        requestDelete: @escaping (Entry) -> Void,
        openReport: @escaping (Date) -> Void,
        setBudget: @escaping () -> Void,
        openPremium: @escaping () -> Void,
        openWeeklyRecap: @escaping () -> Void,
        dismissWeeklyRecap: @escaping () -> Void
    ) {
        self.limit = limit
        self.canShowMore = canShowMore
        self.today = today
        self.questions = questions
        self.weeklyRecap = weeklyRecap
        self.undoableEntryIDs = undoableEntryIDs
        self.showMore = showMore
        self.undo = undo
        self.edit = edit
        self.requestDelete = requestDelete
        self.openReport = openReport
        self.setBudget = setBudget
        self.openPremium = openPremium
        self.openWeeklyRecap = openWeeklyRecap
        self.dismissWeeklyRecap = dismissWeeklyRecap
        _recentEntries = Query(Entry.timelineDescriptor(limit: limit))
    }

    /// タイムラインのやりとりの 1 つ（送信か、質問とその答えか、先週のふりかえり）。
    private enum Exchange {
        case send(EntrySend)
        case question(QuestionExchange)
        case weeklyRecap(WeeklyRecapModel)

        /// 並べる日時。送信は送った日時（記録した日時）、質問は送った日時、ふりかえりは出した日時。日付の見出しもこの日で決める。
        var date: Date {
            switch self {
            case .send(let send): send.sentAt
            case .question(let exchange): exchange.askedAt
            case .weeklyRecap(let recap): recap.shownAt
            }
        }
    }

    /// 画面に並べる 1 つ（日付の見出し・送った文の吹き出し・記録の返事・質問とその答え・先週のふりかえり）。
    private enum Item: Identifiable {
        case day(Date)
        case sentText(EntrySend)
        case reply(EntrySend)
        case question(QuestionExchange)
        case weeklyRecap(WeeklyRecapModel)

        var id: ItemID {
            switch self {
            case .day(let day): .day(day)
            case .sentText(let send): .sentText(send.id)
            case .reply(let send): .reply(send.id)
            case .question(let exchange): .question(exchange.id)
            case .weeklyRecap(let recap): .weeklyRecap(recap.id)
            }
        }
    }

    private enum ItemID: Hashable {
        case day(Date)
        case sentText(PersistentIdentifier)
        case reply(PersistentIdentifier)
        case question(UUID)
        case weeklyRecap(UUID)
    }

    /// 送信と質問とふりかえりを送った順（古いものが上）に並べ、送信を吹き出しと返事に分け、日が替わるところに見出しを置く。
    private var items: [Item] {
        let sends = EntrySend.sends(from: Array(recentEntries.reversed()))
        let exchanges = (sends.map(Exchange.send) + questions.map(Exchange.question)
            + (weeklyRecap.map { [Exchange.weeklyRecap($0)] } ?? []))
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
            case .question(let exchange):
                items.append(.question(exchange))
            case .weeklyRecap(let recap):
                items.append(.weeklyRecap(recap))
            }
        }
        return items
    }

    var body: some View {
        ScrollViewReader { proxy in
            TimelineScrollView {
                if recentEntries.isEmpty && questions.isEmpty && weeklyRecap == nil {
                    EmptyTimelineView()
                }
                // 読み込んだ件数が上限に届いていれば、まだ前の記録があるかもしれない。
                if recentEntries.count >= limit {
                    TimelineOlderRecords(canShowMore: canShowMore, isHousehold: false, showMore: showMore)
                }
                ForEach(items) { item in
                    switch item {
                    case .day(let day):
                        TimelineDayHeader(day: day, today: today)
                    case .sentText(let send):
                        SentTextBubble(send: send)
                    case .reply(let send):
                        RecordedReplyCard(
                            send: send, today: today, canUndo: canUndo(send), undo: undo, edit: edit, requestDelete: requestDelete
                        )
                        // 送信のいちばん下（返事のカード）の位置を知らせる。
                        .reportsTimelineFrame(.row(send.id))
                    case .question(let exchange):
                        QuestionExchangeView(
                            exchange: exchange, openReport: openReport, setBudget: setBudget, openPremium: openPremium
                        )
                        .reportsTimelineFrame(.row(exchange.id))
                    case .weeklyRecap(let recap):
                        WeeklyRecapCard(model: recap, open: openWeeklyRecap, dismiss: dismissWeeklyRecap, setBudget: setBudget)
                            .reportsTimelineFrame(.row(recap.id))
                            // 出し入れの動き（薄く出て消える）はカードにだけ付ける。タイムライン全体に `animation(_:value:)` を
                            // 付けていたときは、カードを出すたびにほかの行とスクロールの位置まで 0.5 秒ほど動きになり、その間に
                            // 見える範囲の高さが変わると（開いた直後の帯の高さが決まるまでなど）、下端からずれて止まりうる
                            // （`TimelineScrollView`。iOS 26.4 のシミュレータでは、下端へ動きなしで送れば全体に付けたままでも
                            // ずれなかった。CI の iOS 27.0 のシミュレータでカードが 2〜3pt ずれた原因の候補として外した）。
                            .transition(.opacity.animation(.default))
                    }
                }
            }
            // 送る先はどれも、いちばん下の行ではなく中身の下端で、動きを付けない（`scrollToTimelineBottom`）。
            // 記録を足した（いちばん新しい記録が替わった）ら、下端まで送る。
            .onChange(of: recentEntries.first?.persistentModelID) { _, id in
                guard id != nil else { return }
                proxy.scrollToTimelineBottom()
            }
            // 質問を送ったときと、返事が届いた（カードが伸びた）ときに、下端まで送る。
            .onChange(of: questions.last) { _, exchange in
                guard exchange != nil else { return }
                proxy.scrollToTimelineBottom()
            }
            // 開いたまま週が替わってふりかえりのカードが出たら、下端まで送る（開いたときは下端から開くので、そのまま見える）。
            .onChange(of: weeklyRecap?.id) { _, id in
                guard id != nil else { return }
                proxy.scrollToTimelineBottom()
            }
        }
    }

    /// この送信の返事に「取り消す」を出すか（直前の送信で記録したもので、まだ取り消せるものを含む）。
    private func canUndo(_ send: EntrySend) -> Bool {
        !undoableEntryIDs.isEmpty && send.entries.contains { undoableEntryIDs.contains($0.persistentModelID) }
    }
}

/// 家族の家計のタイムライン（「家族」のとき）。家計の記録を、記録した日時の新しいものから `limit` 件読み、古い順に並べる。
/// 吹き出しには記録した人の名前を添える。押すと直し（ほかの人の記録も）、長押しで削除できる。
///
/// 家計の記録は送った文を持たないので、自分の記録のタイムラインのような会話の形（送った文と返事のカード）にはしていない
/// （記録ごとの吹き出しのまま。会話の形にするかは docs/design.md §15 のあとの作業）。記録の直後の「取り消す」だけは、下の
/// バナーをやめたので、直前に記録した吹き出し（複数件ならいちばん新しいもの）のすぐ下に出す（`HouseholdUndoRow`）。
///
/// 家計の保存先（household.store）を読むので、呼び出し側が家計の保存先を環境に渡す（`.modelContainer`）。
private struct HouseholdTimeline: View {
    let limit: Int
    /// 「前の記録を表示」でさらに読み込めるか（読み込む件数が上限に届いていなければ）。
    let canShowMore: Bool
    let today: Date
    /// 直前に家計へ記録したもの（まだ取り消せるもの）の id。その吹き出しの下に「取り消す」を出す。取り消せなければ空。
    let undoableEntryIDs: Set<UUID>
    let showMore: () -> Void
    let undo: () -> Void
    let edit: (HouseholdEntry) -> Void
    let requestDelete: (HouseholdEntry) -> Void

    @Query private var recentEntries: [HouseholdEntry]

    init(
        zoneName: String,
        limit: Int,
        canShowMore: Bool,
        today: Date,
        undoableEntryIDs: Set<UUID>,
        showMore: @escaping () -> Void,
        undo: @escaping () -> Void,
        edit: @escaping (HouseholdEntry) -> Void,
        requestDelete: @escaping (HouseholdEntry) -> Void
    ) {
        self.limit = limit
        self.canShowMore = canShowMore
        self.today = today
        self.undoableEntryIDs = undoableEntryIDs
        self.showMore = showMore
        self.undo = undo
        self.edit = edit
        self.requestDelete = requestDelete
        _recentEntries = Query(HouseholdEntry.timelineDescriptor(zoneName: zoneName, limit: limit))
    }

    /// 「記録しました 取り消す」の行を下に置く吹き出し（直前に記録したもののうち、いちばん新しいもの）。
    ///
    /// いちばん下の吹き出しの下に置かないのは、「取り消す」は次の文を送るまで出したままなので、その間に家族の記録が同期で
    /// 届くと、ほかの人の記録の下に「記録しました 取り消す」が並び、その記録を取り消すように見えるため（押すと消えるのは自分の記録）。
    private var undoRowAnchor: UUID? {
        guard !undoableEntryIDs.isEmpty else { return nil }
        return recentEntries.first { undoableEntryIDs.contains($0.id) }?.id
    }

    var body: some View {
        let undoRowAnchor = undoRowAnchor
        ScrollViewReader { proxy in
            TimelineScrollView {
                if recentEntries.isEmpty {
                    HouseholdEmptyTimelineView()
                }
                if recentEntries.count >= limit {
                    TimelineOlderRecords(canShowMore: canShowMore, isHousehold: true, showMore: showMore)
                }
                ForEach(recentEntries.reversed()) { entry in
                    EntryBubble(
                        entry: entry, today: today, edit: { edit(entry) }, requestDelete: { requestDelete(entry) },
                        recorderName: entry.recorderName
                    )
                    .reportsTimelineFrame(.row(entry.id))
                    if entry.id == undoRowAnchor {
                        HouseholdUndoRow(undo: undo)
                            .reportsTimelineFrame(.householdUndo)
                    }
                }
            }
            // いちばん新しい家計の記録が替わったら、下端まで送る（行ではなく中身の下端で、動きを付けない。`scrollToTimelineBottom`）。
            .onChange(of: recentEntries.first?.id) { _, id in
                guard id != nil else { return }
                proxy.scrollToTimelineBottom()
            }
        }
    }
}

/// 家計のタイムラインの、記録の直後の「記録しました」と「取り消す」（直前に記録した吹き出しの下に右寄せで出す）。
/// 時間では引っ込めない（次の文を送る・取り消す・その記録を直す・記録先を切り替えるまで。自分の記録の返事と同じ）。
private struct HouseholdUndoRow: View {
    let undo: () -> Void

    var body: some View {
        // 1 行に収まらなければ（アクセシビリティサイズの文字）、「取り消す」を下の行に右寄せで置く。HStack のままだと、AX5 で
        // 「記録しました」が語の途中で折り返され、「取り消す」が「取り…」に切れた。
        AdaptiveRowLayout(stacksWhenNeeded: true, spacing: 12, stackAlignment: .trailing) {
            Text("記録しました")
                .foregroundStyle(Theme.inkSecondary)
            Button(action: undo) {
                Text("取り消す")
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.accentText)
                    .lineLimit(1)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect)
            }
            .accessibilityHint("記録を消して、送った文を入力欄に戻します")
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// タイムラインの上の端（読み込んだ件数が上限に届いていて、まだ前の記録があるかもしれないとき）。
///
/// 読み込む件数を増やせるうちは「前の記録を表示」を出す。上限（`HomeModel.timelineMaxLimit`）に届いたら、代わりにそれより前の
/// 記録の見方を案内する。タイムラインは読み込んだ行をすべて描き直すので、上限なしに読み足すと、記録を足すたび・前面に戻るたびに
/// 引っかかるようになるため（`TimelineScrollView`）。
private struct TimelineOlderRecords: View {
    let canShowMore: Bool
    /// 家計の記録のタイムラインか。家計の記録は月のまとめにも CSV の書き出しにも出ない（v1 は「自分」だけ）ので、ほかで見られるとは
    /// 案内しない。
    let isHousehold: Bool
    let showMore: () -> Void

    var body: some View {
        if canShowMore {
            Button("前の記録を表示", action: showMore)
                .font(.subheadline)
                .frame(minHeight: 44)
        } else {
            Group {
                if isHousehold {
                    Text("ホームに出せるのは、新しく記録した方から \(HomeModel.timelineMaxLimit) 件までです。")
                } else {
                    Text("ホームに出せるのは、新しく記録した方から \(HomeModel.timelineMaxLimit) 件までです。それより前の記録は、月のまとめのカテゴリの一覧と、設定の「記録を書き出す」で見られます。")
                }
            }
            .font(.footnote)
            .foregroundStyle(Theme.inkSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }
}

/// タイムラインのスクロール（自分の記録と家計の記録で共通）。下端から開き、いちばん新しいものを入力欄のすぐ上に出す。
///
/// 行は LazyVStack ではなく、すべての行を測る並べ方（`TimelineStack`。VStack と同じ位置に置く）に並べる。LazyVStack は、まだ
/// 描いていない行の高さを、そのとき描いている行から見積もる。
/// タイムラインの行は高さがそろわない（送った文の吹き出し・品目の数だけ伸びる返事のカード・回答カード・ふりかえりのカード）ので、描く行が替わるたびに
/// 全体の高さの見積もりが大きく揺れる。下端に合わせる（`defaultScrollAnchor(.bottom)`）と、揺れるたびに位置も同じだけ動いて
/// 描く行がまた替わり、見える範囲に行が 1 つも無い位置で止まることがあった。開いたときにタイムラインが空に見えた不具合で、
/// 見える行が少なく見積もりが数行で決まる大きな文字で起きた（シミュレータで、見積もりが 1 万 pt ほど揺れ、行を描かないまま
/// 止まるのを確かめた。どの文字の大きさで起きるかは記録の中身と画面の幅で変わる）。途中で止まって、いちばん下の行が入力欄に
/// 隠れることもあった（先週のふりかえりのカード）。すべての行を測れば全体の高さが正しく、下端に正しく合う。
///
/// すべての行を測るぶん開くときの手間は件数に比例するので、読み込む件数を `HomeModel.timelinePageSize` で区切る。
/// 読み込んだ行は、記録の追加・削除や同期の取り込み、前面に戻ったときにもすべて描き直すので、「前の記録を表示」で読み足せる件数にも
/// 上限（`HomeModel.timelineMaxLimit`）を設ける。
///
/// 開いた後にいちばん新しいものを足したとき（送信の返事・質問・ふりかえりのカード・家計の記録）は、中身の本当の下端に置いた目印
/// （`TimelineBottomMarker`）まで、動きを付けずに送る（`ScrollViewProxy.scrollToTimelineBottom`）。
/// - 行の id で下端に合わせると、行の下の端が見える範囲の下の端にそろい、その下の余白（`padding()` の 16pt）が見える範囲の外に
///   隠れた（中身が画面より高いときだけ。開いたときと、当時あった「取り消す」のバナーが引っ込んだ後は余白が見えるので、送った
///   直後だけ行が入力欄に寄って見えた）。目印は `defaultScrollAnchor(.bottom)` と同じ位置を指すので、二つの合わせ方が食い違わない。
/// - 動きを付けると、送り先の位置が送り始めたときの見える範囲の高さで決まり、動いている間はその位置に向かい続ける。同じときに
///   見える範囲の高さが変わると（声の入力の知らせ。当時は送った記録と一緒に出た「取り消す」のバナーも）、`defaultScrollAnchor(.bottom)`
///   が下端に合わせ直す分が打ち消され、変わった分だけ下端からずれて止まった（シミュレータの iOS 26.4 で、送った記録が見える範囲の
///   下に 36〜129pt はみ出し、声の入力の知らせと同時に出たふりかえりのカードは AX1 と AX5 で 400pt 以上下に隠れた）。動きなしで
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
/// いちばん新しいもの（送信の返事・質問・ふりかえりのカード・家計の記録）はいつもいちばん下に並ぶので、下端まで送れば見える。
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
    /// 行。送信の返事のカードは送信の `id`（送信のいちばん古い記録の `persistentModelID`）、家計の記録・質問・ふりかえりは `id`。
    case row(AnyHashable)
    /// 家計のタイムラインの、記録の直後の「記録しました 取り消す」の行（`HouseholdUndoRow`）。
    case householdUndo
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

/// 家族の家計にまだ記録が無いときの案内。
private struct HouseholdEmptyTimelineView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("家族の家計")
                .font(.title2.bold())
            Text("下の入力欄に送ると、家族と共有している家計に記録します。家族が記録したものも、ここに並びます。自分の記録は帯の「自分」に切り替えると見られます。")
                .foregroundStyle(Theme.inkSecondary)
        }
        .foregroundStyle(Theme.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 24)
    }
}

/// 記録が 1 件も無いときの案内。入力の例を見せて、何を書けばよいかを伝える。質問も同じ入力欄からできることを添える。
private struct EmptyTimelineView: View {
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
                Text(verbatim: example)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.surface, in: .rect(cornerRadius: 12))
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
