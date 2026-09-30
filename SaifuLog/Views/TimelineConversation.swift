import SaifuLogCore
import SwiftData
import SwiftUI

// ホームのタイムラインの会話の部品。送った文を自分の吹き出し（右寄せ・山吹の塗り）に、アプリの返事をカード（左寄せ・面の色）に
// 出し、日が替わるところに日付の見出しを置く（docs/design.md §2・§9）。
//
// タイムラインは行をすべて測る（`HomeView` の `TimelineScrollView`）ので、行ごとの部品は HStack・ViewThatFits の測り直しを
// 避けて組む（右寄せ・左寄せは幅いっぱいの枠の端に置き、行の並べ方は同じ形に置く Layout にする）。

// MARK: - 送信

/// タイムラインの 1 回の送信（送った文と、そこから記録したもの）。記録からその場で組み立て、保存しない（コアの `TimelineSend`）。
struct EntrySend: Identifiable {
    /// 送信の ID（送信のいちばん古い記録の ID）。
    let id: PersistentIdentifier
    /// 記録したもの（書いた順）。空にはならない。
    let entries: [Entry]
    /// 送った文（レシートは「レシート: 店名 合計 ¥…」の要約）。
    let originalText: String
    /// どこから送ったか（ひとこと入力・声・レシート）。
    let source: EntrySource
    /// 送った日時（いちばん古い記録の記録した日時）。タイムラインの並びと日付の見出しに使う。
    let sentAt: Date

    /// 記録した日時の古い順に並べた記録を、送信ごとにまとめる（古い順）。
    ///
    /// まとめるのに読んだ値（送った文・入力元・記録した日時）はそのまま持つ（描くたびに記録から読み直さない。どれも直しても
    /// 変わらない値）。
    static func sends(from entries: [Entry]) -> [EntrySend] {
        let records = entries.map {
            TimelineSend.Record(id: $0.persistentModelID, originalText: $0.originalText, source: $0.source, createdAt: $0.createdAt)
        }
        return TimelineSend.groupRanges(of: records).map { range in
            let first = records[range.lowerBound]
            return EntrySend(
                id: first.id, entries: Array(entries[range]), originalText: first.originalText, source: first.source,
                sentAt: first.createdAt
            )
        }
    }
}

// MARK: - 自分の吹き出し

/// 自分が送ったもの（送った文・質問）の吹き出し。右に寄せ、灰色の面（`Theme.userBubble`）に墨の文字で出す。左に寄せる返事の
/// カード（面の色と細い枠）とは、寄せる側と色で見分ける。山吹の塗りにしていた時期もあったが、送るたびに山吹の大きな塊が並んで、
/// 山吹を使う送信ボタンや予算の進捗バーより目立ったため、灰色にした（デザイン案の質問の画面と同じ考え方）。押せるものではない。
struct UserMessageBubble: View {
    let text: String
    /// 文の前に添える記号（声で入れた文のマイク・レシートの印）。nil なら添えない。
    var symbol: String?
    /// VoiceOver が読む文（「送った文: …」「質問: …」）。
    let accessibilityLabel: Text

    var body: some View {
        content
            .foregroundStyle(Theme.ink)
            // 折り返すときも各行を吹き出しの右の端にそろえる（右寄せで出しているため）。
            .multilineTextAlignment(.trailing)
            .padding(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
            .background(Theme.userBubble, in: Self.shape)
            .trailingMessage()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
    }

    /// 吹き出しの形。右下の角だけを小さくして、自分の側（右）から出た吹き出しに見せる。
    static var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18, bottomTrailingRadius: 6, topTrailingRadius: 18)
    }

    @ViewBuilder
    private var content: some View {
        if let symbol {
            // 記号のある吹き出し（声・レシート）は少ないので、HStack で並べる。
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: symbol)
                    .font(.footnote.weight(.semibold))
                Text(verbatim: text)
            }
        } else {
            Text(verbatim: text)
        }
    }
}

/// 送信の吹き出し（送った文を、打ったとおりに）。声で入れた文にはマイクを、レシートには印を添える（レシートの要約は
/// 「レシート: 店名 合計 ¥…」なので、語は繰り返さない）。
struct SentTextBubble: View {
    let send: EntrySend

    var body: some View {
        UserMessageBubble(text: send.originalText, symbol: symbol, accessibilityLabel: accessibilityLabel)
    }

    private var symbol: String? {
        switch send.source {
        case .text: nil
        case .voice: "mic.fill"
        case .receipt: "receipt"
        }
    }

    /// レシートの要約は「レシート: …」と名乗っているので、そのまま読む。送った文は、質問の吹き出しの「質問: …」と同じ形で読む。
    private var accessibilityLabel: Text {
        send.source == .receipt ? Text(verbatim: send.originalText) : Text("送った文: \(send.originalText)")
    }
}

