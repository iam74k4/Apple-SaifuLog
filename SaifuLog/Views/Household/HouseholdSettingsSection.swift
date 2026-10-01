import SwiftUI

/// 設定（⑧）の「家族と共有」の節。家計の共有が有効なビルド（DEBUG と社内テスト用）で、家計の保存先を開けたときだけ出す。
///
/// 家計に入っていなければ「家計を作る」だけを出す。入っていれば、家計の名前と自分の表示名、家族の招待（参加者は参加している人）、
/// 共有をやめる（持ち主）・家計から抜ける（参加者）・家計を削除する（持ち主）を出す。
struct HouseholdSettingsSection: View {
    @Bindable var model: HouseholdSettingsModel

    var body: some View {
        Section {
            if let household = model.household {
                joinedRows(household)
            } else {
                createRow
            }
        } header: {
            Text("家族と共有")
                .foregroundStyle(Theme.inkSecondary)
        } footer: {
            footer
        }
    }

    // MARK: - 家計が無いとき

    private var createRow: some View {
        Button {
            model.presentCreation()
        } label: {
            HStack(spacing: 12) {
                Label {
                    Text("家計を作って家族を招待する")
                } icon: {
                    SettingsRowIcon(symbolName: "person.2.fill", fill: SettingsRowIcon.orange)
                }
                Spacer(minLength: 0)
                if model.host.isWorking {
                    ProgressView()
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .disabled(model.host.isWorking)
        .accessibilityHint("家計の名前とあなたの名前を決めます")
        .listRowBackground(Theme.surface)
    }

    // MARK: - 家計に入っているとき

    @ViewBuilder
    private func joinedRows(_ household: Household) -> some View {
        Button {
            model.presentNamesEdit()
        } label: {
            Label {
                householdNames(household)
            } icon: {
                SettingsRowIcon(symbolName: "house.fill", fill: SettingsRowIcon.orange)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(.rect)
        }
        .accessibilityHint("家計の名前とあなたの名前を直します")
        .listRowBackground(Theme.surface)

        Button {
            model.presentSharing()
        } label: {
            HStack(spacing: 12) {
                Label {
                    Text(household.role == .owner ? "家族を招待・管理" : "参加している人")
                } icon: {
                    SettingsRowIcon(symbolName: "person.2.fill", fill: SettingsRowIcon.orange)
                }
                Spacer(minLength: 0)
                if model.host.isWorking {
                    ProgressView()
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .disabled(model.host.isWorking)
        .accessibilityHint(household.role == .owner ? "招待を送る画面を開きます" : "家計に参加している人の一覧を開きます")
        .listRowBackground(Theme.surface)

        switch household.role {
        case .owner:
            destructiveRow("共有をやめる", confirmation: .stopSharing)
            destructiveRow("家計を削除", confirmation: .delete)
        case .participant:
            destructiveRow("家計から抜ける", confirmation: .leave)
        }
    }

    /// 家計の名前・自分の表示名・作ったか招待されたか。
    private func householdNames(_ household: Household) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: household.name.isEmpty ? String(localized: "家族の家計") : household.name)
                .foregroundStyle(Theme.ink)
            Group {
                if household.memberName.isEmpty {
                    Text("あなたの名前が未設定です（押して決めてください）")
                } else {
                    Text("あなたの名前: \(household.memberName)")
                }
            }
            .font(.footnote)
            .foregroundStyle(Theme.inkSecondary)
            Text(household.role == .owner ? "あなたが作った家計" : "招待されて入った家計")
                .font(.footnote)
                .foregroundStyle(Theme.inkSecondary)
        }
    }

    private func destructiveRow(_ title: LocalizedStringKey, confirmation: HouseholdSettingsModel.Confirmation) -> some View {
        Button(role: .destructive) {
            model.requestConfirmation(confirmation)
        } label: {
            Text(title)
                .foregroundStyle(Theme.danger)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(.rect)
        }
        .disabled(model.host.isWorking)
        .listRowBackground(Theme.surface)
    }

    // MARK: - 注記

    private var footer: some View {
        // 家計の名前は共有（CKShare）の題名で、招待に出すので暗号化フィールドに入らない。暗号化すると書いた項目と取り違えないよう添える。
        Text("家計の記録を、招待した家族と iCloud（Apple）でそろえます。家族は家計の記録を見て、足し、直し、削除できます。自分の記録は共有しません。金額・メモ・カテゴリ・記録した人の名前などは暗号化して保存し、開発者は中身を見られません。家計の名前は招待に出すため、暗号化せずに共有の情報として保存します。この機能はテスト中で、App Store 版にはまだありません。")
            .foregroundStyle(Theme.inkSecondary)
    }

}

/// 「家族と共有」の節のシート・確認（家計を作る・名前を直す・共有の画面・やめる前の確認）。
///
/// 節（`Section`）の中ではなく、設定の画面のリストに付ける（`SettingsView`。ほかのシートと同じ置き場所にし、節の行が作り直されても
/// 出し入れが途切れないように）。
struct HouseholdSettingsPresentations: ViewModifier {
    @Bindable var model: HouseholdSettingsModel

    func body(content: Content) -> some View {
        content
            .sheet(item: $model.draft) { draft in
                HouseholdDraftSheet(draft: draft) { submitted in
                    await model.submit(submitted)
                }
            }
            .sheet(item: $model.sharing) { presentation in
                HouseholdSharingView(
                    presentation: presentation,
                    didStopSharing: { model.host.sharingControllerDidStopSharing() },
                    didFail: { model.host.notice = .sharingFailed }
                )
                .ignoresSafeArea()
            }
            .confirmationDialog(
                confirmationTitle,
                isPresented: showsConfirmation,
                titleVisibility: .visible,
                presenting: model.confirmation
            ) { confirmation in
                Button(role: .destructive) {
                    model.confirm(confirmation)
                } label: {
                    switch confirmation {
                    case .stopSharing: Text("共有をやめる")
                    case .leave: Text("家計から抜ける")
                    case .delete: Text("家計を削除")
                    }
                }
            } message: { confirmation in
                switch confirmation {
                case .stopSharing:
                    Text("家族は家計を見られなくなり、家族の iPhone から家計の記録が消えます。この iPhone の家計の記録は残り、もう一度招待できます。")
                case .leave:
                    Text("この iPhone から家計の記録が消えます。家族の家計の記録はそのまま残ります。")
                case .delete:
                    Text("家計の記録を、あなたと家族のすべての端末と iCloud から削除します。この操作は取り消せません。")
                }
            }
    }

    private var confirmationTitle: Text {
        switch model.confirmation {
        case .stopSharing: Text("家族との共有をやめますか？")
        case .leave: Text("家計から抜けますか？")
        case .delete, nil: Text("家計を削除しますか？")
        }
    }

    private var showsConfirmation: Binding<Bool> {
        Binding(get: { model.confirmation != nil }, set: { if !$0 { model.confirmation = nil } })
    }
}

/// 「家族と共有」の節があるときだけ、そのシート・確認を付ける（家計の共有が無効なビルドでは何も付けない）。
struct HouseholdSettingsPresentationsIfAvailable: ViewModifier {
    let model: HouseholdSettingsModel?

    func body(content: Content) -> some View {
        if let model {
            content.modifier(HouseholdSettingsPresentations(model: model))
        } else {
            content
        }
    }
}

/// 家計を作る・名前を直すシート。家計の名前（空なら「家族の家計」）と、自分の表示名（家族に見える「記録した人」）を入れる。
///
/// 作れなかった・保存できなかったときは、シートを閉じずにこの中で知らせる（入れた名前を打ち直さずに済むように）。
private struct HouseholdDraftSheet: View {
    @State var draft: HouseholdSettingsModel.Draft
    let submit: (HouseholdSettingsModel.Draft) async -> HouseholdNotice?

    @Environment(\.dismiss) private var dismiss
    @State private var isSubmitting = false
    @State private var failure: HouseholdNotice?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(text: $draft.householdName, prompt: Text("家族の家計").foregroundStyle(Theme.inkSecondary)) {
                        Text("家計の名前")
                    }
                    .foregroundStyle(Theme.ink)
                    .listRowBackground(Theme.surface)
                } header: {
                    Text("家計の名前")
                        .foregroundStyle(Theme.inkSecondary)
                } footer: {
                    householdNameFooter
                        .foregroundStyle(Theme.inkSecondary)
                }
                Section {
                    TextField(text: $draft.memberName, prompt: Text("例: はなこ").foregroundStyle(Theme.inkSecondary)) {
                        Text("あなたの名前")
                    }
                    .foregroundStyle(Theme.ink)
                    .listRowBackground(Theme.surface)
                } header: {
                    Text("あなたの名前")
                        .foregroundStyle(Theme.inkSecondary)
                } footer: {
                    // 家計の名前（空欄でよい）と違って空にできないことを、押せない「作成」「保存」の前に伝える。
                    Text("必須です。家計に記録したとき、「記録した人」として家族に見えます。")
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(draft.kind == .create ? Text("家計を作る") : Text("家計の名前"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        isSubmitting = true
                        Task {
                            let failure = await submit(draft)
                            isSubmitting = false
                            if let failure {
                                self.failure = failure
                            } else {
                                dismiss()
                            }
                        }
                    } label: {
                        switch draft.kind {
                        case .create: Text("作成")
                        case .edit: Text("保存")
                        }
                    }
                    .disabled(!draft.canSubmit || isSubmitting)
                    // 押せない理由を VoiceOver でも伝える（「淡色表示」だけでは何が足りないか分からないため）。
                    .accessibilityHint(draft.canSubmit ? Text(verbatim: "") : Text("あなたの名前を入れると押せます"))
                }
            }
            .alert(failure?.title ?? Text(verbatim: ""), isPresented: showsFailure, presenting: failure) { _ in
                Button("OK", role: .cancel) {}
            } message: { failure in
                failure.message
            }
        }
    }

    private var showsFailure: Binding<Bool> {
        Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
    }

    /// 家計の名前の注記。作るとき・持ち主が直すとき・参加者が直すときで、名前が出る先が違う。
    ///
    /// 持ち主が直した名前は、次に共有の画面を開いたときに共有の題名にも書く（`HouseholdHost.prepareSharing`）が、すでに入っている
    /// 家族の端末の家計の名前は変わらない。参加者の家計の名前はその端末の中だけのもの。
    private var householdNameFooter: Text {
        switch draft.kind {
        case .create:
            Text("招待の画面にも出ます。空欄なら「家族の家計」になります。")
        case .edit(.owner):
            Text("次に「家族を招待・管理」を開いたときに、招待の画面の名前も変わります。すでに入っている家族の iPhone の家計の名前は変わりません。空欄なら「家族の家計」になります。")
        case .edit(.participant):
            Text("この iPhone の中だけの名前で、家族には見えません。空欄なら「家族の家計」になります。")
        }
    }
}

/// 家計の共有の知らせのアラートの題名と本文。
extension HouseholdNotice {
    var title: Text {
        switch self {
        case .joined: Text("家計に入りました")
        case .alreadyJoined: Text("もう入っている家計です")
        case .anotherHousehold: Text("ほかの家計に入っています")
        case .invitationInvalid: Text("この招待は受け入れられません")
        case .acceptFailed: Text("招待を受け入れられませんでした")
        case .accountUnavailable: Text("iCloud を使えません")
        case .sharingFailed: Text("共有の画面を開けませんでした")
        case .stopSharingFailed: Text("共有をやめられませんでした")
        case .sharingStopped: Text("家族との共有をやめました")
        case .leaveFailed: Text("家計から抜けられませんでした")
        case .left: Text("家計から抜けました")
        case .deleted: Text("家計を削除しました")
        case .removed: Text("家計が共有されなくなりました")
        case .saveFailed: Text("保存できませんでした")
        }
    }

