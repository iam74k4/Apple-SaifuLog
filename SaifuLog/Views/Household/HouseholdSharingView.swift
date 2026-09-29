import CloudKit
import SwiftUI
import UIKit

/// 家計の共有の画面（UIKit の UICloudSharingController）を SwiftUI のシートに出す。
///
/// 持ち主には招待と参加している人の管理と「共有をやめる」、参加者には参加している人の一覧と「自分を外す」を、iOS の標準の画面が
/// 出し分ける。参加者の権限は読み書きにし（家族のだれでも記録を足し、直し、消せる）、招待した人だけが入れるようにする。
struct HouseholdSharingView: UIViewControllerRepresentable {
    let presentation: HouseholdSharingPresentation
    /// 共有をやめた・自分を外した（画面の中で）。
    let didStopSharing: @MainActor () -> Void
    /// 共有を保存できなかった。
    let didFail: @MainActor () -> Void

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: presentation.share, container: presentation.makeContainer())
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        controller.delegate = context.coordinator
        controller.modalPresentationStyle = .formSheet
        return controller
    }

    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(title: presentation.title, didStopSharing: didStopSharing, didFail: didFail)
    }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let title: String
        let didStopSharing: @MainActor () -> Void
        let didFail: @MainActor () -> Void

        init(title: String, didStopSharing: @escaping @MainActor () -> Void, didFail: @escaping @MainActor () -> Void) {
            self.title = title
            self.didStopSharing = didStopSharing
            self.didFail = didFail
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            title
        }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: any Error) {
            didFail()
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            didStopSharing()
        }
    }
}
