import SaifuLogCore
import SwiftData
import SwiftUI

/// ホーム。今月の合計、記録のタイムライン、入力欄を 1 画面に置く。
///
/// 記録も（将来は）質問も同じ入力欄から行う。入口を分けると「どこに書けばいいか」を
/// 利用者に考えさせることになるため。
struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar

    /// 送った順（チャットと同じく新しいものが下）。
    @Query(sort: \Entry.createdAt) private var entries: [Entry]

    @State private var draft = ""
    @State private var isParsing = false
    /// 直前に記録したもの。記録の直後に「取り消す」を出すため。
    @State private var justRecorded: [Entry] = []
    @State private var showsNoAmountAlert = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if entries.isEmpty {
                            EmptyTimelineView()
                        }
                        ForEach(entries) { entry in
                            EntryBubble(entry: entry)
                                .id(entry.persistentModelID)
                        }
                    }
                    .padding()
                }
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: entries.last?.persistentModelID) { _, id in
                    guard let id else { return }
                    withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
            .background(Theme.background)
            .safeAreaInset(edge: .top, spacing: 0) {
                SummaryHeader(summary: MonthlySummary(records: entries, month: .now, calendar: calendar))
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 8) {
                    if !justRecorded.isEmpty {
                        UndoBanner(undo: undoLastRecord)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    InputBar(text: $draft, isSending: isParsing, send: send)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .animation(.default, value: justRecorded.isEmpty)
            }
            .toolbar(.hidden, for: .navigationBar)
            .alert("金額が見つかりませんでした", isPresented: $showsNoAmountAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("「ランチ 850」のように、金額の数字を入れてください。")
            }
            // 「取り消す」は記録の直後だけのもの。しばらくしたら引っ込め、タイムラインを広く使う。
            .task(id: justRecorded.map(\.persistentModelID)) {
                guard !justRecorded.isEmpty else { return }
                try? await Task.sleep(for: .seconds(8))
                if !Task.isCancelled { justRecorded = [] }
            }
        }
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
            let now = Date.now
            // 1 回の送信を複数件に分けたときは、書いた順に並ぶよう記録の日時を 1 ミリ秒ずつずらす。
            // 同じ日時だと並べ替えの順が定まらず、「スーパー」と「ドラッグ」が入れ替わることがあるため。
            let recorded = parsed.enumerated().map { index, entry in
                Entry(
                    parsed: entry, originalText: text, source: .text,
                    now: now.addingTimeInterval(Double(index) / 1000), calendar: calendar
                )
            }
            for entry in recorded {
                modelContext.insert(entry)
            }
            try? modelContext.save()
            justRecorded = recorded
            announce(recorded)
        }
    }

    /// 何円をどのカテゴリに記録したかを VoiceOver に読み上げさせる。
    ///
    /// 「記録しました / 取り消す」のバナーは、画面に出ても VoiceOver では読まれない。読み上げないと、
    /// VoiceOver の利用者は記録できたかも、AI がどう読んだかも分からず、読み違いにその場で気づけない
    /// （バナーは 8 秒で消えるので、探しにいく前に「取り消す」も無くなる）。
    private func announce(_ recorded: [Entry]) {
        let items = recorded.map { entry in
            let kind = entry.isIncome ? String(localized: "収入") : String(localized: entry.category.label)
            return "\(kind) \(YenFormatter.string(from: entry.amount))"
        }
        var message = AttributedString(String(localized: "記録しました: \(items.formatted(.list(type: .and)))"))
        // 送信の後は入力欄にフォーカスが戻り、その読み上げに割り込まれて結果が聞こえないことがあるので、優先して読ませる。
        message.accessibilitySpeechAnnouncementPriority = .high
        AccessibilityNotification.Announcement(message).post()
    }

    private func undoLastRecord() {
        for entry in justRecorded {
            modelContext.delete(entry)
        }
        try? modelContext.save()
        justRecorded = []
    }
}

/// 記録の直後に出す「取り消す」。AI が読み違えても、その場で戻せるようにするため。
private struct UndoBanner: View {
    let undo: () -> Void

    var body: some View {
        HStack {
            Label("記録しました", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.secondary)
            Spacer()
            Button("取り消す", action: undo)
                .fontWeight(.semibold)
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.bubble, in: .capsule)
    }
}

/// 記録が 1 件も無いときの案内。入力の例を見せて、何を書けばよいかを伝える。
private struct EmptyTimelineView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ひとことで記録")
                .font(.title2.bold())
            Text("下の入力欄に、こんなふうに送るだけで記録できます。")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Self.examples, id: \.self) { example in
                    Text(verbatim: example)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Theme.bubble, in: .rect(cornerRadius: 12))
                }
            }
        }
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
