import AppIntents
import Foundation
import Testing
@testable import SaifuLog

/// ショートカットの操作（App Intents）の題名と説明。
///
/// App Store Connect は、題名や説明に「Apple」の語があるとアップロードを弾く（ITMS-90626「Invalid Siri Support」。
/// 「Apple Pay」も同じ。2026-10-02 に社内テスト用のビルド 2 が、支払いを記録する操作の説明で弾かれた）。弾かれるのは
/// アップロードの後の処理で分かるので、ここで日本語と英語の両方を確かめる。
@MainActor
struct AppIntentMetadataTests {
    /// すべての操作の題名と説明。操作を足したら、ここにも足す。
    static func texts() -> [LocalizedStringResource] {
        [
            RecordEntryIntent.title, RecordEntryIntent.description.descriptionText,
            AskQuestionIntent.title, AskQuestionIntent.description.descriptionText,
            ComposeEntryIntent.title, ComposeEntryIntent.description.descriptionText,
            ScanReceiptIntent.title, ScanReceiptIntent.description.descriptionText,
            VoiceEntryIntent.title, VoiceEntryIntent.description.descriptionText,
            RecordPaymentIntent.title, RecordPaymentIntent.description.descriptionText,
        ]
    }

    static func localized(_ resource: LocalizedStringResource, _ language: String) -> String {
        var resource = resource
        resource.locale = Locale(identifier: language)
        return String(localized: resource)
    }

    @Test(arguments: ["ja", "en"])
    func titlesAndDescriptionsDoNotMentionApple(language: String) {
        for text in Self.texts().map({ Self.localized($0, language) }) {
            #expect(!text.localizedCaseInsensitiveContains("apple"), "\(language): \(text)")
        }
    }

    /// 英語の訳を引けていること（引けずに日本語のままだと、上のテストが英語を確かめないまま通るため）。
    @Test func englishDescriptionIsTranslated() {
        let english = Self.localized(RecordPaymentIntent.description.descriptionText, "en")
        #expect(english.contains("Wallet"))
    }
}
