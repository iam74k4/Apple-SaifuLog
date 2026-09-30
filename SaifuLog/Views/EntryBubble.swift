import SaifuLogCore
import SwiftUI

/// タイムラインの 1 件。自分が送ったメッセージのように右寄せの吹き出しで出す。
///
/// 吹き出しを押すと「直す」のシートを開く。長押しのメニューには「直す」と「削除」を出す。
///
/// 自分の記録（`Entry`）と家計の記録（`HouseholdEntry`）の両方に使う。家計の記録は、だれが記録したか（`recorderName`）を
/// 日付の前に添える（家族の記録が混ざって並ぶので、だれのものかが分からないと直す・消すを決められないため）。
struct EntryBubble<Record: LedgerEntryDisplaying>: View {
    let entry: Record
    /// 今日。日付に年を添えるかの基準にする。
    let today: Date
    /// 「直す」のシートを出す。
    let edit: () -> Void
    /// 削除を求める（確認は呼び出し側で出す）。
    let requestDelete: () -> Void
    /// 記録した人の名前（家計の記録だけ）。nil なら出さない（自分の記録）。
    var recorderName: String?

    @Environment(\.calendar) private var calendar
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.displayScale) private var displayScale
    @ScaledMetric(relativeTo: .body) private var iconSize = 28

    /// アクセシビリティサイズの文字では、横に並べると種別・記録した人・日付が数文字の幅に押し込まれ、
    /// 語の途中で折り返される。そのときは左の余白と右のアイコンをやめ、1 行に収まらない行を縦に積む
    /// （品目と金額の行は、文字の大きさによらず `EntryTitleAmountRow` が収まるかどうかで選ぶ）。
    private var stacksVertically: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        // 左の余白・吹き出し・右のアイコンを、HStack（Spacer + 吹き出し + アイコン）と同じ位置に置く（`EntryBubbleRowLayout`）。
        // 縦に積むときは左の余白と右のアイコンをやめ、吹き出しに画面の幅を使わせる。
        EntryBubbleRowLayout(leadingMinimum: stacksVertically ? 0 : 40, spacing: 10, displayScale: displayScale) {
            // 押せるのは吹き出しだけにする（左の余白や右の丸を押して、思わず開かないように）。
            Button(action: edit) {
                bubble
            }
            // 文字の色は吹き出しの中で決めているので、tint に染めない形にする（押している間は薄くなる）。
            .buttonStyle(.plain)
            .contentShape(.contextMenuPreview, .rect(cornerRadius: 18))
            .contextMenu {
                Button("直す", systemImage: "pencil", action: edit)
                Button("削除", systemImage: "trash", role: .destructive, action: requestDelete)
            }
            if !stacksVertically {
                icon
            }
        }
        // VoiceOver では 1 件を 1 つの要素として、品目・金額・カテゴリ・日付の順に読ませる。
        .accessibilityElement(children: .combine)
        // ダブルタップ（既定の操作）で吹き出しを押したときと同じく「直す」を開く。
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("記録を直す画面を開きます")
        .accessibilityAction(.default, edit)
        // 長押しのメニューは VoiceOver から見つけにくいので、直す・削除を操作の一覧にも出す。
        .accessibilityAction(named: "直す", edit)
        .accessibilityAction(named: "削除", requestDelete)
    }

    private var bubble: some View {
        VStack(alignment: .trailing, spacing: 6) {
            EntryTitleAmountRow(titleHasLineBreaks: entry.memo.contains(where: \.isNewline)) {
                title
            } amount: {
                Text(verbatim: amountText)
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(entry.isIncome ? Theme.income : Theme.ink)
                    // 金額は桁の途中で改行させない。収まらなければ縮めて 1 行に収める。
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            AdaptiveRowLayout(stacksWhenNeeded: stacksVertically, spacing: 6) {
                // メモが空のときは見出しがカテゴリ名なので、ここでは繰り返さない
                // （同じ語が 2 回表示され、VoiceOver でも 2 回読まれるため）。
                if !entry.memo.isEmpty {
                    kindLabel
                }
                if let recorderName {
                    recorderLabel(recorderName)
                }
                Text(entry.spentAt, format: dateFormat)
            }
            .font(.caption)
            .foregroundStyle(Theme.inkSecondary)
        }
        // 見出しの文字をシステムの黒ではなく墨にそろえる（金額と日付の行は内側で色を決めている）。
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.surface, in: .rect(cornerRadius: 18))
        .contentShape(.rect(cornerRadius: 18))
    }

    private var icon: some View {
        Image(systemName: entry.isIncome ? "yensign" : entry.category.symbolName)
            .font(.system(size: iconSize * 0.5, weight: .semibold))
            .foregroundStyle(Theme.onCategory)
            .frame(width: iconSize, height: iconSize)
            .background(tint, in: .circle)
            // 丸はダークモードでもライトの色（濃い色）で塗る。ダークの色は暗い地の上の文字用に明るくしてあり、
            // 白い記号を載せるとコントラストが 2:1 前後まで落ちるため。
            .environment(\.colorScheme, .light)
            .accessibilityHidden(true)
    }

    /// メモが空なら（品目が書かれていなければ）カテゴリ名を見出しにする。
    @ViewBuilder
    private var title: some View {
        if entry.memo.isEmpty {
            kindLabel
        } else {
            Text(verbatim: entry.memo)
        }
    }

    /// 種別の名前（「収入」かカテゴリ名）。訳した文字を先に引いてから渡す（`kindText`）。`LocalizedStringResource` のまま
    /// Text に渡すと、行ごとに訳の表を引いて装飾つきの文字に組み立て直し、`today` が変わって描き直すたびにも組み立て直して
    /// 測り直すため（タイムラインは読み込んだ行をすべて描き直す。`HomeView` の `TimelineScrollView`）。
    private var kindLabel: some View {
        Text(verbatim: entry.kindText)
    }

    /// 記録した人の名前。名前が空（決める前に記録したものなど）なら「名前なし」と出す（空欄で並べると、だれのものかの印が
    /// 消えたように見えるため）。
    @ViewBuilder
    private func recorderLabel(_ name: String) -> some View {
        if name.isEmpty {
            Label("名前なし", systemImage: "person")
                .labelStyle(.titleAndIcon)
        } else {
            Label {
                Text(verbatim: name)
            } icon: {
                Image(systemName: "person")
            }
            .labelStyle(.titleAndIcon)
        }
    }

    private var amountText: String {
        entry.isIncome ? YenFormatter.signedString(from: entry.amount) : YenFormatter.string(from: entry.amount)
    }

    private var dateFormat: Date.FormatStyle {
        entry.showsYear(today: today, calendar: calendar) ? .dateTime.year().month().day() : .dateTime.month().day()
    }

    private var tint: Color {
        entry.isIncome ? Theme.income : Theme.color(for: entry.category)
    }
}

