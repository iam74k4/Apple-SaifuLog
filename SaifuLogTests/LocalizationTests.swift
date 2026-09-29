import Foundation
import SaifuLogCore
import Testing
@testable import SaifuLog

/// 画面の文字列の訳（String Catalog からアプリの中に作られる、言語ごとの表）。
///
/// `Text(verbatim:)` で書いた文字は String Catalog に載らず、訳し漏れても画面を見るまで気づけない。
/// 訳すべき記号を訳し忘れたまま戻さないよう、訳の値を確かめる。
struct LocalizationTests {
    /// アプリの中の、その言語の表（`<言語>.lproj`）。テストはアプリの中で動くので `Bundle.main` がアプリ。
    static func bundle(for language: String) throws -> Bundle {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    /// 日本語の中黒（全角）のまま英語の画面に出すと、半角の文の間で幅が広く浮いて見える。
    @Test("ホームの帯の区切りの点は、英語では中点にする")
    func summarySeparatorIsLocalized() throws {
        let english = try Self.bundle(for: "en")

        #expect(english.localizedString(forKey: "・", value: nil, table: nil) == "·")
    }

    /// CSV の見出しと値（種類・カテゴリ）は、コア（`LedgerCSVWriter`）が言語ごとに持つ。アプリの画面の言葉（String Catalog）と
    /// 食い違うと、画面では「Daily goods」なのに CSV では別の名前になるので、日本語は表のキー、英語は en の訳と照合する。
    @Test("CSV の見出し・種類・カテゴリは、画面の言葉と同じ")
    func csvLabelsMatchCatalog() throws {
        let english = try Self.bundle(for: "en")
        func en(_ key: String) -> String {
            english.localizedString(forKey: key, value: nil, table: nil)
        }

        for category in EntryCategory.allCases {
            let key = category.label.key
            #expect(LedgerCSVWriter.categoryName(category, language: .japanese) == key)
            #expect(LedgerCSVWriter.categoryName(category, language: .english) == en(key))
        }
        for isIncome in [false, true] {
            let key = LedgerCSVWriter.kindName(isIncome: isIncome, language: .japanese)
            #expect(LedgerCSVWriter.kindName(isIncome: isIncome, language: .english) == en(key))
        }
        // 時刻（1 列目の次）は画面に出す言葉ではないので、表に無い。ほかの見出しは画面の見出しと同じ訳にする。
        let japaneseHeader = LedgerCSVWriter.header(language: .japanese)
        let englishHeader = LedgerCSVWriter.header(language: .english)
        for (key, value) in zip(japaneseHeader, englishHeader) where key != "時刻" {
            #expect(value == en(key))
        }
    }

    /// 許可を求める API は、Info.plist に利用目的が無いとアプリを落とす。マイク（声の入力）とカメラ（レシート）の利用目的が、
    /// 開発言語の既定値（project.yml）と英語の訳（InfoPlist.xcstrings）の両方に入っていることを確かめる。
    @Test("マイクとカメラの利用目的が Info.plist にあり、英語にも訳してある", arguments: [
        "NSMicrophoneUsageDescription", "NSCameraUsageDescription",
    ])
    func usageDescriptions(key: String) throws {
        let value = try #require(Bundle.main.object(forInfoDictionaryKey: key) as? String)
        #expect(!value.isEmpty)
        let english = try Self.bundle(for: "en").localizedString(forKey: key, value: nil, table: "InfoPlist")
        #expect(english != key)
        #expect(english.contains("never saved or sent"))
    }
}
