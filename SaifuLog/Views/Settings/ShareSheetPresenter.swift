import SwiftUI
import UIKit

/// 書き出したファイルを iOS の共有のシート（UIActivityViewController）で渡し、閉じたら知らせる。
///
/// SwiftUI の ShareLink を使わないのは、共有を終えたこと（渡し終えたか、やめたか）を知る方法が無く、書き出した
/// ファイルを共有の後に消せないため。家計の記録の写しを一時ディレクトリに残さないよう、閉じたときに呼ばれる
/// `completionWithItemsHandler` で消す。共有のシートには「"ファイル"に保存」も並ぶので、fileExporter は別に置かない。
///
/// 画面の背景に見えない ViewController を置き、その画面のいちばん上から出す。SwiftUI のシートの中に入れると、共有の
/// シートの外側にもう 1 枚シートができ、閉じ方を SwiftUI と UIKit の両方で合わせることになるため。
struct ShareSheetPresenter: UIViewControllerRepresentable {
    /// 共有するファイル。nil でなくなったら共有のシートを出す。
    let fileURL: URL?
    /// 共有のシートを閉じたあと（渡し終えたか、やめたか）に呼ぶ。シートを出せなかったときは false を渡す。
    let onFinish: @MainActor (_ sheetWasShown: Bool) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        let coordinator = context.coordinator
        coordinator.onFinish = onFinish
        // 書き出しのたびにファイルの場所は変わるので、同じ場所のファイルで二度は出さない（閉じた直後の描き直しで
        // また出さないように）。
        guard let fileURL, coordinator.lastURL != fileURL else { return }
        coordinator.begin(fileURL)
        // いちばん上に出ている画面から出す（書き出しの間に「予算を決める」のシートを開いていても出せるように）。
        guard var presenter = controller.viewIfLoaded?.window?.rootViewController else {
            Task { @MainActor in coordinator.finish(sheetWasShown: false) }
            return
        }
        while let presented = presenter.presentedViewController, !presented.isBeingDismissed {
            presenter = presented
        }
        let activity = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        // この知らせは共有のシートを閉じたときだけでなく、選んだ先（メール・メッセージ・"ファイル"に保存など）の画面を
        // 閉じるたびにも来る。先の画面でやめると、共有のシートは出たまま「やめた（completed が false）」で来るので、
        // そこでファイルを消すと、続けて別の先を選んだときに渡すファイルが無くなる。シートが本当に閉じたときだけ終える。
        // activity は弱く持つ（activity がこの知らせを持つので、強く持つと互いに放さなくなる）。
        activity.completionWithItemsHandler = { [weak activity] activityType, completed, _, _ in
            let activity = activity
            Task { @MainActor in
                let isStillPresented = activity.map { $0.presentingViewController != nil && !$0.isBeingDismissed } ?? false
                guard Coordinator.sheetHasClosed(
                    activityType: activityType, completed: completed, isStillPresented: isStillPresented
                ) else { return }
                coordinator.finish(sheetWasShown: true)
            }
        }
        // 吹き出しの基準（sourceView）は渡さない。iOS 26 の iPhone では、渡すとその位置（ここでは画面全体）を指す
        // 吹き出しの形になり、ふだんの下から出る共有のシートにならないため（シミュレータの iOS 26.4 で確かめた）。
        // iPhone 専用のアプリなので、iPad でも iPhone 版として動き、吹き出しの基準は要らない。
        presenter.present(activity, animated: true) { [weak activity] in
            // 出せなかったものとして片づけた後に出てきたら（出すのが遅れたとき）、ファイルはもう無いので閉じる。
            if !coordinator.didPresent(fileURL) {
                activity?.dismiss(animated: true)
            }
        }
        // 出せなかった（ほかの画面が出たり閉じたりしている途中など）ときは、出し終えた知らせが来ないので、しばらく待って
        // 終えたことにし、ファイルを片づける。出せないまま待つと、書き出しのボタンが押せないままになるため（もう一度押せば
        // 書き出し直せる）。present の直後には判断しない（SwiftUI の描き直しの中から出すと、出す処理が後に回り、
        // 直後の presentingViewController は出せたときも nil だった。シミュレータの iOS 26.4 で確かめた）。
        // 待ち終えたときは、出し終えた知らせだけでなく UIKit の上の状態も見る。実機では最初の共有のシートを出すのに
        // 時間がかかることがあり（共有の先の一覧を読むため）、出している途中や出し終えた直後に消すと、出てきたシートが
        // 無いファイルを渡すことになるため。
        Task { @MainActor [weak activity] in
            try? await Task.sleep(for: .seconds(2))
            let isShowing = activity.map { $0.presentingViewController != nil || $0.isBeingPresented } ?? false
            coordinator.finishIfNotPresented(fileURL, isShowing: isShowing)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    /// 共有のシートを出してから閉じるまでの状態。UIKit から切り離し、SaifuLogTests で確かめられるようにしている。
    @MainActor
    final class Coordinator {
        /// 最後に共有のシートを出したファイル。
        private(set) var lastURL: URL?
        /// 共有のシートを出しているか（出し始めてから、終えたことにするまで）。
        private(set) var isPresenting = false
        /// 共有のシートを出し終えたファイル（出す動きが済んだ知らせを受けたもの）。
        private var presentedURL: URL?
        var onFinish: @MainActor (_ sheetWasShown: Bool) -> Void

        init(onFinish: @escaping @MainActor (_ sheetWasShown: Bool) -> Void) {
            self.onFinish = onFinish
        }

        /// そのファイルの共有のシートを出し始める。
        func begin(_ url: URL) {
            lastURL = url
            isPresenting = true
            presentedURL = nil
        }

        /// 共有のシートを閉じた（出せなかった）。二度呼ばれても、知らせるのは一度だけにする（ファイルを消すのは一度でよいため）。
        func finish(sheetWasShown: Bool) {
            guard isPresenting else { return }
            isPresenting = false
            onFinish(sheetWasShown)
        }

        /// 共有のシートを出し終えた。すでに出せなかったものとして片づけたファイルなら false を返す（呼んだ側がシートを閉じる）。
        func didPresent(_ url: URL) -> Bool {
            guard lastURL == url, isPresenting else { return false }
            presentedURL = url
            return true
        }

        /// 待ち終えても、そのファイルの共有のシートを出し終えた知らせが無く、UIKit の上でも出ていなければ（出している
        /// 途中でもなければ）、出せなかったことにして終える。
        /// - Parameter isShowing: UIKit の上で共有のシートを出しているか、出している途中か。
        func finishIfNotPresented(_ url: URL, isShowing: Bool) {
            guard lastURL == url, presentedURL != url, !isShowing else { return }
            finish(sheetWasShown: false)
        }

        /// `completionWithItemsHandler` の知らせが、共有のシートを閉じたことを表すか。
        ///
        /// 選んだ先がない（シートを閉じた）か、選んだ先で渡し終えた（その後にシートは閉じる）なら閉じた。選んだ先で
        /// やめたときは、シートが出たまま戻るので閉じていない。ただし、そのときも UIKit の上でシートが出ていなければ
        /// 閉じたとみなす（先の画面を出す前にシートを閉じる形の先もあり、待ち続けるとファイルとボタンが残るため）。
        static func sheetHasClosed(activityType: UIActivity.ActivityType?, completed: Bool, isStillPresented: Bool) -> Bool {
            activityType == nil || completed || !isStillPresented
        }
    }
}
