import CoreData
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

        #expect(Set(container.schema.entities.map(\.name)) == ["Entry", "Budget"])
    }

    /// 予算のモデルを足す前の保存先（記録のモデルだけ）を開いても、記録はそのまま読め、予算を書き込める。
    /// SwiftData の自動の移行（テーブルを足すだけの軽い移行）が効くことを確かめる。効かないと、アップデートした
    /// 利用者の保存先が開けなくなる（再試行の画面から先へ進めない）。
    @Test func opensStoreCreatedBeforeBudgetWasAdded() throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "default.store", directoryHint: .notDirectory)

        do {
            let previousSchema = Schema([Entry.self])
            let previous = try ModelContainer(
                for: previousSchema,
                configurations: [ModelConfiguration(schema: previousSchema, url: url, cloudKitDatabase: .none)]
            )
            #expect(previous.schema.entities.map(\.name) == ["Entry"])
            previous.mainContext.insert(TestSupport.entry(amount: 850))
            try previous.mainContext.save()
        }

        let upgraded = try ModelContainerFactory.makeContainer(url: url, cloudKitDatabase: .none)
        let context = upgraded.mainContext

        #expect(try context.fetch(FetchDescriptor<Entry>()).map(\.amount) == [850])
        try BudgetStore(context: context).setAmount(150_000, for: .total)
        #expect(try BudgetStore(context: context).plan().total == 150_000)
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

    // MARK: - iCloud 同期

    /// iCloud 同期のオンとオフで同じファイルを開く（オンにした時点の記録が iCloud に上がり、オフに戻しても端末の記録が
    /// 残る）。オンのときは利用者の私用データベース（アプリのコンテナ）だけと同期し、`.automatic` にはしない。
    @Test func iCloudConfigurationUsesSameFileAndPrivateDatabase() {
        let local = ModelContainerFactory.configuration(url: ModelContainerFactory.storeURL, cloudKitDatabase: .none)
        let synced = ModelContainerFactory.configuration(url: ModelContainerFactory.storeURL, cloudKitDatabase: .private)

        #expect(synced.url == local.url)
        #expect(synced.url == ModelContainerFactory.storeURL)
        #expect(!synced.isStoredInMemoryOnly)
        #expect(synced.groupAppContainerIdentifier == nil)
        #expect(synced.cloudKitContainerIdentifier == ModelContainerFactory.iCloudContainerIdentifier)
        #expect(
            String(reflecting: synced.cloudKitDatabase)
                == String(reflecting: ModelConfiguration.CloudKitDatabase.private(ModelContainerFactory.iCloudContainerIdentifier))
        )
        #expect(!Self.isNone(synced.cloudKitDatabase))
        #expect(String(reflecting: synced.cloudKitDatabase) != String(reflecting: ModelConfiguration.CloudKitDatabase.automatic))
    }

    /// CloudKit のコンテナは、エンタイトルメント（Config/Base.xcconfig の `ICLOUD_CONTAINER_ID = iCloud.$(APP_BUNDLE_ID)`）と
    /// 同じ決まりで Bundle ID から組み立てる。
    @Test func iCloudContainerIdentifierFollowsBundleIdentifier() {
        #expect(ModelContainerFactory.iCloudContainerIdentifier(bundleIdentifier: "com.iam74k4.SaifuLog") == "iCloud.com.iam74k4.SaifuLog")
        #expect(ModelContainerFactory.iCloudContainerIdentifier(bundleIdentifier: "com.example.SaifuLog") == "iCloud.com.example.SaifuLog")
        #expect(ModelContainerFactory.iCloudContainerIdentifier(bundleIdentifier: nil) == "iCloud.com.iam74k4.SaifuLog")
    }

    /// 設定の「iCloud で同期」の値と、保存先の開き方の対応（既定のオフは端末の中だけ）。
    @Test func cloudKitDatabaseFollowsSetting() {
        #expect(ModelContainerFactory.CloudKitDatabase(syncEnabled: AppSettings.iCloudSyncEnabled.defaultValue) == .none)
        #expect(ModelContainerFactory.CloudKitDatabase(syncEnabled: true) == .private)
        #expect(!ModelContainerFactory.CloudKitDatabase.none.isSyncEnabled)
        #expect(ModelContainerFactory.CloudKitDatabase.private.isSyncEnabled)
        #expect(ModelContainerFactory.CloudKitDatabase.none.diagnosticName == "none")
        #expect(ModelContainerFactory.CloudKitDatabase.private.diagnosticName == "private")
        #expect(Self.isNone(ModelContainerFactory.CloudKitDatabase.none.configurationValue))
    }

    /// 保存するモデルが CloudKit の制約を満たす（SwiftData の CloudKit 同期は、満たさないモデルの保存先を開けない）。
    ///
    /// CloudKit には実際にはつながず（`initializeCloudKitSchema` も使わない）、Core Data の CloudKit の連携が確かめるのと
    /// 同じ形（SwiftData のモデルから作った NSManagedObjectModel）で、モデルの定義を検査する。
    @Test func modelsSatisfyCloudKitConstraints() throws {
        let model = try #require(NSManagedObjectModel.makeManagedObjectModel(for: ModelContainerFactory.modelTypes))

        #expect(Set(model.entities.compactMap(\.name)) == ["Entry", "Budget"])
        #expect(Self.cloudKitViolations(in: model).isEmpty, "\(Self.cloudKitViolations(in: model))")
        // SwiftData の Schema の側でも、一意の属性が無い。
        for entity in ModelContainerFactory.schema.entities {
            for attribute in entity.attributes {
                #expect(!attribute.isUnique, "\(entity.name).\(attribute.name) が一意の属性になっています")
            }
        }
    }

    /// 上の検査が、制約を破ったモデルを見逃さないこと（いつも空を返す検査になっていないか）。
    @Test func cloudKitCheckFindsViolations() throws {
        let model = try #require(NSManagedObjectModel.makeManagedObjectModel(for: [CloudKitIncompatibleSample.self]))

        let violations = Self.cloudKitViolations(in: model)

        #expect(violations.contains { $0.contains("uniqueness") })
        #expect(violations.contains { $0.contains("CloudKitIncompatibleSample.code") && $0.contains("default") })
    }

    /// iCloud 同期を出した後は、今の項目の名前と型を変えたり消したりしない（Production に出した CloudKit のスキーマは
    /// 足すことしかできず、端末の保存先も移行が要る）。足すのはよい（CloudKit の制約は上のテストで確かめる）。
    @Test func existingAttributesAreKept() throws {
        let model = try #require(NSManagedObjectModel.makeManagedObjectModel(for: ModelContainerFactory.modelTypes))
        let expected: [String: [String: NSAttributeType]] = [
            "Entry": [
                "amount": .integer64AttributeType, "isIncome": .booleanAttributeType, "categoryRawValue": .stringAttributeType,
                "memo": .stringAttributeType, "spentAt": .dateAttributeType, "createdAt": .dateAttributeType,
                "sourceRawValue": .stringAttributeType, "originalText": .stringAttributeType,
            ],
            "Budget": [
                "scopeRawValue": .stringAttributeType, "amount": .integer64AttributeType, "updatedAt": .dateAttributeType,
            ],
        ]

        for (entityName, attributes) in expected {
            let entity = try #require(model.entitiesByName[entityName])
            for (name, type) in attributes {
                let attribute = try #require(entity.attributesByName[name], "\(entityName).\(name) がありません")
                #expect(attribute.attributeType == type, "\(entityName).\(name) の型が変わっています")
            }
        }
    }

    /// 端末の中だけの保存先でも、変更の履歴（Core Data の persistent history）を残している。
    ///
    /// iCloud 同期（NSPersistentCloudKitContainer の仕組み）は履歴を使うので、オンにした保存先は履歴つきで開かれる。
    /// Core Data は、履歴つきで開いたことのある保存先を履歴なしで開くと、書き込めない（読むだけの）状態にする。
    /// オフのときも履歴を残していれば、オンからオフに戻しても同じファイルに書き込め、オンにするときに移行も要らない。
    @Test func localStoreKeepsHistoryForLaterSync() throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "default.store", directoryHint: .notDirectory)

        do {
            let container = try ModelContainerFactory.makeContainer(url: url, cloudKitDatabase: .none)
            container.mainContext.insert(TestSupport.entry(amount: 850))
            try container.mainContext.save()
            let history = try container.mainContext.fetchHistory(HistoryDescriptor<DefaultHistoryTransaction>())
            #expect(!history.isEmpty)
        }

        // 開き直しても書き込める（読むだけの状態になっていない）。
        let reopened = try ModelContainerFactory.makeContainer(url: url, cloudKitDatabase: .none)
        reopened.mainContext.insert(TestSupport.entry(amount: 400))
        try reopened.mainContext.save()
        #expect(try reopened.mainContext.fetch(FetchDescriptor<Entry>()).map(\.amount).sorted() == [400, 850])
    }

    /// Core Data の CloudKit の連携が受け付けないモデルの形を並べる（空なら満たしている）。
    ///
    /// - 一意制約（uniquenessConstraints）が無い
    /// - すべての属性が optional か、既定値を持つ
    /// - 関係は optional で、逆向きの関係があり、順序つきでなく、削除の規則が Deny でない
    static func cloudKitViolations(in model: NSManagedObjectModel) -> [String] {
        var violations: [String] = []
        for entity in model.entities {
            let name = entity.name ?? "?"
            if entity.uniquenessConstraints.contains(where: { !$0.isEmpty }) {
                violations.append("\(name): uniqueness constraints \(entity.uniquenessConstraints)")
            }
            for attribute in entity.attributesByName.values where !attribute.isTransient {
                if !attribute.isOptional && attribute.defaultValue == nil {
                    violations.append("\(name).\(attribute.name): not optional and has no default value")
                }
            }
            for relationship in entity.relationshipsByName.values {
                if !relationship.isOptional {
                    violations.append("\(name).\(relationship.name): relationship is not optional")
                }
                if relationship.inverseRelationship == nil {
                    violations.append("\(name).\(relationship.name): relationship has no inverse")
                }
                if relationship.isOrdered {
                    violations.append("\(name).\(relationship.name): relationship is ordered")
                }
                if relationship.deleteRule == .denyDeleteRule {
                    violations.append("\(name).\(relationship.name): relationship uses the deny delete rule")
                }
            }
        }
        return violations
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

/// CloudKit の制約を破ったモデル（検査が見逃さないことを確かめるためだけのもの。保存先には入れない）。
@Model
final class CloudKitIncompatibleSample {
    @Attribute(.unique) var code: String

    init(code: String) {
        self.code = code
    }
}
