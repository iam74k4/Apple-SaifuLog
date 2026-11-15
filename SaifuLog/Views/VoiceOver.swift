import SwiftUI
import UIKit

/// VoiceOver への読み上げ。画面のモデル（`HomeModel`）と保存先の状態（`StoreHost`）で同じ出し方にする。
enum VoiceOver {
    @MainActor
    static func announce(_ text: String) {
        var message = AttributedString(text)
        // 操作の後は入力欄などにフォーカスが移り、その読み上げに割り込まれて結果が聞こえないことがあるので、優先して読ませる。
        message.accessibilitySpeechAnnouncementPriority = .high
        AccessibilityNotification.Announcement(message).post()
    }

    /// 読み上げて、読み終えるまで待つ。VoiceOver が動いていなければ読み上げずにすぐ戻る。
    ///
    /// 声の入力を始める前に使う。読み上げの途中でマイクを開くと、読み上げの声を書き起こして入力欄に入れてしまうため。
    /// 読み終えた知らせ（`announcementDidFinishNotification`）が来なくても、`timeout` で待つのをやめる（知らせが来ずに
    /// 聞き始められなくなるのを避けるため）。
    @MainActor
    static func announceAndWait(_ text: String, timeout: Duration = .seconds(3)) async {
        guard UIAccessibility.isVoiceOverRunning else { return }
        let (finished, continuation) = AsyncStream.makeStream(of: Void.self)
        let observer = NotificationCenter.default.addObserver(
            forName: UIAccessibility.announcementDidFinishNotification, object: nil, queue: .main
        ) { notification in
            // 前に読み上げていた別の文の終わりの知らせでは進まない（その文を読み終えた直後にマイクを開くと、この文を拾うため）。
            guard notification.userInfo?[UIAccessibility.announcementStringValueUserInfoKey] as? String == text else { return }
            continuation.yield()
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        let timer = Task {
            try? await Task.sleep(for: timeout)
            continuation.finish()
        }
        defer { timer.cancel() }
        announce(text)
        for await _ in finished { break }
    }

    /// 画面がまるごと替わったことを知らせる。VoiceOver は新しい画面の最初の要素にフォーカスを移して読む。
    ///
    /// 横に進む・シートを出すときは SwiftUI が知らせるが、根元の画面の切り替え（初回の案内からホームへ）は知らせない
    /// ため、そのときに呼ぶ。VoiceOver が動いていなければ何も起きない。
    @MainActor
    static func screenChanged() {
        AccessibilityNotification.ScreenChanged().post()
    }
}
