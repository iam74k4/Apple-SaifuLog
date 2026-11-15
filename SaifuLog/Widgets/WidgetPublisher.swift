import Foundation
import os
import SaifuLogCore
import SwiftUI
import WidgetKit

/// ホームの帯の数字を、ウィジェットに渡す（共有の領域のファイルに書き、ウィジェットに描き直させる）。アプリで 1 つ（`SaifuLogApp`）。
///
/// 帯（`MonthSummaryHeader`）が数字の変わるたびに呼ぶ（記録を足した・直した・消した、予算を変えた、ほかの端末の変更が届いた、
/// 月が替わった、アプリのロックを切り替えた）。帯と同じ数字を渡すので、画面とウィジェットの数字が食い違わない。前に書いたものと
/// 同じなら書かない（ウィジェットの描き直しには回数の上限があるため）。
///
/// 撮影用のデモと UI テストでは作らない（架空の記録の数字で、端末の本物のウィジェットを書き換えないため）。
@MainActor
final class WidgetPublisher {
    private static let logger = Logger(subsystem: "com.iam74k4.SaifuLog", category: "widget")

    private let url: URL?
    private let reload: @MainActor () -> Void
    /// 前に書いたもの。同じなら書かない。
    private var lastWritten: WidgetSnapshot?

    init(url: URL? = WidgetSnapshotFile.defaultURL, reload: @escaping @MainActor () -> Void = { WidgetCenter.shared.reloadAllTimelines() }) {
        self.url = url
        self.reload = reload
    }

    func publish(_ snapshot: WidgetSnapshot) {
        guard snapshot != lastWritten else { return }
        guard let url else {
            // App Group を使えないビルド（署名なしなど）。ウィジェットも読めないので、何もしない。
            return
        }
        do {
            try WidgetSnapshotFile.write(snapshot, to: url)
            lastWritten = snapshot
            reload()
        } catch {
            // 書けなくても記録は止めない（ウィジェットが前の数字のままになるだけ。次に数字が変わったときにまた書く）。
            Self.logger.error("ウィジェットの数字を書けませんでした: \(String(describing: error), privacy: .public)")
        }
    }
}

extension EnvironmentValues {
    /// ウィジェットに数字を渡すもの。撮影用のデモと UI テストでは nil（渡さない）。
    @Entry var widgetPublisher: WidgetPublisher? = nil
}
