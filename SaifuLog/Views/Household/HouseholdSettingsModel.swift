import Foundation
import Observation

/// 設定（⑧）の「家族と共有」の節の状態と操作。家計を作る、名前を直す、家族を招待する（参加している人を見る）、共有をやめる、
/// 家計から抜ける、家計を消す。家計そのものの操作は `HouseholdHost` が受け持つ。
///
/// 家計の共有が有効で、家計の保存先を開けたときだけ作る（`SettingsModel.household`）。
@MainActor
@Observable
final class HouseholdSettingsModel {
    let host: HouseholdHost
    /// 家計を作るシート・名前を直すシートの入力。出していなければ nil。
    var draft: Draft?
    /// 共有の画面（UICloudSharingController）に渡すもの。出していなければ nil。
    var sharing: HouseholdSharingPresentation?
    /// 共有をやめる・抜ける・消す前の確認。出していなければ nil。
    var confirmation: Confirmation?

    init(host: HouseholdHost) {
        self.host = host
    }

    /// いまの家計（入っていなければ nil）。
    var household: Household? {
        host.currentHousehold
    }

    // MARK: - 作る・名前を直す

    /// 家計を作るシートを出す。
    func presentCreation() {
        draft = Draft(kind: .create, householdName: "", memberName: "")
    }

    /// 家計の名前と自分の表示名を直すシートを出す。
    func presentNamesEdit() {
        guard let household else { return }
        draft = Draft(kind: .edit(household.role), householdName: household.name, memberName: household.memberName)
    }

    /// シートの「作成」「保存」。作れた・保存できたら nil（シートを閉じる）、できなければその理由（シートの中で知らせる）。
    @discardableResult
    func submit(_ draft: Draft) async -> HouseholdNotice? {
        guard draft.canSubmit else { return .saveFailed }
        let failure = switch draft.kind {
        case .create: await host.createHousehold(name: draft.householdName, memberName: draft.memberName)
        case .edit: host.updateNames(householdName: draft.householdName, memberName: draft.memberName)
        }
        if failure == nil { self.draft = nil }
        return failure
    }

    /// 家計の知らせを、設定の画面で出してよいか（シートを出している間は出せないので、閉じてから出す）。
    var canPresentNotice: Bool {
        draft == nil && sharing == nil && confirmation == nil
    }

    // MARK: - 招待・参加している人

    /// 共有の画面を出す（持ち主は招待と管理、参加者は参加している人の一覧と自分を外す）。用意できるまでを待つ Task を返す。
    @discardableResult
    func presentSharing() -> Task<Void, Never> {
        Task {
            sharing = await host.prepareSharing()
        }
    }

    // MARK: - やめる・抜ける・消す

    func requestConfirmation(_ confirmation: Confirmation) {
        self.confirmation = confirmation
    }

    /// 確認のあとで実行する。終わるまでを待つ Task を返す。
    @discardableResult
    func confirm(_ confirmation: Confirmation) -> Task<Void, Never> {
        self.confirmation = nil
        return Task {
            switch confirmation {
            case .stopSharing: await host.stopSharing()
            case .leave: await host.leaveHousehold()
            case .delete: await host.deleteHousehold()
            }
        }
    }

    // MARK: - 型

    /// 家計を作る・名前を直すシートの入力。
    struct Draft: Identifiable, Equatable {
        enum Kind: Equatable {
            case create
            /// 名前を直す（持ち主か参加者かで、家計の名前が出る先が違うので注記を替える）。
            case edit(HouseholdRole)
        }

        let id = UUID()
        let kind: Kind
        var householdName: String
        /// 自分の表示名（家族に見える「記録した人」）。
        var memberName: String

        /// 作れる・保存できるか。表示名は空にしない（家族の記録が混ざって並ぶので、だれの記録かの印が要るため）。
        var canSubmit: Bool {
            !memberName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// 確認を出す操作。
    enum Confirmation: Identifiable, Equatable {
        /// 共有をやめる（持ち主）。
        case stopSharing
        /// 家計から抜ける（参加者）。
        case leave
        /// 家計を消す（持ち主）。
        case delete

        var id: Self { self }
    }
}
