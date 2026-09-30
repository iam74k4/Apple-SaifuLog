import Foundation
import SaifuLogCore
import Testing
@testable import SaifuLog

private final class ConfigurationBundleToken {}

/// StoreKit の設定ファイル（Config/SaifuLog.storekit）が、App Store Connect に登録した課金アイテムと合っていること。
///
/// Xcode の Run と購入のテストはこのファイルを App Store の代わりに使う。製品 ID・種類・ファミリー共有・価格が食い違うと、
/// 手元では動くのに App Store では買えない（または逆）ことに気づけないため。
struct StoreKitConfigurationTests {
    static func configuration() throws -> [String: Any] {
        let url = try #require(Bundle(for: ConfigurationBundleToken.self).url(forResource: "SaifuLog", withExtension: "storekit"))
        return try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    static func product(_ id: PremiumProduct) throws -> [String: Any] {
        let products = try #require(try configuration()["products"] as? [[String: Any]])
        return try #require(products.first { $0["productID"] as? String == id.rawValue })
    }

    static func displayName(_ product: [String: Any], locale: String) -> String? {
        (product["localizations"] as? [[String: Any]])?.first { $0["locale"] as? String == locale }?["displayName"] as? String
    }

    @Test func productsMatchAppStoreConnect() throws {
        let configuration = try Self.configuration()
        let products = try #require(configuration["products"] as? [[String: Any]])
        #expect(Set(products.compactMap { $0["productID"] as? String }) == Set(PremiumProduct.allCases.map(\.rawValue)))
        #expect((configuration["subscriptionGroups"] as? [Any])?.isEmpty == true)

        let premium = try Self.product(.premium)
        #expect(premium["type"] as? String == "NonConsumable")
        #expect(premium["familyShareable"] as? Bool == true)
        #expect(premium["displayPrice"] as? String == "1800")
        #expect(Self.displayName(premium, locale: "ja") == "サイフログ プレミアム")
        #expect(Self.displayName(premium, locale: "en_US") == "SaifuLog Premium")

        let trial = try Self.product(.trial14)
        #expect(trial["type"] as? String == "NonConsumable")
        #expect(trial["familyShareable"] as? Bool == false)
        #expect(trial["displayPrice"] as? String == "0")
        #expect(Self.displayName(trial, locale: "ja") == "14日間の無料体験")
        // 審査ガイドライン 3.1.1 は、価格 0 の非消耗型の体験に「XX-day Trial」の形の名前を求める。英語の表示名がこの形から
        // 外れると差し戻されるおそれがあり、App Store Connect の側と食い違っても手元の購入では気づけないため、値で決める。
        #expect(Self.displayName(trial, locale: "en_US") == "14-day Trial")

        let settings = try #require(configuration["settings"] as? [String: Any])
        #expect(settings["_storefront"] as? String == "JPN")
    }

    /// 設定ファイルはテストのバンドルにだけ入れ、アプリには入れない（提出物は本物の App Store とつながる）。
    @Test func configurationIsNotInApp() {
        #expect(Bundle.main.url(forResource: "SaifuLog", withExtension: "storekit") == nil)
    }
}
