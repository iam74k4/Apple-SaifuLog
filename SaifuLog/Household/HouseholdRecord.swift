import CloudKit
import Foundation
import SaifuLogCore

/// 家計の記録（`HouseholdEntry`）と CloudKit の記録（CKRecord）の相互変換。
///
/// **中身の項目はすべて暗号化フィールド（`encryptedValues`）に入れる。** 金額・メモ・カテゴリ・記録した人の名前に加えて、
/// 収入か・使った日時・記録した日時・直した日時も、家計の情報（いつ何に使ったか）なので入れる。暗号化フィールドは端末の中で
/// 暗号化してから iCloud に置かれる（Apple の `encryptedValues` の説明）。高度なデータ保護をオンにした利用者では、鍵は記録の
/// 持ち主と共有の参加者だけが持ち、エンドツーエンドで暗号化される。標準のデータ保護では、通信中と Apple のサーバー上で暗号化
/// されるが、鍵は Apple が管理する（エンドツーエンドではない。Apple の iCloud のデータセキュリティの説明 https://support.apple.com/102651 ）。
/// ふつうの項目にすると高度なデータ保護でもエンドツーエンドにならないので、はじめから暗号化フィールドにしておく。
/// 暗号化フィールドは CKQuery の条件や並べ替えに使えないが、家計の同期は CKSyncEngine で変更を取るだけなので困らない。
/// 一度出した項目を後から暗号化フィールドに変えることはできない（CloudKit の制約）ので、最初からそうしている。
enum HouseholdRecord {
    /// CloudKit の記録の種類。一度出したら変えない（CloudKit の Production のスキーマは足すことしかできない）。
    static let recordType: CKRecord.RecordType = "HouseholdEntry"

    /// 項目の名前。一度出したら変えない。
    enum Field {
        static let amount = "amount"
        static let isIncome = "isIncome"
        static let category = "category"
        static let memo = "memo"
        static let spentAt = "spentAt"
        static let recorderName = "recorderName"
        static let createdAt = "createdAt"
        static let modifiedAt = "modifiedAt"

        static let all = [amount, isIncome, category, memo, spentAt, recorderName, createdAt, modifiedAt]
    }

    /// 家計の記録の CloudKit の ID（記録の名前は記録の UUID）。
    static func recordID(for id: UUID, zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
    }

    /// 送る CloudKit の記録を作る。
    ///
    /// 前にサーバーから受け取ったシステムフィールドがあれば、それに値を載せる（サーバーの記録と同じ版として送るため。版が
    /// 違うと `serverRecordChanged` で弾かれる）。システムフィールドが読めない・別の記録のものなら、新しい記録として作る。
    static func record(for entry: HouseholdEntry, zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = recordID(for: entry.id, zoneID: zoneID)
        let record: CKRecord
        if let data = entry.systemFields, let saved = decodeSystemFields(data), saved.recordID == recordID,
           saved.recordType == recordType {
            record = saved
        } else {
            record = CKRecord(recordType: recordType, recordID: recordID)
        }
        populate(record, from: entry)
        return record
    }

    /// 記録の値を CloudKit の記録の暗号化フィールドに書く。
    static func populate(_ record: CKRecord, from entry: HouseholdEntry) {
        let values = record.encryptedValues
        values[Field.amount] = entry.amount
        values[Field.isIncome] = entry.isIncome
        values[Field.category] = entry.categoryRawValue
        values[Field.memo] = entry.memo
        values[Field.spentAt] = entry.spentAt
        values[Field.recorderName] = entry.recorderName
        values[Field.createdAt] = entry.createdAt
        values[Field.modifiedAt] = entry.modifiedAt
    }

    /// CloudKit の記録から読んだ値。
    struct Values: Equatable {
        var amount: Int
        var isIncome: Bool
        var category: EntryCategory
        var memo: String
        var spentAt: Date
        var recorderName: String
        var createdAt: Date
        /// 読めなければ nil（衝突の解決では、読める端末の値を採る。`HouseholdConflict`）。
        var modifiedAt: Date?
    }

    /// CloudKit の記録から値を読む。家計の記録でない・金額か使った日時が読めない記録は nil（取り込まない）。
    ///
    /// 金額と使った日時が無い記録を取り込むと、¥0 や今日の記録として合計に入ってしまうため。ほかの項目は、無ければ既定の値
    /// （メモは空・カテゴリはその他など）で読む。
    static func values(from record: CKRecord) -> Values? {
        guard record.recordType == recordType else { return nil }
        let encrypted = record.encryptedValues
        guard let amount: Int = encrypted[Field.amount], amount >= 0, let spentAt: Date = encrypted[Field.spentAt] else {
            return nil
        }
        let categoryRawValue: String? = encrypted[Field.category]
        let createdAt: Date? = encrypted[Field.createdAt]
        return Values(
            amount: amount,
            isIncome: encrypted[Field.isIncome] ?? false,
            category: categoryRawValue.flatMap(EntryCategory.init(rawValue:)) ?? .other,
            memo: encrypted[Field.memo] ?? "",
            spentAt: spentAt,
            recorderName: encrypted[Field.recorderName] ?? "",
            createdAt: createdAt ?? spentAt,
            modifiedAt: encrypted[Field.modifiedAt]
        )
    }

    /// 読んだ値を家計の記録に書く（サーバーの値を採ったとき）。同じ値の項目は書かない（書いたことにしない）。
    static func apply(_ values: Values, to entry: HouseholdEntry) {
        if entry.amount != values.amount { entry.amount = values.amount }
        if entry.isIncome != values.isIncome { entry.isIncome = values.isIncome }
        if entry.category != values.category { entry.category = values.category }
        if entry.memo != values.memo { entry.memo = values.memo }
        if entry.spentAt != values.spentAt { entry.spentAt = values.spentAt }
        if entry.recorderName != values.recorderName { entry.recorderName = values.recorderName }
        if entry.createdAt != values.createdAt { entry.createdAt = values.createdAt }
        if let modifiedAt = values.modifiedAt, entry.modifiedAt != modifiedAt { entry.modifiedAt = modifiedAt }
    }

    // MARK: - システムフィールド

    /// CloudKit の記録のシステムフィールド（ID・種類・版など。値は含まない）を保存できる形にする。
    static func encodeSystemFields(of record: CKRecord) -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        archiver.finishEncoding()
        return archiver.encodedData
    }

    /// 保存したシステムフィールドから、値の無い CloudKit の記録を作り直す。読めなければ nil（新しい記録として送り直す）。
    static func decodeSystemFields(_ data: Data) -> CKRecord? {
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        unarchiver.requiresSecureCoding = true
        defer { unarchiver.finishDecoding() }
        return CKRecord(coder: unarchiver)
    }

    /// サーバーから受け取った記録のシステムフィールドを、新しいときだけ家計の記録に残す。
    ///
    /// 古い版（届く順が入れ替わったもの）で上書きすると、次に送るときにまた `serverRecordChanged` で弾かれるため。
    /// どちらの更新日時も分からなければ、受け取ったものを残す。
    static func keepSystemFieldsIfNewer(_ record: CKRecord, in entry: HouseholdEntry) {
        if let data = entry.systemFields, let saved = decodeSystemFields(data),
           let savedDate = saved.modificationDate, let newDate = record.modificationDate, newDate < savedDate {
            return
        }
        entry.systemFields = encodeSystemFields(of: record)
    }
}