// MARK: - アプリの返事

/// 送信へのアプリの返事（記録したもの）のカード。左に寄せる（右の自分の吹き出しと見分けるため）。質問の回答カード・先週の
/// ふりかえりのカードと同じ見た目（`replyCardSurface`）。
///
/// 見出しに「記録しました」（2 件以上なら件数も）を出し、直前の送信なら右に「取り消す」を出す。「取り消す」は時間では
/// 引っ込めない（次の文を送る・取り消す・その記録を直す・記録先を切り替える・開き直すまで。`HomeModel.canUndo`）。記録ごとに
/// 1 行（`RecordedReplyRow`）を並べ、行を押すと ⑥ 直すを開く。割り勘などの説明の文は、その記録の行の下に添える（`RecordedReplyRow`）。
/// 直前の送信の返事には、最後に今月の状況の一行（`ReplyStatusLine`）を添える（「取り消す」と同じ間だけ）。
///
/// 記録ごとの縦の並びにしてあるので、あとで記録ごとの選択肢（カテゴリを選ぶボタンなど）を行の下に足せる。
struct RecordedReplyCard: View {
    let send: EntrySend
    /// 今日。日付に年を添えるかの基準と、今月の状況の一行の「今月」にする。
    let today: Date
    /// 「取り消す」を出すか（直前の送信で、まだ取り消せるとき）。
    let canUndo: Bool
    /// 今月の状況の一行を出すか。直前の送信の返事で、「取り消す」を出している間（`canUndo` と同じ値を渡す。見出しの高さを
    /// 確かめるテストで分けられるように、別に受け取る）。
    var showsStatus = false
    /// カテゴリを聞き返している記録（`HomeModel.categoryQuestionIDs`）。その記録の行の下にカテゴリのボタンを出す。
    var askingCategory: Set<PersistentIdentifier> = []
    let undo: () -> Void
    let edit: (Entry) -> Void
    /// 削除を求める（確認は呼び出し側で出す）。
    let requestDelete: (Entry) -> Void
    /// 聞き返したカテゴリを選ぶ（「その他のまま」は `.other`）。
    var chooseCategory: (Entry, EntryCategory) -> Void = { _, _ in }
    /// 聞き返した記録のために、カテゴリを作る画面を開く（作ったらその記録のカテゴリにする）。
    var createCategory: (Entry) -> Void = { _ in }

    @Environment(\.calendar) private var calendar

    var body: some View {
        LeadingStack(spacing: 2) {
            RecordedReplyHeader(count: send.entries.count, isReceipt: send.source == .receipt, undo: canUndo ? undo : nil)
            // たいていの送信は 1 件なので、1 件のときは行を並べる入れ物（`LeadingStack`・ForEach）を挟まない（行はすべて測るため）。
            // 記録ごとの一言や選択肢を足すときは、行の下（ここと ForEach の中）に並べる。
            if send.entries.count == 1 {
                row(send.entries[0])
            } else {
                LeadingStack(spacing: 12) {
                    ForEach(send.entries) { entry in
                        row(entry)
                    }
                }
            }
            if showsStatus {
                ReplyStatusLine(today: today, calendar: calendar, isIncomeOnly: send.entries.allSatisfy(\.isIncome))
                    // 行どうしの間（12pt）と同じだけ空ける（見出しと行の間の 2pt に足す）。
                    .padding(.top, 10)
            }
        }
        // 見出しは 44pt の高さの真ん中に文字があるので、上の余白を詰めて、下の余白とつり合わせる。
        .replyCardSurface(topPadding: 2)
        .leadingReply()
    }

    /// 記録 1 件の行。カテゴリを聞き返している記録は、行の下にカテゴリのボタンを添える（聞き返すのは直前の送信だけなので、
    /// たいていの行は入れ物を挟まない。行はすべて測るため）。
    @ViewBuilder
    private func row(_ entry: Entry) -> some View {
        let recorded = RecordedReplyRow(
            entry: entry, sentAt: send.sentAt, today: today, edit: { edit(entry) }, requestDelete: { requestDelete(entry) }
        )
        if askingCategory.contains(entry.persistentModelID) {
            LeadingStack(spacing: 10) {
                recorded
                CategoryQuestionView(entry: entry, choose: { chooseCategory(entry, $0) }, create: { createCategory(entry) })
            }
        } else {
            recorded
        }
    }
}

