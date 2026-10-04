import SaifuLogCore
import StoreKit
import SwiftUI

/// ⑨ プレミアム。下から出すシート（用が済めば閉じる一時的な画面のため）。入口は設定（⑧）と、無料体験が終わった後の
/// 最初の起動（一度だけ）と、無料の回数を使い切ったときと、月のまとめ（⑦）の無料の人へのカテゴリ別の予算の案内。
///
/// 上から、プレミアムでできること（機能ごとの効きめと、無料との違い。まだ出していない機能があれば「近日」と書く）、価格
/// （App Store の表示のまま）と買い切り・ファミリー共有、無料のまま使えること、無料体験の説明（まだ体験していないときだけ。
/// 体験は無料で、終わっても自動で課金されないこと）、購入の復元、利用規約とプライバシーポリシーを並べる。状態と操作は
/// `PremiumSheetModel`（購入そのものは `PurchaseManager`）。
///
/// 体験と購入のボタンは、下に固定したガラスの帯に置く（どこまで読んでいても押せるように。内容はその下を流れる）。主の塗り
/// （墨か白）は、いちばん先に押してほしいボタン 1 つにだけ使う。まだ体験していなければ体験（0 円で全部を試せるので、買う前に使ってみてもらう
/// のがいちばん確かな案内になるため）、体験の後と体験中は購入。体験と購入は、塗りではなくボタンの文（「14日間 無料で試す」と
/// 価格・「買い切り」）と、2 つのボタンの間の一言（「0円。体験が終わっても自動で課金されません。」）で見分けさせる。体験の商品が
/// App Store に無いときは体験を案内しない（`PurchaseManager.offersTrial`）。
struct PremiumSheet: View {
    @Bindable var model: PremiumSheetModel

    @Environment(\.dismiss) private var dismiss
    /// 購入の手続きを StoreKit に頼む（シートを出す場面を StoreKit に教える）。
    @Environment(\.purchase) private var purchase

