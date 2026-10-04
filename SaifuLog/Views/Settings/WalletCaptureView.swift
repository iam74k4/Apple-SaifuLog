import Observation
import SaifuLogCore
import SwiftUI

/// 設定の「Apple Pay の支払い」の状態（受け取って、まだ記録していない支払いの数）。
@MainActor
@Observable
final class WalletCaptureModel: Identifiable {
    /// 受け取って、まだ記録していない支払いの数（ホームを開くと記録にする）。
    private(set) var pendingCount = 0

    private(set) var lastReceivedAt: Date?
    private(set) var loadFailed = false

    @ObservationIgnored private let inbox: PaymentInbox

    init(inbox: PaymentInbox? = nil) {
        self.inbox = inbox ?? .shared
        reload()
    }

    func reload() {
        do {
            pendingCount = try inbox.readPending().count
            lastReceivedAt = inbox.lastReceivedAt
            loadFailed = false
        } catch {
            pendingCount = 0
            lastReceivedAt = nil
            loadFailed = true
        }
    }
}

/// 設定の「Apple Pay の支払い」。ショートカットのオートメーション（「取引」）で、Apple Pay で払ったときに金額と店名を
/// サイフログへ渡す作り方を案内する（アプリからオートメーションは作れないので、手順を出す）。docs/design.md §9。
///
/// 通常サイズでは設定を開くボタンを下に固定し、アクセシビリティサイズでは本文と一緒にスクロールする。
struct WalletCaptureView: View {
    let model: WalletCaptureModel
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var openFailed = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 20) {
                    Text("払うだけで、自動で記録").font(.title2.bold())
                    Text("最初に一度だけ設定").font(.subheadline).foregroundStyle(Theme.inkSecondary)
                    let layout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                        : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
                    layout {
                        flowNode("タッチ決済", symbol: "wave.3.right.circle.fill")
                        Image(systemName: dynamicTypeSize.isAccessibilitySize ? "arrow.down" : "arrow.right")
                            .accessibilityHidden(true).foregroundStyle(Theme.inkSecondary)
                        flowNode("自動で受信", symbol: "tray.and.arrow.down.fill")
                        Image(systemName: dynamicTypeSize.isAccessibilitySize ? "arrow.down" : "arrow.right")
                            .accessibilityHidden(true).foregroundStyle(Theme.inkSecondary)
                        flowNode("次に開くと記録", symbol: "checkmark.circle.fill")
                    }
                    Text("払うたびに金額を入力したり、アプリを開いたりする必要はありません。")
                        .font(.subheadline)
                    Label("カテゴリもおまかせ", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                }.padding(.vertical, 8)
            }.listRowBackground(Theme.surface)

            if dynamicTypeSize.isAccessibilitySize {
                Section { shortcutsButton }.listRowBackground(Theme.surface)
            }

            Section("受信状況") {
                if model.loadFailed {
                    LoadFailedView(retry: { model.reload() })
                } else {
                    if model.pendingCount > 0 {
                        Label("受け取った支払いが \(model.pendingCount) 件あります。ホームに戻ると記録します。", systemImage: "tray.and.arrow.down")
                    } else if model.lastReceivedAt != nil {
                        Label("取り込み待ちはありません", systemImage: "tray")
                    }
                    if let date = model.lastReceivedAt {
                        LabeledContent("最終受信") { Text(date, format: .dateTime.month().day().hour().minute()) }
                        Text("受信日時は、オートメーションが今も有効かを保証するものではありません。")
                            .font(.caption).foregroundStyle(Theme.inkSecondary)
                    } else if model.pendingCount == 0 {
                        Label("まだ支払いを受け取っていません", systemImage: "antenna.radiowaves.left.and.right")
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
            }.listRowBackground(Theme.surface)

            Section("最初の設定・4ステップ") {
                setupStep(1, title: "支払いをきっかけにする", symbol: "creditcard") {
                    Text("「ショートカット」App の「オートメーション」で「＋」を押し、「取引」を選びます。")
                }
                setupStep(2, title: "毎回の確認をなくす", symbol: "bolt.fill") {
                    Text("記録したいカードを選び、「すぐに実行」にして「次へ」を押します。")
                }
                setupStep(3, title: "サイフログへ渡す", symbol: "tray.and.arrow.down") {
                    Text("「新規の空のオートメーション」から「アクションを追加」を押し、「サイフログ」の「支払いを記録」を選びます。")
                }
                setupStep(4, title: "金額と店名をつなぐ", symbol: "link") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("「ショートカットの入力」から選びます。固定の金額や店名は入力しません。")
                        mapping("金額", input: "金額", symbol: "yensign.circle")
                        mapping("店名", input: "加盟店", symbol: "storefront")
                        Text("設定できたら「完了」を押します。")
                    }
                }
            }.listRowBackground(Theme.surface)

            Section {
                DisclosureGroup("カテゴリを自動で振り分ける") {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("あなたが直した分類を最優先", systemImage: "checkmark.circle")
                        Label("お店の辞書と端末内AIで補う", systemImage: "sparkles")
                        Label("分からないものだけ確認", systemImage: "questionmark.circle")
                        Text("AIが使えるiPhoneでは、未分類のお店を端末内で振り分けます。金額や日時は変えません。AIの判断は学習せず、あなたが選んだ分類を次回に使います。")
                            .foregroundStyle(Theme.inkSecondary)
                    }.padding(.vertical, 8)
                }
                DisclosureGroup("最初の支払いで確かめる") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("次のタッチ決済のあと、サイフログを開いて金額と店名を確認してください。試すために買い物をする必要はありません。")
                        Text("受信されない場合は、対象カード・「すぐに実行」・金額と加盟店の割り当てを確認してください。")
                        Text("決済やカードによって、金額や店名が渡らないことがあります。金額がない支払いを推測で記録することはありません。")
                    }.padding(.vertical, 8)
                }
                DisclosureGroup("自動記録の範囲") {
                    Text("対象は、このiPhoneで選んだカードを使うタッチ決済です。銀行・カードの利用明細全体を取得する機能ではありません。円の支払いに対応します。")
                        .padding(.vertical, 8)
                    Text("円のほかの通貨の支払いは記録しません。カテゴリはお店の名前で決め、分からないお店は返事で聞き返します（一度選べば、次からそのカテゴリで記録します）。違っていたら、返事の「取り消す」で消せます。")
                }
                DisclosureGroup("データの扱い") {
                    Text("受け取った支払い（金額・店名・日時）は、記録にするまで、この iPhone の中の小さなファイルに置きます。iPhone がロックされていても受け取れるよう、このファイルは、iPhone を起動して最初にロックを解いた後から読める保護にしています。記録にしたら消します。")
                        .padding(.vertical, 8)
                    Text("受信確認のため、最後に受け取った日時だけを端末内に残します。金額や店名は受信状況には残しません。")
                }
            }.font(.subheadline).listRowBackground(Theme.surface)
        }
        .foregroundStyle(Theme.ink)
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.hard, for: .top)
        .background(Theme.background)
        .safeAreaBar(edge: .bottom, spacing: 0) {
            if !dynamicTypeSize.isAccessibilitySize {
                shortcutsButton.padding(.horizontal).padding(.vertical, 8)
            }
        }
        .navigationTitle(Text(.walletCaptureTitle))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.reload() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model.reload() } }
        .onReceive(NotificationCenter.default.publisher(for: PaymentInbox.didReceive)) { _ in model.reload() }
        .alert("ショートカットを開けませんでした", isPresented: $openFailed) {
            Button("OK", role: .cancel) {}
        } message: { Text("「ショートカット」App がインストールされているか確認してください。") }
    }

    private var shortcutsButton: some View {
        Button {
            if let url = URL(string: "shortcuts://") { openURL(url) { openFailed = !$0 } }
        } label: {
            Label("「ショートカット」App を開く", systemImage: "arrow.up.forward.app")
                .fontWeight(.semibold).foregroundStyle(Theme.onAccent)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.glassProminent).tint(Theme.accentFill)
    }

    private func flowNode(_ title: LocalizedStringResource, symbol: String) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(HStackLayout(alignment: .center, spacing: 12))
            : AnyLayout(VStackLayout(spacing: 8))
        return layout {
            Image(systemName: symbol).font(.system(size: 26)).accessibilityHidden(true)
            Text(title).font(.caption.weight(.semibold))
                .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .center)
                .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .center)
    }

    private func setupStep<Content: View>(_ number: Int, title: LocalizedStringResource, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(verbatim: "\(number)").font(.system(size: 16, weight: .bold)).monospacedDigit()
                    .foregroundStyle(Theme.onAccent).frame(width: 30, height: 30)
                    .background(Theme.accentFill, in: .circle).accessibilityHidden(true)
                Label { Text(title).font(.headline) } icon: { Image(systemName: symbol) }
            }
            content().font(.subheadline).foregroundStyle(Theme.inkSecondary)
        }.padding(.vertical, 8)
    }

    private func mapping(_ field: LocalizedStringResource, input: LocalizedStringResource, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label { Text(field) } icon: { Image(systemName: symbol) }.fontWeight(.semibold)
            HStack {
                Image(systemName: "arrow.turn.down.right").accessibilityHidden(true)
                Text(input).padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Theme.track, in: .capsule)
            }
        }.foregroundStyle(Theme.ink)
    }
}

extension LocalizedStringResource {
    /// 設定の「Apple Pay の支払い」（行・画面の題名）。
    static let walletCaptureTitle = LocalizedStringResource(
        "Apple Pay の支払い（設定）", defaultValue: "Apple Pay の支払い",
        comment: "設定の行と画面の題名。Apple Pay で払ったときに、ショートカットのオートメーションで金額と店名をサイフログに渡して記録する"
    )
}

#Preview {
    NavigationStack {
        WalletCaptureView(model: WalletCaptureModel())
    }
}
