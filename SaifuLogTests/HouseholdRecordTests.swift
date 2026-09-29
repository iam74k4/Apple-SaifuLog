import CloudKit
import Foundation
import SaifuLogCore
import Testing
@testable import SaifuLog

/// 家計の記録と CloudKit の記録の相互変換（暗号化フィールドに入れること・システムフィールドを残すこと）。
@MainActor
struct HouseholdRecordTests {
    let zoneID = TestSupport.householdZoneID(role: .owner)

    /// 中身の項目はすべて暗号化フィールドに入れ、ふつうの項目には置かない（金額・メモ・カテゴリ・記録した人の名前も）。
    @Test func contentGoesToEncryptedValues() throws {
        let entry = TestSupport.householdEntry(amount: 1_280, memo: "スーパー", category: .daily, recorderName: "たろう")
        let record = HouseholdRecord.record(for: entry, zoneID: zoneID)

        #expect(record.recordType == HouseholdRecord.recordType)
        #expect(record.recordID == CKRecord.ID(recordName: entry.id.uuidString, zoneID: zoneID))
        let encrypted = record.encryptedValues
        #expect(encrypted[HouseholdRecord.Field.amount] as Int? == 1_280)
        #expect(encrypted[HouseholdRecord.Field.memo] as String? == "スーパー")
        #expect(encrypted[HouseholdRecord.Field.category] as String? == EntryCategory.daily.rawValue)
        #expect(encrypted[HouseholdRecord.Field.recorderName] as String? == "たろう")
        #expect(encrypted[HouseholdRecord.Field.isIncome] as Bool? == false)
        #expect(encrypted[HouseholdRecord.Field.spentAt] as Date? == TestSupport.now)
        #expect(encrypted[HouseholdRecord.Field.modifiedAt] as Date? == TestSupport.now)
        for field in HouseholdRecord.Field.all {
            #expect(record[field] == nil, "暗号化しないふつうの項目に \(field) を置かない")
        }
    }

    /// 書いた値をそのまま読み戻せる。
    @Test func valuesRoundTrip() throws {
        let entry = TestSupport.householdEntry(amount: 12_000, memo: "焼肉", recorderName: "はなこ")
        entry.isIncome = false
        let record = HouseholdRecord.record(for: entry, zoneID: zoneID)

        let values = try #require(HouseholdRecord.values(from: record))
        #expect(values == HouseholdRecord.Values(
            amount: 12_000, isIncome: false, category: .food, memo: "焼肉", spentAt: TestSupport.now, recorderName: "はなこ",
            createdAt: TestSupport.now, modifiedAt: TestSupport.now
        ))
    }

    /// 金額か使った日時の無い記録・ほかの種類の記録は取り込まない（¥0 や今日の記録として合計に入らないように）。
    @Test func rejectsIncompleteOrForeignRecords() {
        let missingAmount = CKRecord(recordType: HouseholdRecord.recordType, recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: zoneID))
        missingAmount.encryptedValues[HouseholdRecord.Field.spentAt] = TestSupport.now
        #expect(HouseholdRecord.values(from: missingAmount) == nil)

        let missingDate = CKRecord(recordType: HouseholdRecord.recordType, recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: zoneID))
        missingDate.encryptedValues[HouseholdRecord.Field.amount] = 500
        #expect(HouseholdRecord.values(from: missingDate) == nil)

        let foreign = CKRecord(recordType: "CD_Entry", recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: zoneID))
        foreign.encryptedValues[HouseholdRecord.Field.amount] = 500
        foreign.encryptedValues[HouseholdRecord.Field.spentAt] = TestSupport.now
        #expect(HouseholdRecord.values(from: foreign) == nil)
    }

    /// 無い項目は既定の値で読む（知らないカテゴリはその他、直した日時が無ければ nil）。
    @Test func missingOptionalFieldsUseDefaults() throws {
        let record = CKRecord(recordType: HouseholdRecord.recordType, recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: zoneID))
        record.encryptedValues[HouseholdRecord.Field.amount] = 500
        record.encryptedValues[HouseholdRecord.Field.spentAt] = TestSupport.now
        record.encryptedValues[HouseholdRecord.Field.category] = "unknown-category"

        let values = try #require(HouseholdRecord.values(from: record))
        #expect(values.category == .other)
        #expect(values.memo.isEmpty)
        #expect(values.recorderName.isEmpty)
        #expect(values.createdAt == TestSupport.now)
        #expect(values.modifiedAt == nil)
    }

    /// システムフィールドを保存でき、読み戻すと同じ記録（ID と種類）を指す。値は含めない。
    @Test func systemFieldsRoundTrip() throws {
        let entry = TestSupport.householdEntry()
        let record = HouseholdRecord.record(for: entry, zoneID: zoneID)

        let data = HouseholdRecord.encodeSystemFields(of: record)
        let restored = try #require(HouseholdRecord.decodeSystemFields(data))

        #expect(restored.recordID == record.recordID)
        #expect(restored.recordType == record.recordType)
        #expect(restored.encryptedValues[HouseholdRecord.Field.amount] as Int? == nil)
    }

    /// 送る記録は、保存したシステムフィールドの上に今の値を載せて作る（サーバーの版として送るため）。
    @Test func recordReusesSavedSystemFields() throws {
        let entry = TestSupport.householdEntry(amount: 850)
        entry.systemFields = HouseholdRecord.encodeSystemFields(of: HouseholdRecord.record(for: entry, zoneID: zoneID))
        entry.amount = 900

        let record = HouseholdRecord.record(for: entry, zoneID: zoneID)

        #expect(record.recordID.recordName == entry.id.uuidString)
        #expect(record.encryptedValues[HouseholdRecord.Field.amount] as Int? == 900)
    }

    /// 別の記録や読めないシステムフィールドは使わず、新しい記録として作る。
    @Test func ignoresForeignOrBrokenSystemFields() throws {
        let other = CKRecord(recordType: HouseholdRecord.recordType, recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: zoneID))
        let entry = TestSupport.householdEntry()
        entry.systemFields = HouseholdRecord.encodeSystemFields(of: other)
        #expect(HouseholdRecord.record(for: entry, zoneID: zoneID).recordID.recordName == entry.id.uuidString)

        entry.systemFields = Data("broken".utf8)
        #expect(HouseholdRecord.decodeSystemFields(Data("broken".utf8)) == nil)
        #expect(HouseholdRecord.record(for: entry, zoneID: zoneID).recordID.recordName == entry.id.uuidString)
    }

    /// サーバーの値を採るときは、同じ値の項目を書かない（書いたことにしない）。直した日時が読めなければ端末の日時を残す。
    @Test func applyWritesServerValues() {
        let entry = TestSupport.householdEntry(amount: 850, memo: "ランチ", modifiedAt: TestSupport.date(2026, 9, 28, hour: 9))
        let values = HouseholdRecord.Values(
            amount: 900, isIncome: false, category: .cafe, memo: "カフェ", spentAt: TestSupport.now, recorderName: "たろう",
            createdAt: TestSupport.now, modifiedAt: nil
        )

        HouseholdRecord.apply(values, to: entry)

        #expect(entry.amount == 900)
        #expect(entry.category == .cafe)
        #expect(entry.memo == "カフェ")
        #expect(entry.recorderName == "たろう")
        #expect(entry.modifiedAt == TestSupport.date(2026, 9, 28, hour: 9))
    }
}
