import SaifuLogCore
import SwiftData
import SwiftUI

/// 設定の「覚えたカテゴリ」。覚えた言葉とカテゴリの一覧（修正の記憶）。行を押すとカテゴリを変えられ、左へのスワイプで忘れる。
///
/// 状態と操作は `LearnedCategoriesModel` が持つ。ここは表示と、確認・アラートの出し入れだけ。
struct LearnedCategoriesView: View {
    @Bindable var model: LearnedCategoriesModel

    @Environment(\.categoryCatalog) private var catalog

    var body: some View {
        List {
            if model.rules.isEmpty {
                Section {
                    Text("まだ覚えたカテゴリはありません。記録の返事でカテゴリを選んだり、直す画面でカテゴリを変えたりすると、ここに並びます。")
                        .foregroundStyle(Theme.inkSecondary)
                        .listRowBackground(Theme.surface)
                }
            } else {
                Section {
                    ForEach(model.rules) { rule in
                        row(rule)
                            .swipeActions {
                                Button("忘れる", role: .destructive) { model.forget(rule) }
                            }
                            // スワイプは VoiceOver から見つけにくいので、操作の一覧にも出す。
                            .accessibilityAction(named: "忘れる") { model.forget(rule) }
                            .listRowBackground(Theme.surface)
                    }
                } footer: {
                    Text("同じ言葉の記録を、次からこのカテゴリで記録します。前に記録したものは変わりません。覚えた言葉は記録と同じ場所（この iPhone、iCloud で同期しているときはあなたの iCloud）に保存し、外へ送りません。")
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("覚えたカテゴリ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !model.rules.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("すべて忘れる", role: .destructive) { model.showsForgetAllConfirmation = true }
                }
            }
        }
        .confirmationDialog(
            "覚えたカテゴリをすべて忘れますか？",
            isPresented: $model.showsForgetAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("すべて忘れる", role: .destructive) { model.forgetAll() }
        } message: {
            Text("記録は消えません。次からは、いつもどおり AI とキーワード辞書でカテゴリを読みます。")
        }
        .alert(
            model.failure == .load ? Text("読み込めませんでした") : Text("保存できませんでした"),
            isPresented: showsFailure
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("もう一度お試しください。")
        }
        // iCloud で届いたほかの端末の覚えも一覧に出す。
        .onReceive(StoreChanges.remote) { _ in model.reload() }
    }

    /// 覚えた言葉と、いまのカテゴリ。押すとカテゴリを選ぶメニューを開く。
    private func row(_ rule: LearnedCategoryStore.Rule) -> some View {
        Menu {
            Picker(selection: Binding(
                get: { rule.category },
                set: { model.change(rule, to: $0, named: catalog.localizedName(for: $0)) }
            )) {
                ForEach(catalog.all) { category in
                    catalog.label(for: category).tag(category)
                }
            } label: {
                Text("カテゴリ")
            }
        } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    phrase(rule)
                    Spacer(minLength: 0)
                    category(rule)
                        .fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: 4) {
                    phrase(rule)
                    category(rule)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .multilineTextAlignment(.leading)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .accessibilityLabel(Text(verbatim: rule.phrase))
        .accessibilityValue(catalog.label(for: rule.category))
        .accessibilityHint("カテゴリを選び直します")
    }

    private func phrase(_ rule: LearnedCategoryStore.Rule) -> some View {
        Text(verbatim: rule.phrase)
            .foregroundStyle(Theme.ink)
    }

    /// カテゴリの色の丸と名前（色だけで見分けさせない）。
    private func category(_ rule: LearnedCategoryStore.Rule) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(catalog.color(for: rule.category))
                .frame(width: 8, height: 8)
            catalog.label(for: rule.category)
            Image(systemName: "chevron.up.chevron.down")
                .imageScale(.small)
        }
        .foregroundStyle(Theme.inkSecondary)
    }

    private var showsFailure: Binding<Bool> {
        Binding(get: { model.failure != nil }, set: { if !$0 { model.failure = nil } })
    }
}

#Preview {
    if let container = try? ModelContainerFactory.makeInMemoryContainer() {
        let store = LearnedCategoryStore(context: container.mainContext)
        let _ = try? store.remember(item: "ユニクロ", category: .other)
        let _ = try? store.remember(item: "ジム", category: .entertainment)
        NavigationStack {
            LearnedCategoriesView(model: LearnedCategoriesModel(store: store))
        }
    }
}