/// 吹き出しの行の並べ方。`HStack(alignment: .top, spacing:) { Spacer(minLength: leadingMinimum); 吹き出し; アイコン }` と同じ
/// 大きさと位置にする（吹き出しには、行の幅から左の余白の最小・間・アイコンを引いた幅を提案し、右に寄せ、上をそろえる）。
///
/// HStack のままにしないのは、タイムラインを開くときの手間を減らすため。タイムラインは読み込んだ行をすべて測る
/// （`HomeView` の `TimelineScrollView`）。HStack は、実際の幅を提案する前に、吹き出しに幅 0 と無限大も提案して伸び縮みの幅を
/// 調べ、そのたびに中の品目と金額の行（`EntryTitleAmountRow`）や日付の行が測り直される。ここでは吹き出しを実際の幅で 1 回だけ測る。
/// 位置の揃え（alignment guide）も中まで問い合わせない（行の中に独自の揃えは無い）。
private struct EntryBubbleRowLayout: Layout {
    /// 吹き出しの左に空ける最小の幅（Spacer の minLength）。
    let leadingMinimum: CGFloat
    /// 左の余白と吹き出し、吹き出しとアイコンの間。
    let spacing: CGFloat
    /// 画面の 1pt あたりの画素数。吹き出しに提案する幅を画素の境目にそろえる（下の `bubbleProposal`）。
    let displayScale: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        guard let bubble = subviews.first else { return .zero }
        let icon = iconSize(subviews)
        let bubbleSize = bubble.sizeThatFits(bubbleProposal(proposal, icon: icon))
        // Spacer は残りを埋めるので、行の幅は提案された幅（吹き出しが収まらないときは、左の余白が最小まで縮んだ幅）。
        let width = max(proposal.width ?? 0, fixedWidth(icon: icon) + bubbleSize.width)
        return CGSize(width: width, height: max(bubbleSize.height, icon?.height ?? 0))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        guard let bubble = subviews.first else { return }
        let icon = iconSize(subviews)
        // 置くときは、HStack と同じく行の高さを吹き出しに提案し直す（HStack は置くときに、子に自分の高さを提案する）。吹き出しの
        // 中の VStack はその高さを品目と金額の行と日付の行に分け直すので、金額は `minimumScaleFactor` で少し縮んで描かれる（標準の
        // 文字で 8 割 5 分ほど）。前の組み立て（HStack）で描かれていた形を変えないため、ここでも同じ提案をする。測るとき（高さの
        // 提案なし）と置くときで吹き出しの幅が変わるので、置くときの幅で右に寄せる。
        var bubbleProposal = bubbleProposal(proposal, icon: icon)
        bubbleProposal.height = bounds.height
        let bubbleSize = bubble.sizeThatFits(bubbleProposal)
        // HStack と同じく、左の余白（残りを埋める）・吹き出し・アイコンの順に、左から幅と間を足して位置を決める。
        let gaps = spacing * CGFloat(icon == nil ? 1 : 2)
        let leading = max(leadingMinimum, bounds.width - gaps - bubbleSize.width - (icon?.width ?? 0))
        let bubbleX = leading + spacing
        bubble.place(at: CGPoint(x: bounds.minX + bubbleX, y: bounds.minY), proposal: bubbleProposal)
        if let icon, subviews.count > 1 {
            subviews[1].place(
                at: CGPoint(x: bounds.minX + (bubbleX + bubbleSize.width + spacing), y: bounds.minY),
                proposal: ProposedViewSize(width: icon.width, height: bounds.height)
            )
        }
    }

    /// 行の中に独自の揃えは無いので、揃えを問われても中を測らずに既定の位置（nil）を返す。
    func explicitAlignment(
        of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void
    ) -> CGFloat? {
        nil
    }

    func explicitAlignment(
        of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void
    ) -> CGFloat? {
        nil
    }

    /// アイコン（2 つ目。大きさの決まった丸）の大きさ。アイコンが無ければ nil。
    private func iconSize(_ subviews: Subviews) -> CGSize? {
        subviews.count > 1 ? subviews[1].sizeThatFits(.unspecified) : nil
    }

    /// 吹き出しの左右にある、吹き出し以外の幅（左の余白の最小・間・アイコン）。
    private func fixedWidth(icon: CGSize?) -> CGFloat {
        leadingMinimum + spacing + (icon.map { spacing + $0.width } ?? 0)
    }

    /// 吹き出しに提案する幅。引き算の丸めの誤差で画素の境目をわずかに超えると、品目の幅が 1 画素広く測られて HStack と
    /// 食い違うので、画素の境目に切り下げる。
    private func bubbleProposal(_ proposal: ProposedViewSize, icon: CGSize?) -> ProposedViewSize {
        let scale = max(displayScale, 1)
        let width = proposal.width.map { width in
            max(0, ((width - fixedWidth(icon: icon)) * scale + 0.0001).rounded(.down) / scale)
        }
        return ProposedViewSize(width: width, height: proposal.height)
    }
}

