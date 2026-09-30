import CoreData
import Foundation
import SaifuLogCore
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

        #expect(Set(container.schema.entities.map(\.name)) == ["Entry", "Budget", "LearnedCategory", "CustomCategory", "RecurringEntry"])
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

    /// 覚えたカテゴリのモデルを足す前の保存先（記録と予算のモデルだけ）を開いても、記録と予算はそのまま読め、覚えを書き込める
    /// （予算のモデルを足したときと同じ、テーブルを足すだけの自動の移行）。
    @Test func opensStoreCreatedBeforeLearnedCategoryWasAdded() throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "default.store", directoryHint: .notDirectory)

        do {
            let previousSchema = Schema([Entry.self, Budget.self])
            let previous = try ModelContainer(
                for: previousSchema,
                configurations: [ModelConfiguration(schema: previousSchema, url: url, cloudKitDatabase: .none)]
            )
            #expect(Set(previous.schema.entities.map(\.name)) == ["Entry", "Budget"])
            previous.mainContext.insert(TestSupport.entry(amount: 850))
            previous.mainContext.insert(Budget(scope: .total, amount: 150_000, updatedAt: TestSupport.now))
            try previous.mainContext.save()
        }

        let upgraded = try ModelContainerFactory.makeContainer(url: url, cloudKitDatabase: .none)
        let context = upgraded.mainContext

        #expect(try context.fetch(FetchDescriptor<Entry>()).map(\.amount) == [850])
        #expect(try BudgetStore(context: context).plan().total == 150_000)
        let learned = LearnedCategoryStore(context: context, now: { TestSupport.now })
        try learned.remember(item: "ユニクロ", category: .other)
        #expect(try learned.memory().rules == ["ユニクロ": .other])
    }

    /// 作ったカテゴリのモデルを足す前の保存先（記録・予算・覚えたカテゴリのモデル）を開いても、それまでの記録・予算・覚えは
    /// そのまま読め、カテゴリを作れる（テーブルを足すだけの自動の移行）。
    @Test func opensStoreCreatedBeforeCustomCategoryWasAdded() throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "default.store", directoryHint: .notDirectory)

        do {
            let previousSchema = Schema([Entry.self, Budget.self, LearnedCategory.self])
            let previous = try ModelContainer(
                for: previousSchema,
                configurations: [ModelConfiguration(schema: previousSchema, url: url, cloudKitDatabase: .none)]
            )
            #expect(Set(previous.schema.entities.map(\.name)) == ["Entry", "Budget", "LearnedCategory"])
            previous.mainContext.insert(TestSupport.entry(amount: 850))
            previous.mainContext.insert(Budget(scope: .total, amount: 150_000, updatedAt: TestSupport.now))
            try previous.mainContext.save()
            try LearnedCategoryStore(context: previous.mainContext, now: { TestSupport.now }).remember(item: "ユニクロ", category: .daily)
        }

        let upgraded = try ModelContainerFactory.makeContainer(url: url, cloudKitDatabase: .none)
        let context = upgraded.mainContext

        #expect(try context.fetch(FetchDescriptor<Entry>()).map(\.amount) == [850])
        #expect(try BudgetStore(context: context).plan().total == 150_000)
        #expect(try LearnedCategoryStore(context: context).memory().rules == ["ユニクロ": .daily])
        let categories = CustomCategoryStore(context: context, now: { TestSupport.now })
        let clothes = try categories.create(name: "衣服", symbolName: "tshirt", colorIndex: 0)
        #expect(try categories.catalog().name(of: clothes) == "衣服")
    }

    /// くり返しの記録のモデルを足す前の保存先を開いても、それまでの記録は読め、くり返しの記録を作って記録できる
    /// （テーブルを足すだけの自動の移行）。記録に足した項目（`Entry.recurrenceKey`）の移行は `opensStoreCreatedBeforeCloudEncryption`。
    @Test func opensStoreCreatedBeforeRecurringEntryWasAdded() throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "default.store", directoryHint: .notDirectory)

        do {
            let previousSchema = Schema([Entry.self, Budget.self, LearnedCategory.self, CustomCategory.self])
            let previous = try ModelContainer(
                for: previousSchema,
                configurations: [ModelConfiguration(schema: previousSchema, url: url, cloudKitDatabase: .none)]
            )
            previous.mainContext.insert(TestSupport.entry(amount: 850))
            try previous.mainContext.save()
        }

        let upgraded = try ModelContainerFactory.makeContainer(url: url, cloudKitDatabase: .none)
        let context = upgraded.mainContext

        #expect(try context.fetch(FetchDescriptor<Entry>()).map(\.amount) == [850])
        let recurring = RecurringEntryStore(context: context, now: { TestSupport.now })
        try recurring.create(
            RecurringDraft(amount: 80_000, memo: "家賃", isIncome: false, category: .other, dayOfMonth: 25),
            startMonth: RecurringMonth(year: 2026, month: 9)
        )
        #expect(try recurring.recordDue(now: TestSupport.date(2026, 9, 26), timeZone: TestSupport.calendar.timeZone).count == 1)
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

        #expect(Set(model.entities.compactMap(\.name)) == ["Entry", "Budget", "LearnedCategory", "CustomCategory", "RecurringEntry"])
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
                "recurrenceKey": .stringAttributeType,
            ],
            "Budget": [
                "scopeRawValue": .stringAttributeType, "amount": .integer64AttributeType, "updatedAt": .dateAttributeType,
            ],
            "LearnedCategory": [
                "phrase": .stringAttributeType, "categoryRawValue": .stringAttributeType, "updatedAt": .dateAttributeType,
            ],
            "CustomCategory": [
                "categoryID": .stringAttributeType, "name": .stringAttributeType, "symbolName": .stringAttributeType,
                "colorIndex": .integer64AttributeType, "sortOrder": .integer64AttributeType, "createdAt": .dateAttributeType,
                "updatedAt": .dateAttributeType,
            ],
            "RecurringEntry": [
                "recurrenceID": .stringAttributeType, "memo": .stringAttributeType, "amount": .integer64AttributeType,
                "isIncome": .booleanAttributeType, "categoryRawValue": .stringAttributeType,
                "dayOfMonth": .integer64AttributeType, "startMonthKey": .integer64AttributeType,
                "lastRecordedMonthKey": .integer64AttributeType, "createdAt": .dateAttributeType, "updatedAt": .dateAttributeType,
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

    // MARK: - iCloud の暗号化フィールド

    /// iCloud と同期する記録と予算の項目は、すべて CloudKit の暗号化フィールドになっている（docs/design.md §5-3）。
    ///
    /// Core Data の CloudKit の連携が使う形（SwiftData のモデルから作った NSManagedObjectModel の `allowsCloudEncryption`）と、
    /// SwiftData の Schema の側の両方で確かめる。CloudKit は、スキーマに載った項目を後から暗号化フィールドに変えられないので、
    /// 項目を足すときに付け忘れると、その項目だけ高度なデータ保護でもエンドツーエンドにならないまま戻せなくなる。
    @Test func syncedAttributesAreCloudEncrypted() throws {
        let model = try #require(NSManagedObjectModel.makeManagedObjectModel(for: ModelContainerFactory.modelTypes))

        #expect(Set(model.entities.compactMap(\.name)) == ["Entry", "Budget", "LearnedCategory", "CustomCategory", "RecurringEntry"])
        #expect(Self.unencryptedAttributes(in: model).isEmpty, "\(Self.unencryptedAttributes(in: model))")
        #expect(Self.unencryptedAttributes(in: ModelContainerFactory.schema).isEmpty, "\(Self.unencryptedAttributes(in: ModelContainerFactory.schema))")
        // 内容にあたる項目を名指しでも確かめる（検査の数え方を誤って、項目を見ずに空を返していないか）。
        let entry = try #require(model.entitiesByName["Entry"])
        let budget = try #require(model.entitiesByName["Budget"])
        let learned = try #require(model.entitiesByName["LearnedCategory"])
        let custom = try #require(model.entitiesByName["CustomCategory"])
        let recurring = try #require(model.entitiesByName["RecurringEntry"])
        for name in [
            "amount", "isIncome", "categoryRawValue", "memo", "spentAt", "createdAt", "sourceRawValue", "originalText", "recurrenceKey",
        ] {
            #expect(entry.attributesByName[name]?.allowsCloudEncryption == true, "Entry.\(name) が暗号化フィールドになっていません")
        }
        for name in ["scopeRawValue", "amount", "updatedAt"] {
            #expect(budget.attributesByName[name]?.allowsCloudEncryption == true, "Budget.\(name) が暗号化フィールドになっていません")
        }
        for name in ["phrase", "categoryRawValue", "updatedAt"] {
            #expect(learned.attributesByName[name]?.allowsCloudEncryption == true, "LearnedCategory.\(name) が暗号化フィールドになっていません")
        }
        for name in ["categoryID", "name", "symbolName", "colorIndex", "sortOrder", "createdAt", "updatedAt"] {
            #expect(custom.attributesByName[name]?.allowsCloudEncryption == true, "CustomCategory.\(name) が暗号化フィールドになっていません")
        }
        for name in [
            "recurrenceID", "memo", "amount", "isIncome", "categoryRawValue", "dayOfMonth", "startMonthKey", "lastRecordedMonthKey",
            "createdAt", "updatedAt",
        ] {
            #expect(recurring.attributesByName[name]?.allowsCloudEncryption == true, "RecurringEntry.\(name) が暗号化フィールドになっていません")
        }
    }

    /// 上の検査が、暗号化の指定を外した項目を見逃さないこと（いつも空を返す検査になっていないか）。
    @Test func cloudEncryptionCheckFindsUnencryptedAttributes() throws {
        let model = try #require(NSManagedObjectModel.makeManagedObjectModel(for: [CloudEncryptionMissingSample.self]))

        #expect(Self.unencryptedAttributes(in: model) == ["CloudEncryptionMissingSample.memo"])
        #expect(Self.unencryptedAttributes(in: Schema([CloudEncryptionMissingSample.self])) == ["CloudEncryptionMissingSample.memo"])
        // 暗号化の指定を付ける前のモデル（下の移行のテストで使う）も、すべての項目を見逃さない。
        let before = try #require(NSManagedObjectModel.makeManagedObjectModel(for: StoreBeforeCloudEncryption.modelTypes))
        #expect(Self.unencryptedAttributes(in: before).count == 11)
    }

    /// 暗号化の指定を付ける前のモデルで作った保存先（iCloud 同期を出す前の版の端末の default.store）を、いまのモデルで開いても、
    /// 記録と予算がそのまま読め、書き込める。
    ///
    /// 暗号化の指定は CloudKit のレコードの作り方だけに効き、Core Data のモデルの版（バージョンハッシュ）に入らないので、保存先は
    /// 移行なしで開ける（スキーマの版を足さなくてよい）。開けないと、アップデートした利用者の保存先が開けなくなる（再試行の画面から
    /// 先へ進めない）。
    ///
    /// 版の比べは、いまのモデルと、その暗号化の指定だけを外した写しとで行う。凍結した `StoreBeforeCloudEncryption` と比べると、
    /// アプリのモデルに項目を足しただけ（docs/design.md §5-2 で想定しているふつうの変更。SwiftData の自動の移行で開ける）で版が
    /// ずれて失敗し、暗号化の指定のせいだと誤って読めてしまうため。この比べが失敗したら、暗号化の指定が版に入るようになった
    /// （OS の変更）ということなので、付ける前の保存先が開けて記録が残ること（下の読み直し）を見て、§5-2 の説明を直す。
    /// 付ける前の保存先が開けないときは、項目を足したときの移行の問題か、暗号化の指定の問題かを、この比べで切り分ける。
    @Test func opensStoreCreatedBeforeCloudEncryption() throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "default.store", directoryHint: .notDirectory)
        let spentAt = TestSupport.date(2026, 9, 27, hour: 12, minute: 30)
        let updatedAt = TestSupport.date(2026, 9, 1, hour: 9)

        do {
            let previousSchema = Schema(StoreBeforeCloudEncryption.modelTypes)
            let previous = try ModelContainer(
                for: previousSchema,
                configurations: [ModelConfiguration(schema: previousSchema, url: url, cloudKitDatabase: .none)]
            )
            #expect(Set(previous.schema.entities.map(\.name)) == ["Entry", "Budget"])
            let entry = StoreBeforeCloudEncryption.Entry()
            entry.amount = 3_000
            entry.isIncome = true
            entry.categoryRawValue = EntryCategory.food.rawValue
            entry.memo = "焼肉"
            entry.spentAt = spentAt
            entry.createdAt = TestSupport.now
            entry.sourceRawValue = EntrySource.voice.rawValue
            entry.originalText = "昨日 焼肉12000 4人で割り勘"
            previous.mainContext.insert(entry)
            let budget = StoreBeforeCloudEncryption.Budget()
            budget.scopeRawValue = BudgetScope.total.rawValue
            budget.amount = 150_000
            budget.updatedAt = updatedAt
            previous.mainContext.insert(budget)
            try previous.mainContext.save()
        }

        let upgraded = try ModelContainerFactory.makeContainer(url: url, cloudKitDatabase: .none)
        let context = upgraded.mainContext

        let entries = try context.fetch(FetchDescriptor<Entry>())
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry.amount == 3_000)
        #expect(entry.isIncome)
        #expect(entry.category == .food)
        #expect(entry.memo == "焼肉")
        #expect(entry.spentAt == spentAt)
        #expect(entry.createdAt == TestSupport.now)
        #expect(entry.source == .voice)
        #expect(entry.originalText == "昨日 焼肉12000 4人で割り勘")
        // 後から足した項目（くり返しの記録の印）は既定値（空）で読める（項目を足しただけの自動の移行）。
        #expect(entry.recurrenceKey.isEmpty)
        let budgets = try context.fetch(FetchDescriptor<Budget>())
        #expect(budgets.map(\.scopeRawValue) == [BudgetScope.total.rawValue])
        #expect(budgets.map(\.amount) == [150_000])
        #expect(budgets.map(\.updatedAt) == [updatedAt])
        #expect(try BudgetStore(context: context).plan().total == 150_000)

        // 開いた保存先に書き込める（読むだけの状態になっていない）。
        context.insert(TestSupport.entry(amount: 400))
        try context.save()
        #expect(try context.fetch(FetchDescriptor<Entry>()).map(\.amount).sorted() == [400, 3_000])

        // 移行なしで開けた理由: 暗号化の指定の有無だけでは、Core Data のモデルの版は変わらない。
        let current = try #require(NSManagedObjectModel.makeManagedObjectModel(for: ModelContainerFactory.modelTypes))
        let withoutEncryption = try #require(current.copy() as? NSManagedObjectModel)
        for attribute in withoutEncryption.entities.flatMap({ $0.attributesByName.values }) {
            attribute.allowsCloudEncryption = false
        }
        // 写しの指定だけが外れていること（写しが元と同じ項目を指していて、同じものどうしを比べている、になっていないか）。
        #expect(Self.unencryptedAttributes(in: withoutEncryption) == Self.persistentAttributes(in: current))
        #expect(Self.unencryptedAttributes(in: current) != Self.unencryptedAttributes(in: withoutEncryption))
        #expect(current.entityVersionHashesByName == withoutEncryption.entityVersionHashesByName)
        // 比べ方が版の違いを見分けられること（写しの版が写す前のまま残っていて、いつも一致する比べ方になっていないか）。
        let changed = try #require(current.copy() as? NSManagedObjectModel)
        let memo = try #require(changed.entitiesByName["Entry"]?.attributesByName["memo"])
        memo.versionHashModifier = "changed"
        #expect(current.entityVersionHashesByName != changed.entityVersionHashesByName)
    }

    /// 保存する項目（一時的なものを除く）を「型.項目」で並べる。
    static func persistentAttributes(in model: NSManagedObjectModel) -> [String] {
        model.entities.flatMap { entity in
            entity.attributesByName.values
                .filter { !$0.isTransient }
                .map { "\(entity.name ?? "?").\($0.name)" }
        }
        .sorted()
    }

    /// 暗号化フィールドになっていない項目を「型.項目」で並べる（空ならすべて暗号化フィールド）。
    static func unencryptedAttributes(in model: NSManagedObjectModel) -> [String] {
        model.entities.flatMap { entity in
            entity.attributesByName.values
                .filter { !$0.isTransient && !$0.allowsCloudEncryption }
                .map { "\(entity.name ?? "?").\($0.name)" }
        }
        .sorted()
    }

    /// SwiftData の Schema の側で、`.allowsCloudEncryption` の付いていない項目を「型.項目」で並べる。
    static func unencryptedAttributes(in schema: Schema) -> [String] {
        schema.entities.flatMap { entity in
            entity.attributes
                .filter { !$0.isTransient && !$0.options.contains(.allowsCloudEncryption) }
                .map { "\(entity.name).\($0.name)" }
        }
        .sorted()
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

/// 項目の一部だけが暗号化フィールドのモデル（暗号化の検査が見逃さないことを確かめるためだけのもの。保存先には入れない）。
@Model
final class CloudEncryptionMissingSample {
    @Attribute(.allowsCloudEncryption) var amount: Int = 0
    var memo: String = ""

    init() {}
}

/// 暗号化フィールドの指定を付ける前の記録と予算のモデル（iCloud 同期を出す前の版の端末の保存先を作るためだけのもの）。
///
/// 型の名前（SwiftData の型の名前 Entry・Budget）と項目の名前・型・既定値はアプリのモデルと同じにし、`.allowsCloudEncryption` だけを
/// 外している。アプリのモデルに項目を足したときも、ここは足さない（足す前の版の保存先を開けることを確かめるため）。
enum StoreBeforeCloudEncryption {
    static var modelTypes: [any PersistentModel.Type] {
        [Entry.self, Budget.self]
    }

    @Model
    final class Entry {
        var amount: Int = 0
        var isIncome: Bool = false
        var categoryRawValue: String = EntryCategory.other.rawValue
        var memo: String = ""
        var spentAt: Date = Date.now
        var createdAt: Date = Date.now
        var sourceRawValue: String = EntrySource.text.rawValue
        var originalText: String = ""

        init() {}
    }

    @Model
    final class Budget {
        var scopeRawValue: String = BudgetScope.totalRawValue
        var amount: Int = 0
        var updatedAt: Date = Date.now

        init() {}
    }
}
