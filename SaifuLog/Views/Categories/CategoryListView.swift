import SaifuLogCore
import SwiftData
import SwiftUI

/// 設定の「カテゴリ」。組み込みのカテゴリと作ったカテゴリの一覧。作ったカテゴリは押すと直せ、左へのスワイプで削除し、
/// 「編集」で並べ替える。いちばん下から「覚えたカテゴリ」（修正の記憶の一覧）へ進む（カテゴリの決まり方のことなので、
/// 設定の行を分けずにここにまとめた）。
///
/// 状態と操作は `CategoryListModel` が持つ。ここは表示と、シート・確認・アラートの出し入れだけ。
/// ほかの端末（iCloud）の変更での読み直しは、この画面の下にある設定の画面が受け持つ（`SettingsView`）。
struct CategoryListView: View {
    @Bindable var model: CategoryListModel
    /// 「覚えたカテゴリ」の状態と操作。無ければ（プレビュー）行を出さない。
    var learnedCategories: LearnedCategoriesModel?

    var body: some View {
        List {
            customSection
            builtInSection
            if let learnedCategories {
                learnedSection(learnedCategories)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(Text(.categoriesTitle))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // 並べ替えは 2 つ以上作ってから。
            if model.customs.count > 1 {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
        }
        .sheet(item: $model.editor) { editor in
            CategoryEditorSheet(model: editor)
        }
        .confirmationDialog(
            deletionTitle,
            isPresented: showsDeletionConfirmation,
            titleVisibility: .visible,
            presenting: model.pendingDeletion
        ) { deletion in
            Button("削除", role: .destructive) { model.confirmDeletion(deletion) }
        } message: { deletion in
            // くり返しの記録も「その他」になる（`CustomCategoryStore.delete`）。次の月から黙って「その他」で記録されないよう、
            // 件数を出して先に伝える。
            if deletion.entryCount > 0, deletion.recurringCount > 0 {
                Text("このカテゴリの記録 \(deletion.entryCount) 件と、くり返しの記録 \(deletion.recurringCount) 件は「その他」になります。覚えたカテゴリからも外します。")
            } else if deletion.entryCount > 0 {
                Text("このカテゴリの記録 \(deletion.entryCount) 件は「その他」になります。覚えたカテゴリからも外します。")
            } else if deletion.recurringCount > 0 {
                Text("このカテゴリのくり返しの記録 \(deletion.recurringCount) 件は「その他」になります。覚えたカテゴリからも外します。")
            } else {
                Text("覚えたカテゴリからも外します。")
            }
        }
        .alert(
            model.failure == .load ? Text("読み込めませんでした") : Text("保存できませんでした"),
            isPresented: showsFailure
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("もう一度お試しください。")
        }
        // 作ったカテゴリの印と色を、この画面の一覧から引く（作った・直した直後にも合うように）。
        .environment(\.categoryCatalog, model.catalog)
    }

    // MARK: - 作ったカテゴリ

    private var customSection: some View {
        Section {
            if model.customs.isEmpty {
                Text("まだ作ったカテゴリはありません。家賃・服・美容など、よく使う分け方を作れます。")
                    .foregroundStyle(Theme.inkSecondary)
                    .listRowBackground(Theme.surface)
            }
            ForEach(model.customs) { info in
                customRow(info)
                    // 削除は確かめてから（記録が「その他」になるため）。破壊の役割にすると、確かめる前に行が消えて見えるので、
                    // 色だけ付ける。
                    .swipeActions {
                        Button {
                            model.requestDeletion(info.category)
                        } label: {
                            Label("削除", systemImage: "trash")
                        }
                        .tint(Theme.dangerFill)
                    }
                    // スワイプとドラッグは VoiceOver から見つけにくいので、操作の一覧にも出す。
                    .accessibilityAction(named: "削除") { model.requestDeletion(info.category) }
                    .accessibilityAction(named: "前へ移動") { model.moveEarlier(info.category) }
                    .accessibilityAction(named: "後ろへ移動") { model.moveLater(info.category) }
                    .listRowBackground(Theme.surface)
            }
            .onMove { model.move(fromOffsets: $0, toOffset: $1) }
            Button {
                model.presentCreation()
            } label: {
                Label("カテゴリを作る", systemImage: "plus")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(.rect)
            }
            .disabled(!model.canCreate)
            .accessibilityHint("名前・色・記号を決めて、新しいカテゴリを作ります")
            .listRowBackground(Theme.surface)
        } header: {
            Text("作ったカテゴリ")
                .foregroundStyle(Theme.inkSecondary)
        } footer: {
            Text(customFooter)
                .foregroundStyle(Theme.inkSecondary)
        }
    }

    private var customFooter: LocalizedStringResource {
        if model.canCreate {
            "「衣服 3000」のようにカテゴリの名前を書いて送ると、そのカテゴリで記録します。\(CategoryCatalog.maximumCustomCount) 個まで作れます。"
        } else {
            "作れるのは \(CategoryCatalog.maximumCustomCount) 個までです。使わないカテゴリを削除すると、新しく作れます。"
        }
    }

    private func customRow(_ info: CustomCategoryInfo) -> some View {
        Button {
            model.presentEditing(info.category)
        } label: {
            HStack(spacing: 12) {
                CategoryIcon(category: info.category)
                Text(verbatim: info.name)
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .accessibilityHint("名前・色・記号を直します")
    }

    // MARK: - 組み込みのカテゴリ

    private var builtInSection: some View {
        Section {
            ForEach(EntryCategory.builtIns) { category in
                HStack(spacing: 12) {
                    CategoryIcon(category: category)
                    Text(category.label)
                        .foregroundStyle(Theme.ink)
                }
                .frame(minHeight: 44)
                .accessibilityElement(children: .combine)
                .listRowBackground(Theme.surface)
            }
        } header: {
            Text("はじめからあるカテゴリ")
                .foregroundStyle(Theme.inkSecondary)
        } footer: {
            Text("はじめからあるカテゴリは、名前を変えたり削除したりできません。どれにも当てはまらない記録は「その他」になります。")
                .foregroundStyle(Theme.inkSecondary)
        }
    }

    // MARK: - 覚えたカテゴリ

    /// 覚えたカテゴリの一覧へ進む行。覚えた言葉の数を出す。
    private func learnedSection(_ learned: LearnedCategoriesModel) -> some View {
        Section {
            NavigationLink {
                LearnedCategoriesView(model: learned)
                    .onAppear { learned.reload() }
            } label: {
                LabeledContent {
                    // 記録の件数の「件」とは別のキーにする（英語では記録ではなく言葉の数として訳すため）。
                    Text(LocalizedStringResource(
                        "%lld 件（覚えたカテゴリ）", defaultValue: "\(learned.rules.count) 件",
                        comment: "カテゴリの画面の「覚えたカテゴリ」の行の右に出す、覚えた言葉の数。%lld は数"
                    ))
                        .foregroundStyle(Theme.inkSecondary)
                        .monospacedDigit()
                } label: {
                    Label {
                        Text("覚えたカテゴリ")
                            .foregroundStyle(Theme.ink)
                    } icon: {
                        SettingsRowIcon(symbolName: "lightbulb", fill: SettingsRowIcon.teal)
                    }
                }
                .frame(minHeight: 44)
            }
            .accessibilityHint("覚えた言葉とカテゴリの一覧を開きます")
            .listRowBackground(Theme.surface)
        } footer: {
            Text("記録の返事でカテゴリを選んだり、直す画面でカテゴリを変えたりすると、同じ言葉を次からそのカテゴリで記録します。")
                .foregroundStyle(Theme.inkSecondary)
        }
    }

    // MARK: - 確認とアラート

    private var deletionTitle: Text {
        Text("「\(model.pendingDeletion?.name ?? "")」を削除しますか？")
    }

    private var showsDeletionConfirmation: Binding<Bool> {
        Binding(get: { model.pendingDeletion != nil }, set: { if !$0 { model.pendingDeletion = nil } })
    }

    private var showsFailure: Binding<Bool> {
        Binding(get: { model.failure != nil }, set: { if !$0 { model.failure = nil } })
    }
}

extension LocalizedStringResource {
    /// 設定の「カテゴリ」（節の見出し・行・一覧の画面の題名）。直すシートの欄の見出し（「カテゴリ」）とは別のキーにする
    /// （日本語は同じでも、英語では一覧を指すので複数形にするため）。
    static let categoriesTitle = LocalizedStringResource(
        "カテゴリ（設定）", defaultValue: "カテゴリ",
        comment: "設定の節の見出しと行、その一覧の画面の題名。はじめからあるカテゴリと作ったカテゴリを並べ、作る・直す・削除する"
    )
}

#Preview {
    if let container = try? ModelContainerFactory.makeInMemoryContainer() {
        let store = CustomCategoryStore(context: container.mainContext)
        let _ = try? store.create(name: "衣服", symbolName: "tshirt", colorIndex: 0)
        let _ = try? store.create(name: "住居", symbolName: "house", colorIndex: 1)
        NavigationStack {
            CategoryListView(model: CategoryListModel(store: store, categories: CategoryCatalogModel(store: store)))
        }
    }
}
