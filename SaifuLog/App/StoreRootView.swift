import SwiftData
import SwiftUI
import UIKit

/// 保存先の状態（`StoreHost`）に合わせて、開けたら `content` を、開くまでは読み込み中の画面を、
/// 開けなければ再試行の画面を出す。
struct StoreRootView<Content: View>: View {
    let host: StoreHost
    /// 開けた保存先で組み立てる画面。開き直すたびに作り直される（前の保存先の ModelContext を持ち越さない）。
    @ViewBuilder let content: (ModelContainer) -> Content

    var body: some View {
        // Group ではなく ZStack にする。Group に付けた onAppear などは中の画面ごとに付き、状態が変わって画面が
        // 入れ替わるたびに付け直されるため。
        ZStack {
            switch host.state {
            case .loading:
                StoreLoadingView()
            case .ready(let container):
                content(container)
                    .modelContainer(container)
            case .unavailable:
                StoreUnavailableView(failedRetryCount: host.failedRetryCount, retry: host.retry)
            case .reopening:
                // この画面が出た時点で、前の保存先を使う画面のツリーは畳まれている。書き込み中の処理が終わるのを
                // 待ってから新しい保存先を開く。
                StoreLoadingView()
                    .task { await host.finishReopening() }
            }
        }
        .onAppear { host.start() }
        .modifier(ProtectedDataObserver(host: host))
    }
}

/// ロックが解けたら、待っていた保存先を開き直させる。
///
/// 前面かどうか（scenePhase）の変化で `StoreRootView` の body を描き直さないよう、別の modifier に分けている
/// （描き直すたびにホームの画面とそのモデルを作り直す処理が走るため）。
private struct ProtectedDataObserver: ViewModifier {
    let host: StoreHost

    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in
                host.protectedDataMayBeAvailable()
            }
            // ロックの解除の通知を取りこぼしても、利用者がアプリを見ている（前面にある）なら開けるはずなので、ここでも試す。
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { host.protectedDataMayBeAvailable() }
            }
    }
}

/// 保存先を開くまでの画面。
///
/// 開くのはたいてい一瞬なので、読み込み中の印はすぐには出さない。起動のたびに印が一瞬だけ見えて、
/// ちらついて見えるのを避けるため。地の色はホームと同じにして、ホームへ切り替わるときの変化を小さくする。
private struct StoreLoadingView: View {
    @State private var showsProgress = false

    var body: some View {
        ZStack {
            Theme.background
                .ignoresSafeArea()
            if showsProgress {
                ProgressView()
                    .tint(Theme.inkSecondary)
                    .accessibilityLabel("記録を読み込んでいます")
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(500))
            showsProgress = true
        }
    }
}

/// 保存先を開けなかったときの画面。
///
/// 何が起きたかと、利用者にできること（空き容量を確かめて、もう一度試す）を伝える。アプリの削除は勧めない
/// （記録が消えるため）。
struct StoreUnavailableView: View {
    /// 再試行してもまた開けなかった回数。
    let failedRetryCount: Int
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label {
                Text("記録を開けませんでした")
                    .foregroundStyle(Theme.ink)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(Theme.inkSecondary)
            }
        } description: {
            VStack(spacing: 8) {
                Text("記録の保存先を開けませんでした。iPhone の空き容量を確かめてから、もう一度お試しください。")
                    .foregroundStyle(Theme.inkSecondary)
                // 再試行してもすぐに同じ画面に戻るので、回数を出して押したことが伝わるようにする
                // （VoiceOver には StoreHost が読み上げる）。
                if failedRetryCount > 0 {
                    Text("もう一度試しましたが、開けませんでした（\(failedRetryCount) 回目）")
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                        .contentTransition(.numericText())
                }
            }
        } actions: {
            Button(action: retry) {
                Text("もう一度試す")
                    .fontWeight(.semibold)
                    // 山吹の塗りの上の文字は墨にする（Theme の説明。白では読めない）。
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 8)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.glassProminent)
            // 主ボタンの塗りは山吹（送信ボタンと同じ）。
            .tint(Theme.accentFill)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        // 再試行してもまた開けなかったことを、手ざわりでも伝える。
        .sensoryFeedback(.error, trigger: failedRetryCount) { _, newValue in newValue > 0 }
        .animation(.default, value: failedRetryCount)
    }
}

#Preview("開けなかったとき") {
    StoreUnavailableView(failedRetryCount: 0, retry: {})
}

#Preview("再試行してもまた開けなかったとき") {
    StoreUnavailableView(failedRetryCount: 2, retry: {})
}