/// 品目と金額の行。品目と金額が 1 行に収まるときだけ横に並べ、収まらなければ金額を品目の下の行に置く（右寄せのまま）。
///
/// 横に並べたまま品目を折り返させると、金額が品目の 1 行目の右端に並び、「焼肉（4人で割り勘・総額 ¥3,000 / ¥12,000・
/// 立替 ¥9,000）」のように品目の文と金額が続けて読めてしまうため。文字の大きさによらず（アクセシビリティサイズでも）、
/// 収まるかどうかで選ぶ。
///
/// どちらの並べ方でも品目・金額の順に置く（VoiceOver が 1 件をまとめて読む順を、並べ方で変えないため）。
struct EntryTitleAmountRow<Title: View, Amount: View>: View {
    /// 横に並べるときの品目と金額の間。
    static var horizontalSpacing: CGFloat { 8 }
    /// 縦に積むときの品目と金額の間。
    static var stackedSpacing: CGFloat { 2 }

    /// 品目に改行が入っているか。入っているときだけ、横に並べる候補で品目を 1 行に限る（下の `ViewThatFits`）。
    var titleHasLineBreaks = false
    @ViewBuilder let title: Title
    @ViewBuilder let amount: Amount

    var body: some View {
        Group {
            if titleHasLineBreaks {
                // ViewThatFits は、理想の幅（文字を折り返さない幅）が収まる最初の候補を選ぶ。横に並べる候補の理想の幅は品目と
                // 金額を 1 行に並べた幅なので、品目が折り返すほど長ければ縦に積む候補に落ちる。
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: Self.horizontalSpacing) {
                        // 横に並べる候補では品目を 1 行に限る。並べた後に品目だけが折り返して、金額が品目の 1 行目に並ぶ形に
                        // ならないようにするため（収まらなければ縦に積む候補が選ばれる）。
                        title
                            .lineLimit(1)
                        amount
                    }
                    VStack(alignment: .trailing, spacing: Self.stackedSpacing) {
                        title
                        amount
                    }
                }
            } else {
                // 改行の無い品目は、理想の幅で 1 行になる（1 行に限らなくても同じ形）ので、品目と金額を 1 組だけ作り、
                // 上の ViewThatFits と同じ選び方で並べる（`TitleAmountLayout`）。ViewThatFits は候補ごとに品目と金額の文字を
                // 作って測るので、タイムラインを開くときの手間が倍になる（行はすべて測る。`HomeView` の `TimelineScrollView`）。
                TitleAmountLayout(horizontalSpacing: Self.horizontalSpacing, stackedSpacing: Self.stackedSpacing) {
                    title
                    amount
                }
            }
        }
        // 品目が折り返すときも各行を吹き出しの右端に揃える（自分が送ったメッセージのように右寄せで出しているため）。
        .multilineTextAlignment(.trailing)
    }
}

