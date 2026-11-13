import SaifuLogCore
import SwiftUI

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

    /// 種別の名前（「収入」かカテゴリ名。作ったカテゴリは一覧から名前を引く）。
    func kindText(in catalog: CategoryCatalog) -> String {
        isIncome ? String(localized: "収入") : catalog.localizedName(for: category)
    }

    /// 削除の確認や入力欄の VoiceOver の「直す: …」に出す「ランチ ¥850」。品目が無ければ種別の名前にする（返事の行の見出しと
    /// 同じ）。作ったカテゴリは一覧から名前を引く。
    func summaryText(in catalog: CategoryCatalog) -> String {
        "\(memo.isEmpty ? kindText(in: catalog) : memo) \(YenFormatter.string(from: amount))"
    }
}
