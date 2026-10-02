import SwiftUI
import UIKit

extension View {
    /// アプリのロック（`AppLock`）を画面に効かせる。場面の状態を渡し、ロック中と前面を離れている間は、ロックの画面を
    /// ほかのすべての画面より上に出す。
    func appLock(_ lock: AppLock) -> some View {
        modifier(AppLockModifier(lock: lock))
    }
}

/// ロックの画面の出し入れ。
///
/// ロックの画面は、アプリの窓の上に重ねる別の窓（`AppLockWindow`）に出す。画面の根元に重ねるだけでは、シート（直す・予算・
/// レシートの読み取り結果）や全画面のカバー（書類カメラ）、アラートの下に隠れ、その上に家計が見えてしまうため。
/// 根元の画面にも地の色を重ねる（窓を出すのが間に合わない一瞬も、家計を見せないため）。
private struct AppLockModifier: ViewModifier {
    let lock: AppLock

    @Environment(\.scenePhase) private var scenePhase
    @State private var window = AppLockWindow()

    func body(content: Content) -> some View {
        content
            // 隠している間は、家計の画面を VoiceOver からも隠す。地の色を重ねるだけでは、VoiceOver が下の記録（品目・金額）を
            // 読み上げ、ボタンを押せてしまうため。
            .accessibilityHidden(lock.hidesContent)
            .overlay {
                if lock.hidesContent {
                    Theme.background
                        .ignoresSafeArea()
                        .accessibilityHidden(true)
                }
            }
            .background(WindowSceneReader { window.attach(to: $0, lock: lock) }.accessibilityHidden(true))
            .onChange(of: scenePhase, initial: true) { _, phase in
                lock.scenePhaseDidChange(to: phase)
            }
            // 再起動して最初にロックを解いた（起動したときに読めなかった設定を読めるようになった）。
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in
                lock.scenePhaseDidChange(to: scenePhase)
            }
            .onChange(of: lock.hidesContent, initial: true) { _, hides in
                window.setVisible(hides, lock: lock)
            }
    }
}

/// ロックの画面を出す窓。アプリの窓とアラートより上に置く。
@MainActor
final class AppLockWindow {
    private weak var scene: UIWindowScene?
    private var window: UIWindow?
    /// 出してほしいか（場面が分かる前に頼まれたときは、分かったときに出す）。
    private var wantsVisible = false

    /// 場面（窓を置く先）を受け取る。先に出すよう頼まれていれば、ここで出す。
    func attach(to scene: UIWindowScene, lock: AppLock) {
        guard self.scene !== scene else { return }
        self.scene = scene
        if wantsVisible { setVisible(true, lock: lock) }
    }

    func setVisible(_ visible: Bool, lock: AppLock) {
        wantsVisible = visible
        if visible {
            guard window == nil, let scene else { return }
            let window = UIWindow(windowScene: scene)
            // アラートやキーボードの入力の候補より上に置く。
            window.windowLevel = .alert + 1
            let host = UIHostingController(rootView: AppLockView(lock: lock))
            host.view.backgroundColor = .clear
            // VoiceOver をこの窓の中だけにとどめる。下の窓（アプリの画面・シート・アラート）の要素へ移れると、ロックの画面の
            // 下の家計を読み上げたり、設定を操作したりできてしまうため。
            host.view.accessibilityViewIsModal = true
            window.accessibilityViewIsModal = true
            window.rootViewController = host
            // キーの窓にして、入力欄のキーボードをロックの画面の上に出さない。
            window.makeKeyAndVisible()
            self.window = window
            // 画面が替わったことを VoiceOver に伝え、フォーカスをロックの画面へ移す（下の画面の要素に残さない）。
            UIAccessibility.post(notification: .screenChanged, argument: nil)
        } else {
            guard let window else { return }
            window.isHidden = true
            self.window = nil
            // アプリの窓をキーの窓に戻す（入力欄にまた打てるように）。
            scene?.windows.first { $0 !== window && !$0.isHidden && $0.windowLevel == .normal }?.makeKey()
            UIAccessibility.post(notification: .screenChanged, argument: nil)
        }
    }
}

/// 置かれた窓の場面（UIWindowScene）を知らせる、見えない View。
private struct WindowSceneReader: UIViewRepresentable {
    let found: (UIWindowScene) -> Void

    func makeUIView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.found = found
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: ReaderView, context: Context) {
        uiView.found = found
    }

    final class ReaderView: UIView {
        var found: ((UIWindowScene) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let scene = window?.windowScene { found?(scene) }
        }
    }
}

/// ロックの画面。前面を離れて隠しているだけのとき（ロックしていない）は、印だけを出す。
struct AppLockView: View {
    let lock: AppLock

    @ScaledMetric(relativeTo: .largeTitle) private var markSize = 64

    var body: some View {
        let size = min(markSize, 88)
        VStack(spacing: 24) {
            Spacer()
            // 主の塗りに onAccent の記号（Theme の説明。ようこその印と同じ）。
            Image(systemName: "wallet.bifold.fill")
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: size, height: size)
                .background(Theme.accentFill, in: .rect(cornerRadius: size * 0.28))
                .accessibilityHidden(true)
            if lock.isLocked {
                VStack(spacing: 8) {
                    Text("ロックしています")
                        .font(.title2.bold())
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("記録を見るには、ロックを解除してください。")
                        .foregroundStyle(Theme.inkSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            Spacer()
            if lock.isLocked {
                Button {
                    Task { await lock.unlock() }
                } label: {
                    Label {
                        Text("ロックを解除")
                    } icon: {
                        Image(systemName: lock.method.symbolName)
                    }
                    .font(.headline)
                    .foregroundStyle(Theme.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Theme.accentFill, in: .capsule)
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .disabled(lock.isAuthenticating)
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
    }
}

extension AppLockMethod {
    /// 解除のボタンの記号。
    var symbolName: String {
        switch self {
        case .faceID: "faceid"
        case .touchID: "touchid"
        case .opticID: "opticid"
        case .passcode, .unavailable: "lock.open"
        }
    }
}