    /// Apple の標準の利用規約（EULA）。アプリ独自の利用規約は持たない。
    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    hero
                    SpendingChoicesPreview()
                    Text("自分の記録での組み替えには、14日以上前から7日以上の支出記録が必要です。記録が揃ってから無料体験を始めると、十分に試せます。")
                        .font(.footnote).foregroundStyle(Theme.inkSecondary)
                    DisclosureGroup("ほかにできること") { benefits.padding(.top, 12) }
                    if model.status.canPurchase {
                        priceSection
                    }
                    freeFeatures
                    // 体験の説明は、下の帯の体験のボタンのすぐ上に来るよう、後ろの方に置く。
                    if model.showsTrial {
                        trialTerms
                    }
                    restoreSection
                    links
                }
                .foregroundStyle(Theme.ink)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .containerRelativeFrame(.horizontal)
            }
            #if DEBUG
            // 撮影用のデモで、体験の説明とボタンを写すときだけ下の端から開く。
            .defaultScrollAnchor(model.screenshotScrollsToBottom ? .bottom : nil)
            #endif
            .background(Theme.background)
            // 文の多い画面なので、上へ流れた見出しや文が「閉じる」の後ろで透けて重ならないよう、上ははっきりした効果にする
            // （ホームの帯と同じ）。下の帯にも文（「0円。…」）を置くので、下も同じにする（レシートの読み取り結果と同じ）。
            .scrollEdgeEffectStyle(.hard, for: [.top, .bottom])
            .safeAreaBar(edge: .bottom) {
                if model.status.canPurchase {
                    actionBar
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // シートを閉じるボタンの専用のキーにする（英語では Close。VoiceOver の操作の「閉じる」などは Dismiss と訳すことが
                    // あり、同じキーにすると言い方が合わなくなるため）。
                    Button {
                        dismiss()
                    } label: {
                        Text(LocalizedStringResource(
                            "閉じる（プレミアムのシート）", defaultValue: "閉じる",
                            comment: "プレミアムのシート（⑨）の左上の、シートを閉じるボタン"
                        ))
                    }
                    .disabled(model.isBusy)
                }
            }
        }
        .task { await model.loadProducts() }
        // 購入や復元の途中は、下へのスワイプで閉じさせない（手続きは閉じても続くが、結果を知らせる場所が無くなるため）。
        .interactiveDismissDisabled(model.isBusy)
        .alert(
            model.alert?.title ?? Text(verbatim: ""),
            isPresented: showsAlert,
            presenting: model.alert
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { alert in
            alert.message
        }
    }

    private var showsAlert: Binding<Bool> {
        Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })
    }

    // MARK: - 見出し

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("サイフログ プレミアム")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            statusText
                .foregroundStyle(Theme.inkSecondary)
        }
    }

    private var statusText: Text {
        switch model.status {
        case .free:
            Text("いつもの支出を、欲しいものへ。まずは回数を変えてみてください。")
        case .trial(let days, let endsAt):
            Text("無料体験中です。あと \(days) 日（\(endsAt.formatted(.dateTime.month().day().hour().minute())) まで）使えます。")
        case .trialEnded:
            Text("14日間の無料体験は終わりました。記録と決めた予算は、そのまま残っています。")
        case .premium(.purchased):
            Text("プレミアムを購入済みです。ありがとうございます。")
        case .premium(.familyShared):
            Text("ファミリー共有で、プレミアムを使えます。")
        }
    }

    // MARK: - プレミアムでできること

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("プレミアムでできること")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(PremiumFeature.allCases) { feature in
                    PremiumBenefitRow(feature: feature)
                    if feature != PremiumFeature.allCases.last {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 16)
            .background(Theme.surface, in: .rect(cornerRadius: 20))
        }
    }

    // MARK: - 価格

    private var priceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            priceRow
            Text("一度の購入でずっと使えます（サブスクではありません）。ファミリー共有に対応しているので、家族も追加の購入なしで使えます。")
                .font(.footnote)
                .foregroundStyle(Theme.inkSecondary)
        }
    }

    @ViewBuilder
    private var priceRow: some View {
        switch model.purchases.productsState {
        case .loaded:
            if let price = model.premiumPrice {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: price)
                        .font(.largeTitle.bold())
                        .monospacedDigit()
                        // 金額は桁の途中で折り返さない。
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("買い切り・ファミリー共有対応")
                        .font(.subheadline.weight(.semibold))
                }
                .accessibilityElement(children: .combine)
            }
        case .notLoaded, .loading:
            HStack(spacing: 8) {
                ProgressView()
                    .accessibilityHidden(true)
                Text("価格を読み込んでいます…")
                    .foregroundStyle(Theme.inkSecondary)
            }
            .accessibilityElement(children: .combine)
        case .failed:
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text("価格を読み込めませんでした。インターネットの接続を確かめて、もう一度お試しください。")
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                        .accessibilityHidden(true)
                }
                .foregroundStyle(Theme.inkSecondary)
                Button {
                    Task { await model.loadProducts() }
                } label: {
                    // 操作のボタンは文字の強調の色（AccentColor。本文と同じ墨）にし、記号を添えて押せることを示す。
                    Label("もう一度読み込む", systemImage: "arrow.clockwise")
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.accentText)
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                }
            }
        }
    }

    // MARK: - 無料体験の説明

    private var trialTerms: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("14日間の無料体験について")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            // 審査ガイドライン 3.1.1 の、期間限定の体験の説明（期間・終わった後に使えなくなるもの・料金がかかるか）。
            Text("14日間、プレミアムの機能をすべて無料で使えます。体験は無料で、終わっても自動で課金されることはありません（続けて使うときだけ、プレミアムを購入してください）。体験が終わると、プレミアムの機能は使えなくなります（記録や決めた予算は消えません）。体験は1つの Apple アカウントにつき1回です。始めるときに App Store の確認が出ます（0円）。")
                .font(.footnote)
                .foregroundStyle(Theme.inkSecondary)
        }
    }

    // MARK: - 無料のまま使えること

    /// 記録は無料で無制限（docs/design.md §6）であることを、買う前に伝える。プレミアムが記録の上に足すものだと分かるように。
    private var freeFeatures: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("無料のまま使えること")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 10) {
                freeItem(Text("ひとこと入力と AI の読み取り（回数の制限なし）"))
                freeItem(Text("声の入力と Siri・ショートカット"))
                freeItem(Text("Apple Pay の支払いとくり返しの記録"))
                freeItem(Text("月の予算・月のまとめ・週のふりかえり"))
                freeItem(Text("iCloud 同期と CSV 書き出し"))
            }
            // 「外へ出ません」とは書かない（CSV の書き出しは利用者が選んだ先へ送れるため）。PRIVACY.md と同じ言い方にする。
            Text("広告は出しません。記録はこの iPhone（iCloud 同期をオンにしたときは、あなたの iCloud にも）に保存し、開発者や第三者へ送信しません。")
                .font(.footnote)
                .foregroundStyle(Theme.inkSecondary)
        }
    }

    private func freeItem(_ text: Text) -> some View {
        Label {
            text
        } icon: {
            // 色はカテゴリ・収入・注意の意味のある表示にだけ使うので、チェックは墨にする（収入の緑にしない。§7）。
            Image(systemName: "checkmark")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.ink)
                .accessibilityHidden(true)
        }
        .font(.subheadline)
    }

    // MARK: - 体験と購入のボタン（下の帯）

    private var actionBar: some View {
        VStack(spacing: 8) {
            if model.showsTrial {
                trialButton
                Text("0円。体験が終わっても自動で課金されません。")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
                purchaseButton(isPrimary: false)
            } else {
                purchaseButton(isPrimary: true)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        // 下に置き続ける帯なので、文字の大きさに上限を設ける（ホームの帯と入力欄と同じ AX1）。最大の文字のままだと、ボタンの文が
        // 2〜3 行に折り返して帯が画面の 3 分の 2 ほどを占め、上の説明がほとんど読めなくなった（シミュレータの iOS 26.4 の AX5）。
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private var trialButton: some View {
        Button {
            Task { await model.startTrial(using: { try await purchase($0) }) }
        } label: {
            HStack(spacing: 8) {
                if model.inFlight == .trial14 {
                    ProgressView()
                        .tint(trialLabelColor)
                        .accessibilityHidden(true)
                    Text("体験を始めています…")
                } else {
                    Text("14日間 無料で試す")
                }
            }
            .fontWeight(.semibold)
            .foregroundStyle(trialLabelColor)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.glassProminent)
        // tint は塗りの色になる。主の塗り（`accentFill`）を明示する。
        .tint(Theme.accentFill)
        .disabled(!model.canStartTrial)
        .accessibilityHint("料金はかかりません。App Store の確認が出ます")
    }

    /// 体験のボタンの文字の色。押せるときは主の塗りの上なので onAccent、押せないとき（手続き中を含む）は塗りが灰色のガラスに
    /// 変わるので補足の文字の色（購入のボタンと同じ）。
    private var trialLabelColor: Color {
        model.canStartTrial ? Theme.onAccent : Theme.inkSecondary
    }

    /// 購入のボタン。体験のボタンを出しているときは塗らないガラスのボタン（主の操作を 1 つに見せるため）。
    @ViewBuilder
    private func purchaseButton(isPrimary: Bool) -> some View {
        let button = Button {
            Task { await model.buyPremium(using: { try await purchase($0) }) }
        } label: {
            HStack(spacing: 8) {
                if model.inFlight == .premium {
                    ProgressView()
                        .tint(purchaseLabelColor(isPrimary: isPrimary))
                        .accessibilityHidden(true)
                }
                if model.inFlight == .premium {
                    Text("購入の手続き中…")
                } else if let price = model.premiumPrice {
                    // 大きな文字で 1 行に収まらなければ「（買い切り）」を外す（ガラスのボタンは 1 行の高さで、折り返さずに文の
                    // 終わりを省くため。買い切りであることは、上の価格の欄と体験の説明にも書いてある）。
                    ViewThatFits(in: .horizontal) {
                        Text("\(price) で購入する（買い切り）")
                        Text("\(price) で購入する")
                    }
                } else {
                    Text("購入する")
                }
            }
            .fontWeight(.semibold)
            .foregroundStyle(purchaseLabelColor(isPrimary: isPrimary))
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        if isPrimary {
            button
                .buttonStyle(.glassProminent)
                .tint(Theme.accentFill)
                .disabled(!model.canPurchase)
                .accessibilityHint("App Store の購入の確認が出ます")
        } else {
            button
                .buttonStyle(.glass)
                .disabled(!model.canPurchase)
                .accessibilityHint("App Store の購入の確認が出ます")
        }
    }

    /// 購入のボタンの文字と進行中の印の色。塗りのボタンで押せるときは主の塗りの上なので onAccent、ガラスのボタンで押せるときは墨。
    /// 押せないとき（手続き中を含む）は補足の文字の色にする（入力欄の送信・予算の保存と同じ）。手続き中も墨のままだと、ダークでは
    /// 暗い灰色の上に墨が載り、「購入の手続き中…」と進行中の印が地に沈んで読めないため。
    private func purchaseLabelColor(isPrimary: Bool) -> Color {
        guard model.canPurchase else { return Theme.inkSecondary }
        return isPrimary ? Theme.onAccent : Theme.ink
    }

    // MARK: - 復元とリンク

    private var restoreSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                Task { await model.restore() }
            } label: {
                HStack(spacing: 8) {
                    // 設定の「購入の復元」と同じ記号と、文字の強調の色（AccentColor。本文と同じ墨なので、記号で押せることを示す）。
                    // 押せないときは薄くする。
                    Label("購入の復元", systemImage: "arrow.clockwise")
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.accentText)
                        .opacity(model.isBusy ? 0.5 : 1)
                    if model.purchases.isRestoring {
                        ProgressView()
                            .accessibilityHidden(true)
                    }
                }
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .disabled(model.isBusy)
            .accessibilityHint("この Apple アカウントで購入したプレミアムを読み込みます")
            Text("機種を変えたときなどに、この Apple アカウントで購入したプレミアムを読み込みます。")
                .font(.footnote)
                .foregroundStyle(Theme.inkSecondary)
        }
    }

    private var links: some View {
        VStack(alignment: .leading, spacing: 4) {
            externalLink("利用規約（Apple の標準 EULA）", destination: Self.termsURL)
            externalLink("プライバシーポリシー", destination: SettingsModel.privacyPolicyURL)
            Text("お支払いと購入の記録は Apple の App Store が扱います。購入の情報を、アプリから開発者やほかの誰かへ送ることはありません。")
                .font(.footnote)
                .foregroundStyle(Theme.inkSecondary)
                .padding(.top, 4)
        }
    }

    /// Safari で開くリンク。アプリの外へ出ることを、矢印の記号と VoiceOver の説明で示す（設定の画面と同じ）。
    private func externalLink(_ title: LocalizedStringKey, destination: URL) -> some View {
        Link(destination: destination) {
            HStack(spacing: 8) {
                Text(title)
                Image(systemName: "arrow.up.forward.square")
                    .accessibilityHidden(true)
            }
            // 折り返した行を左にそろえる（リンクの中の文字は、既定では折り返した行が中央にそろうため）。
            .multilineTextAlignment(.leading)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .accessibilityHint("Safari で開きます")
    }
}

/// プレミアムの印（主の塗りの角丸の四角に onAccent の記号。ライトは墨の地に白、ダークは白の地に墨）。プレミアムのシートの見出しと
/// 機能の行・月のまとめの案内で使う。記号は飾りなので読ませない。
struct PremiumSymbolTile: View {
    let symbolName: String
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(Theme.onAccent)
            .frame(width: size, height: size)
            .background(Theme.accentFill, in: .rect(cornerRadius: size * 0.28))
            .accessibilityHidden(true)
    }
}

