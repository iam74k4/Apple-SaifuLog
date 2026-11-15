import SaifuLogCore
import SwiftUI

extension EnvironmentValues {
    /// いまのカードの一覧。ホームが渡し（`CardCatalogModel`）、直す画面・レシート・くり返しの記録のカードを選ぶ欄と、
    /// 返事の行のカードの名前に使う。カテゴリの一覧（`categoryCatalog`）と同じく、シートやまとめの画面にも届く。
    @Entry var paymentCards: [PaymentCard] = []
}

/// 払ったカードを選ぶメニュー（直す画面・レシート・くり返しの記録）。「現金・その他」と登録したカードを並べる。
///
/// 一覧に無いカード（ほかの端末で消した）を指していれば、「現金・その他」として出す（選び直すと書き換わる）。
struct CardPickerMenu: View {
    @Binding var cardID: String
    /// 欄の地の色（置く画面に合わせる）。
    var fill: Color = Theme.surface

    @Environment(\.paymentCards) private var cards

    var body: some View {
        Menu {
            Picker(selection: $cardID) {
                Label {
                    Text("現金・その他")
                } icon: {
                    Image(systemName: "banknote")
                }
                .tag("")
                ForEach(cards) { card in
                    Label {
                        Text(verbatim: card.name)
                    } icon: {
                        Image(systemName: "creditcard")
                    }
                    .tag(card.id)
                }
            } label: {
                Text("支払い")
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selected == nil ? "banknote" : "creditcard")
                    .foregroundStyle(Theme.inkSecondary)
                    .accessibilityHidden(true)
                selectedName
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(fill, in: .rect(cornerRadius: 14))
            .contentShape(.rect(cornerRadius: 14))
        }
        .accessibilityLabel(Text("支払い"))
        .accessibilityValue(selectedName)
        .accessibilityIdentifier(AccessibilityID.Cards.picker)
    }

    private var selected: PaymentCard? {
        cards.first { $0.id == cardID }
    }

    private var selectedName: Text {
        selected.map { Text(verbatim: $0.name) } ?? Text("現金・その他")
    }
}
