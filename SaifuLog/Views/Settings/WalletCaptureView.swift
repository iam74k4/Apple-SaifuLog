import Observation
import SaifuLogCore
import SwiftUI

/// 設定の「Apple Pay の支払い」の状態（受け取って、まだ記録していない支払いの数）。
@MainActor
@Observable
final class WalletCaptureModel {
    /// 受け取って、まだ記録していない支払いの数（ホームを開くと記録にする）。
    private(set) var pendingCount = 0

    @ObservationIgnored private let inbox: PaymentInbox

    init(inbox: PaymentInbox? = nil) {
        self.inbox = inbox ?? .shared
        reload()
    }

    func reload() {
        pendingCount = inbox.pending().count
    }
}

/// 設定の「Apple Pay の支払い」。ショートカットのオートメーション（「取引」）で、Apple Pay で払ったときに金額と店名を
/// サイフログへ渡す作り方を案内する（アプリからオートメーションは作れないので、手順を出す）。docs/design.md §9。
struct WalletCaptureView: View {
    let model: WalletCaptureModel

    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section {
                Text("Apple Pay で払うと、金額と店名をサイフログが受け取り、次に開いたときに記録して返事でお知らせします。銀行やカードのログインは要らず、受け取った支払いはこの iPhone の中にだけ置きます。")
                    .foregroundStyle(Theme.ink)
                    .listRowBackground(Theme.surface)
                if model.pendingCount > 0 {
                    Label {
                        Text("受け取った支払いが \(model.pendingCount) 件あります。ホームに戻ると記録します。")
                    } icon: {
                        Image(systemName: "tray.and.arrow.down")
                    }
                    .foregroundStyle(Theme.ink)
                    .listRowBackground(Theme.surface)
                }
            }
            Section {
                step(1, Text("「ショートカット」App の「オートメーション」で「＋」を押し、「取引」を選びます。"))
                step(2, Text("記録したいカードを選び、「すぐに実行」にして「次へ」を押します。"))
                step(3, Text("「新規の空のオートメーション」から「アクションを追加」を押し、「サイフログ」の「支払いを記録」を選びます。"))
                step(4, Text("「金額」に「ショートカットの入力」の「金額」を、「店名」に「加盟店」を入れて、「完了」を押します。"))
                Button {
                    if let url = URL(string: "shortcuts://") { openURL(url) }
                } label: {
                    Label("「ショートカット」App を開く", systemImage: "arrow.up.forward.app")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(.rect)
                }
                .accessibilityHint("オートメーションを作るために、ショートカット App を開きます")
                .listRowBackground(Theme.surface)
            } header: {
                Text("オートメーションの作り方")
                    .foregroundStyle(Theme.inkSecondary)
            } footer: {
                Text("円のほかの通貨の支払いは記録しません。カテゴリはお店の名前で決め、分からないお店は返事で聞き返します（一度選べば、次からそのカテゴリで記録します）。違っていたら、返事の「取り消す」で消せます。")
                    .foregroundStyle(Theme.inkSecondary)
            }
            Section {
                Text("受け取った支払い（金額・店名・日時）は、記録にするまで、この iPhone の中の小さなファイルに置きます。iPhone がロックされていても受け取れるよう、このファイルだけは、iPhone を起動して最初にロックを解いた後から読める保護にしています。記録にしたら消します。")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
                    .listRowBackground(Theme.surface)
            } header: {
                Text("データの扱い")
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(Text(.walletCaptureTitle))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.reload() }
    }

    /// 手順の 1 行（番号の丸と文）。
    private func step(_ number: Int, _ text: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(verbatim: "\(number)")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 24, height: 24)
                .background(Theme.accentFill, in: .circle)
                .accessibilityHidden(true)
            text
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .listRowBackground(Theme.surface)
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
