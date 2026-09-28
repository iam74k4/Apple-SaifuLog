import SwiftUI

/// ホームの下の入力欄。
///
/// カメラ（レシート）とマイク（声で記録）のボタンは、機能ができてから足す。
/// 押しても何も起きないボタンは置かない。
struct InputBar: View {
    @Binding var text: String
    let isSending: Bool
    let send: () -> Void
    /// 直前の記録を取り消す。記録の直後（「取り消す」のバナーが出ている間）だけ渡す。
    var undo: (() -> Void)?
    /// 直前に記録したもの（VoiceOver の操作の「直す」の対象）。バナーが出ていなければ空。
    var recorded: [Entry] = []
    /// 「直す」のシートを出す。
    var edit: (Entry) -> Void = { _ in }

    @FocusState private var isFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var canSend: Bool {
        !isSending && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 送信ボタンの記号（矢印と読み取り中の印）の色。
    ///
    /// 押せるときは山吹の塗りの上なので墨にする（白を載せると 2:1 に届かない。Theme の説明）。
    /// 押せないとき（空・読み取り中）は塗りが灰色のガラスに変わり、墨のままだとダークで地に沈んで
    /// ボタンがあることも分からなくなるので、補足の文字の色にする。
    private var sendSymbolColor: Color {
        canSend ? Theme.onAccent : Theme.inkSecondary
    }

    var body: some View {
        HStack(spacing: 8) {
            // 1 行の入力欄にする。複数行にすると Return が改行になり、チャットのように送れないため。
            TextField(text: $text, prompt: prompt) {
                Text("記録する内容")
            }
            .foregroundStyle(Theme.ink)
            .focused($isFocused)
            .submitLabel(.send)
            .onSubmit {
                send()
                // Return で送るとキーボードが閉じる。続けて記録できるよう、入力欄にとどまる。
                isFocused = true
            }
            .accessibilityLabel("記録する内容")
            // 送信の後、VoiceOver のフォーカスは入力欄に戻る。バナーまで移らずに直す・取り消すができるようにする
            // （読み上げで読み違いに気づいたら、その場で直せるように）。複数件なら 1 件ずつ出す。
            .accessibilityActions {
                ForEach(recorded) { entry in
                    Button("直す: \(entry.summaryText)") { edit(entry) }
                }
                if let undo {
                    Button("直前の記録を取り消す", action: undo)
                }
            }
            // 入力欄は高さ 44pt 以上にし、文字の周りの余白（ガラスの枠の中）を押してもフォーカスが入るようにする。
            // 文字の部分だけが押せる範囲だと、高さが 22pt ほどしかないため。
            .frame(minHeight: 44)
            .padding(.horizontal, 16)
            .contentShape(.rect(cornerRadius: 22))
            .simultaneousGesture(TapGesture().onEnded { isFocused = true })
            .glassEffect(.regular, in: .rect(cornerRadius: 22))

            Button(action: send) {
                Group {
                    if isSending {
                        ProgressView()
                            .tint(sendSymbolColor)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.body.weight(.bold))
                    }
                }
                .frame(width: 44, height: 44)
                .foregroundStyle(sendSymbolColor)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            // tint は塗りの色になる。AccentColor（ライトは濃い琥珀）のままにせず、塗り用の山吹にする。
            .tint(Theme.accentFill)
            .disabled(!canSend)
            .accessibilityLabel(isSending ? "読み取り中" : "送信")
        }
    }

    /// 入力の例。アクセシビリティサイズの文字では例だけにする。入力欄の幅に収まらない案内は、
    /// 読めないほど小さく縮められるため。例の「ランチ 850」は訳さない（解析が日本語の入力を前提にしているため）。
    ///
    /// 色は補足の文字と同じにする。システムの既定の薄い灰色は、ガラスの地の上で 3:1 に届かないため。
    private var prompt: Text {
        (dynamicTypeSize.isAccessibilitySize ? Text(verbatim: "ランチ 850") : Text("ランチ 850 のように入力"))
            .foregroundStyle(Theme.inkSecondary)
    }
}

#Preview {
    @Previewable @State var text = "ランチ 850"
    InputBar(text: $text, isSending: false, send: {})
        .padding()
}
