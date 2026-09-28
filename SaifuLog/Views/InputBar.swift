import SwiftUI

/// ホームの下の入力欄。
///
/// カメラ（レシート）とマイク（声で記録）のボタンは、機能ができてから足す。
/// 押しても何も起きないボタンは置かない。
struct InputBar: View {
    @Binding var text: String
    let isSending: Bool
    let send: () -> Void

    @FocusState private var isFocused: Bool

    private var canSend: Bool {
        !isSending && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: 8) {
            // 1 行の入力欄にする。複数行にすると Return が改行になり、チャットのように送れないため。
            TextField("ランチ 850 のように入力", text: $text)
                .focused($isFocused)
                .submitLabel(.send)
                .onSubmit {
                    send()
                    // Return で送るとキーボードが閉じる。続けて記録できるよう、入力欄にとどまる。
                    isFocused = true
                }
                .accessibilityLabel("記録する内容")
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: .rect(cornerRadius: 22))

            Button(action: send) {
                if isSending {
                    ProgressView()
                        .frame(width: 44, height: 44)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.bold))
                        .frame(width: 44, height: 44)
                }
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .disabled(!canSend)
            .accessibilityLabel(isSending ? "読み取り中" : "送信")
        }
    }
}

#Preview {
    @Previewable @State var text = "ランチ 850"
    InputBar(text: $text, isSending: false, send: {})
        .padding()
}
