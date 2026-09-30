import SwiftUI

/// 記録の直後に出す「直す」「取り消す」。AI が読み違えても、その場で直すか戻せるようにするため。
///
/// いつ引っ込めるかは HomeView と HomeModel が決める（支援技術を使っているとき、「直す」のシート・どれを直すかの確認・
/// 保存の失敗のアラートを出している間は、時間では引っ込めない。次の文を送ったら、読み取りを待たずにすぐ引っ込める）。
struct UndoBanner: View {
    /// 直前に記録したもの（「直す」の対象）。1 回の送信で複数件を記録したときは、どれを直すかを選ばせる。
    let recorded: [RecordedItem]
    /// どれを直すかの確認を出しているか（複数件のとき。`HomeModel.showsRecordedItemChoice`）。
    @Binding var showsItemChoice: Bool
    /// 「直す」を押した。1 件ならそのままシートを出し、複数件ならどれを直すかの確認を出す（`HomeModel.requestRecordedEdit`）。
    let requestEdit: () -> Void
    /// 確認で選んだものの「直す」のシートを出す。
    let edit: (RecordedItem) -> Void
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
            // 確認は「直す」ではなくバナーに付ける。アクセシビリティサイズの文字では、ボタンを ViewThatFits の並べ方ごとに
            // 作るので、ボタンに付けると同じ確認がいくつもできるため。iOS 26 では付けたものを指す吹き出しの形で、バナーの上に出る
            // （「直す」には重ならない）。
            .confirmationDialog("どれを直しますか？", isPresented: $showsItemChoice, titleVisibility: .visible) {
                ForEach(recorded) { item in
                    Button { edit(item) } label: {
                        Text(verbatim: item.summaryText)
                    }
                }
                Button("キャンセル", role: .cancel) {}
            }
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

    /// 1 件なら押すとそのまま開き、複数件ならどれを直すかの確認（`confirmationDialog`）を出す。
    ///
    /// 選ぶところをメニュー（`Menu`）にしないのは、メニューが指を置いた時点で開き、画面の下のバナーからは「直す」の上に
    /// 重なって開くため。指を離したところの項目が選ばれ、選ばせないまま 1 件のシートが開くことがあった。確認は指を離して
    /// から出るので、押しただけで項目が選ばれることはない。確認を出している間は、バナーを時間で引っ込めない
    /// （`HomeModel.autoHidesUndo`。メニューは開いていることを知れず、時間切れでバナーごと閉じることがあった）。
    @ViewBuilder
    private var editButton: some View {
        if !recorded.isEmpty {
            Button(action: requestEdit) {
                buttonLabel("直す")
            }
            .accessibilityHint(recorded.count > 1 ? Text("どれを直すかを選びます") : Text("記録を直す画面を開きます"))
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

/// 記録の直後の「直す」「取り消す」の対象の 1 件（自分の記録か家計の記録か）。
///
/// バナーと入力欄の VoiceOver の操作は、どちらの保存先の記録かを知らなくてよいので、見出しと ID だけを持つ。
/// どの記録を直すかは、ID から `HomeModel` が決める。
struct RecordedItem: Identifiable {
    let id: AnyHashable
    /// 「ランチ ¥850」
    let summaryText: String
}

#Preview {
    UndoBanner(
        recorded: [RecordedItem(id: 1, summaryText: "ランチ ¥850"), RecordedItem(id: 2, summaryText: "コーヒー ¥400")],
        showsItemChoice: .constant(false),
        requestEdit: {},
        edit: { _ in },
        undo: {},
        dismiss: {}
    )
        .padding()
}
