import SaifuLogCore
import SwiftUI

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

/// 種別・記録した人・日付を横に並べる行（家計の記録の吹き出しと、アプリの返事のカードの行の種別と日付）。すべてが理想の幅
/// （折り返さない幅）で収まるときは 1 行に並べる。収まらないときは、`stacksWhenNeeded` なら縦に積み（`stackAlignment` に寄せる）、
/// そうでなければ HStack に任せる（文字を折り返して詰める）。
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
struct AdaptiveRowLayout: Layout {
    let stacksWhenNeeded: Bool
    /// 横に並べるときの間。
    let spacing: CGFloat
    /// 縦に積むときの揃え。吹き出し（右寄せ）は右、アプリの返事のカード（左寄せ）は左。
    var stackAlignment: HorizontalAlignment = .trailing

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
            return .stack(AnyLayout(VStackLayout(alignment: stackAlignment, spacing: 2)))
        }
        return .stack(horizontal)
    }
}

/// 子を理想の大きさ（幅の提案なし）で左から並べ、`alignment` の位置をそろえた形。HStack が、すべての子に理想の幅を与えて
/// 並べるときと同じ大きさと位置。
struct IdealRowArrangement {
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
struct FallbackLayout {
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

/// 家計の記録の吹き出し・返事の行・削除の確認・入力欄の VoiceOver の「直す」に出す記録の形（自分の記録と家計の記録）。
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

    /// 種別の名前（「収入」かカテゴリ名。組み込みのカテゴリだけの記録（家計の記録）に使う）。
    var kindText: String {
        kindText(in: .builtIn)
    }

    /// 種別の名前（「収入」かカテゴリ名。作ったカテゴリは一覧から名前を引く）。
    func kindText(in catalog: CategoryCatalog) -> String {
        isIncome ? String(localized: "収入") : catalog.localizedName(for: category)
    }

    /// 削除の確認や入力欄の VoiceOver の「直す: …」に出す「ランチ ¥850」。品目が無ければ種別の名前にする（返事の行と吹き出しの
    /// 見出しと同じ）。組み込みのカテゴリだけの記録（家計の記録）に使う。
    var summaryText: String {
        summaryText(in: .builtIn)
    }

    /// 「ランチ ¥850」（作ったカテゴリは一覧から名前を引く）。
    func summaryText(in catalog: CategoryCatalog) -> String {
        "\(memo.isEmpty ? kindText(in: catalog) : memo) \(YenFormatter.string(from: amount))"
    }
}