/// 品目と金額（2 つの子）を、1 行に収まれば横に（1 行目の文字の下端をそろえ、間は `horizontalSpacing`）、収まらなければ
/// 縦に（右寄せ、間は `stackedSpacing`）並べる。
///
/// `ViewThatFits(in: .horizontal) { HStack(alignment: .firstTextBaseline) { 品目; 金額 }; VStack(alignment: .trailing) { 品目; 金額 } }`
/// と同じ選び方と形にする。横に並べる候補は、理想の幅の合計が提案された幅に収まるときだけ選ばれるので、そのとき HStack は
/// ほぼ必ず子を理想の大きさで並べる。ここでは HStack のように伸び縮みの幅を調べる提案（幅 0 と無限大。金額は縮めて収める計算も
/// 走る）をせずに、理想の大きさで並べる。縦に積むときは VStack（`VStackLayout`）にそのまま任せる。
///
/// 例外は、品目と金額の理想の幅がほぼ同じで、行の幅の半分をまたぐとき。HStack は残りの幅を子の数で割って伸び縮みの小さい子から
/// 渡すので、前の組み立てでは品目が理想の幅より狭く渡されて「…」で切れることがあった（撮影用のデモの記録と、品目の長さ・金額の
/// 桁を変えた記録を、すべての文字の大きさと iPhone の幅で描き比べた範囲では起きなかった）。ここではそのときも両方を 1 行に並べる。
private struct TitleAmountLayout: Layout {
    let horizontalSpacing: CGFloat
    let stackedSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        if let row = row(proposal: proposal, subviews: subviews) {
            return row.size
        }
        return FallbackLayout(stacked).sizeThatFits(proposal: proposal, subviews: subviews)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        if let row = row(proposal: proposal, subviews: subviews) {
            row.place(subviews, in: bounds)
        } else {
            FallbackLayout(stacked).placeSubviews(in: bounds, proposal: proposal, subviews: subviews)
        }
    }

    func explicitAlignment(
        of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void
    ) -> CGFloat? {
        // 横に並べるとき: HStack は子の独自の横の揃えを合わせるが、品目と金額の文字には無いので、既定の位置（nil）。
        guard row(proposal: proposal, subviews: subviews) == nil else { return nil }
        return FallbackLayout(stacked).explicitAlignment(of: guide, in: bounds, proposal: proposal, subviews: subviews)
    }

    func explicitAlignment(
        of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void
    ) -> CGFloat? {
        let layout = row(proposal: proposal, subviews: subviews) == nil ? stacked : horizontal
        return FallbackLayout(layout).explicitAlignment(of: guide, in: bounds, proposal: proposal, subviews: subviews)
    }

    private var horizontal: AnyLayout {
        AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: horizontalSpacing))
    }

    private var stacked: AnyLayout {
        AnyLayout(VStackLayout(alignment: .trailing, spacing: stackedSpacing))
    }

    /// 横に並べる形。1 行に収まらなければ nil（縦に積む）。
    private func row(proposal: ProposedViewSize, subviews: Subviews) -> IdealRowArrangement? {
        let row = IdealRowArrangement(subviews: subviews, alignment: .firstTextBaseline, spacing: horizontalSpacing, proposal: proposal)
        return row.fits(proposal) ? row : nil
    }
}

