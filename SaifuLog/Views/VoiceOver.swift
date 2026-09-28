import SwiftUI

/// VoiceOver への読み上げ。画面のモデル（`HomeModel`）と保存先の状態（`StoreHost`）で同じ出し方にする。
enum VoiceOver {
    @MainActor
    static func announce(_ text: String) {
        var message = AttributedString(text)
        // 操作の後は入力欄などにフォーカスが移り、その読み上げに割り込まれて結果が聞こえないことがあるので、優先して読ませる。
        message.accessibilitySpeechAnnouncementPriority = .high
        AccessibilityNotification.Announcement(message).post()
    }
}
