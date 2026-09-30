import SaifuLogCore
import SwiftData
import SwiftUI

/// 設定の「カテゴリ」。組み込みのカテゴリと作ったカテゴリの一覧。作ったカテゴリは押すと直せ、左へのスワイプで削除し、
/// 「編集」で並べ替える。
///
/// 状態と操作は `CategoryListModel` が持つ。ここは表示と、シート・確認・アラートの出し入れだけ。
struct CategoryListView: View {
    @Bindable var model: CategoryListModel

    var body: some View {
        List {
            customSection
            builtInSection
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
            if deletion.entryCount > 0 {
                Text("このカテゴリの記録 \(deletion.entryCount) 件は「その他」になります。カテゴリ別の予算と覚えたカテゴリからも外します。")
            } else {
                Text("カテゴリ別の予算と覚えたカテゴリからも外します。")
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
        // iCloud で届いたほかの端末のカテゴリも一覧に出す。
        .onReceive(StoreChanges.remote) { _ in model.reload() }
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
                        .tint(Theme.danger)
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