/// 返事の行の下の、カテゴリの聞き返し（「その他」になり、品目が辞書にも覚えにも当たらない支出。`CategoryMemory.asksCategory`）。
///
/// 選んだカテゴリにその記録を直し、品目とカテゴリの組を覚えて次から使う（`HomeModel.chooseCategory`）。「その他のまま」も覚える
/// （同じ品目でもう聞き返さない）。記録は済んでいるので、選ばずに次を送ってもよい（聞き返しは消え、記録は「その他」のまま）。
/// ボタンは横に送れる 1 行に並べる（折り返すと返事のカードが 3 行分ほど高くなり、タイムラインを押し上げるため）。
struct CategoryQuestionView: View {
    let entry: Entry
    let choose: (EntryCategory) -> Void
    /// カテゴリを作る画面を開く（「＋ カテゴリを作る」。作れる数に届いていれば出さない）。
    var create: (() -> Void)?

    @Environment(\.categoryCatalog) private var catalog

    /// 覚える品目（割り勘などの説明を除いたメモ）。品目の無い記録（金額だけ）は覚えられないので、覚えることは書かない。
    private var item: String {
        CategoryMemory.item(ofMemo: entry.memo, amount: entry.amount, isIncome: entry.isIncome)
    }

    var body: some View {
        LeadingStack(spacing: 6) {
            Text("カテゴリはどれですか？")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(catalog.all.filter { $0 != .other }) { category in
                        chip(category: category, label: catalog.label(for: category))
                    }
                    chip(category: .other, label: Text("その他のまま"))
                    // デザイン案の「＋ 衣服を作る」。当てはまるカテゴリが無いときに、その場で作れるようにする。
                    if let create, catalog.customs.count < CategoryCatalog.maximumCustomCount {
                        createChip(create)
                    }
                }
            }
            .scrollIndicators(.hidden)
            // カードの左右の余白（`replyCardSurface`）の外まで送れるようにする。余白の内側で切ると、右の端のボタンが途中で
            // 切れて見えるため。並べ始めはほかの行と同じ位置にそろえる。
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .padding(.horizontal, -16)
            if CategoryMemory.key(for: item) != nil {
                Text("選ぶと、次から「\(item)」の記録にも使います。")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// カテゴリのボタン（カテゴリの色の丸と名前）。色だけで見分けさせないよう、名前をいつも出す。
    private func chip(category: EntryCategory, label: Text) -> some View {
        Button {
            choose(category)
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(catalog.color(for: category))
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                label
                    .lineLimit(1)
            }
            .font(.subheadline)
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .background {
                Capsule()
                    .fill(Theme.background)
                    .stroke(Theme.track, lineWidth: 1)
            }
            // 見た目は 36pt の高さにし、押せる範囲は上下の余白まで広げて 44pt にする（よく使うひとことのボタンと同じ）。
            .padding(.vertical, 4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint(category == .other ? Text("この記録をその他のままにします") : Text("この記録のカテゴリにします"))
    }

    /// 「＋ カテゴリを作る」。ほかのボタンと形をそろえ、文字は強調の色にする（押すと画面が開くことを見分けられるように）。
    private func createChip(_ create: @escaping () -> Void) -> some View {
        Button(action: create) {
            Label {
                Text("カテゴリを作る")
            } icon: {
                Image(systemName: "plus")
                    .font(.footnote.weight(.semibold))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.accentText)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .background {
                Capsule()
                    .fill(Theme.background)
                    .stroke(Theme.track, lineWidth: 1)
            }
            .padding(.vertical, 4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("新しいカテゴリを作って、この記録のカテゴリにします")
    }
}

/// 返事の見出し。「記録しました」（2 件以上なら件数）と、取り消せるときだけ右の端に「取り消す」。
///
/// 高さは「取り消す」の有無で変えない（44pt）。次の文を送ると前の返事の「取り消す」が消えるので、高さが変わると、その瞬間に
/// タイムラインの行がずれて見えるため。1 行に収まらなければ（アクセシビリティサイズの文字）、「取り消す」を下の行に置く。
private struct RecordedReplyHeader: View {
    let count: Int
    let isReceipt: Bool
    /// 取り消す。取り消せないときは nil（「取り消す」を出さない）。
    let undo: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var checkWidth = 16

    /// 「記録しました」。訳した文字を先に引いておく。`Text("記録しました")` のままだと、送信の数だけあるカードごとに訳の表を引いて
    /// 装飾つきの文字に組み立て直し、行をすべて測るタイムライン（`HomeView` の `TimelineScrollView`）を開くのが目に見えて遅くなった。
    private static let recordedText = String(localized: "記録しました")

    /// チェックの印を添えるか。アクセシビリティサイズの文字では省き、見出しの文に幅を使わせる。
    private var showsCheck: Bool {
        !dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        Group {
            if let undo {
                SplitRowLayout(spacing: 12, stackedSpacing: 0, stacksAtTrailingEdge: false) {
                    title
                    undoButton(undo)
                }
            } else {
                title
            }
        }
        .font(.subheadline)
        .frame(minHeight: 44)
    }

    /// 印は HStack（Label）ではなく文字に重ねて置く（HStack は伸び縮みの幅を調べるために文字を測り直すため）。
    private var title: some View {
        Text(verbatim: count > 1 ? String(localized: "記録しました（\(count)件）") : Self.recordedText)
            .foregroundStyle(Theme.inkSecondary)
            .padding(.leading, showsCheck ? checkWidth + 4 : 0)
            .overlay(alignment: .leading) {
                if showsCheck {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.accentText)
                        .frame(width: checkWidth)
                        .accessibilityHidden(true)
                }
            }
    }

    private func undoButton(_ undo: @escaping () -> Void) -> some View {
        Button(action: undo) {
            Text("取り消す")
                .fontWeight(.semibold)
                .foregroundStyle(Theme.accentText)
                .lineLimit(1)
                // 押せる範囲を 44pt 四方以上にする（見出しの高さも 44pt にそろえてある）。
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .accessibilityHint(
            isReceipt ? Text("レシートから記録したものを消します") : Text("記録を消して、送った文を入力欄に戻します")
        )
    }
}

/// 返事の 1 行（記録 1 件）。カテゴリの印・品目（無ければカテゴリ名）・カテゴリ名（使った日が送った日と違えば日付も）・金額を
/// 並べ、押すと ⑥ 直すを開く（右の「›」で押せることを示す）。長押しのメニューに「直す」と「削除」を出す。
///
/// 品目と金額は、1 行に収まるときだけ横に並べ、収まらなければ金額を品目の下の行の右の端に置く（`SplitRowLayout`。金額は桁の
/// 途中で折り返さず、収まらなければ縮める）。アクセシビリティサイズの文字では、左の印を省いて中身に幅を使わせる。
///
/// 解析がメモに説明を書き足した記録（割り勘・1 人分の額。コアの `EntryMemoNote`）は、品目（「焼肉」）だけを見出しにし、説明を
/// 行の下の文にする（「¥12,000 を4人で割り勘。立て替えた ¥9,000 はメモに残しました。」`ReplyTexts.note(for:)`）。メモそのものは
/// 変えない（⑥ のメモの欄と CSV には説明が書かれたまま）。メモを直した記録は、書き足した形でなくなるので、メモをそのまま見出しにする。
struct RecordedReplyRow: View {
    let entry: Entry
    /// 送った日時。使った日がこの日と違うときだけ、日付を添える（「昨日 焼肉…」の昨日）。
    let sentAt: Date
    /// 今日。日付に年を添えるかの基準にする。
    let today: Date
    /// 「直す」のシートを出す。
    let edit: () -> Void
    /// 削除を求める（確認は呼び出し側で出す）。
    let requestDelete: () -> Void

    @Environment(\.calendar) private var calendar
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.displayScale) private var displayScale
    @Environment(\.categoryCatalog) private var catalog
    @ScaledMetric(relativeTo: .body) private var tileSize = 36

    private var showsTile: Bool {
        !dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        let text = Self.text(of: entry)
        return Button(action: edit) {
            label(item: text.item, note: text.note)
                .contentShape(.rect)
        }
        // 文字の色は行の中で決めているので、tint に染めない形にする（押している間は薄くなる）。
        .buttonStyle(.plain)
        .contentShape(.contextMenuPreview, .rect(cornerRadius: 12))
        .contextMenu {
            Button("直す", systemImage: "pencil", action: edit)
            Button("削除", systemImage: "trash", role: .destructive, action: requestDelete)
        }
        // VoiceOver では 1 件を 1 つのボタンとして、品目・金額・カテゴリ・日付の順に読ませる（ボタンが中の文を並べた順に読む。
        // 印と「›」は読ませない）。ダブルタップで ⑥ を開く。
        .accessibilityHint("記録を直す画面を開きます")
        // 長押しのメニューは VoiceOver から見つけにくいので、直す・削除を操作の一覧にも出す。
        .accessibilityAction(named: "直す", edit)
        .accessibilityAction(named: "削除", requestDelete)
    }

    /// 見出しにする品目と、行の下に添える説明の文（解析が説明を書き足していない記録・メモや金額を直した記録は nil）。
    static func text(of entry: Entry) -> (item: String, note: String?) {
        guard let note = EntryMemoNote(memo: entry.memo, amount: entry.amount, isIncome: entry.isIncome) else {
            return (entry.memo, nil)
        }
        return (note.item, ReplyTexts.note(for: note))
    }

    /// 行の中身。説明を書き足した記録は、行の下に説明の文を置く（カードの左の端から。印の下も使い、文に幅を使わせる）。
    /// たいていの記録は説明を持たないので、そのときは行を並べる入れ物（`LeadingStack`）を挟まない（行はすべて測るため）。
    @ViewBuilder
    private func label(item: String, note: String?) -> some View {
        if let note {
            LeadingStack(spacing: 6) {
                row(title: item)
                Text(verbatim: note)
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
            }
        } else {
            row(title: item)
        }
    }

    /// カテゴリの印・品目と金額と種別・「›」の行。
    ///
    /// - Parameter title: 品目（説明を書き足した記録は、説明を除いた品目）。空なら種別を見出しにする。
    private func row(title: String) -> some View {
        ReplyRowLayout(hasLeadingTile: showsTile, spacing: 12, displayScale: displayScale) {
            if showsTile {
                tile
            }
            content(title: title)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.inkSecondary)
                .accessibilityHidden(true)
        }
    }

    private func content(title: String) -> some View {
        // 品目が無いときは見出しが種別なので、下の行に種別は繰り返さない（同じ語が 2 回出て、VoiceOver でも 2 回読まれるため）。
        let kind = title.isEmpty ? nil : entry.kindText(in: catalog)
        let date = dateText
        return LeadingStack(spacing: 2) {
            SplitRowLayout(spacing: 8, stackedSpacing: 2, alwaysStacks: title.contains(where: \.isNewline)) {
                Text(verbatim: title.isEmpty ? entry.kindText(in: catalog) : title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text(verbatim: amountText)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(entry.isIncome ? Theme.income : Theme.ink)
                    // 金額は桁の途中で改行させない。収まらなければ縮めて 1 行に収める。
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            if kind != nil || date != nil {
                detail(kind: kind, date: date)
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
    }

    /// 種別（カテゴリ名か「収入」）と、使った日が送った日と違えば日付。
    @ViewBuilder
    private func detail(kind: String?, date: String?) -> some View {
        if let kind, let date {
            // 1 行に収まらなければ（アクセシビリティサイズの文字）、日付を次の行に移す（日付の途中で折り返さない）。区切りの点は
            // 種別の側に付ける（日本語では「・」を行の頭に置かないため）。
            AdaptiveRowLayout(stacksWhenNeeded: dynamicTypeSize.isAccessibilitySize, spacing: 0, stackAlignment: .leading) {
                Text("\(kind)・")
                    // 区切りの点は読ませない。
                    .accessibilityLabel(Text(verbatim: kind))
                Text(verbatim: date)
            }
        } else if let text = kind ?? date {
            Text(verbatim: text)
        }
    }

    /// 使った日（送った日と違うときだけ）。今年でなければ年も添える。
    private var dateText: String? {
        guard !calendar.isDate(entry.spentAt, inSameDayAs: sentAt) else { return nil }
        let format: Date.FormatStyle = entry.showsYear(today: today, calendar: calendar)
            ? .dateTime.year().month().day() : .dateTime.month().day()
        return entry.spentAt.formatted(format)
    }

    private var amountText: String {
        entry.isIncome ? YenFormatter.signedString(from: entry.amount) : YenFormatter.string(from: entry.amount)
    }

    /// カテゴリの印（収入は円の印）。ダークでもライトの色（濃い色）で塗る（白い記号を読めるように。`Palette.category`）。
    private var tile: some View {
        Image(systemName: entry.isIncome ? "yensign" : catalog.symbolName(for: entry.category))
            .font(.system(size: tileSize * 0.45, weight: .semibold))
            .foregroundStyle(Theme.onCategory)
            .frame(width: tileSize, height: tileSize)
            .background(
                entry.isIncome ? Theme.income : catalog.color(for: entry.category), in: .rect(cornerRadius: tileSize * 0.28)
            )
            .environment(\.colorScheme, .light)
            .accessibilityHidden(true)
    }
}

/// 直前の送信の返事の最後の一行。今月の状況を、ホームの帯と同じ数字で言う（「今月あと ¥…（1日あたり ¥…）」「今月の予算を ¥… 超えて
/// います」「今月の支出 ¥…」、収入だけの送信は「今月の収入 ¥…」。`ReplyTexts.status`）。
///
/// 数字は帯と同じ読み込みと計算（今月の記録と予算の @Query と `MonthSummaryHeader.figures`）で、記録を直す・消す・予算を変える・
/// iCloud で取り込むと、その場で変わる（送ったときの数字の写しではない）。そのため出すのは直前の送信の返事だけにする（「取り消す」と
/// 同じ間）。前の送信の返事にも出すと、いまの数字がその送信のときの数字のように読めてしまい、送信は保存しないので、送ったときの
/// 数字を残すこともできない。直前の返事にあれば、送った直後に目を向ける場所で「あといくら使えるか」が分かる。
private struct ReplyStatusLine: View {
    let today: Date
    let isIncomeOnly: Bool

    @Environment(\.calendar) private var calendar
    @ScaledMetric(relativeTo: .subheadline) private var iconWidth = 16
    @Query private var records: [Entry]
    @Query private var budgets: [Budget]

    init(today: Date, calendar: Calendar, isIncomeOnly: Bool) {
        self.today = today
        self.isIncomeOnly = isIncomeOnly
        _records = Query(Entry.monthDescriptor(containing: today, calendar: calendar))
    }

    var body: some View {
        let figures = MonthSummaryHeader.figures(records: records, budgets: budgets, today: today, calendar: calendar)
        let sentence = ReplyTexts.status(summary: figures.summary, budget: figures.budget, isIncomeOnly: isIncomeOnly)
        LeadingStack(spacing: 10) {
            // 記録の行と分けて、返事の終わりに添えた一行だと分かるようにする（カードの枠と同じ色の細い線）。
            Rectangle()
                .fill(Theme.track)
                .frame(height: 1)
                .accessibilityHidden(true)
            Text(sentence.attributed(figureColor: sentence.isWarning ? Theme.danger : Theme.ink))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(Theme.inkSecondary)
                // 予算を超えたときは、色だけでなくアイコンも添える（帯の「¥… オーバー」と同じ）。印は HStack ではなく文字に重ねる。
                .padding(.leading, sentence.isWarning ? iconWidth + 4 : 0)
                .overlay(alignment: Alignment(horizontal: .leading, vertical: .firstTextBaseline)) {
                    if sentence.isWarning {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(Theme.danger)
                            .frame(width: iconWidth)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityLabel(Text(verbatim: sentence.text))
        }
    }
}

// MARK: - 日付の見出し

/// タイムラインの日付の見出し（「今日」「昨日」「9月28日(月)」。今年でなければ年も）。日付だけで、金額は添えない（翌朝に送った
/// 「昨日 焼肉…」のように、見出しの下に別の日の支出が並ぶことがあり、合計を出すとその日に使った額と読み違えるため。
/// コアの `TimelineDay`）。
struct TimelineDayHeader: View {
    /// 見出しの日（その日の 0 時）。
    let day: Date
    /// 今日。「今日」「昨日」の基準にする。
    let today: Date

    @Environment(\.calendar) private var calendar

    var body: some View {
        label
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.inkSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Theme.surface, in: .capsule)
            .frame(maxWidth: .infinity)
            // 前の日の行との間を、行どうしの間より少し広く空ける。
            .padding(.top, 8)
            // VoiceOver の見出しの移動で、日ごとに飛べるようにする。
            .accessibilityAddTraits(.isHeader)
    }

    private var label: Text {
        switch TimelineDay.label(for: day, now: today, calendar: calendar) {
        case .today:
            Text("今日")
        case .yesterday:
            Text("昨日")
        case .date(let includesYear):
            Text(day, format: includesYear
                ? .dateTime.year().month().day().weekday(.abbreviated)
                : .dateTime.month().day().weekday(.abbreviated))
        }
    }
}

// MARK: - 見た目

extension View {
    /// アプリからの返事のカード（記録しました・質問の回答・先週のふりかえり）の面。面の色の角丸に、細い枠を付ける。
    /// 幅は置いた場所いっぱいに広げ、中身は左に寄せる。
    ///
    /// - Parameter topPadding: 上の余白。見出しが 44pt の高さを持つカード（記録しました）は詰める。
    func replyCardSurface(topPadding: CGFloat = 12) -> some View {
        self
            .padding(EdgeInsets(top: topPadding, leading: 16, bottom: 12, trailing: 16))
            .frame(maxWidth: .infinity, alignment: .leading)
            // 面と背景の色の差は小さい（ライトは白と温かい白）ので、枠でカードの形を見せる。面と枠は 1 つの形で描く（重ねて
            // 描くと、カードごとに形が 2 つになり、行をすべて測るタイムラインを開くのが遅くなったため）。
            .background {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Theme.surface)
                    .stroke(Theme.track, lineWidth: 1)
            }
    }

    /// アプリからの返事として左に寄せ、右に余白を残す（アクセシビリティサイズの文字では幅を使わせる）。
    func leadingReply() -> some View {
        modifier(MessageSideMargin(margin: .trailing))
    }

    /// 自分が送ったものとして右に寄せ、左に余白を残す（アクセシビリティサイズの文字では幅を使わせる）。
    func trailingMessage() -> some View {
        modifier(MessageSideMargin(margin: .leading))
    }
}

/// 会話の片側に寄せ、反対の側に 40pt の余白を残す。HStack と Spacer ではなく、余白を空けた幅いっぱいの枠の端に置く
/// （HStack は伸び縮みの幅を調べるために中身を測り直すため）。
private struct MessageSideMargin: ViewModifier {
    /// 余白を空ける側。
    let margin: HorizontalEdge

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        content
            .padding(margin == .leading ? .leading : .trailing, dynamicTypeSize.isAccessibilitySize ? 0 : 40)
            .frame(maxWidth: .infinity, alignment: margin == .leading ? .trailing : .leading)
    }
}

// MARK: - 並べ方

/// 返事の行の並べ方。左のカテゴリの印（無いときもある）・中身・右の「›」を、
/// `HStack(alignment: .top, spacing:) { 印; 中身.frame(maxWidth: .infinity, alignment: .leading); 「›」 }` のように置く
/// （中身には、行の幅から印と「›」と間を引いた幅を提案する）。「›」だけは行の高さの真ん中に置く。
///
/// HStack にしないのは、タイムラインを開くときの手間を減らすため（`EntryBubbleRowLayout` と同じ理由。HStack は伸び縮みの幅を
/// 調べるために中身に幅 0 と無限大も提案し、そのたびに品目と金額の行が測り直される）。ここでは中身を実際の幅で 1 回だけ測る。
struct ReplyRowLayout: Layout {
    /// 1 つ目の子が左の印か（アクセシビリティサイズの文字では印を置かない）。
    let hasLeadingTile: Bool
    /// 印と中身、中身と「›」の間。
    let spacing: CGFloat
    /// 画面の 1pt あたりの画素数。中身に提案する幅を画素の境目にそろえる。
    let displayScale: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        guard let parts = parts(of: subviews) else { return .zero }
        let tile = parts.tile?.sizeThatFits(.unspecified)
        let chevron = parts.chevron.sizeThatFits(.unspecified)
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        let content = parts.content.sizeThatFits(contentProposal(width: width, tile: tile, chevron: chevron))
        let natural = fixedWidth(tile: tile, chevron: chevron) + content.width
        return CGSize(
            width: max(width ?? natural, natural),
            height: max(content.height, tile?.height ?? 0, chevron.height)
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        guard let parts = parts(of: subviews) else { return }
        let tile = parts.tile?.sizeThatFits(.unspecified)
        let chevron = parts.chevron.sizeThatFits(.unspecified)
        var x = bounds.minX
        if let view = parts.tile, let tile {
            view.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(tile))
            x += tile.width + spacing
        }
        parts.content.place(
            at: CGPoint(x: x, y: bounds.minY), proposal: contentProposal(width: bounds.width, tile: tile, chevron: chevron)
        )
        parts.chevron.place(
            at: CGPoint(x: bounds.maxX - chevron.width, y: bounds.midY - chevron.height / 2), proposal: ProposedViewSize(chevron)
        )
    }

    /// 行の中に独自の揃えは無いので、揃えを問われても中を測らずに既定の位置（nil）を返す。
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

    private func parts(of subviews: Subviews) -> (tile: LayoutSubview?, content: LayoutSubview, chevron: LayoutSubview)? {
        if hasLeadingTile, subviews.count == 3 {
            return (subviews[0], subviews[1], subviews[2])
        }
        if subviews.count == 2 {
            return (nil, subviews[0], subviews[1])
        }
        return nil
    }

    /// 中身の左右にある、中身以外の幅（印・「›」と間）。
    private func fixedWidth(tile: CGSize?, chevron: CGSize) -> CGFloat {
        (tile.map { $0.width + spacing } ?? 0) + spacing + chevron.width
    }

    /// 中身に提案する大きさ。幅は画素の境目に切り下げる（丸めの誤差で境目をわずかに超えると、文字の幅が 1 画素広く測られるため）。
    /// 高さは提案しない（金額を `minimumScaleFactor` で縮めさせないため）。
    private func contentProposal(width: CGFloat?, tile: CGSize?, chevron: CGSize) -> ProposedViewSize {
        let scale = max(displayScale, 1)
        return ProposedViewSize(
            width: width.map { max(0, (($0 - fixedWidth(tile: tile, chevron: chevron)) * scale + 0.0001).rounded(.down) / scale) },
            height: nil
        )
    }
}

/// 2 つの子（前・後ろ）を、1 行に収まれば前を左の端に・後ろを右の端に置き（1 行目の文字の下端をそろえる）、収まらなければ
/// 後ろを前の下の行に置く。子が 1 つなら左の端に置く。幅を提案されれば、その幅いっぱいを使う。
///
/// 1 行に収まるかは、どちらも折り返さない幅（理想の幅）で並べて入るかで決める（吹き出しの `TitleAmountLayout` と同じ選び方）。
/// 品目が折り返すほど長いのに金額を横に並べると、金額が品目の 1 行目の右に並び、「…総額」「¥3,000」のように続けて読めて
/// しまうため。返事の行の品目と金額、見出しの「記録しました」と「取り消す」に使う。
struct SplitRowLayout: Layout {
    /// 横に並べるときの、前と後ろの間の最小。
    var spacing: CGFloat = 8
    /// 縦に積むときの、前と後ろの間。
    var stackedSpacing: CGFloat = 2
    /// 縦に積むとき、後ろを右の端に寄せるか（金額）。false なら左の端（ボタン）。
    var stacksAtTrailingEdge = true
    /// いつも縦に積むか（改行の入った品目。1 行目の右に金額が並ぶため）。
    var alwaysStacks = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        switch subviews.count {
        case 0:
            return .zero
        case 1:
            let size = subviews[0].sizeThatFits(ProposedViewSize(width: width, height: nil))
            return CGSize(width: max(width ?? size.width, size.width), height: size.height)
        default:
            if let row = row(width: width, subviews: subviews) {
                return CGSize(width: max(width ?? row.size.width, row.size.width), height: row.size.height)
            }
            let first = subviews[0].sizeThatFits(ProposedViewSize(width: width, height: nil))
            let second = subviews[1].sizeThatFits(ProposedViewSize(width: width, height: nil))
            return CGSize(
                width: max(width ?? 0, first.width, second.width), height: first.height + stackedSpacing + second.height
            )
        }
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let childProposal = ProposedViewSize(width: bounds.width, height: nil)
        switch subviews.count {
        case 0:
            return
        case 1:
            subviews[0].place(at: bounds.origin, proposal: childProposal)
        default:
            if let row = row(width: bounds.width, subviews: subviews) {
                subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.minY + row.origins[0].y), proposal: row.childProposal)
                subviews[1].place(
                    at: CGPoint(x: bounds.maxX - row.widths[1], y: bounds.minY + row.origins[1].y), proposal: row.childProposal
                )
            } else {
                let first = subviews[0].sizeThatFits(childProposal)
                let second = subviews[1].sizeThatFits(childProposal)
                subviews[0].place(at: bounds.origin, proposal: childProposal)
                subviews[1].place(
                    at: CGPoint(
                        x: stacksAtTrailingEdge ? bounds.maxX - second.width : bounds.minX,
                        y: bounds.minY + first.height + stackedSpacing
                    ),
                    proposal: childProposal
                )
            }
        }
    }

    /// 行の中に独自の揃えは無いので、揃えを問われても中を測らずに既定の位置（nil）を返す。
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

    /// 横に並べる形（理想の大きさで並べ、1 行目の文字の下端をそろえる）。1 行に収まらなければ nil（縦に積む）。
    private func row(width: CGFloat?, subviews: Subviews) -> IdealRowArrangement? {
        guard !alwaysStacks else { return nil }
        let row = IdealRowArrangement(
            subviews: subviews, alignment: .firstTextBaseline, spacing: spacing, proposal: ProposedViewSize(width: width, height: nil)
        )
        return row.fits(ProposedViewSize(width: width, height: nil)) ? row : nil
    }
}

/// 子を上から左の端にそろえて並べる（`VStack(alignment: .leading, spacing:)` と同じ大きさと位置）。返事のカードの見出しと行、
/// 行の中の品目と種別の行に使う。
///
/// VStack にしないのは、タイムラインを開くときの手間を減らすため。返事のカードは送信の数だけあり、行はすべて測る
/// （`HomeView` の `TimelineScrollView`）。VStack は子を並べるときに揃えの位置を子の中まで問い合わせるが、カードの中の子には独自の
/// 揃えが無いので、問い合わせずに左の端に置く（撮影用のデモの 50 件で、ホームを開いて最初に並べ終えるまでが 0.23 秒から 0.2 秒ほどに
/// 縮んだ。`TimelineStack` と同じ測り方）。
struct LeadingStack: Layout {
    /// 子の間。
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        // 子には幅だけを提案する（高さは提案しない。VStack が上から順に子を測るときと同じく、子は自分の高さで並ぶ）。
        let childProposal = ProposedViewSize(width: proposal.width, height: nil)
        var size = CGSize.zero
        for (index, subview) in subviews.enumerated() {
            let child = subview.sizeThatFits(childProposal)
            size.width = max(size.width, child.width)
            size.height += child.height + (index == 0 ? 0 : spacing)
        }
        return size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let childProposal = ProposedViewSize(width: bounds.width, height: nil)
        var y = bounds.minY
        for subview in subviews {
            let child = subview.sizeThatFits(childProposal)
            subview.place(at: CGPoint(x: bounds.minX, y: y), proposal: childProposal)
            y += child.height + spacing
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
