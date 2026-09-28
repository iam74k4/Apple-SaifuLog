import SaifuLogCore
import SwiftData
import SwiftUI
import UIKit

/// ホーム。今月の合計、記録のタイムライン、入力欄を 1 画面に置く。
///
/// 記録も（将来は）質問も同じ入力欄から行う。入口を分けると「どこに書けばいいか」を
/// 利用者に考えさせることになるため。
struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControlEnabled

    @State private var draft = ""
    @State private var isParsing = false
    /// 直前に記録したもの。記録の直後に「取り消す」を出すため。
    @State private var justRecorded: [Entry] = []
    @State private var showsNoAmountAlert = false
    @State private var storeFailure: StoreFailure?
    @State private var pendingDeletion: PendingDeletion?
    /// 今日。「今月」の範囲と、日付に年を添えるかの基準にする。
    ///
    /// 描画のたびに `.now` を読むだけだと、アプリを開いたまま（または裏に置いたまま）月をまたいだとき、
    /// 描き直しが起きずに前の月の合計が「今月」として出続ける。前面に戻ったときと日付が変わったときに更新する。
    @State private var today = Date.now
    /// タイムラインに読み込む件数。上の「前の記録を表示」で増やす。
    @State private var timelineLimit = EntryTimeline.pageSize

    /// 支援技術（VoiceOver・スイッチコントロール）を使っているときは、「取り消す」を自動で引っ込めない。
    /// 8 秒では、バナーまでたどり着く前に消えてしまうため。次の記録を送るか、取り消すか、「閉じる」の操作で消える。
    private var keepsUndoBanner: Bool {
        voiceOverEnabled || switchControlEnabled
    }

    private var store: EntryStore {
        EntryStore(context: modelContext)
    }

    var body: some View {
        NavigationStack {
            timeline
                .toolbar(.hidden, for: .navigationBar)
                .alert("金額が見つかりませんでした", isPresented: $showsNoAmountAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("「ランチ 850」のように、金額の数字を入れてください。")
                }
                .alert(
                    storeFailure?.title ?? Text(verbatim: ""),
                    isPresented: showsStoreFailure,
                    presenting: storeFailure
                ) { _ in
                    Button("OK", role: .cancel) {}
                } message: { failure in
                    failure.message
                }
                .confirmationDialog(
                    "この記録を削除しますか？",
                    isPresented: showsDeletionConfirmation,
                    titleVisibility: .visible,
                    presenting: pendingDeletion
                ) { pending in
                    Button("削除", role: .destructive) { delete(pending) }
                } message: { pending in
                    Text("\(pending.summary)の記録を削除します。この操作は取り消せません。")
                }
                // 「取り消す」は記録の直後だけのもの。しばらくしたら引っ込め、タイムラインを広く使う。
                // 支援技術を使い始めたときにも数え直す（id に含める）と、途中で引っ込むことがない。
                .task(id: undoBannerSchedule) {
                    guard !justRecorded.isEmpty, !keepsUndoBanner else { return }
                    try? await Task.sleep(for: .seconds(8))
                    if !Task.isCancelled { justRecorded = [] }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { today = .now }
                }
                // 日付が変わったとき（0 時・時間帯の変更など）。前面に置いたまま月をまたいでも合計を切り替える。
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                    today = .now
                }
        }
    }

    private var timeline: some View {
        EntryTimeline(
            limit: timelineLimit,
            today: today,
            showMore: { timelineLimit += EntryTimeline.pageSize },
            requestDelete: { entry in
                pendingDeletion = PendingDeletion(entry: entry, summary: entry.summaryText)
            }
        )
        .background(Theme.background)
        .safeAreaInset(edge: .top, spacing: 0) {
            MonthSummaryHeader(month: today, calendar: calendar)
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
            if !justRecorded.isEmpty {
                UndoBanner(undo: undoLastRecord, dismiss: { justRecorded = [] })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            InputBar(text: $draft, isSending: isParsing, send: send, undo: undoAction)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .animation(.default, value: justRecorded.isEmpty)
    }

    /// 入力欄の「直前の記録を取り消す」の操作。取り消せるものがあるときだけ渡す。
    private var undoAction: (() -> Void)? {
        if justRecorded.isEmpty { return nil }
        return { undoLastRecord() }
    }

    private var showsStoreFailure: Binding<Bool> {
        Binding(get: { storeFailure != nil }, set: { if !$0 { storeFailure = nil } })
    }

    private var showsDeletionConfirmation: Binding<Bool> {
        Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })
    }

    private var undoBannerSchedule: UndoBannerSchedule {
        UndoBannerSchedule(ids: justRecorded.map(\.persistentModelID), keepsOpen: keepsUndoBanner)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isParsing else { return }
        isParsing = true
        // 送った時点で入力欄を空ける。解析（AI だと 1 秒以上かかることがある）を待ってから空けると、
        // 入力欄にとどまって打ち始めた次の入力まで、黙って消してしまうため。
        draft = ""
        Task {
            defer { isParsing = false }
            let parsed = (try? await EntryParserFactory.makeParser().parse(text)) ?? []
            guard !parsed.isEmpty else {
                // 送った文を入力欄に戻し、その場で直せるようにする。ただし解析の間に次の入力を
                // 打ち始めていたら、そちらを上書きしない。
                if draft.isEmpty { draft = text }
                showsNoAmountAlert = true
                return
            }
            let recorded = Entry.records(from: parsed, originalText: text, source: .text, now: .now, calendar: calendar)
            do {
                try store.insert(recorded)
            } catch {
                // 保存できなかった。記録したことにはせず、送った文を戻して送り直せるようにする。
                if draft.isEmpty { draft = text }
                storeFailure = .record
                return
            }
            justRecorded = recorded
            announce(recorded)
        }
    }

    /// 何円をどのカテゴリに記録したかを VoiceOver に読み上げさせる。
    ///
    /// 「記録しました / 取り消す」のバナーは、画面に出ても VoiceOver では読まれない。読み上げないと、
    /// VoiceOver の利用者は記録できたかも、AI がどう読んだかも分からず、読み違いにその場で気づけない。
    /// 今日でない日付に記録したときは日付も読む（「昨日」の読み違いや、未来の日付に気づけるように）。
    private func announce(_ recorded: [Entry]) {
        let items = recorded.map { entry in
            var item = "\(entry.kindText) \(YenFormatter.string(from: entry.amount))"
            if !calendar.isDate(entry.spentAt, inSameDayAs: .now) {
                let format: Date.FormatStyle = entry.showsYear(today: .now, calendar: calendar)
                    ? .dateTime.year().month().day() : .dateTime.month().day()
                item += " \(entry.spentAt.formatted(format))"
            }
            return item
        }
        announce(String(localized: "記録しました: \(items.formatted(.list(type: .and)))"))
    }

    private func announce(_ text: String) {
        var message = AttributedString(text)
        // 操作の後は入力欄などにフォーカスが移り、その読み上げに割り込まれて結果が聞こえないことがあるので、優先して読ませる。
        message.accessibilitySpeechAnnouncementPriority = .high
        AccessibilityNotification.Announcement(message).post()
    }

    private func undoLastRecord() {
        let targets = justRecorded
        guard !targets.isEmpty else { return }
        // 消した記録の値は、保存した後には読めない。読み上げと入力欄に戻す文は先に取っておく。
        let items = targets.map { "\($0.kindText) \(YenFormatter.string(from: $0.amount))" }
        let originalText = targets.first?.originalText ?? ""
        do {
            try store.delete(targets)
        } catch {
            // バナーは残し、もう一度押せるようにする。
            storeFailure = .undo
            return
        }
        justRecorded = []
        // 元の文を入力欄に戻し、その場で直して送り直せるようにする。打ち始めた次の入力は上書きしない。
        if draft.isEmpty { draft = originalText }
        announce(String(localized: "取り消しました: \(items.formatted(.list(type: .and)))"))
    }

    private func delete(_ pending: PendingDeletion) {
        let id = pending.entry.persistentModelID
        do {
            try store.delete([pending.entry])
        } catch {
            storeFailure = .delete
            return
        }
        justRecorded.removeAll { $0.persistentModelID == id }
        announce(String(localized: "削除しました: \(pending.summary)"))
    }
}

/// 削除の確認を待っている記録。確認の文は先に作っておく（消した後の記録の値は読めないため）。
private struct PendingDeletion {
    let entry: Entry
    let summary: String
}

/// 「取り消す」を引っ込めるタイマーの数え直しの条件。
private struct UndoBannerSchedule: Hashable {
    var ids: [PersistentIdentifier]
    var keepsOpen: Bool
}

/// 保存先への書き込みの失敗。利用者に知らせ、記録したつもり・消したつもりにさせない。
private enum StoreFailure {
    case record
    case undo
    case delete

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
    static let pageSize = 200

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
    HomeView()
        .modelContainer(for: Entry.self, inMemory: true)
}
