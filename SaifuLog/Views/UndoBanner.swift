import SwiftUI

/// 記録の直後に出す「直す」「取り消す」。AI が読み違えても、その場で直すか戻せるようにするため。
///
/// いつ引っ込めるかは HomeView と HomeModel が決める（支援技術を使っているとき、「直す」のシートや保存の失敗のアラートを
/// 出している間は、時間では引っ込めない。次の文を送ったら、読み取りを待たずにすぐ引っ込める）。
struct UndoBanner: View {
    /// 直前に記録したもの（「直す」の対象）。1 回の送信で複数件を記録したときは、どれを直すかを選ばせる。
    let recorded: [Entry]
    /// 「直す」のシートを出す。
    let edit: (Entry) -> Void
    let undo: () -> Void
    /// バナーを閉じる。VoiceOver などの操作の一覧から使う（自動で引っ込めないときの閉じ方）。
    let dismiss: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        content
            .font(.subheadline)
            .padding(.horizontal, 16)
            // 高さ 44pt なら丸い端のカプセルになり、文字が大きく縦に積んだときは角丸の四角になる。
            .background(Theme.surface, in: .rect(cornerRadius: 22))
    }

    /// アクセシビリティサイズの文字では、横に並べると「記録しました」もボタンも語の途中で折り返されるので、
    /// 1 行に収まらなければ、文の下にボタンを並べ、それでも収まらなければボタンも縦に積む。飾りのチェックの印も外し、
    /// 文に幅を使わせる。
    @ViewBuilder
    private var content: some View {
        if dynamicTypeSize.isAccessibilitySize {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    message(showsIcon: false)
                    buttons
                }
                VStack(alignment: .leading, spacing: 0) {
                    message(showsIcon: false)
                    HStack(spacing: 16) { buttons }
                }
                VStack(alignment: .leading, spacing: 0) {
                    message(showsIcon: false)
                    buttons
                }
            }
        } else {
            HStack(spacing: 8) {
                message(showsIcon: true)
                buttons
            }
        }
    }

    private func message(showsIcon: Bool) -> some View {
        Group {
            if showsIcon {
                Label("記録しました", systemImage: "checkmark.circle.fill")
            } else {
                Text("記録しました")
            }
        }
        .foregroundStyle(Theme.inkSecondary)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAction(named: "閉じる", dismiss)
    }

    @ViewBuilder
    private var buttons: some View {
        editButton
        undoButton
    }

    /// 1 件なら押すとそのまま開き、複数件ならどれを直すかのメニューを出す。
    ///
    /// メニューを開いているかは SwiftUI から知る手段が無いので、開いている間も 8 秒のタイマーは数え続け、時間切れで
    /// バナーごとメニューが閉じることがある（docs/design.md §15 の 5 で実機で確かめる）。
    @ViewBuilder
    private var editButton: some View {
        if recorded.count == 1, let entry = recorded.first {
            Button { edit(entry) } label: {
                buttonLabel("直す")
            }
            .accessibilityAction(named: "閉じる", dismiss)
        } else if !recorded.isEmpty {
            Menu {
                ForEach(recorded) { entry in
                    Button { edit(entry) } label: {
                        Text(verbatim: entry.summaryText)
                    }
                }
            } label: {
                buttonLabel("直す")
            }
            .accessibilityAction(named: "閉じる", dismiss)
        }
    }

    private var undoButton: some View {
        Button(action: undo) {
            buttonLabel("取り消す")
        }
        // バナーの中のどの要素からでも閉じられるようにする（VoiceOver の操作の一覧）。
        .accessibilityAction(named: "閉じる", dismiss)
    }

    private func buttonLabel(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .fontWeight(.semibold)
            .lineLimit(1)
            // 押せる範囲を 44pt 四方以上にする。文字の大きさだけだと高さが 20pt ほどしかなく、
            // 文字の少し外を押しても反応しないため。
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
    }
}

#Preview {
    UndoBanner(recorded: [], edit: { _ in }, undo: {}, dismiss: {})
        .padding()
}