/// 種別・記録した人・日付を横に並べる行。すべてが理想の幅（折り返さない幅）で収まるときは 1 行に並べる。収まらないときは、
/// `stacksWhenNeeded` なら縦に積み（右寄せ）、そうでなければ HStack に任せる（文字を折り返して詰める）。
///
/// 文字が大きいときも一律に縦に積むと、「食費 9月28日」のように 1 行に収まるものまで行が増え、
/// 画面に出る記録が減るため、収まるかどうかで選ぶ。
///
/// 並べ方は、前の組み立て（`stacksWhenNeeded` なら `ViewThatFits { HStack; VStack }`、そうでなければ `HStack`）と同じにする。
/// HStack は、収まるときでも子に幅 0 と無限大を提案して伸び縮みの幅を調べてから、残りの幅を子の数で割って伸び縮みの小さい子から
/// 順に渡す。どの子も理想の幅が「行の幅 ÷ 子の数」以下なら、どの順で渡してもすべての子が理想の幅を受け取るので、ここでは
/// 調べる提案をせずに理想の大きさで並べる（`IdealRowArrangement`）。そうでないとき（家計の記録で名前が長いときや、文字が大きい
/// ときなど）は、HStack・VStack にそのまま任せる（割った幅より広い子が先に渡されると、収まるのに折り返されることがあり、その形も
/// 変えないため）。`stacksWhenNeeded` のときに `ViewThatFits` を使わないのは、候補ごとに文字を作って測るため。
private struct AdaptiveRowLayout: Layout {
    let stacksWhenNeeded: Bool
    /// 横に並べるときの間。
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        switch arrangement(proposal: proposal, subviews: subviews) {
        case .ideal(let row): row.size
        case .stack(let layout): FallbackLayout(layout).sizeThatFits(proposal: proposal, subviews: subviews)
        }
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        switch arrangement(proposal: proposal, subviews: subviews) {
        case .ideal(let row): row.place(subviews, in: bounds)
        case .stack(let layout): FallbackLayout(layout).placeSubviews(in: bounds, proposal: proposal, subviews: subviews)
        }
    }

    func explicitAlignment(
        of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void
    ) -> CGFloat? {
        switch arrangement(proposal: proposal, subviews: subviews) {
        // 1 行に並べるとき: HStack は子の独自の横の揃えを合わせるが、文字とラベルには無いので、既定の位置（nil）。
        case .ideal: nil
        case .stack(let layout):
            FallbackLayout(layout).explicitAlignment(of: guide, in: bounds, proposal: proposal, subviews: subviews)
        }
    }

    func explicitAlignment(
        of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void
    ) -> CGFloat? {
        let layout = switch arrangement(proposal: proposal, subviews: subviews) {
        case .ideal: horizontal
        case .stack(let layout): layout
        }
        return FallbackLayout(layout).explicitAlignment(of: guide, in: bounds, proposal: proposal, subviews: subviews)
    }

    private enum Arrangement {
        case ideal(IdealRowArrangement)
        case stack(AnyLayout)
    }

    private var horizontal: AnyLayout {
        AnyLayout(HStackLayout(spacing: spacing))
    }

    private func arrangement(proposal: ProposedViewSize, subviews: Subviews) -> Arrangement {
        let row = IdealRowArrangement(subviews: subviews, alignment: .center, spacing: spacing, proposal: proposal)
        if row.fitsEqualShares(proposal, spacing: spacing) {
            return .ideal(row)
        }
        // 前の組み立てと同じ選び方: 縦に積めるときは、理想の幅で 1 行に収まれば HStack、収まらなければ VStack。
        if stacksWhenNeeded && !row.fits(proposal) {
            return .stack(AnyLayout(VStackLayout(alignment: .trailing, spacing: 2)))
        }
        return .stack(horizontal)
    }
}

/// 子を理想の大きさ（幅の提案なし）で左から並べ、`alignment` の位置をそろえた形。HStack が、すべての子に理想の幅を与えて
/// 並べるときと同じ大きさと位置。
private struct IdealRowArrangement {
    let size: CGSize
    let origins: [CGPoint]
    /// 子の理想の幅（左から）。
    let widths: [CGFloat]
    /// 子に提案する大きさ（幅は提案せず、高さは親の提案のまま）。
    let childProposal: ProposedViewSize

