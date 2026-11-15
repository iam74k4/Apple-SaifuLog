import SaifuLogCore
import SwiftUI

/// カードを登録する・直す画面（下から出るシート）。名前・締め日・引き落とし日（翌月か翌々月か）・いつものカードを決める。
/// 登録するときは、よく使うカードの候補も出す。
///
/// 状態と操作は `CardEditorModel` が持つ。
struct CardEditorSheet: View {
    @Bindable var model: CardEditorModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.calendar) private var calendar

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    nameSection
                    if !model.availablePresets.isEmpty {
                        presetSection
                    }
                    scheduleSection
                    defaultSection
                }
                .padding()
            }
            .background(Theme.background)
            .scrollEdgeEffectStyle(.hard, for: .top)
            .navigationTitle(model.mode == .create ? Text("カードを登録") : Text("カードを直す"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) {
                        if model.requestClose() { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        if model.save() { dismiss() }
                    }
                    .disabled(!model.canSave)
                    .accessibilityIdentifier(AccessibilityID.Cards.saveButton)
                }
            }
            .alert("保存できませんでした", isPresented: $model.showsSaveFailure) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("もう一度お試しください。")
            }
            .confirmationDialog(
                model.mode == .create ? Text("入力した内容を破棄しますか？") : Text("直した内容を破棄しますか？"),
                isPresented: $model.showsDiscardConfirmation,
                titleVisibility: .visible
            ) {
                Button("破棄して閉じる", role: .destructive) { dismiss() }
                Button(role: .cancel) {} label: {
                    model.mode == .create ? Text("入力を続ける") : Text("直すのを続ける")
                }
            }
        }
        .interactiveDismissDisabled(model.hasChanges)
        .background(SheetDismissAttemptObserver { model.showsDiscardConfirmation = true })
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("名前")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
            TextField(text: $model.name, prompt: Text("楽天カード・メインのカード など").foregroundStyle(Theme.inkSecondary)) {
                Text("名前")
            }
            .foregroundStyle(Theme.ink)
            .accessibilityIdentifier(AccessibilityID.Cards.nameField)
            .submitLabel(.done)
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .background(Theme.surface, in: .rect(cornerRadius: 14))
            if let issue = model.issue {
                Label {
                    switch issue {
                    case .empty: Text("名前を入れてください。")
                    case .tooLong: Text("名前は \(PaymentCard.maximumNameLength) 文字までにしてください。")
                    case .duplicate: Text("同じ名前のカードがあります。")
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.footnote)
                .foregroundStyle(Theme.danger)
            }
        }
    }

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("よく使うカード")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
            FlowLayout(spacing: 8) {
                ForEach(model.availablePresets, id: \.name) { preset in
                    Button {
                        model.choosePreset(name: preset.name, closingDay: preset.closingDay, paymentDay: preset.paymentDay)
                    } label: {
                        Text(verbatim: preset.name)
                            .font(.subheadline)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 40)
                            .background(Theme.surface, in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.ink)
                }
            }
        }
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(spacing: 0) {
                dayPicker(Text("締め日"), selection: $model.closingDay)
                Divider().padding(.leading, 16)
                pickerRow(Text("引き落とす月"), selection: $model.paymentMonthOffset) {
                    Text("翌月").tag(1)
                    Text("翌々月").tag(2)
                }
                Divider().padding(.leading, 16)
                dayPicker(Text("引き落とし日"), selection: $model.paymentDay)
            }
            .background(Theme.surface, in: .rect(cornerRadius: 14))
            if let example = model.example(now: .now, calendar: calendar) {
                Text(verbatim: example)
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
    }

    /// 見出しを左、選んだ値を右に置く行。メニューの Picker は Form の外ではラベルを描かず、値だけが真ん中に並んで
    /// どの欄か分からなかったので、見出しを自分で置く（読み上げは Picker のラベルのまま）。
    private func pickerRow<Value: Hashable, Content: View>(
        _ label: Text, selection: Binding<Value>, @ViewBuilder choices: () -> Content
    ) -> some View {
        HStack {
            label
            Spacer(minLength: 8)
            Picker(selection: selection, content: choices) { label }
                .pickerStyle(.menu)
                .labelsHidden()
        }
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .frame(minHeight: 48)
    }

    private func dayPicker(_ label: Text, selection: Binding<Int>) -> some View {
        pickerRow(label, selection: selection) {
            ForEach(PaymentCard.dayRange, id: \.self) { day in
                Text(verbatim: CardTexts.dayChoice(day)).tag(day)
            }
        }
    }

    private var defaultSection: some View {
        Toggle(isOn: $model.isDefault) {
            Text("いつものカード")
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
        .background(Theme.surface, in: .rect(cornerRadius: 14))
    }
}
