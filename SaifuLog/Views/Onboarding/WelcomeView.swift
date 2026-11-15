import SwiftUI

/// ① ようこそ。初回だけ出す。
///
/// 何ができるか（入力の例 3 つ）と、記録をどこに置くか（1 行）だけを伝え、「はじめる」でホームへ進む。前は AI の可否と
/// 置き場所の段落も並べていたが、文が「はじめる」の下に潜るほど長く、例が埋もれたので削った（AI が使えなくても記録できる
/// ので、可否は伝えなくても困らない）。状態と操作は `OnboardingModel` が持ち、進み方は `OnboardingView` が決める。
struct WelcomeView: View {
    /// 「はじめる」。
    let start: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var markSize = 64

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                header
                examples
                privacyNote
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal)
            .padding(.top, 32)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
        // ナビゲーションバーを隠しているので、上へ流した中身が時刻や電池の表示に重なる。高さ 0 の帯の背景を
        // 安全領域の上（ステータスバーの裏）まで広げ、地の色で隠す。
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear
                .frame(height: 0)
                .background(Theme.background)
        }
        // 「はじめる」は画面の下に置き続ける。大きな文字サイズで中身が長くなっても、スクロールせずに進めるように。
        // 下の帯は safeAreaBar に置き、中身がその下を流れるようにする（地を塗らない。スクロール端の効果が下端をぼかす。ホームの入力欄と同じ）。
        .safeAreaBar(edge: .bottom, spacing: 0) {
            startButton
                .padding(.horizontal)
                .padding(.vertical, 8)
        }
    }

    private var header: some View {
        // 飾りの印は文字に合わせて大きくするが、最大の文字サイズでは本文の場所を取りすぎないよう上限を設ける。
        let size = min(markSize, 88)
        return VStack(alignment: .leading, spacing: 12) {
            // 主の塗りに onAccent の記号（アプリのアイコンの地と財布と同じ白と黒。Theme の説明）。
            Image(systemName: "wallet.bifold.fill")
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: size, height: size)
                .background(Theme.accentFill, in: .rect(cornerRadius: size * 0.28))
                .accessibilityHidden(true)
            // 画面でいちばん上の見出し。VoiceOver の見出しの移動で、ここから順に読めるようにする。
            Text("ひとことで家計簿")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text("一行送るだけで記録でき、同じ入力欄で家計について聞けます。")
                .foregroundStyle(Theme.inkSecondary)
        }
    }

    private var examples: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(WelcomeExample.all) { example in
                WelcomeExampleRow(example: example)
            }
        }
    }

    /// 記録の置き場所の 1 行。iCloud 同期は既定でオフなので「この iPhone の中」は案内の時点では正しい。設定でオンにしたときだけ
    /// 利用者の iCloud にも置くことを書き添え、あとで同期を選んでも食い違わないようにする。
    private var privacyNote: some View {
        Label {
            Text("記録はこの iPhone の中に置き、外へは送りません（iCloud の同期は、設定でオンにしたときだけ）。")
        } icon: {
            Image(systemName: "lock")
                .accessibilityHidden(true)
        }
        .font(.footnote)
        .foregroundStyle(Theme.inkSecondary)
    }

    private var startButton: some View {
        Button(action: start) {
            Text("はじめる")
                .fontWeight(.semibold)
                // 主ボタンは主の塗りに onAccent の文字（Theme の説明）。
                .foregroundStyle(Theme.onAccent)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.glassProminent)
        .tint(Theme.accentFill)
        .accessibilityIdentifier(AccessibilityID.Onboarding.startButton)
    }
}

/// 入力の例の 1 行。打つ文を吹き出しのように見せ、下にどう記録されるかを添える。
///
/// 横に並べると、大きな文字サイズで打つ文が途中で折り返して読みにくいので、いつも縦に積む。
private struct WelcomeExampleRow: View {
    let example: WelcomeExample

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: example.text)
                .font(.body.weight(.semibold))
                .monospacedDigit()
            Label {
                Text(example.result)
            } icon: {
                Image(systemName: "arrow.turn.down.right")
            }
            .font(.subheadline)
            .foregroundStyle(Theme.inkSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: .rect(cornerRadius: 16))
        // VoiceOver では 1 つの要素にまとめ、例であることを先に伝える（打つ文だけを読むと、何の文か分からないため）。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("入力例: \(example.text)"))
        .accessibilityValue(Text(example.result))
    }
}

#Preview {
    WelcomeView(start: {})
}
