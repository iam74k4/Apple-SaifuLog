import SwiftUI

/// ① ようこそ。初回だけ出す。
///
/// 何ができるか（1 行）と、記録をどこに置くか（1 行）だけを伝え、「はじめる」でホームへ進む。入力の例は、続いて開く記録の
/// 無いホームに、押すと入力欄に入る形で並べる（`HomeExamples`。前はここにも同じような例を並べ、続けて同じ例を見せていた）。
/// 状態と操作は `OnboardingModel` が持ち、進み方は `OnboardingView` が決める。
struct WelcomeView: View {
    /// 「はじめる」。
    let start: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var markSize = 64

    var body: some View {
        ScrollView {
            header
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
        // 記録の置き場所の 1 行は「はじめる」のすぐ上に置く（見出しの下に続けると、上に寄って画面の真ん中が大きく空いた）。
        .safeAreaBar(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                privacyNote
                startButton
            }
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

#Preview {
    WelcomeView(start: {})
}
