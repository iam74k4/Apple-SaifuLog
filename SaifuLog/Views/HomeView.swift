import SaifuLogCore
import SwiftData
import SwiftUI
import UIKit

/// ホーム。今月の合計、記録のタイムライン、入力欄を 1 画面に置く。
///
/// 記録も（将来は）質問も同じ入力欄から行う。入口を分けると「どこに書けばいいか」を
/// 利用者に考えさせることになるため。
///
/// 状態と操作（送信・取り消し・削除・予算を決める画面の出し入れ）は `HomeModel` が持つ。ここは表示と、
/// 環境（文字の大きさ・支援技術・前面かどうか）に合わせた出し方だけを受け持つ。
struct HomeView: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControlEnabled

    @State private var model: HomeModel

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
                .task(id: undoBannerSchedule) {
                    guard model.canUndo, !keepsUndoBanner else { return }
                    try? await Task.sleep(for: .seconds(8))
                    if !Task.isCancelled { model.dismissUndo() }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.refreshToday() }
                }
                // 日付が変わったとき（0 時・時間帯の変更など）。前面に置いたまま月をまたいでも合計を切り替える。
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                    model.refreshToday()
                }
        }
    }

    private var timeline: some View {
        EntryTimeline(
            limit: model.timelineLimit,
            today: model.today,
            showMore: { model.showMoreTimeline() },
            requestDelete: { model.requestDelete($0) }
        )
        .background(Theme.background)
        .safeAreaInset(edge: .top, spacing: 0) {
            MonthSummaryHeader(today: model.today, calendar: calendar, editBudget: { model.presentBudgetSetup() })
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
                UndoBanner(undo: { model.undoLastRecord() }, dismiss: { model.dismissUndo() })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            InputBar(text: $model.draft, isSending: model.isParsing, send: { model.send(calendar: calendar) }, undo: undoAction)
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
        UndoBannerSchedule(ids: model.justRecorded.map(\.persistentModelID), keepsOpen: keepsUndoBanner)
    }
}

/// 「取り消す」を引っ込めるタイマーの数え直しの条件。
private struct UndoBannerSchedule: Hashable {
    var ids: [PersistentIdentifier]
    var keepsOpen: Bool
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
///
/// 全期間を読むと、記録が増えるほど開くのも描き直すのも遅くなる。読み込む件数は `limit` で区切り、
/// さかのぼりたいときは上の「前の記録を表示」で増やす。
private struct EntryTimeline: View {
    let limit: Int
    let today: Date
    let showMore: () -> Void
    let requestDelete: (Entry) -> Void

    @Query private var recentEntries: [Entry]

    init(limit: Int, today: Date, showMore: @escaping () -> Void, requestDelete: @escaping (Entry) -> Void) {
        self.limit = limit
        self.today = today
        self.showMore = showMore
        self.requestDelete = requestDelete
        _recentEntries = Query(Entry.timelineDescriptor(limit: limit))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if recentEntries.isEmpty {
                        EmptyTimelineView()
                    }
                    // 読み込んだ件数が上限に届いていれば、まだ前の記録があるかもしれない。
                    if recentEntries.count >= limit {
                        Button("前の記録を表示", action: showMore)
                            .font(.subheadline)
                            .frame(minHeight: 44)
                    }
                    ForEach(recentEntries.reversed()) { entry in
                        EntryBubble(entry: entry, today: today) { requestDelete(entry) }
                            .id(entry.persistentModelID)
                    }
                }
                .padding()
            }
            // 下端に合わせておくと、前の記録を読み足しても見ている位置がずれない。
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: recentEntries.first?.persistentModelID) { _, id in
                guard let id else { return }
                withAnimation { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
    }
}

/// 記録が 1 件も無いときの案内。入力の例を見せて、何を書けばよいかを伝える。
private struct EmptyTimelineView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ひとことで記録")
                .font(.title2.bold())
            Text("下の入力欄に、こんなふうに送るだけで記録できます。")
                .foregroundStyle(Theme.inkSecondary)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Self.examples, id: \.self) { example in
                    Text(verbatim: example)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Theme.surface, in: .rect(cornerRadius: 12))
                }
            }
        }
        .foregroundStyle(Theme.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 24)
    }

    /// 入力の例は日本語のまま見せる（解析が日本語の入力を前提にしているため、訳さない）。
    private static let examples = ["ランチ 850", "昨日 焼肉12000 4人で割り勘", "給料 25万"]
}

#Preview {
    // プレビューも、アプリとテストと同じ作り方の保存先（iCloud を切った、メモリの上だけのもの）を使う。
    if let container = try? ModelContainerFactory.makeInMemoryContainer() {
        HomeView(model: HomeModel(context: container.mainContext))
            .modelContainer(container)
    }
}
