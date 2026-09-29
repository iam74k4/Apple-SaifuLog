import SwiftUI
import UIKit
import VisionKit

/// ④ 撮影。VisionKit の書類カメラ（枠に合わせると自動で撮り、傾きと影を直す）。
///
/// 撮った画像は受け取ったらすぐ読み取りに渡し、どこにも保存しない（書類カメラもアルバムに保存しない）。
struct DocumentCameraView: UIViewControllerRepresentable {
    /// 撮り終えたとき（撮った順のページと、上限を超えて読み取らなかったページの数）。
    let finish: @MainActor ([ReceiptImage], _ skippedPageCount: Int) -> Void
    /// やめたとき・撮れなかったとき。
    let cancel: @MainActor () -> Void

    /// 読み取るページの上限。長いレシートを分けて撮っても、この枚数までにする（メモリと読み取りの時間を抑えるため）。
    /// 超えたページは読まず、⑤ にそのことを出す（合計は最後のページにあることが多く、黙って落とすと気づけないため）。
    nonisolated static let maximumPages = 4

    /// この端末で書類カメラを使えるか（使えない端末では「撮る」を出さない）。
    static var isSupported: Bool {
        VNDocumentCameraViewController.isSupported
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(finish: finish, cancel: cancel)
    }

    /// 書類カメラの知らせを受ける。VisionKit は知らせをメインスレッドで送るが、ヘッダーにアクターの注記が無いので、
    /// `@preconcurrency` で受け、メインアクターの上にいることを実行時に確かめる。
    @MainActor
    final class Coordinator: NSObject, @preconcurrency VNDocumentCameraViewControllerDelegate {
        let finish: @MainActor ([ReceiptImage], Int) -> Void
        let cancel: @MainActor () -> Void

        init(finish: @escaping @MainActor ([ReceiptImage], Int) -> Void, cancel: @escaping @MainActor () -> Void) {
            self.finish = finish
            self.cancel = cancel
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let pages = min(scan.pageCount, DocumentCameraView.maximumPages)
            finish((0..<pages).compactMap { ReceiptImage(scan.imageOfPage(at: $0)) }, scan.pageCount - pages)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            cancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: any Error) {
            cancel()
        }
    }
}
