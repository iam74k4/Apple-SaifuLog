import CloudKit
import UIKit

/// 家計の共有への招待を、UIKit の場面の委任先（`HouseholdSceneDelegate`）から家計の受け持ち（`HouseholdHost`）へ渡す受け皿。
///
/// 招待のリンクでアプリが起動したときは、場面ができた時点（`scene(_:willConnectTo:options:)`）で招待が届くが、家計の保存先は
/// 自分の記録の保存先を開いた後（ロックが解けた後）にしか開けない。それまでは受け皿に溜め、`HouseholdHost.start` で受け取る。
@MainActor
final class HouseholdInvitationInbox {
    static let shared = HouseholdInvitationInbox()

    private var pending: [HouseholdInvitation] = []
    private var handler: (@MainActor (HouseholdInvitation) -> Void)?

    /// 招待を渡す。受け取り手がまだいなければ溜める。
    func deliver(_ invitation: HouseholdInvitation) {
        if let handler {
            handler(invitation)
        } else {
            pending.append(invitation)
        }
    }

    /// 受け取り手を決め、溜まっていた招待を渡す。
    func setHandler(_ handler: @escaping @MainActor (HouseholdInvitation) -> Void) {
        self.handler = handler
        let invitations = pending
        pending = []
        for invitation in invitations { handler(invitation) }
    }
}

/// 家計の共有の招待を受け取るための、アプリの委任先。場面の委任先に `HouseholdSceneDelegate` を使わせる。
///
/// SwiftUI のアプリは場面の委任先を持たないので、Apple の説明（Accepting Share Invitations in a SwiftUI App）のとおり、
/// アプリの委任先で場面の構成に委任先のクラスを入れる。`SaifuLogApp` が DEBUG と社内テスト用のビルドでだけ使う
/// （家計の共有を隠している間は、App Store へ出すビルドの起動の仕組みを変えないため）。
final class HouseholdAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        // 家計の共有が無効なら、Info.plist の既定の構成のまま（何も変えない）。
        guard HouseholdSharing.isEnabled else { return connectingSceneSession.configuration }
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = HouseholdSceneDelegate.self
        return configuration
    }
}

/// 家計の共有の招待を受け取る、場面の委任先。画面（ウィンドウ）は SwiftUI が作るので、ここでは作らない。
///
/// アプリが動いているときは `windowScene(_:userDidAcceptCloudKitShareWith:)`、招待のリンクで起動したときは
/// `scene(_:willConnectTo:options:)` の `connectionOptions.cloudKitShareMetadata` に届く（Apple の CKShare.Metadata の説明）。
final class HouseholdSceneDelegate: UIResponder, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let metadata = connectionOptions.cloudKitShareMetadata else { return }
        deliver(metadata)
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        deliver(cloudKitShareMetadata)
    }

    private func deliver(_ metadata: CKShare.Metadata) {
        // 無効なビルドでは受け入れない（Info.plist に CKSharingSupported が無いので、ふつうは届かない）。
        guard HouseholdSharing.isEnabled else { return }
        HouseholdInvitationInbox.shared.deliver(HouseholdInvitation(metadata: metadata))
    }
}