/// プレミアムでできることの行（機能の名前・効きめ・無料との違い）。
enum PremiumFeature: CaseIterable, Identifiable {
    case spendingChoices
    case receiptScan
    case question
    case categoryBudget
    /// 先週のふりかえりと月のまとめの AI の一言。
    case recapAI

    var id: Self { self }

    /// まだ出していない機能か（「近日」と書く。まだできないことを、できるように書かないため）。いまはすべて出している。
    var isComingSoon: Bool {
        switch self {
        case .spendingChoices, .receiptScan, .question, .categoryBudget, .recapAI: false
        }
    }

    /// 行の印（SF Symbols）。
    var symbolName: String {
        switch self {
        case .spendingChoices: "arrow.triangle.branch"
        case .receiptScan: "doc.text.viewfinder"
        case .question: "bubble.left.and.text.bubble.right"
        case .categoryBudget: "chart.pie"
        case .recapAI: "sparkles"
        }
    }
}

private struct PremiumBenefitRow: View {
    let feature: PremiumFeature

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            PremiumSymbolTile(symbolName: feature.symbolName)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    title
                        .font(.body.weight(.semibold))
                    comingSoonBadge
                }
                note
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
                // 無料との違い。小さな札（灰色の地）にして、何が増えるのかを一目で分かるようにする。
                difference
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.track, in: .capsule)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 14)
        // 名前・近日・効きめ・無料との違いを 1 つの要素として読ませる。
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var comingSoonBadge: some View {
        if feature.isComingSoon {
            Text("近日")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.inkSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .overlay(Capsule().strokeBorder(Theme.inkSecondary))
        }
    }

    private var title: Text {
        switch feature {
        case .spendingChoices: Text("いつもの支出を、欲しいものへ")
        case .receiptScan: Text("レシートの読み取りが無制限")
        case .question: Text("家計への質問が無制限")
        // 予算を決める画面の見出し（英語は Budgets by category）とは別のキーにする。行の名前は、英語でほかの行と同じく
        // 語頭を大文字にするため。
        case .categoryBudget: Text(LocalizedStringResource(
            "カテゴリ別の予算（プレミアムの行）", defaultValue: "カテゴリ別の予算",
            comment: "プレミアムのシート（⑨）。プレミアムでできることの行の名前"
        ))
        case .recapAI: Text("ふりかえりの AI の一言")
        }
    }

    private var note: Text {
        switch feature {
        // 読み取った後に確かめてから記録すること、数えるのは記録したときだけであることを添える（無料の 5 回の数え方が分かるように）。
        case .spendingChoices: Text("買う前チェックで、カフェ・娯楽の記録をもとに回数を減らす案を組み合わせ、買い物後の余裕を比較できます。記録が十分にあるときに使え、AI対応は不要です。")
        case .receiptScan: Text("撮るか写真から選ぶと、品目ごとにカテゴリを分けて読み取ります。確かめてから記録し、数えるのは記録したときだけです。")
        // 例はホームの入力の例と同じ文にする（英語でも訳さない。解析は日本語の入力を前提にしているため）。
        case .question: Text("「今月カフェいくら?」のように聞くと、数字はアプリが計算して答えます。")
        case .categoryBudget: Text("食費・交通など、カテゴリごとにも月の予算を決められ、月のまとめで使った額と比べられます。")
        // AI の使えない端末では、プレミアムでも一言は付かない。買ってから気づくことが無いよう、ここで書いておく。
        case .recapAI: Text("先週のふりかえりと月のまとめに、端末内の AI が一言を添えます（Apple Intelligence に対応した iPhone のみ。数字はどちらもアプリが計算します）。")
        }
    }

    private var difference: Text {
        switch feature {
        case .spendingChoices: Text("買い物前後の予算チェックは無料")
        case .receiptScan: Text("無料は月\(QuotaFeature.receiptScan.freeMonthlyLimit)回まで")
        case .question: Text("無料は月\(QuotaFeature.question.freeMonthlyLimit)回まで")
        case .categoryBudget: Text("無料は全体の予算だけ")
        case .recapAI: Text("無料は決まった文だけ")
        }
    }
}

