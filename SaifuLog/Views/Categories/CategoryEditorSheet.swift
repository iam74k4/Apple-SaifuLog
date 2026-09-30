import SaifuLogCore
import SwiftUI

/// カテゴリを作る・直す画面（下から出るシート）。名前・色・記号を選ぶ。作るときは、よく使うカテゴリの候補も出す。
///
/// 状態と操作は `CategoryEditorModel` が持つ。
struct CategoryEditorSheet: View {
    @Bindable var model: CategoryEditorModel

    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .title2) private var previewSize = 44
    @ScaledMetric(relativeTo: .body) private var swatchSize = 36

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    preview
                    nameSection
                    if !model.availablePresets.isEmpty {
                        presetSection
                    }
                    colorSection
                    symbolSection
                }
                .padding()
            }
            .background(Theme.background)
            .navigationTitle(model.mode == .create ? Text("カテゴリを作る") : Text("カテゴリを直す"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if model.save() { dismiss() }
                    }
                    .disabled(!model.canSave)
                }
            }
            .alert("保存できませんでした", isPresented: $model.showsSaveFailure) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("もう一度お試しください。")
            }
        }
    }

    /// 選んでいる色と記号の見本（返事の行の印と同じ形）。
    private var preview: some View {
        HStack(spacing: 12) {
            Image(systemName: model.symbolName)
                .font(.system(size: previewSize * 0.45, weight: .semibold))
                .foregroundStyle(Theme.onCategory)
                .frame(width: previewSize, height: previewSize)
                .background(Palette.customCategory(model.colorIndex).color, in: .rect(cornerRadius: previewSize * 0.28))
                // 印はダークでもライトの色で塗る（返事の行と同じ。白い記号を読めるように）。
                .environment(\.colorScheme, .light)
                .accessibilityHidden(true)
            Text(verbatim: model.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? " " : model.name)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .accessibilityHidden(true)
        }
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("名前")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
            TextField(text: $model.name, prompt: Text("衣服・住居・美容 など").foregroundStyle(Theme.inkSecondary)) {
                Text("名前")
            }
            .foregroundStyle(Theme.ink)
            .submitLabel(.done)
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .background(Theme.surface, in: .rect(cornerRadius: 14))
            if let issue = model.issue {
                Label {
                    issueText(issue)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.footnote)
                .foregroundStyle(Theme.danger)
            } else {
                Text("「衣服 3000」のように名前を書いて送ると、このカテゴリで記録します。")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
    }

    private func issueText(_ issue: CategoryNameIssue) -> Text {
        switch issue {
        case .empty: Text("名前を入れてください。")
        case .tooLong: Text("名前は \(CategoryCatalog.maximumNameLength) 文字までにしてください。")
        case .duplicate: Text("同じ名前のカテゴリがあります。")
        }
    }

    /// よく使うカテゴリの候補（押すと名前と記号を入れる）。
    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("よく使うカテゴリ")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
            FlowLayout(spacing: 8) {
                ForEach(model.availablePresets, id: \.name) { preset in
                    Button {
                        model.choosePreset(name: preset.name, symbolName: preset.symbolName)
                    } label: {
                        Label {
                            Text(verbatim: preset.name)
                        } icon: {
                            Image(systemName: preset.symbolName)
                        }
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 36)
                        .background {
                            Capsule()
                                .fill(Theme.surface)
                                .stroke(Theme.track, lineWidth: 1)
                        }
                        .padding(.vertical, 4)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("名前と記号を入れます")
                }
            }
        }
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("色")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
            FlowLayout(spacing: 12) {
                ForEach(Palette.customCategoryChoices.indices, id: \.self) { index in
                    let isSelected = model.colorIndex == index
                    Button {
                        model.colorIndex = index
                    } label: {
                        Circle()
                            .fill(Palette.customCategory(index).color)
                            .frame(width: swatchSize, height: swatchSize)
                            .overlay {
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: swatchSize * 0.4, weight: .bold))
                                        .foregroundStyle(Theme.onCategory)
                                }
                            }
                            // 選んだ色は枠でも示す（色だけに頼らない）。
                            .padding(3)
                            .overlay { Circle().stroke(isSelected ? Theme.ink : .clear, lineWidth: 2) }
                            .environment(\.colorScheme, .light)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(CategoryEditorModel.colorName(index)))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }

    private var symbolSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("記号")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
            FlowLayout(spacing: 8) {
                ForEach(CategoryCatalog.symbolChoices, id: \.self) { symbol in
                    let isSelected = model.symbolName == symbol
                    Button {
                        model.symbolName = symbol
                    } label: {
                        symbolTile(symbol, isSelected: isSelected)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(CategoryEditorModel.symbolLabel(symbol)))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }
}

extension CategoryEditorSheet {
    /// 記号のボタンの中身。選んだ記号は選んだ色で塗り（返事の行の印と同じく、ダークでもライトの色で塗って白い記号を読めるように）、
    /// ほかは面の色に墨の記号にする。
    @ViewBuilder
    private func symbolTile(_ symbol: String, isSelected: Bool) -> some View {
        let image = Image(systemName: symbol)
            .font(.system(size: swatchSize * 0.45, weight: .semibold))
            .frame(width: swatchSize + 8, height: swatchSize + 8)
        if isSelected {
            image
                .foregroundStyle(Theme.onCategory)
                .background(Palette.customCategory(model.colorIndex).color, in: .rect(cornerRadius: 12))
                .environment(\.colorScheme, .light)
        } else {
            image
                .foregroundStyle(Theme.ink)
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Theme.surface)
                        .stroke(Theme.track, lineWidth: 1)
                }
        }
    }
}

/// 子を左から並べ、幅に収まらなければ次の行に折り返す（候補・色・記号のボタン）。
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        var current: (indices: [Int], width: CGFloat, height: CGFloat) = ([], 0, 0)
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if !current.indices.isEmpty, needed > width {
                rows.append(current)
                current = ([index], size.width, size.height)
            } else {
                current.indices.append(index)
                current.width = needed
                current.height = max(current.height, size.height)
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
