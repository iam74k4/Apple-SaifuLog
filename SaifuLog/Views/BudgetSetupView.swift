import SaifuLogCore
import SwiftUI

/// ② 予算を決める。月の予算の金額を入れて保存する。
///
/// 初回の案内（②）・設定（⑧）・ホームのシートで使い回せるよう、閉じ方（`onFinish`）とナビゲーションは
/// 呼び出し側に任せ、ここは中身だけを持つ。状態と操作は `BudgetSetupModel` が持つ。
struct BudgetSetupView: View {
    @Bindable var model: BudgetSetupModel
    /// 保存した（または予算をなくした）あとに呼ぶ。呼び出し側が画面を閉じる・次へ進む。
    let onFinish: () -> Void

    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case total
        case category(EntryCategory)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                introduction
                VStack(alignment: .leading, spacing: 12) {
                    totalField
                    QuickAmountPicker(model: model)
                    Text("予算はあとからいつでも変えられます。")
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                }
                if model.showsCategoryBudgets {
                    categorySection
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
        .background(Theme.background)
        // 保存のボタンは画面の下に置き続ける。数字のキーボードには確定のキーが無いので、キーボードを出したまま
        // 押せる場所に置く（キーボードが出るとその上に移る）。
        .safeAreaInset(edge: .bottom, spacing: 0) {
            saveButton
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Theme.background)
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
            Text("1か月に使うお金の上限を決めると、ホームに今月あといくら使えるかと、1日あたりに使える額が出ます。")
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
                .onChange(of: model.totalText) { model.normalizeTotalText() }
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

    /// カテゴリ別の予算（プレミアム）。空欄のカテゴリは予算なし。
    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("カテゴリ別の予算")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            // 決めた額はまだどの画面の数字にも使わない（使った額との比べは近日）。できるように読ませないため、そのことも書く。
            Text("カテゴリごとにも上限を決められます。空欄のカテゴリは予算なしになります。使った額との比べの表示は近日対応です。")
                .font(.footnote)
                .foregroundStyle(Theme.inkSecondary)
            VStack(spacing: 0) {
                ForEach(EntryCategory.allCases) { category in
                    CategoryBudgetRow(
                        category: category,
                        text: categoryBinding(category),
                        focus: $focusedField,
                        field: .category(category)
                    )
                    .onChange(of: model.categoryTexts[category]) { model.normalizeCategoryText(category) }
                    if category != EntryCategory.allCases.last {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 16)
            .background(Theme.surface, in: .rect(cornerRadius: 16))
        }
    }

    private func categoryBinding(_ category: EntryCategory) -> Binding<String> {
        Binding(
            get: { model.categoryTexts[category] ?? "" },
            set: { model.categoryTexts[category] = $0 }
        )
    }

    private var saveButton: some View {
        Button {
            if model.save() { onFinish() }
        } label: {
            Text("保存")
                .fontWeight(.semibold)
                // 押せるときは山吹の塗りの上なので墨（Theme の説明）。押せないときは灰色のガラスの上なので、
                // 墨のままだとダークで地に沈む。補足の文字の色にする（送信ボタンと同じ）。
                .foregroundStyle(model.canSave ? Theme.onAccent : Theme.inkSecondary)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.glassProminent)
        .tint(Theme.accentFill)
        .disabled(!model.canSave)
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
                    // 選んだ額は山吹で塗る（山吹は塗りにだけ使い、上の文字は墨にする）。
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

/// カテゴリ別の予算の 1 行。大きな文字サイズで 1 行に収まらなければ、名前と入力欄を縦に積む。
private struct CategoryBudgetRow<Field: Hashable>: View {
    let category: EntryCategory
    @Binding var text: String
    var focus: FocusState<Field?>.Binding
    let field: Field

    @ScaledMetric(relativeTo: .body) private var iconSize = 24

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                name
                Spacer(minLength: 8)
                amountField
                    .frame(maxWidth: 160)
            }
            VStack(alignment: .leading, spacing: 4) {
                name
                amountField
            }
            .padding(.vertical, 6)
        }
        .frame(minHeight: 44)
    }

    private var name: some View {
        HStack(spacing: 8) {
            Image(systemName: category.symbolName)
                .font(.system(size: iconSize * 0.5, weight: .semibold))
                .foregroundStyle(Theme.onCategory)
                .frame(width: iconSize, height: iconSize)
                .background(Theme.color(for: category), in: .circle)
                // 丸はダークでもライトの色で塗る（EntryBubble と同じ理由）。
                .environment(\.colorScheme, .light)
                .accessibilityHidden(true)
            Text(category.label)
                .accessibilityHidden(true)
        }
    }

    private var amountField: some View {
        HStack(spacing: 2) {
            Text(verbatim: "¥")
                .foregroundStyle(Theme.inkSecondary)
                .accessibilityHidden(true)
            TextField(text: $text, prompt: Text("予算なし").foregroundStyle(Theme.inkSecondary)) {
                Text(category.label)
            }
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .lineLimit(1)
            .focused(focus, equals: field)
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
                        Button("キャンセル", role: .cancel) { dismiss() }
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

#Preview("カテゴリ別の予算も（プレミアム）") {
    if let container = try? ModelContainerFactory.makeInMemoryContainer() {
        let store = BudgetStore(context: container.mainContext)
        let _ = try? store.setAmounts([.total: 150_000, .category(.food): 40_000])
        BudgetSetupSheet(model: BudgetSetupModel(store: store, showsCategoryBudgets: true))
    }
}
