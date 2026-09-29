import Foundation
import Testing
@testable import SaifuLogCore

/// 家計の共有の同期の決め事（衝突・ゾーンの名前・ゾーンが消えたとき）。
struct HouseholdSyncRulesTests {
    // MARK: - 衝突

    /// 利用者が直した日時の新しいほうを採る（送った順ではない）。
    @Test func newerModificationWins() {
        let older = Fixture.date(2026, 9, 28, hour: 9)
        let newer = Fixture.date(2026, 9, 28, hour: 10)

        #expect(HouseholdConflict.winner(localModifiedAt: newer, serverModifiedAt: older) == .local)
        #expect(HouseholdConflict.winner(localModifiedAt: older, serverModifiedAt: newer) == .server)
    }

    /// 同じ日時ならサーバーの値（どの端末でも同じ値に落ち着く）。
    @Test func tieGoesToServer() {
        #expect(HouseholdConflict.winner(localModifiedAt: Fixture.now, serverModifiedAt: Fixture.now) == .server)
    }

    /// サーバーの記録から日時を読めなければ、端末の値を採る（読めない値で上書きしない）。
    @Test func unreadableServerDateKeepsLocal() {
        #expect(HouseholdConflict.winner(localModifiedAt: Fixture.now, serverModifiedAt: nil) == .local)
    }

    /// オフラインで先に直した古い値は、後からオンラインで直した新しい値に負ける（後から送っても）。
    @Test func offlineEditMadeEarlierLosesEvenIfSentLater() {
        let offlineEdit = Fixture.date(2026, 9, 28, hour: 8)
        let laterOnlineEdit = Fixture.date(2026, 9, 28, hour: 11)

        #expect(HouseholdConflict.winner(localModifiedAt: offlineEdit, serverModifiedAt: laterOnlineEdit) == .server)
    }

    // MARK: - ゾーンの名前

    @Test func zoneNameRoundTrips() throws {
        let id = try #require(UUID(uuidString: "5B1F7C1E-3C2A-4F7E-9E1D-2A6B8C0D4E5F"))
        let name = HouseholdZoneName.make(householdID: id)

        #expect(name == "household-5B1F7C1E-3C2A-4F7E-9E1D-2A6B8C0D4E5F")
        #expect(HouseholdZoneName.householdID(fromZoneName: name) == id)
        #expect(HouseholdZoneName.isHouseholdZone(name))
    }

    /// iCloud 同期（SwiftData）のゾーンや、頭だけ合う名前は家計のゾーンとみなさない。
    @Test(arguments: ["com.apple.coredata.cloudkit.zone", "_defaultZone", "household-", "household-not-a-uuid", "Household-5B1F7C1E-3C2A-4F7E-9E1D-2A6B8C0D4E5F"])
    func otherZonesAreNotHouseholds(name: String) {
        #expect(!HouseholdZoneName.isHouseholdZone(name))
        #expect(HouseholdZoneName.householdID(fromZoneName: name) == nil)
    }

    // MARK: - ゾーンが消えたとき

    /// 消えたら、持ち主でも参加者でも端末の記録を消す（削除が勝つ）。
    @Test(arguments: [HouseholdZoneRemoval.Reason.deleted, .purged, .notFound])
    func removalDeletesLocalData(reason: HouseholdZoneRemoval.Reason) {
        #expect(HouseholdZoneRemoval.action(for: reason, role: .owner) == .removeLocalData)
        #expect(HouseholdZoneRemoval.action(for: reason, role: .participant) == .removeLocalData)
    }

    /// 暗号化したデータのリセットは、持ち主なら送り直し、参加者なら消す（持ち主のデータを送り直せないため）。
    @Test func encryptedDataResetReuploadsOnlyForOwner() {
        #expect(HouseholdZoneRemoval.action(for: .encryptedDataReset, role: .owner) == .reuploadLocalData)
        #expect(HouseholdZoneRemoval.action(for: .encryptedDataReset, role: .participant) == .removeLocalData)
    }
}
