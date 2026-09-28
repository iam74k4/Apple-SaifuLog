import ObjectiveC
import SwiftUI
import UIKit

/// シートを下へスワイプして閉じようとしたこと（`interactiveDismissDisabled` で止めたとき）を知らせる。
///
/// SwiftUI には止めたスワイプを受け取る方法が無く、UIKit の `presentationControllerDidAttemptToDismiss` だけが知らせる。
/// 止めるだけだと、スワイプしてもシートが戻ってくるだけで、なぜ閉じないのか・どう閉じればよいのかが分からない。
///
/// シートの presentation controller の delegate（SwiftUI が置いたもの）を包み、その知らせだけを受け取って、ほかは
/// すべて元の delegate へそのまま渡す（SwiftUI の、閉じたときにシートの状態を戻す処理などを止めないため）。
/// 包めなかったとき（見つからない・delegate が無い）は何もしない。スワイプで閉じないだけで、キャンセルのボタンからは
/// 確認を出せる。シートの中の、どこかの背景に置く。
struct SheetDismissAttemptObserver: UIViewControllerRepresentable {
    let onAttempt: @MainActor () -> Void

    func makeUIViewController(context: Context) -> ObserverController {
        ObserverController(onAttempt: onAttempt)
    }

    func updateUIViewController(_ controller: ObserverController, context: Context) {
        controller.onAttempt = onAttempt
    }

    final class ObserverController: UIViewController {
        var onAttempt: @MainActor () -> Void {
            didSet { proxy?.onAttempt = onAttempt }
        }

        private weak var proxy: DismissAttemptProxy?

        init(onAttempt: @escaping @MainActor () -> Void) {
            self.onAttempt = onAttempt
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) {
            nil
        }

        override func loadView() {
            // 見た目は持たない。押す操作も VoiceOver も素通りさせる。
            let view = UIView()
            view.isUserInteractionEnabled = false
            view.isAccessibilityElement = false
            view.accessibilityElementsHidden = true
            self.view = view
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            installIfNeeded()
        }

        private func installIfNeeded() {
            guard proxy == nil,
                  let presentationController = presentedRoot?.presentationController,
                  let original = presentationController.delegate,
                  !(original is DismissAttemptProxy)
            else { return }
            let proxy = DismissAttemptProxy(original: original, onAttempt: onAttempt)
            // delegate は弱い参照なので、包んだものは presentation controller に持たせ、同じだけ生かす。
            // この画面（ObserverController）に持たせると、シートより先に消えたとき delegate が空になり、
            // 閉じたときに SwiftUI へ知らせが届かなくなる。
            objc_setAssociatedObject(
                presentationController, &AssociationKey.proxy, proxy, .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
            presentationController.delegate = proxy
            self.proxy = proxy
        }

        /// このシートとして出ている画面（親をたどった根元）。シートの中に無ければ nil。
        private var presentedRoot: UIViewController? {
            var current: UIViewController = self
            while let parent = current.parent {
                current = parent
            }
            return current.presentingViewController == nil ? nil : current
        }
    }
}

/// `objc_setAssociatedObject` のキー。変わらないアドレスであればよいので、値は使わない。
private enum AssociationKey {
    nonisolated(unsafe) static var proxy: UInt8 = 0
}

/// presentation controller の元の delegate を包み、閉じようとした知らせだけを受け取る。
@MainActor
private final class DismissAttemptProxy: NSObject, UIAdaptivePresentationControllerDelegate {
    /// 元の delegate（SwiftUI のもの）。SwiftUI が持ち続けるので、弱い参照にする。
    /// 転送の判定（`responds(to:)`・`forwardingTarget(for:)`）は MainActor の外から呼ばれうるので、隔離しない。
    nonisolated(unsafe) weak var original: (any UIAdaptivePresentationControllerDelegate)?
    var onAttempt: @MainActor () -> Void

    init(original: any UIAdaptivePresentationControllerDelegate, onAttempt: @escaping @MainActor () -> Void) {
        self.original = original
        self.onAttempt = onAttempt
    }

    func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
        onAttempt()
        original?.presentationControllerDidAttemptToDismiss?(presentationController)
    }

    // 受け取らない知らせと問い合わせ（閉じてよいか・閉じた後など）は、元の delegate がそのまま受け取る。
    nonisolated override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || (original?.responds(to: aSelector) ?? false)
    }

    nonisolated override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if let original, original.responds(to: aSelector) {
            return original
        }
        return super.forwardingTarget(for: aSelector)
    }
}
