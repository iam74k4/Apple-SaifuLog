import SwiftUI

/// 記録の直後に出す「取り消す」。AI が読み違えても、その場で戻せるようにするため。
///
/// いつ引っ込めるかは HomeView が決める（支援技術を使っているときは自動では引っ込めない）。
struct UndoBanner: View {
    let undo: () -> Void
    /// バナーを閉じる。VoiceOver などの操作の一覧から使う（自動で引っ込めないときの閉じ方）。
    let dismiss: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        content
            .font(.subheadline)
            .padding(.horizontal, 16)
            // 高さ 44pt なら丸い端のカプセルになり、文字が大きく縦に積んだときは角丸の四角になる。
            .background(Theme.bubble, in: .rect(cornerRadius: 22))
    }

    /// アクセシビリティサイズの文字では、横に並べると「記録しました」も「取り消す」も語の途中で
    /// 折り返されるので、1 行に収まらなければ縦に積む。飾りのチェックの印も外し、文に幅を使わせる。
    @ViewBuilder
    private var content: some View {
        if dynamicTypeSize.isAccessibilitySize {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    message(showsIcon: false)
                    undoButton
                }
                VStack(alignment: .leading, spacing: 0) {
                    message(showsIcon: false)
                    undoButton
                }
            }
        } else {
            HStack(spacing: 8) {
                message(showsIcon: true)
                undoButton
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
        .foregroundStyle(.secondary)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAction(named: "閉じる", dismiss)
    }

    private var undoButton: some View {
        Button(action: undo) {
            Text("取り消す")
                .fontWeight(.semibold)
                // 押せる範囲を 44pt 四方以上にする。文字の大きさだけだと高さが 20pt ほどしかなく、
                // 文字の少し外を押しても反応しないため。
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        // バナーの中のどちらの要素からでも閉じられるようにする（VoiceOver の操作の一覧）。
        .accessibilityAction(named: "閉じる", dismiss)
    }
}

#Preview {
    UndoBanner(undo: {}, dismiss: {})
        .padding()
}
