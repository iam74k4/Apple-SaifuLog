import SaifuLogCore
import SwiftUI

/// 声で入力するマイクのボタン（入力欄の右。入力欄が空なら送信ボタンの位置）。
///
/// 山吹は送信と止めるボタンの塗りにだけ使うので、カメラのボタンと同じくガラスの地に墨の記号にする。
struct VoiceMicButton: View {
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "mic")
                .font(.body.weight(.semibold))
                // 記号は 44pt の丸に収める（カメラのボタンと同じ上限）。
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .frame(width: 44, height: 44)
                .foregroundStyle(isEnabled ? Theme.ink : Theme.inkSecondary)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .disabled(!isEnabled)
        .accessibilityLabel("声で入力")
        .accessibilityHint("話した内容を文字にして入力欄に入れます。送信はしません。")
    }
}

/// 声の入力の間、入力欄の代わりに出す表示（ダウンロードの進み・準備・聞いている・文字にしている）。
///
/// 聞いている間は、確定した文を墨で、途中の文を補足の文字の色（薄く）で出す。途中の文は後から変わりうることを、色の濃さで
/// 伝えるため（VoiceOver では文として読む）。山吹は音の大きさの目安と止めるボタンの塗りにだけ使い、文字には使わない。
struct VoiceInputPanel: View {
    let model: VoiceInputModel
    /// 入力欄に打ちかけの文（書き起こしはこの後ろに入る）。
    let prefix: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            content
                // 入力欄の代わりに画面の下に出し続けるので、文字の大きさに上限を設ける。最大の文字サイズのままだと、1 行に 3 文字ほどしか
                // 入らず、話した内容の確かめにならないうえ、タイムラインがほとんど見えなくなるため（帯と同じ考え方）。
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .glassEffect(.regular, in: .rect(cornerRadius: 22))
            trailingButton
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 6) {
                Text("日本語の音声モデルをダウンロードしています")
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
                // 進捗のバーは山吹の塗り（数字の % も VoiceOver の値で読む）。
                ProgressView(value: progress)
                    .tint(Theme.accentFill)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("日本語の音声モデルをダウンロードしています")
            .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
        case .preparing:
            HStack(spacing: 8) {
                ProgressView()
                    .tint(Theme.inkSecondary)
                Text("準備しています…")
                    .foregroundStyle(Theme.inkSecondary)
            }
            .accessibilityElement(children: .combine)
        case .listening:
            HStack(spacing: 10) {
                VoiceLevelMeter(level: model.level, animates: !reduceMotion)
                transcriptText
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("聞いています…")
            .accessibilityValue(Text(verbatim: model.preview(prefix: prefix).full))
        case .finishing:
            HStack(spacing: 10) {
                ProgressView()
                    .tint(Theme.inkSecondary)
                transcriptText
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("文字にしています…")
            .accessibilityValue(Text(verbatim: model.preview(prefix: prefix).full))
        case .idle, .requestingPermission:
            EmptyView()
        }
    }

    /// 書き起こしの文。まだ何も無ければ「聞いています…」。長くなったら、新しい語が見えるよう頭を省く。
    @ViewBuilder
    private var transcriptText: some View {
        let preview = model.preview(prefix: prefix)
        if preview.full.isEmpty {
            Text(model.phase == .finishing ? "文字にしています…" : "聞いています…")
                .foregroundStyle(Theme.inkSecondary)
        } else {
            Text(Self.styled(settled: preview.settled, tentative: preview.tentative))
                .lineLimit(3)
                .truncationMode(.head)
        }
    }

    /// 確定した文は墨、途中の文は補足の文字の色。文字列は訳さない（話した内容そのもの）。
    private static func styled(settled: String, tentative: String) -> AttributedString {
        var settledPart = AttributedString(settled)
        settledPart.foregroundColor = Theme.ink
        var tentativePart = AttributedString(tentative)
        tentativePart.foregroundColor = Theme.inkSecondary
        return settledPart + tentativePart
    }

    @ViewBuilder
    private var trailingButton: some View {
        switch model.phase {
        case .downloading:
            Button { model.cancelDownload() } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .frame(width: 44, height: 44)
                    .foregroundStyle(Theme.ink)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("ダウンロードの表示を閉じる")
            .accessibilityHint("ダウンロードが続いていれば、次にマイクのボタンを押したときに使えます。")
        case .preparing, .listening, .finishing:
            Button { model.stop(.user) } label: {
                Image(systemName: "stop.fill")
                    .font(.body.weight(.bold))
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .frame(width: 44, height: 44)
                    // 山吹の塗りの上なので墨（Theme の説明）。
                    .foregroundStyle(model.phase == .finishing ? Theme.inkSecondary : Theme.onAccent)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .tint(Theme.accentFill)
            .disabled(model.phase == .finishing)
            .accessibilityLabel("声の入力を止める")
            .accessibilityHint("話した内容を入力欄に入れます。送信はしません。")
        case .idle, .requestingPermission:
            EmptyView()
        }
    }
}

/// マイクの音の大きさの目安（山吹の塗りの棒）。聞こえていることを目で確かめるためのもので、VoiceOver では読まない
/// （「聞いています」と書き起こしの文で伝える）。
struct VoiceLevelMeter: View {
    let level: Double
    /// 動きを減らす設定のときは、棒の高さを変えるだけにして動きの補間をしない。
    let animates: Bool

    /// 棒ごとの伸び方（同じ高さに並ぶと、音に合わせて動いているように見えないため）。
    private static let weights: [Double] = [0.55, 1.0, 0.75, 0.45]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Self.weights.indices, id: \.self) { index in
                Capsule()
                    .fill(Theme.accentFill)
                    .frame(width: 4, height: 6 + 18 * level * Self.weights[index])
            }
        }
        .frame(height: 24)
        .animation(animates ? .easeOut(duration: 0.12) : nil, value: level)
        .accessibilityHidden(true)
    }
}

/// 声の入力の後の知らせ（入力欄の上に少しの間だけ出す）。
struct VoiceNoticeView: View {
    let notice: VoiceInputModel.Notice

    var body: some View {
        Label {
            message
        } icon: {
            Image(systemName: symbol)
        }
        .font(.footnote)
        .foregroundStyle(Theme.inkSecondary)
        // 入力欄の上に重ねて出すので、声の入力の表示と同じ上限にする（同じ文を VoiceOver でも読み上げる）。
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    /// 文は読み上げと同じもの（`Notice.message`。訳した文字列）。
    private var message: Text {
        Text(verbatim: notice.message)
    }

    private var symbol: String {
        switch notice {
        case .nothingHeard: "mic.slash"
        case .failed, .downloadFailed: "exclamationmark.circle"
        case .modelReady: "checkmark.circle"
        }
    }
}
