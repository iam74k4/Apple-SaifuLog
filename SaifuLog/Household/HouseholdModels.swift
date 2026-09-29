import Foundation
import SaifuLogCore
import SwiftData

/// この端末が入っている家計（家族・パートナーと共有する家計）。家計の保存先（household.store）に置く。
///
/// 自分の記録（default.store）とは別の保存先にする。SwiftData の CloudKit 同期は共有データベース（CKShare）を扱えないので、
/// 家計は CKSyncEngine で専用のゾーンと同期し、ゾーンごと共有する（docs/design.md §5-5）。家計の保存先は iCloud と同期しない
/// （`cloudKitDatabase` は `.none`）。同期は CKSyncEngine が受け持つ。
///
/// v1 では、端末が入る家計は 1 つだけ（入っている間に別の招待を受け入れない）。
@Model
final class Household {
    /// 家計のゾーンの名前（`HouseholdZoneName`。「household-」と UUID）。家計ごとに 1 つ。
    var zoneName: String = ""
    /// ゾーンの持ち主（CloudKit のゾーンの ID の ownerName）。自分で作った家計は `CKCurrentUserDefaultName`、
    /// 招待を受け入れた家計は持ち主の利用者の記録の名前（共有データベースのゾーンの ID に要る）。
    var zoneOwnerName: String = ""
    /// 自分が持ち主か参加者か（`HouseholdRole` の rawValue）。
    var roleRawValue: String = HouseholdRole.owner.rawValue
    /// 家計の名前（招待の画面の題名にも使う）。
    var name: String = ""
    /// この端末の利用者の表示名。家計の記録の「記録した人」に書く。家族に見える名前なので、利用者が自分で決める。
    var memberName: String = ""
    /// この端末で家計を作った（受け入れた）日時。
    var createdAt: Date = Date.now

    init(zoneName: String, zoneOwnerName: String, role: HouseholdRole, name: String, memberName: String, createdAt: Date) {
        self.zoneName = zoneName
        self.zoneOwnerName = zoneOwnerName
        self.roleRawValue = role.rawValue
        self.name = name
        self.memberName = memberName
        self.createdAt = createdAt
    }

    var role: HouseholdRole {
        get { HouseholdRole(rawValue: roleRawValue) ?? .participant }
        set { roleRawValue = newValue.rawValue }
    }
}

/// 家計での立場。rawValue は保存に使うので変えないこと。
enum HouseholdRole: String, Sendable, CaseIterable {
    /// 家計を作った人。ゾーンは自分の私用データベースにある。
    case owner
    /// 招待を受け入れた人。ゾーンは共有データベースにある。
    case participant
}

/// 家計の 1 件の記録。家族のだれが記録したかを持つ。
///
/// CloudKit の記録（`HouseholdRecord`）と相互に変換する。金額・メモ・カテゴリ・記録した人の名前などの中身は、CloudKit の
/// 暗号化フィールド（`encryptedValues`）に入れる。家計のお金の情報なので、Apple のサーバーの上でも鍵を持つ人（家計の参加者）
/// にしか読めないようにするため。
@Model
final class HouseholdEntry {
    /// 記録の ID。CloudKit の記録の名前（recordName）に使う。どの端末でも同じ記録を同じ ID で指す。
    var id: UUID = UUID()
    /// どの家計の記録か（家計のゾーンの名前）。
    var zoneName: String = ""
    /// 金額（円）。支出も収入も正の数で持つ（自分の記録と同じ）。
    var amount: Int = 0
    var isIncome: Bool = false
    /// カテゴリの rawValue（自分の記録と同じく文字列で持つ）。
    var categoryRawValue: String = EntryCategory.other.rawValue
    var memo: String = ""
    /// 使った日時（収入なら受け取った日時）。
    var spentAt: Date = Date.now
    /// 記録した人の表示名（その人の端末の `Household.memberName`）。
    var recorderName: String = ""
    /// 記録した日時。タイムラインはこの順に並べる。
    var createdAt: Date = Date.now
    /// 利用者が最後に直した日時。同じ記録を 2 つの端末で直したときに、新しいほうを採るのに使う（`HouseholdConflict`）。
    var modifiedAt: Date = Date.now
    /// 最後にサーバーから受け取った CloudKit の記録のシステムフィールド（`CKRecord.encodeSystemFields`）。
    ///
    /// 送るときはこれに値を載せる。サーバーの記録と同じ版（change tag）として送らないと、毎回 `serverRecordChanged` で
    /// 弾かれるため。まだ一度も送っていなければ nil。
    var systemFields: Data?