    var message: Text {
        switch self {
        case .joined:
            // 参加者の表示名は Apple アカウントの名前から入れる（`HouseholdInvitation.suggestedMemberName`）ので、家族に見える名前を
            // 確かめて変えられることを、入ったときに伝える。
            Text("ホームの上の「家族」に切り替えると、家族の記録が見られ、家計に記録できます。家族に見える「あなたの名前」は、設定の「家族と共有」で確かめて変えられます。")
        case .alreadyJoined:
            Text("この家計には、もう入っています。")
        case .anotherHousehold:
            Text("入れる家計は 1 つだけです。設定の「家族と共有」で、いまの家計から抜ける（作った家計なら削除する）と、受け入れられます。")
        case .invitationInvalid:
            Text("サイフログの家計の招待ではないか、形の違う招待です。")
        case .acceptFailed:
            Text("インターネットにつながっているか、iCloud にサインインしているかを確かめて、招待のリンクをもう一度開いてください。")
        case .accountUnavailable(let status):
            Text(verbatim: status.guidanceText ?? "")
        case .sharingFailed:
            Text("インターネットにつながっているか、iCloud にサインインしているかを確かめて、もう一度お試しください。")
        case .stopSharingFailed:
            Text("家族は、まだこの家計を見られます。インターネットにつながっているか、iCloud にサインインしているかを確かめて、もう一度お試しください。")
        case .sharingStopped:
            Text("家族はこの家計を見られなくなりました。この iPhone の家計の記録は残っています。")
        case .leaveFailed:
            Text("インターネットにつながっているかを確かめて、もう一度お試しください。この iPhone の家計の記録は残っています。")
        case .left:
            Text("この iPhone から家計の記録を消しました。")
        case .deleted:
            Text("家族の端末からも、家計の記録が消えます。")
        case .removed(let removal):
            switch removal {
            case .zoneRemoved(role: .participant):
                Text("家計を作った人が共有をやめたか、家計を削除しました。この iPhone から家計の記録を消しました。自分の記録はそのまま残っています。")
            case .zoneRemoved(role: .owner):
                Text("家計が iCloud から削除されました（ほかの端末で削除したときなど）。この iPhone から家計の記録を消しました。自分の記録はそのまま残っています。")
            case .reuploadedAfterEncryptionReset:
                Text("Apple アカウントの暗号化したデータがリセットされたため、家族との共有が消えました。この iPhone の家計の記録を iCloud に保存し直しています。家族をもう一度招待してください。")
            case .accountChanged:
                Text("iCloud のアカウントが変わったため、この iPhone から家計の記録を消しました。自分の記録はそのまま残っています。")
            }
        case .saveFailed:
            Text("もう一度お試しください。")
        }
    }
}
