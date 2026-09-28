import SaifuLogCore
import SwiftData
import SwiftUI
import UIKit

/// ホーム。今月の合計、記録のタイムライン、入力欄を 1 画面に置く。
///
/// 記録も質問も同じ入力欄から行う。入口を分けると「どこに書けばいいか」を利用者に考えさせることになるため。
/// 質問とその返事は、記録の吹き出しと同じタイムラインに送った順で出す（保存はしない）。
///
/// 週が替わって最初に開いたときは、先週のふりかえりのカードも同じタイムラインに出す（アプリからの返事として、出した時点の位置に）。
///
/// 状態と操作（送信・質問・取り消し・直す・削除・予算を決める画面と月のまとめと設定とプレミアムの出し入れ・先週のふりかえり）は
/// `HomeModel` が持つ。ここは表示と、
/// 環境（文字の大きさ・支援技術・前面かどうか）に合わせた出し方だけを受け持つ。
struct HomeView: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControlEnabled

    @State private var model: HomeModel
    #if DEBUG || INTERNAL_DIAGNOSTICS
    /// 診断画面を出しているか。社内テスト用のビルドと DEBUG だけの画面なので、App Store へ出すビルドにも入る
    /// `HomeModel` には持たせず、ここに置く。
    @State private var showsDiagnostics = false
    @Environment(\.modelContext) private var modelContext
    #endif

    init(model: HomeModel) {
        _model = State(initialValue: model)
    }

    /// 支援技術（VoiceOver・スイッチコントロール）を使っているときは、「取り消す」を自動で引っ込めない。
    /// 8 秒では、バナーまでたどり着く前に消えてしまうため。次の記録を送るか、取り消すか、「閉じる」の操作で消える。
    private var keepsUndoBanner: Bool {
        voiceOverEnabled || switchControlEnabled
    }

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
                    model.showWeeklyRecapIfDue(calendar: calendar)
                }
                // 週の始まりの設定を変えると画面の暦が変わるので、変えた後の週で決め直す。
                .onChange(of: calendar) { _, calendar in
                    model.showWeeklyRecapIfDue(calendar: calendar)
                }
                // 保存先に書き込まれたら、ふりかえりのカード（と内訳）の数字を読み直す（先週の日付で記録したり、直したりしたとき）。
                .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
                    model.weeklyRecap?.reload()
                }
                #if DEBUG || INTERNAL_DIAGNOSTICS
                .sheet(isPresented: $showsDiagnostics) {
                    DiagnosticsView(model: DiagnosticsModel(context: modelContext))
                }
                // 帯の右上に診断のボタンを出させる（渡さなければ出ない）。
                .environment(\.openDiagnostics, OpenDiagnosticsAction { showsDiagnostics = true })
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
                // 「取り消す」は記録の直後だけのもの。しばらくしたら引っ込め、タイムラインを広く使う。
                // 支援技術を使い始めたときにも数え直す（id に含める）と、途中で引っ込むことがない。
                // 「直す」のシートと保存の失敗のアラートを出している間は止め、閉じたら 8 秒を数え直す（`HomeModel.autoHidesUndo`）。
                .task(id: undoBannerSchedule) {
                    guard model.autoHidesUndo, !keepsUndoBanner else { return }
                    try? await Task.sleep(for: .seconds(8))
                    if !Task.isCancelled { model.dismissUndo() }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        model.refreshToday()
                        // 状態が変わらなくても、前面に戻ったときには確かめる（ほかの画面を閉じた後で出せるように）。
                        model.presentPremiumIfTrialEnded()
                        model.showWeeklyRecapIfDue(calendar: calendar)
                    }
                }
                // 日付が変わったとき（0 時・時間帯の変更など）。前面に置いたまま月をまたいでも合計を切り替える。
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                    model.refreshToday()
                    model.showWeeklyRecapIfDue(calendar: calendar)
                }
        }
    }

    private var timeline: some View {
        EntryTimeline(
            limit: model.timelineLimit,
            today: model.today,
            questions: model.questions,
            weeklyRecap: model.weeklyRecap,
            showMore: { model.showMoreTimeline() },
            edit: { model.presentEdit($0, calendar: calendar) },
            requestDelete: { model.requestDelete($0) },
            openReport: { model.presentMonthlyReport(calendar: calendar, month: $0) },
            setBudget: { model.presentBudgetSetup() },
            openPremium: { model.presentPremium() },
            openWeeklyRecap: { model.presentWeeklyRecapDetail() },
            dismissWeeklyRecap: { model.dismissWeeklyRecap() }
        )
        .background(Theme.background)
        .safeAreaInset(edge: .top, spacing: 0) {
            MonthSummaryHeader(
                today: model.today,
                calendar: calendar,
                editBudget: { model.presentBudgetSetup() },
                openReport: { model.presentMonthlyReport(calendar: calendar) },
                openSettings: { model.presentSettings() }
            )
                // 合計は画面の上に常に出ている帯なので、文字の大きさに上限を設ける。最大の文字サイズの
                // ままだと、下の入力欄と合わせて画面の半分以上を占め、タイムラインがほとんど見えなくなるため。
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if model.canUndo {
                UndoBanner(
                    recorded: model.justRecorded,
                    edit: { model.presentEdit($0, calendar: calendar) },
                    undo: { model.undoLastRecord() },
                    dismiss: { model.dismissUndo() }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            InputBar(
                text: $model.draft,
                isSending: model.isParsing,
                send: { model.send(calendar: calendar) },
                undo: undoAction,
                recorded: model.justRecorded,
                edit: { model.presentEdit($0, calendar: calendar) }
            )
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .animation(.default, value: model.canUndo)
    }

    /// 入力欄の「直前の記録を取り消す」の操作。取り消せるものがあるときだけ渡す。
    private var undoAction: (() -> Void)? {
        guard model.canUndo else { return nil }
        return { model.undoLastRecord() }
    }

    private var showsStoreFailure: Binding<Bool> {
        Binding(get: { model.storeFailure != nil }, set: { if !$0 { model.storeFailure = nil } })
    }

    private var showsDeletionConfirmation: Binding<Bool> {
        Binding(get: { model.pendingDeletion != nil }, set: { if !$0 { model.pendingDeletion = nil } })
    }

    private var undoBannerSchedule: UndoBannerSchedule {
        UndoBannerSchedule(
            ids: model.justRecorded.map(\.persistentModelID),
            keepsOpen: keepsUndoBanner,
            isEditing: model.editing != nil,
            showsStoreFailure: model.storeFailure != nil
        )
    }
}

/// 「取り消す」を引っ込めるタイマーの数え直しの条件。
private struct UndoBannerSchedule: Hashable {
    var ids: [PersistentIdentifier]
    var keepsOpen: Bool
    /// 「直す」のシートを出しているか。出したときにタイマーを止め、閉じたときに数え直すため。
    var isEditing: Bool
    /// 保存の失敗のアラートを出しているか。「直す」のシートと同じく、出している間は止め、閉じたら数え直す。
    var showsStoreFailure: Bool
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

/// 記録のタイムライン。記録した日時の新しいものから `limit` 件を読み、古い順（新しいものが下）に並べる。
/// この起動の間に送った質問とその返事も、送った順に同じ流れへ差し込む。先週のふりかえりのカードは、出した日時の位置に差し込む
/// （出したときはいちばん下で、開いたときに見える。その後に記録すると、その上に流れていく）。
///
/// 全期間を読むと、記録が増えるほど開くのも描き直すのも遅くなる。読み込む件数は `limit` で区切り、
/// さかのぼりたいときは上の「前の記録を表示」で増やす。
private struct EntryTimeline: View {
    let limit: Int
    let today: Date
    let questions: [QuestionExchange]
    let weeklyRecap: WeeklyRecapModel?
    let showMore: () -> Void
    let edit: (Entry) -> Void
    let requestDelete: (Entry) -> Void
    let openReport: (Date) -> Void
    let setBudget: () -> Void
    let openPremium: () -> Void
    let openWeeklyRecap: () -> Void
    let dismissWeeklyRecap: () -> Void

    @Query private var recentEntries: [Entry]

    init(
        limit: Int,
        today: Date,
        questions: [QuestionExchange],
        weeklyRecap: WeeklyRecapModel?,
        showMore: @escaping () -> Void,
        edit: @escaping (Entry) -> Void,
        requestDelete: @escaping (Entry) -> Void,
        openReport: @escaping (Date) -> Void,
        setBudget: @escaping () -> Void,
        openPremium: @escaping () -> Void,
        openWeeklyRecap: @escaping () -> Void,
        dismissWeeklyRecap: @escaping () -> Void
    ) {
        self.limit = limit
        self.today = today
        self.questions = questions
        self.weeklyRecap = weeklyRecap
        self.showMore = showMore
        self.edit = edit
        self.requestDelete = requestDelete
        self.openReport = openReport
        self.setBudget = setBudget
        self.openPremium = openPremium
        self.openWeeklyRecap = openWeeklyRecap
        self.dismissWeeklyRecap = dismissWeeklyRecap
        _recentEntries = Query(Entry.timelineDescriptor(limit: limit))
    }

    /// タイムラインの 1 つ（記録か、質問とその返事か、先週のふりかえり）。
    private enum Item: Identifiable {
        case entry(Entry)
        case question(QuestionExchange)
        case weeklyRecap(WeeklyRecapModel)

        var id: ItemID {
            switch self {
            case .entry(let entry): .entry(entry.persistentModelID)
            case .question(let exchange): .question(exchange.id)
            case .weeklyRecap(let recap): .weeklyRecap(recap.id)
            }
        }

        /// 並べる日時。記録は記録した日時（送った順）、質問は送った日時、ふりかえりは出した日時。
        var date: Date {
            switch self {
            case .entry(let entry): entry.createdAt
            case .question(let exchange): exchange.askedAt
            case .weeklyRecap(let recap): recap.shownAt
            }
        }
    }

    private enum ItemID: Hashable {
        case entry(PersistentIdentifier)
        case question(UUID)
        case weeklyRecap(UUID)
    }

    /// 記録と質問とふりかえりを、送った順（古いものが上）に並べる。
    private var items: [Item] {
        (recentEntries.map(Item.entry) + questions.map(Item.question) + (weeklyRecap.map { [Item.weeklyRecap($0)] } ?? []))
            .sorted { $0.date < $1.date }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if recentEntries.isEmpty && questions.isEmpty && weeklyRecap == nil {
                        EmptyTimelineView()
                    }
                    // 読み込んだ件数が上限に届いていれば、まだ前の記録があるかもしれない。
                    if recentEntries.count >= limit {
                        Button("前の記録を表示", action: showMore)
                            .font(.subheadline)
                            .frame(minHeight: 44)
                    }
                    ForEach(items) { item in
                        switch item {
                        case .entry(let entry):
                            EntryBubble(entry: entry, today: today, edit: { edit(entry) }, requestDelete: { requestDelete(entry) })
                                .id(item.id)
                        case .question(let exchange):
                            QuestionExchangeView(
                                exchange: exchange, openReport: openReport, setBudget: setBudget, openPremium: openPremium
                            )
                            .id(item.id)
                        case .weeklyRecap(let recap):
                            WeeklyRecapCard(model: recap, open: openWeeklyRecap, dismiss: dismissWeeklyRecap, setBudget: setBudget)
                                .id(item.id)
                                .transition(.opacity)
                        }
                    }
                }
                .padding()
            }
            // 下端に合わせておくと、前の記録を読み足しても見ている位置がずれない。
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: recentEntries.first?.persistentModelID) { _, id in
                guard let id else { return }
                withAnimation { proxy.scrollTo(ItemID.entry(id), anchor: .bottom) }
            }
            // 質問を送ったときと、返事が届いた（カードが伸びた）ときに、いちばん下の質問まで送る。
            .onChange(of: questions.last) { _, exchange in
                guard let exchange else { return }
                withAnimation { proxy.scrollTo(ItemID.question(exchange.id), anchor: .bottom) }
            }
            // 開いたまま週が替わってふりかえりのカードが出たら、そこまで送る（開いたときは下端から開くので、そのまま見える）。
            .onChange(of: weeklyRecap?.id) { _, id in
                guard let id else { return }
                withAnimation { proxy.scrollTo(ItemID.weeklyRecap(id), anchor: .bottom) }
            }
            .animation(.default, value: weeklyRecap?.id)
        }
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