    init(
        id: UUID = UUID(),
        zoneName: String,
        amount: Int,
        isIncome: Bool,
        category: EntryCategory,
        memo: String,
        spentAt: Date,
        recorderName: String,
        createdAt: Date,
        modifiedAt: Date,
        systemFields: Data? = nil
    ) {
        self.id = id
        self.zoneName = zoneName
        self.amount = amount
        self.isIncome = isIncome
        self.categoryRawValue = category.rawValue
        self.memo = memo
        self.spentAt = spentAt
        self.recorderName = recorderName
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.systemFields = systemFields
    }

    var category: EntryCategory {
        get { EntryCategory(rawValue: categoryRawValue) ?? .other }
        set { categoryRawValue = newValue.rawValue }
    }
}

/// 家族の今月の合計（SaifuLogCore の LedgerSummary）にそのまま渡せるようにする。
extension HouseholdEntry: LedgerEntryDisplaying {}

extension HouseholdEntry {
    /// 1 回の送信の解析結果から、家計の記録を書いた順に作る（日時の振り方は自分の記録と同じ `ParsedEntry.timestamps`）。
    static func records(
        from parsed: [ParsedEntry], zoneName: String, recorderName: String, now: Date, calendar: Calendar
    ) -> [HouseholdEntry] {
        zip(parsed, ParsedEntry.timestamps(for: parsed, now: now, calendar: calendar)).map { entry, timestamps in
            HouseholdEntry(
                zoneName: zoneName,
                amount: entry.amount,
                isIncome: entry.isIncome,
                category: entry.category,
                memo: entry.memo,
                spentAt: timestamps.spentAt,
                recorderName: recorderName,
                createdAt: timestamps.createdAt,
                modifiedAt: now
            )
        }
    }

    /// その家計の、`date` を含む月の記録だけを読む条件（家族の今月の合計）。月の区切りは自分の記録と同じ `ReportPeriod.thisMonth`。
    static func monthDescriptor(zoneName: String, containing date: Date, calendar: Calendar) -> FetchDescriptor<HouseholdEntry> {
        guard let month = ReportPeriod.thisMonth.interval(now: date, calendar: calendar) else {
            return FetchDescriptor(predicate: #Predicate { _ in false })
        }
        let start = month.start
        let end = month.end
        return FetchDescriptor(predicate: #Predicate { $0.zoneName == zoneName && $0.spentAt >= start && $0.spentAt < end })
    }

    /// タイムラインに出す、その家計の記録した日時の新しいものから `limit` 件。
    static func timelineDescriptor(zoneName: String, limit: Int) -> FetchDescriptor<HouseholdEntry> {
        var descriptor = FetchDescriptor<HouseholdEntry>(
            predicate: #Predicate { $0.zoneName == zoneName },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return descriptor
    }
}

/// CKSyncEngine の状態（`CKSyncEngine.State.Serialization` を JSON にしたもの）。データベース（私用・共有）ごとに 1 行。
///
/// 次の起動で CKSyncEngine に渡す（渡さないと、毎回はじめから全部を取り直し、送っていない変更も忘れる）。送っていない変更
/// （削除を含む）もこの中に入るので、家計の記録と同じ保存先（データ保護 Complete）に置く。
@Model
final class HouseholdSyncState {
    /// どのデータベースの状態か（`HouseholdDatabaseScope` の rawValue）。
    var scopeRawValue: String = ""
    var serialization: Data?

    init(scopeRawValue: String, serialization: Data?) {
        self.scopeRawValue = scopeRawValue
        self.serialization = serialization
    }
}
