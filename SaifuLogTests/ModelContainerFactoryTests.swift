import Foundation
import SwiftData
import Testing
@testable import SaifuLog

/// 保存先の作り方。場所と iCloud の扱いを、SwiftData の既定に任せずに決めていること。
@MainActor
struct ModelContainerFactoryTests {
    /// 以前のアプリ（場所を指定せず、SwiftData の既定の場所で開いていた）と同じファイルを開く。
    /// 場所が変わると、それまでの記録が読めなくなる（空の保存先が新しく作られる）。
    @Test func storeURLMatchesPreviousDefaultLocation() {
        let previous = ModelConfiguration(schema: ModelContainerFactory.schema, cloudKitDatabase: .none)

        #expect(ModelContainerFactory.storeURL == previous.url)
        #expect(ModelContainerFactory.storeURL.lastPathComponent == "default.store")
        #expect(
            ModelContainerFactory.storeURL.deletingLastPathComponent().standardizedFileURL
                == URL.applicationSupportDirectory.standardizedFileURL
        )
    }

    /// 端末に保存する設定は、場所も iCloud も明示している（App Group の共有の場所に移らない、勝手に同期しない）。
    @Test func fileConfigurationIsExplicit() {
        let configuration = ModelContainerFactory.configuration(url: ModelContainerFactory.storeURL, cloudKitDatabase: .none)

        #expect(configuration.url == ModelContainerFactory.storeURL)
        #expect(!configuration.isStoredInMemoryOnly)
        #expect(Self.isNone(configuration.cloudKitDatabase))
        #expect(configuration.cloudKitContainerIdentifier == nil)
        #expect(configuration.groupAppContainerIdentifier == nil)
    }

    /// テストとプレビューの保存先も iCloud を切る（既定の `.automatic` にしない）。
    @Test func inMemoryContainerTurnsOffICloud() throws {
        let container = try ModelContainerFactory.makeInMemoryContainer()

        #expect(!container.configurations.isEmpty)
        for configuration in container.configurations {
            #expect(configuration.isStoredInMemoryOnly)
            #expect(Self.isNone(configuration.cloudKitDatabase))
        }
    }

    @Test func schemaListsModelTypes() throws {
        let container = try ModelContainerFactory.makeInMemoryContainer()

        #expect(container.schema.entities.map(\.name) == ["Entry"])
    }

    /// ファイルの保存先に書いた記録は、開き直しても残る。
    /// アプリの本物の保存先には触れないよう、一時フォルダの中に開く。
    @Test func fileContainerKeepsRecordsAcrossReopen() throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        // フォルダはまだ無い（初回起動と同じ）。makeContainer が作る。
        let url = folder.appending(path: "default.store", directoryHint: .notDirectory)

        do {
            let container = try ModelContainerFactory.makeContainer(url: url, cloudKitDatabase: .none)
            container.mainContext.insert(TestSupport.entry())
            try container.mainContext.save()
        }
        let reopened = try ModelContainerFactory.makeContainer(url: url, cloudKitDatabase: .none)

        #expect(try reopened.mainContext.fetchCount(FetchDescriptor<Entry>()) == 1)
    }

    /// 下の比べ方が `.none` と `.automatic` を見分けられること（いつも一致してしまう比べ方になっていないか）。
    @Test func cloudKitDatabaseComparisonDistinguishesValues() {
        #expect(Self.isNone(.none))
        #expect(!Self.isNone(.automatic))
        #expect(!Self.isNone(.private("iCloud.example")))
    }

    /// `ModelConfiguration.CloudKitDatabase` は比べられない型なので、中身を書き出した文字列どうしで比べる。
    static func isNone(_ database: ModelConfiguration.CloudKitDatabase) -> Bool {
        String(reflecting: database) == String(reflecting: ModelConfiguration.CloudKitDatabase.none)
    }
}
