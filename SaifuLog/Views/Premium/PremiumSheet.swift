import SaifuLogCore
import StoreKit
import SwiftUI

/// ⑨ プレミアム。下から出すシート（用が済めば閉じる一時的な画面のため）。入口は設定（⑧）と、無料体験が終わった後の
/// 最初の起動（一度だけ）。
///
/// 無料との違い（まだ出していない機能があれば「近日」と書く）、価格（App Store の表示のまま）、買い切り・ファミリー共有、
/// 無料体験（まだ体験していないときだけ。体験は無料で、終わっても自動で課金されないこと）、購入の復元、利用規約と
/// プライバシーポリシーを出す。状態と操作は `PremiumSheetModel`（購入そのものは `PurchaseManager`）。
///
/// 山吹の塗りは購入のボタンにだけ使う。体験のボタンは塗らない（主の操作を 1 つに見せ、0 円の体験と買い切りの購入を
/// 取り違えさせないため）。
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
                    header
                    comparison
                    if model.status.canPurchase {
                        purchaseSection
                    }
                    if model.showsTrial {
                        trialSection
                    }
                    restoreSection
                    links
                }
                .foregroundStyle(Theme.ink)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            #if DEBUG
            // 撮影用のデモで、体験の説明とボタンを写すときだけ下の端から開く。
            .defaultScrollAnchor(model.screenshotScrollsToBottom ? .bottom : nil)
            #endif
            .background(Theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // 取り消しのバナーの「閉じる」（英語は Dismiss）とは別のキーにする。英語ではシートを閉じるボタンは Close のため。
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("サイフログ プレミアム")
                .font(.title.bold())
                .accessibilityAddTraits(.isHeader)
            statusText
                .foregroundStyle(Theme.inkSecondary)
        }
    }

    private var statusText: Text {
        switch model.status {
        case .free:
            Text("買い切りで、プレミアムの機能をすべて使えます。")
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

    // MARK: - 無料との違い

    private var comparison: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("無料とプレミアムの違い")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(PremiumFeature.allCases) { feature in
                    PremiumFeatureRow(feature: feature)
                    if feature != PremiumFeature.allCases.last {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 16)
            .background(Theme.surface, in: .rect(cornerRadius: 16))
            Text("ひとこと入力と AI の文章の読み取り、CSV 書き出しは、無料のまま回数の制限なく使えます。広告はありません。")
                .font(.footnote)
                .foregroundStyle(Theme.inkSecondary)
        }
    }

    // MARK: - 購入

    private var purchaseSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            priceRow
            Text("一度の購入でずっと使えます（サブスクではありません）。ファミリー共有に対応しているので、家族も追加の購入なしで使えます。")
                .font(.footnote)
                .foregroundStyle(Theme.inkSecondary)
            Button {
                Task { await model.buyPremium(using: { try await purchase($0) }) }
            } label: {
                HStack(spacing: 8) {
                    if model.inFlight == .premium {
                        ProgressView()
                            .tint(purchaseLabelColor)
                            .accessibilityHidden(true)
                    }
                    if model.inFlight == .premium {
                        Text("購入の手続き中…")
                    } else if let price = model.premiumPrice {
                        Text("\(price) で購入する")
                    } else {
                        Text("購入する")
                    }
                }
                .fontWeight(.semibold)
                .foregroundStyle(purchaseLabelColor)
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.accentFill)
            .disabled(!model.canPurchase)
            .accessibilityHint("App Store の購入の確認が出ます")
        }
    }

    /// 購入のボタンの文字と進行中の印の色。押せるときは山吹の塗りの上なので墨。押せないとき（手続き中を含む）は塗りが
    /// 灰色のガラスに変わるので、補足の文字の色にする（入力欄の送信・予算の保存と同じ）。手続き中も墨のままだと、ダークでは
    /// 暗い灰色の上に墨が載り、「購入の手続き中…」と進行中の印が地に沈んで読めないため。
    private var purchaseLabelColor: Color {
        model.canPurchase ? Theme.onAccent : Theme.inkSecondary
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
                    Text("もう一度読み込む")
                        // 操作のボタンは、ほかの画面のボタンと同じ文字の強調の色（AccentColor）にする。
                        .foregroundStyle(Theme.accentText)
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                }
            }
        }
    }

    // MARK: - 無料体験

    private var trialSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("14日間の無料体験")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            // 審査ガイドライン 3.1.1 の、期間限定の体験の説明（期間・終わった後に使えなくなるもの・料金がかかるか）。
            Text("14日間、プレミアムの機能をすべて無料で使えます。体験は無料で、終わっても自動で課金されることはありません（続けて使うときだけ、プレミアムを購入してください）。体験が終わると、プレミアムの機能は使えなくなります（記録や決めた予算は消えません）。体験は1つの Apple アカウントにつき1回です。始めるときに App Store の確認が出ます（0円）。")
                .font(.footnote)
                .foregroundStyle(Theme.inkSecondary)
            Button {
                Task { await model.startTrial(using: { try await purchase($0) }) }
            } label: {
                HStack(spacing: 8) {
                    if model.inFlight == .trial14 {
                        ProgressView()
                            .accessibilityHidden(true)
                        Text("体験を始めています…")
                    } else {
                        Text("14日間の無料体験を始める")
                    }
                }
                .fontWeight(.semibold)
                .foregroundStyle(model.canStartTrial || model.inFlight == .trial14 ? Theme.ink : Theme.inkSecondary)
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glass)
            .disabled(!model.canStartTrial)
            .accessibilityHint("料金はかかりません。App Store の確認が出ます")
        }
    }

    // MARK: - 復元とリンク

    private var restoreSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                Task { await model.restore() }
            } label: {
                HStack(spacing: 8) {
                    Text("購入の復元")
                        // 設定の「購入の復元」と同じ、文字の強調の色（AccentColor）。押せないときは薄くする。
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

/// 無料とプレミアムの違いの行。
enum PremiumFeature: CaseIterable, Identifiable {
    case receiptScan
    case question
    case categoryBudget
    /// 先週のふりかえりと月のまとめの AI の一言。
    case recapAI

    var id: Self { self }

    /// まだ出していない機能か（「近日」と書く。まだできないことを、できるように書かないため）。いまはすべて出している。
    var isComingSoon: Bool {
        switch self {
        case .receiptScan, .question, .categoryBudget, .recapAI: false
        }
    }
}

private struct PremiumFeatureRow: View {
    let feature: PremiumFeature

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // アクセシビリティサイズの文字では、名前と「近日」、無料とプレミアムを横に並べずに縦に積む。横に並べると、
            // 名前が 2〜3 文字ごとに折り返し、「プレミアム」の語も途中で切れた（シミュレータの iOS 26.2 の AX5 で確かめた）。
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    titleText
                    comingSoonBadge
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    titleText
                    comingSoonBadge
                }
            }
            if let note {
                note
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
            }
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) { values }
            } else {
                // 1 行に収まらなければ（大きな文字サイズ）縦に積む。
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 24) { values }
                    VStack(alignment: .leading, spacing: 2) { values }
                }
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        // 名前・近日・補足・無料・プレミアムを 1 つの要素として読ませる。
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var values: some View {
        valueLabel(Text("無料"), free)
        valueLabel(Text("プレミアム"), premium)
    }

    @ViewBuilder
    private func valueLabel(_ label: Text, _ value: Text) -> some View {
        let labelText = label
            .font(.footnote)
            .foregroundStyle(Theme.inkSecondary)
        let valueText = value
            .font(.subheadline.weight(.semibold))
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 0) {
                labelText
                valueText
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                labelText
                valueText
            }
        }
    }

    private var titleText: some View {
        title
            .font(.body.weight(.semibold))
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
        case .receiptScan: Text("レシート・スクショの読み取り")
        case .question: Text("家計への質問")
        // 予算を決める画面の見出し（英語は Budgets by category）とは別のキーにする。表の行の名前は、英語でほかの行と同じく
        // 語頭を大文字にするため。
        case .categoryBudget: Text(LocalizedStringResource(
            "カテゴリ別の予算（プレミアムの表）", defaultValue: "カテゴリ別の予算",
            comment: "プレミアムのシート（⑨）。無料とプレミアムの違いの表の行"
        ))
        case .recapAI: Text("ふりかえりの AI の一言")
        }
    }

    private var note: Text? {
        switch feature {
        case .categoryBudget: Text("食費・交通など、カテゴリごとにも月の予算を決められます。使った額との比べの表示は近日対応です。")
        // AI の使えない端末では、プレミアムでも一言は付かない。買ってから気づくことが無いよう、ここで書いておく。
        case .recapAI: Text("先週のふりかえりと月のまとめに、端末内の AI が一言を添えます（Apple Intelligence に対応した iPhone のみ。数字はどちらもアプリが計算します）。")
        // 読み取った後に確かめてから記録すること、数えるのは記録したときだけであることを添える（無料の 5 回の数え方が分かるように）。
        case .receiptScan: Text("撮るか写真から選ぶと、品目ごとに仕分けて記録できます。数えるのは記録したときだけです。")
        case .question: nil
        }
    }

    private var free: Text {
        switch feature {
        case .receiptScan: Text("月\(QuotaFeature.receiptScan.freeMonthlyLimit)回")
        case .question: Text("月\(QuotaFeature.question.freeMonthlyLimit)回")
        case .categoryBudget, .recapAI: Text("なし")
        }
    }

    private var premium: Text {
        switch feature {
        case .receiptScan, .question: Text("無制限")
        case .categoryBudget, .recapAI: Text("あり")
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

extension PremiumStatus {
    /// 設定の「プレミアム」の行の値（無料／体験中 あと N 日／購入済み／ファミリー共有）。
    var summaryText: Text {
        switch self {
        case .free, .trialEnded: Text("無料")
        case .trial(let days, _): Text("体験中 あと \(days) 日")
        case .premium(.purchased): Text("購入済み")
        case .premium(.familyShared): Text("ファミリー共有")
        }
    }
}

#Preview("無料") {
    PremiumSheet(model: PremiumSheetModel(purchases: PurchaseManager(loadPurchases: { [] })))
}
