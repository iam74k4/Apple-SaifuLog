import SaifuLogCore
import SwiftUI

/// 自動記録を止めず、利用者の判断が要る分だけをまとめる。
struct EntryReviewQueueView: View {
    @Bindable var model: HomeModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.categoryCatalog) private var catalog

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if model.reviewLoadFailed {
                        LoadFailedView(retry: { model.refreshPendingReviews() })
                    } else if model.reviewItems.isEmpty {
                        ContentUnavailableView("確認はすべて完了", systemImage: "checkmark.circle", description: Text("記録は保存されています。"))
                    } else {
                        Text("迷った記録だけ、ここで確認。閉じても残ります。")
                            .font(.subheadline).foregroundStyle(Theme.inkSecondary)
                        ForEach(model.reviewItems) { item in
                            VStack(alignment: .leading, spacing: 14) {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: item.overlap == nil ? "tag.fill" : "square.on.square")
                                        .font(.title2).foregroundStyle(catalog.color(for: item.category))
                                        .frame(width: 38, height: 44).accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(verbatim: item.memo).font(.headline)
                                        Text(item.spentAt, format: .dateTime.month().day()).font(.caption).foregroundStyle(Theme.inkSecondary)
                                        Text(verbatim: YenFormatter.string(from: item.amount)).font(.title3.bold()).monospacedDigit()
                                    }
                                }
                                if let overlap = item.overlap {
                                    PaymentOverlapView(question: overlap, remove: { model.removeOverlappingPayment(for: item.id) },
                                                       keep: { model.keepOverlappingPayment(for: item.id) })
                                }
                                if item.needsCategory {
                                    if model.classifyingPaymentIDs.contains(item.id) {
                                        HStack { ProgressView(); Text("AIがカテゴリを振り分け中") }.font(.subheadline)
                                    } else {
                                        Menu {
                                            ForEach(catalog.all) { category in
                                                Button { model.chooseReviewCategory(category, for: item.id) } label: { catalog.label(for: category) }
                                            }
                                        } label: {
                                            Label("カテゴリを選ぶ", systemImage: "tag").frame(maxWidth: .infinity, minHeight: 32)
                                        }
                                        .buttonStyle(.glass).accessibilityIdentifier("review-category")
                                    }
                                }
                            }
                            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.surface, in: .rect(cornerRadius: 20))
                        }
                    }
                }.padding()
            }
            .background(Theme.background).foregroundStyle(Theme.ink)
            .navigationTitle("確認待ち").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } } }
        }
        .onAppear { model.refreshPendingReviews() }
        .alert(model.storeFailure?.title ?? Text(verbatim: ""),
               isPresented: Binding(get: { model.storeFailure != nil }, set: { if !$0 { model.storeFailure = nil } }),
               presenting: model.storeFailure) { _ in Button("OK", role: .cancel) {} }
               message: { $0.message }
    }
}
