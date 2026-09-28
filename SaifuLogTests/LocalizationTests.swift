import Foundation
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
}
