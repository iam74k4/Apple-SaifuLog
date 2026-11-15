import SaifuLogCore
import SwiftUI

/// ② 予算を決める。月の予算の金額を入れて保存する。
///
/// 設定（⑧）・ホームのシートで使い回せるよう、閉じ方（`onFinish`）とナビゲーションは呼び出し側に任せ、ここは
/// 中身だけを持つ。状態と操作は `BudgetSetupModel` が持つ。
struct BudgetSetupView: View {
    @Bindable var model: BudgetSetupModel
    /// 保存した（または予算をなくした）あとに呼ぶ。呼び出し側が画面を閉じる。
    let onFinish: () -> Void

    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case total
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                introduction
                VStack(alignment: .leading, spacing: 12) {
                    totalField
                    QuickAmountPicker(model: model)
                }
                if model.hadTotalBudget {
                    removeButton
                }
            }
            .foregroundStyle(Theme.ink)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        // 上へ流れた文や大きな金額が、ツールバーのボタンの後ろで透けて重ならないよう、上ははっきりした効果にする（ホームの帯と同じ）。
        .scrollEdgeEffectStyle(.hard, for: .top)
        .background(Theme.background)
        // 閉じると保存は、iOS 26 の標準の形（左上の ×・右上の ✓）にする。前は文字の「キャンセル」と、下に浮く大きな「保存」で、
        // 押せない間は灰色の塊になって中身（日付の欄）を隠し、シートごとに保存の場所も違った。右上の ✓ は、数字のキーボードを
        // 出したままでも押せる（数字のキーボードには確定のキーが無い）。
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(role: .confirm) {
                    if model.save() { onFinish() }
                }
                .disabled(!model.canSave)
                .accessibilityIdentifier(AccessibilityID.Budget.saveButton)
            }
        }
        .alert("予算を保存できませんでした", isPresented: $model.showsSaveFailure) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("保存に失敗しました。もう一度お試しください。")
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("月の予算を決める")
                .font(.title.bold())
                .accessibilityAddTraits(.isHeader)
            Text("1か月に使うお金の上限を決めると、ホームに今月あといくら使えるかが出ます。")
                .foregroundStyle(Theme.inkSecondary)
        }
    }

    /// 全体の予算の入力欄。「¥」を前に置き、入れた数字は 3 桁ごとにカンマを入れて見せる。
    private var totalField: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 見出しは入力欄のラベルと同じなので、VoiceOver では入力欄だけを読ませる。
            Text("月の予算")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
                .accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: "¥")
                    .foregroundStyle(Theme.inkSecondary)
                    .accessibilityHidden(true)
                TextField(text: $model.totalText, prompt: Text(verbatim: "0").foregroundStyle(Theme.inkSecondary)) {
                    Text("月の予算（円）")
                }
                .keyboardType(.numberPad)
                .focused($focusedField, equals: .total)
                // 打っている間は区切りを入れず、入力欄を離れたときにそろえる（`formatsAmountAfterEditing` の説明）。桁数を超えた
                // ときだけ、打っている間にも切る（切った額で黙って保存しないように）。
                .onChange(of: model.totalText) { model.limitTotalText() }
                .formatsAmountAfterEditing(isEditing: focusedField == .total, normalize: model.normalizeTotalText)
                .accessibilityIdentifier(AccessibilityID.Budget.amountField)
            }
            .font(.largeTitle.bold())
            .monospacedDigit()
            .lineLimit(1)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Theme.surface, in: .rect(cornerRadius: 16))
            // 「¥」や枠の余白を押しても入力欄にフォーカスが入るようにする。入力欄そのものの操作（カーソルの移動や
            // 長押しの貼り付け）を妨げないよう、同時に働くジェスチャーにする（ホームの入力欄と同じ）。
            .contentShape(.rect(cornerRadius: 16))
            .simultaneousGesture(TapGesture().onEnded { focusedField = .total })
            // 入力欄の文字は縮められない（1 行のまま横にはみ出す）。最大の文字サイズでは 8 桁の額が枠に
            // 収まらず、打った桁が見えなくなるので、大きさに上限を設ける。
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
    }

    /// 全体の予算をなくす。決めた予算があるときだけ出す。押すと確認を出し、確かめてからなくす
    /// （`BudgetSetupModel.requestRemoveTotalBudget()`）。VoiceOver のダブルタップも同じ操作なので、同じ確認が出る。
    private var removeButton: some View {
        Button {
            model.requestRemoveTotalBudget()
        } label: {
            Text("予算をなくす")
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(.rect)
        }
        .foregroundStyle(Theme.danger)
        // ボタンに付ける（画面全体に付けると、吹き出しの形で出たときに、押したボタンではなく画面の途中を指すため）。
        .confirmationDialog(
            "予算をなくしますか？", isPresented: $model.showsRemoveConfirmation, titleVisibility: .visible
        ) {
            Button("予算をなくす", role: .destructive) {
                if model.removeTotalBudget() { onFinish() }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("ホームに今月あといくら使えるかが出なくなります。予算はあとからまた決められます。")
        }
    }
}

/// すぐに選べる額のボタン。1 行に収まらなければ（大きな文字サイズ）縦に並べる。
private struct QuickAmountPicker: View {
    let model: BudgetSetupModel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { buttons }
            VStack(alignment: .leading, spacing: 8) { buttons }
        }
    }

    private var buttons: some View {
        ForEach(BudgetSetupModel.quickAmounts, id: \.self) { amount in
            let isSelected = model.isSelected(quickAmount: amount)
            Button {
                model.selectQuickAmount(amount)
            } label: {
                Text(verbatim: YenFormatter.string(from: amount))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    // 金額は桁の途中で折り返さない。
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    // 選んだ額は主の塗りで塗る（上の文字は onAccent）。
                    .foregroundStyle(isSelected ? Theme.onAccent : Theme.ink)
                    .background(isSelected ? Theme.accentFill : Theme.surface, in: .capsule)
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            // 選んだことを色だけで伝えない（VoiceOver には「選択中」と読ませる）。
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }
}

/// ホームから出す「予算を決める」のシート。保存したら閉じる。
struct BudgetSetupSheet: View {
    let model: BudgetSetupModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            BudgetSetupView(model: model, onFinish: { dismiss() })
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .close) { dismiss() }
                    }
                }
        }
    }
}

#Preview("初めて決める") {
    if let container = try? ModelContainerFactory.makeInMemoryContainer() {
        BudgetSetupSheet(model: BudgetSetupModel(store: BudgetStore(context: container.mainContext)))
    }
}