    init(subviews: LayoutSubviews, alignment: VerticalAlignment, spacing: CGFloat, proposal: ProposedViewSize) {
        let childProposal = ProposedViewSize(width: nil, height: proposal.height)
        let dimensions = subviews.map { $0.dimensions(in: childProposal) }
        let guides = dimensions.map { $0[alignment] }
        let above = guides.max() ?? 0
        let below = zip(dimensions, guides).map { $0.height - $1 }.max() ?? 0
        var x: CGFloat = 0
        var origins: [CGPoint] = []
        for (dimension, guide) in zip(dimensions, guides) {
            origins.append(CGPoint(x: x, y: above - guide))
            x += dimension.width + spacing
        }
        let width = dimensions.reduce(0) { $0 + $1.width } + spacing * CGFloat(max(subviews.count - 1, 0))
        size = CGSize(width: width, height: above + below)
        self.origins = origins
        widths = dimensions.map(\.width)
        self.childProposal = childProposal
    }

    /// 提案された幅に収まるか（幅の提案が無ければ収まる）。
    func fits(_ proposal: ProposedViewSize) -> Bool {
        proposal.width.map { size.width <= $0 } ?? true
    }

    /// どの子の理想の幅も、提案された幅から間を引いて子の数で割った幅以下か（幅の提案が無ければ真）。このとき HStack は、
    /// どの順で子に幅を渡しても、すべての子に理想の幅を渡す。
    func fitsEqualShares(_ proposal: ProposedViewSize, spacing: CGFloat) -> Bool {
        guard let proposed = proposal.width else { return true }
        guard !widths.isEmpty else { return true }
        let share = (proposed - spacing * CGFloat(widths.count - 1)) / CGFloat(widths.count)
        return widths.allSatisfy { $0 <= share }
    }

    func place(_ subviews: LayoutSubviews, in bounds: CGRect) {
        for (subview, origin) in zip(subviews, origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: childProposal)
        }
    }
}

/// 標準の並べ方（HStack・VStack）に、測る・置く・揃えを任せる（`HStackLayout` などは、それらの関数を公開していないので
/// `AnyLayout` を通して呼ぶ）。理想の大きさで並べられないときと、揃えを問われたときだけ使うので、キャッシュはそのたびに作る。
private struct FallbackLayout {
    let layout: AnyLayout

    init(_ layout: AnyLayout) {
        self.layout = layout
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews) -> CGSize {
        var cache = layout.makeCache(subviews: subviews)
        return layout.sizeThatFits(proposal: proposal, subviews: subviews, cache: &cache)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews) {
        var cache = layout.makeCache(subviews: subviews)
        layout.placeSubviews(in: bounds, proposal: proposal, subviews: subviews, cache: &cache)
    }

    func explicitAlignment(
        of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews
    ) -> CGFloat? {
        var cache = layout.makeCache(subviews: subviews)
        return layout.explicitAlignment(of: guide, in: bounds, proposal: proposal, subviews: subviews, cache: &cache)
    }

    func explicitAlignment(
        of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews
    ) -> CGFloat? {
        var cache = layout.makeCache(subviews: subviews)
        return layout.explicitAlignment(of: guide, in: bounds, proposal: proposal, subviews: subviews, cache: &cache)
    }
}

/// タイムラインの吹き出し・削除の確認・直す対象の選択に出す記録の形（自分の記録と家計の記録）。
protocol LedgerEntryDisplaying: LedgerRecord {
    /// 品目（メモ）。
    var memo: String { get }
}

extension Entry: LedgerEntryDisplaying {}

extension LedgerEntryDisplaying {
    /// 日付に年を添えるか。今年でない記録を年なしで出すと今年の記録に見え、今月の合計に
    /// 入っていない理由が利用者に分からないため。
    func showsYear(today: Date, calendar: Calendar) -> Bool {
        !calendar.isDate(spentAt, equalTo: today, toGranularity: .year)
    }

    /// 種別の名前（「収入」かカテゴリ名）。
    var kindText: String {
        isIncome ? String(localized: "収入") : String(localized: category.label)
    }

    /// 削除の確認や直す対象の選択に出す「ランチ ¥850」。品目が無ければ種別の名前にする（吹き出しの見出しと同じ）。
    var summaryText: String {
        "\(memo.isEmpty ? kindText : memo) \(YenFormatter.string(from: amount))"
    }
}
