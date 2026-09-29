import SwiftUI

/// ホームの下の入力欄。記録も家計への質問も、ここに打つ（見分けは `HomeModel` がコアに任せる）。
/// 左のカメラのボタンから、レシートを読み取って記録できる。右のマイクのボタンから、話した内容を入力欄に入れられる
/// （入力欄が空のときは、送信ボタンの位置にマイクを出す。空の入力は送れないので、その位置を声の入力の入口に使う）。
///
/// マイクのボタンは、日本語の書き起こしを使える端末でだけ出す（押しても何も起きないボタンは置かない）。
/// 声の入力の間は、入力欄の代わりに書き起こしの表示（`VoiceInputPanel`）を出す。
struct InputBar: View {
    @Binding var text: String
    let isSending: Bool
    let send: () -> Void
    /// レシートを読み取る（カメラのボタン）。渡さなければボタンを出さない。
    var scanReceipt: (() -> Void)?
    /// 「撮る」「写真から選ぶ」の確認を出しているか。カメラのボタンに付けて、ボタンのそばに出す。
    var showsReceiptChoice: Binding<Bool> = .constant(false)
    /// 「撮る」を出すか（書類カメラを使える端末だけ）。
    var canUseDocumentCamera = false
    /// 「撮る」「写真から選ぶ」を選んだ。
    var chooseReceiptSource: (ReceiptCaptureSource) -> Void = { _ in }
    /// 直前の記録を取り消す。記録の直後（「取り消す」のバナーが出ている間）だけ渡す。
    var undo: (() -> Void)?
    /// 直前に記録したもの（VoiceOver の操作の「直す」の対象）。バナーが出ていなければ空。
    var recorded: [RecordedItem] = []
    /// 「直す」のシートを出す。
    var edit: (RecordedItem) -> Void = { _ in }
    /// 声の入力。渡さなければマイクのボタンを出さない。
    var voice: VoiceInputModel?
    /// 家族の家計に記録しているか（ホームの帯の「家族」）。入力欄の名前と例で、家計に記録することを示す。
    var targetsHousehold = false

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

    /// マイクのボタンを出すか（日本語の書き起こしを使える端末だけ）。
    private var showsMicrophone: Bool {
        voice?.isAvailable == true
    }

    /// 送信ボタンを出すか。マイクを出す端末では、入力欄が空の間はマイクに譲る（読み取り中の印は出したままにする）。
    private var showsSendButton: Bool {
        !showsMicrophone || isSending || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        if let voice, voice.isActive {
            VoiceInputPanel(model: voice, prefix: text)
        } else {
            textInput
        }
    }

    private var textInput: some View {
        HStack(spacing: 8) {
            if let scanReceipt {
                receiptButton(scanReceipt)
            }
            // 1 行の入力欄にする。複数行にすると Return が改行になり、チャットのように送れないため。
            TextField(text: $text, prompt: prompt) {
                fieldLabel
            }
            .foregroundStyle(Theme.ink)
            .focused($isFocused)
            .submitLabel(.send)
            .onSubmit {
                send()
                // Return で送るとキーボードが閉じる。続けて記録できるよう、入力欄にとどまる。
                isFocused = true
            }
            // 記録も質問も同じ入力欄に打つ（記録か質問かはアプリが見分ける）。家族の家計のときは記録だけ。
            .accessibilityLabel(fieldLabel)
            // 送信の後、VoiceOver のフォーカスは入力欄に戻る。バナーまで移らずに直す・取り消すができるようにする
            // （読み上げで読み違いに気づいたら、その場で直せるように）。複数件なら 1 件ずつ出す。
            .accessibilityActions {
                ForEach(recorded) { item in
                    Button("直す: \(item.summaryText)") { edit(item) }
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

            if let voice, showsMicrophone {
                VoiceMicButton(isEnabled: voice.canStart) { voice.toggle() }
            }
            if showsSendButton {
                sendButton
            }
        }
    }

    private var sendButton: some View {
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

    /// レシートを読み取るボタン。山吹は送信の塗りにだけ使うので、ガラスの地に墨の記号にする。
    private func receiptButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "camera")
                .font(.body.weight(.semibold))
                // 記号は幅が広く、アクセシビリティサイズの文字では 44pt の丸からはみ出すので、大きさに上限を設ける。
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .frame(width: 44, height: 44)
                .foregroundStyle(Theme.ink)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel("レシートを読み取る")
        // iOS 26 では、付けたボタンを指す吹き出しの形で出る。
        .confirmationDialog("レシートを読み取る", isPresented: showsReceiptChoice, titleVisibility: .visible) {
            if canUseDocumentCamera {
                Button("撮る") { chooseReceiptSource(.camera) }
            }
            Button("写真から選ぶ") { chooseReceiptSource(.photos) }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("画像はこの iPhone の中で読み取り、保存も送信もしません。")
        }
    }

    /// 入力の例。アクセシビリティサイズの文字では例だけにする。入力欄の幅に収まらない案内は、
    /// 読めないほど小さく縮められるため。例の「ランチ 850」は訳さない（解析が日本語の入力を前提にしているため）。
    ///
    /// 色は補足の文字と同じにする。システムの既定の薄い灰色は、ガラスの地の上で 3:1 に届かないため。
    private var prompt: Text {
        let text = if targetsHousehold {
            // 「自分／家族」を取り違えて記録しないよう、家計に記録することを例の文でも示す。アクセシビリティサイズでも
            // 「家族」の印だけは残す（例だけにすると、「自分」のときと見分けがつかないため）。
            dynamicTypeSize.isAccessibilitySize ? Text("家族: ランチ 850") : Text("家族に記録（ランチ 850）")
        } else if dynamicTypeSize.isAccessibilitySize {
            Text(verbatim: "ランチ 850")
        } else {
            Text("ランチ 850 のように入力")
        }
        return text.foregroundStyle(Theme.inkSecondary)
    }

    /// 入力欄の名前（VoiceOver が読む）。
    private var fieldLabel: Text {
        targetsHousehold ? Text("家族の家計に記録") : Text("記録や質問")
    }
}

#Preview {
    @Previewable @State var text = "ランチ 850"
    InputBar(text: $text, isSending: false, send: {})
        .padding()
}
