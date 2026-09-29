import Foundation

/// 家計の共有（家族・パートナーと家計を共有する）の機能フラグ。
///
/// 家計の共有は、CloudKit のゾーンの共有（CKShare）と CKSyncEngine を使い、2 つの Apple アカウントと 2 台の端末でしか
/// 確かめられない（CI でも 1 台のシミュレータでも確かめられない）。実機で確かめ終えるまでは、DEBUG のビルドと社内テスト用の
/// ビルド（Swift の条件 INTERNAL_DIAGNOSTICS。TestFlight の社内テスト専用）でだけ有効にし、App Store へ出すビルドでは
/// 画面・同期・共有の受け入れを一切出さない・動かさない（コードは入るが到達しない）。docs/design.md §5-5。
///
/// App Store へ出すビルドで有効になっていないことは、release.mk がアーカイブの中身で確かめる（アプリの中に `enabledMarker` の
/// 文字列が無いこと、Info.plist に CKSharingSupported が無いこと）。
enum HouseholdSharing {
    /// 家計の共有が有効なビルドにだけある印。release.mk の `RELEASE_HOUSEHOLD_MARKER` と同じ値にする（変えるときは両方）。
    ///
    /// release.mk は、アーカイブのアプリの中にこの文字列があるかで家計の共有が有効かを見分け、App Store へ出すビルド
    /// （INTERNAL_BUILD=NO）にあれば止める。有効なときに同期を始める処理（`HouseholdHost.start`）がこの文字列をログに書くので、
    /// 最適化で消されない。16 バイト以上にしておく（15 バイトまでの文字列は、Swift がバイナリに文字列として置かないことがあるため）。
    #if DEBUG || INTERNAL_DIAGNOSTICS
    static let enabledMarker: String? = "SaifuLog-HouseholdSharing-v1"
    #else
    static let enabledMarker: String? = nil
    #endif

    /// 家計の共有が有効か。
    ///
    /// 印から決める。ここを直接 true にしないこと（印の無いビルドで有効になると、release.mk の確かめが空振りするため）。
    /// 画面・同期・共有の受け入れは、この値を外から渡せるようにしてテストで false も確かめる（`HouseholdHost` の `isEnabled`）。
    static var isEnabled: Bool {
        enabledMarker != nil
    }

    /// このプロセスが CloudKit を使えるか（iCloud の entitlement つきで署名したビルドか）。
    ///
    /// 署名の無いビルド（`make build`・`make test-app` の CODE_SIGNING_ALLOWED=NO。アプリのテストもこのアプリの中で動く）は
    /// iCloud の entitlement を持たず、CKContainer を作るとプロセスが止まる（SIGTRAP。iOS 26.4 のシミュレータで確かめた）。家計の
    /// 同期は起動したときに CKSyncEngine を作るので、使えないビルドでは家計の共有を始めない（`HouseholdHost.start`）。entitlement
    /// そのものは iOS の公開の API で読めないので、署名の印（`_CodeSignature/CodeResources`）の有無で見分ける。このアプリの署名した
    /// ビルドは、どれも iCloud の entitlement を持つ（`project.yml` の entitlements）。
    static var canUseCloudKit: Bool {
        let signature = Bundle.main.bundleURL.appending(path: "_CodeSignature/CodeResources")
        return FileManager.default.fileExists(atPath: signature.path(percentEncoded: false))
    }
}
