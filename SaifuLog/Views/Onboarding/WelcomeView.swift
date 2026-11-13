import SwiftUI

/// ① ようこそ。初回だけ出す。
///
/// 何ができるか（入力の例）、この iPhone で AI が文を読むか（読まなくても記録できること）、記録をどこに置くかを
/// 伝え、「はじめる」で ② 予算を決める へ進む。状態と操作は `OnboardingModel` が持つ。
struct WelcomeView: View {
    let model: OnboardingModel

    @ScaledMetric(relativeTo: .largeTitle) private var markSize = 64

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                header
                examples
                VStack(alignment: .leading, spacing: 20) {
                    let aiStatus = model.aiStatus
                    WelcomeNote(
                        symbolName: aiStatus.isAvailable ? "sparkles" : "text.book.closed",
                        title: aiStatus.title,
                        message: aiStatus.message
                    )
                    WelcomeNote(
                        symbolName: "lock.iphone",
                        title: "記録はこの iPhone の中に",
                        // iCloud 同期は既定でオフなので、見出しの「この iPhone の中に」は案内の時点では正しい。
                        // 設定でオンにしたときだけ利用者の iCloud にも置くことを書き添え、あとで同期を選んでも食い違わないようにする。
                        message: "記録はこの iPhone の中に保存し、文の読み取りもこの iPhone の中で行います。開発者のサーバーはなく、記録や入力した文を開発者や第三者に送ることはありません。設定で iCloud の同期をオンにしたときだけ、記録をあなたの iCloud にも保存し、同じ Apple アカウントの端末どうしでそろえます。"
                    )
                }
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
            Text("サイフログは、「ランチ 850」のように一行送るだけで記録できる家計簿です。分類と計算はアプリが引き受け、同じ入力欄で家計について聞くこともできます。")
                .foregroundStyle(Theme.inkSecondary)
        }
    }

    private var examples: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("こんなふうに書けます")
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            ForEach(WelcomeExample.all) { example in
                WelcomeExampleRow(example: example)
            }
        }
    }

    private var startButton: some View {
        Button {
            model.start()
        } label: {
            Text("はじめる")
                .fontWeight(.semibold)
                // 主ボタンは主の塗りに onAccent の文字（Theme の説明）。
                .foregroundStyle(Theme.onAccent)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.glassProminent)
        .tint(Theme.accentFill)
        .accessibilityHint("月の予算を決める画面に進みます")
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

/// 案内の 1 項目（AI の可否・記録の置き場所）。見出しと本文に、飾りの記号を添える。
private struct WelcomeNote: View {
    let symbolName: String
    let title: LocalizedStringResource
    let message: LocalizedStringResource

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            // アクセシビリティサイズの文字では、本文に幅を使わせるため記号を省く（見出しで分かる）。
            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: symbolName)
                    .font(.headline)
                    .foregroundStyle(Theme.accentText)
                    .frame(minWidth: 24)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
    }
}

extension OnDeviceAIStatus {
    /// ようこその案内の見出し。
    var title: LocalizedStringResource {
        switch self {
        case .available: "この iPhone では AI が文を読みます"
        case .deviceNotEligible: "この iPhone ではキーワード辞書で読みます"
        case .appleIntelligenceNotEnabled, .modelNotReady, .unavailable: "いまはキーワード辞書で読みます"
        }
    }

    /// ようこその案内の本文。AI が使えなくても記録できることを、どの場合にも伝える（使えない端末を欠陥のように見せない）。
    var message: LocalizedStringResource {
        switch self {
        case .available:
            "Apple Intelligence が、この iPhone の中で品目やカテゴリを読み取ります。読み違えたときは、記録の直後に取り消すか、記録をタップして直せます。"
        case .deviceNotEligible:
            "この iPhone は Apple Intelligence に対応していないため、端末内の辞書で金額やカテゴリを読み取ります。上の例のような書き方なら、AI がなくても記録や質問ができます。"
        case .appleIntelligenceNotEnabled:
            "Apple Intelligence がオフのため、端末内の辞書で読み取ります。記録はそのままできます。設定で Apple Intelligence をオンにすると、AI が読むようになります。"
        case .modelNotReady:
            "Apple Intelligence の準備（モデルのダウンロードなど）が済むまでは、端末内の辞書で読み取ります。記録はそのままできます。準備が済むと、AI が読むようになります。"
        case .unavailable:
            "いまは Apple Intelligence を使えないため、端末内の辞書で読み取ります。記録はそのままできます。"
        }
    }
}

#Preview("AI が使える") {
    if let container = try? ModelContainerFactory.makeInMemoryContainer() {
        WelcomeView(model: OnboardingModel(budgetStore: BudgetStore(context: container.mainContext), aiStatus: { .available }))
    }
}

#Preview("非対応の機種") {
    if let container = try? ModelContainerFactory.makeInMemoryContainer() {
        WelcomeView(model: OnboardingModel(budgetStore: BudgetStore(context: container.mainContext), aiStatus: { .deviceNotEligible }))
    }
}
