#if DEBUG || INTERNAL_DIAGNOSTICS
import SwiftData
import SwiftUI

/// 実機での確認のための診断画面（社内テスト用のビルドと DEBUG のビルドだけ）。
///
/// シミュレータでは確かめられないもの（保存先のデータ保護、端末内 AI や音声の書き起こしの可否、iCloud のアカウントと同期）を、TestFlight で
/// 入れた実機で見るために置く。ホームの帯の右上の小さなボタン（VoiceOver では「診断」）から開く。長押しや隠しの
/// ジェスチャにしないのは、ほかの操作（予算のボタンなど）と取り違えず、入っているビルドかどうかが見て分かるように
/// するため。App Store へ出すビルドには入らない（release.mk がアーカイブの中身で確かめる）。
struct DiagnosticsView: View {
    @State private var model: DiagnosticsModel

    @Environment(\.dismiss) private var dismiss

    init(model: DiagnosticsModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("診断")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        // 文字は OS に任せる（閉じるの印と、OS の言語での読み上げ）。既存の「閉じる」のキーは取り消すのバナーの
                        // VoiceOver の操作用（en は Dismiss）で、シートを閉じるボタンの文言とは合わないため。
                        Button(role: .close) { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("再読み込み", systemImage: "arrow.clockwise") {
                            Task { await model.load() }
                        }
                    }
                }
        }
        .task { await model.load() }
        .sensoryFeedback(.success, trigger: model.copyCount)
    }

    @ViewBuilder
    private var content: some View {
        if let report = model.report {
            List {
                Section {
                    Text("社内テスト用と開発用のビルドにだけある画面です。コピーする文には、金額やメモなどの記録の中身は入りません。")
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                }
                ForEach(report.sections) { section in
                    Section {
                        ForEach(section.rows) { row in
                            LabeledContent {
                                Text(verbatim: row.value)
                                    .monospaced()
                                    .textSelection(.enabled)
                            } label: {
                                Text(row.label)
                            }
                        }
                    } header: {
                        Text(section.title)
                    }
                }
                Section {
                    Button("まとめてコピー", systemImage: "doc.on.doc") { model.copyReport() }
                } footer: {
                    if model.copyCount > 0 {
                        Text("コピーしました")
                    }
                }
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// 診断画面を開く操作。`dismiss` と同じく、呼ぶだけの値にする。
struct OpenDiagnosticsAction: Equatable {
    let action: @MainActor () -> Void

    @MainActor
    func callAsFunction() {
        action()
    }

    /// どの値も同じものとして扱う。中身はいつも「ホームの同じ @State を true にする」だけで違いが無いのに、
    /// 関数は比べられないので、ホームを描き直すたびに帯（環境を読む側）まで描き直しになるため。
    static func == (lhs: Self, rhs: Self) -> Bool {
        true
    }
}

extension EnvironmentValues {
    /// ホームの帯の診断ボタンの操作。nil ならボタンを出さない。
    ///
    /// ホームの帯（`SummaryHeader`）の引数に足さず環境で渡すのは、App Store へ出すビルドの型と呼び出しを
    /// 社内テスト用のビルドと同じに保つため（`#if` を帯の作り方まで広げない）。
    @Entry var openDiagnostics: OpenDiagnosticsAction? = nil
}

#Preview {
    if let container = try? ModelContainerFactory.makeInMemoryContainer() {
        // プレビューでは CloudKit に問い合わせない（iCloud の entitlement の無いプロセスで CKContainer を作ると落ちる）。
        DiagnosticsView(model: DiagnosticsModel(context: container.mainContext, iCloudAccount: { .available }))
            .modelContainer(container)
    }
}
#endif