/// 購入・復元の結果のアラートの文。
extension PurchaseAlert {
    var title: Text {
        switch self {
        case .pending: Text("購入の承認を待っています")
        case .purchaseFailed(let failure): failure.title(restoring: false)
        case .restored: Text("購入を復元しました")
        case .nothingToRestore: Text("復元できる購入はありませんでした")
        case .restoreFailed(let failure): failure.title(restoring: true)
        }
    }

    var message: Text {
        switch self {
        case .pending:
            Text("承認されると、自動でプレミアムが使えるようになります。")
        case .purchaseFailed(let failure), .restoreFailed(let failure):
            failure.message
        case .restored:
            Text("プレミアムを使えます。")
        case .nothingToRestore:
            Text("この Apple アカウントで購入したプレミアムは見つかりませんでした。購入したときの Apple アカウントでサインインしているか、お確かめください。")
        }
    }
}

extension PurchaseFailure {
    func title(restoring: Bool) -> Text {
        switch self {
        case .network: Text("App Store に接続できませんでした")
        case .notAllowed: Text("この iPhone では購入が制限されています")
        case .productUnavailable: Text("いまは購入できません")
        case .unverified: Text("購入を確かめられませんでした")
        case .cancelled, .unknown: restoring ? Text("購入を復元できませんでした") : Text("購入を完了できませんでした")
        }
    }

    var message: Text {
        switch self {
        case .network: Text("インターネットの接続を確かめて、もう一度お試しください。")
        case .notAllowed: Text("スクリーンタイムの「App 内課金」などの制限をお確かめください。")
        case .productUnavailable: Text("この国や地域の App Store では、いま購入できません。時間をおいて、もう一度お試しください。")
        case .unverified: Text("App Store の購入の記録を確かめられなかったため、プレミアムを有効にしていません。「購入の復元」をお試しください。")
        case .cancelled, .unknown: Text("時間をおいて、もう一度お試しください。")
        }
    }
}

#Preview("無料") {
    PremiumSheet(model: PremiumSheetModel(purchases: PurchaseManager(loadPurchases: { [] })))
}
