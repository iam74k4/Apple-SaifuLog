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

    /// 画面がまるごと替わったことを知らせる。VoiceOver は新しい画面の最初の要素にフォーカスを移して読む。
    ///
    /// 横に進む・シートを出すときは SwiftUI が知らせるが、根元の画面の切り替え（初回の案内からホームへ）は知らせない
    /// ため、そのときに呼ぶ。VoiceOver が動いていなければ何も起きない。
    @MainActor
    static func screenChanged() {
        AccessibilityNotification.ScreenChanged().post()
    }
}
