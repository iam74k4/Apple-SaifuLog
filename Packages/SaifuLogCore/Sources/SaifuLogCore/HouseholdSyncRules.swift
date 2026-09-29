import Foundation

/// 家計の共有（家族・パートナー）で、同じ記録を 2 つの端末がそれぞれ直したときにどちらを採るか。
///
/// 家計の記録は CloudKit の共有したゾーンに置き、参加者は全員が読み書きできる。オフラインの間に直した記録を後から送ると、
/// その間にほかの人が直した記録と食い違う（CloudKit は `serverRecordChanged` で知らせる）。送った順ではなく、
/// **利用者が直した日時（`modifiedAt`）の新しいほうを採る。** 送った順で決めると、何時間も前にオフラインで直した古い値が、
/// 後から直した新しい値を上書きしてしまうため（Apple の CKSyncEngine のサンプルと同じ考え方）。
/// 同じ日時ならサーバーの値を採る（どの端末でも同じ値に落ち着かせるため）。端末の時計が大きくずれていると、あとから直した値が
/// 負けることがある（受け入れている。予算の行の「最後に書いた値」と同じ。docs/design.md §5-5）。
public enum HouseholdConflict {
    /// どちらの値を採るか。
    public enum Winner: Sendable, Equatable {
        /// 端末の値（サーバーへ送り直す）。
        case local
        /// サーバーの値（端末の記録を書き換える）。
        case server
    }

    /// - Parameters:
    ///   - localModifiedAt: 端末の記録を利用者が最後に直した日時。
    ///   - serverModifiedAt: サーバーの記録に書かれていた、同じ意味の日時。読めなければ nil（壊れた記録・古い形の記録）。
    public static func winner(localModifiedAt: Date, serverModifiedAt: Date?) -> Winner {
        // サーバーの記録から日時を読めなければ、読める端末の値を採る（読めない値で端末の記録を上書きしないため）。
        guard let serverModifiedAt else { return .local }
        return localModifiedAt > serverModifiedAt ? .local : .server
    }
}

/// 家計を置く CloudKit のゾーンの名前（「household-」と家計の UUID）。
///
/// ゾーンは家計ごとに 1 つ作り、ゾーンごと共有する（CKShare のゾーンの共有）。名前に決まった頭を付けるのは、同じ私用データベースに
/// iCloud 同期（SwiftData）のゾーンもあり、家計の同期がそれを自分のものと取り違えないようにするため。
public enum HouseholdZoneName {
    /// ゾーンの名前の頭。一度出したら変えない（変えると、それまでの家計のゾーンを見分けられなくなる）。
    public static let prefix = "household-"

    /// 家計の UUID からゾーンの名前を作る。
    public static func make(householdID: UUID) -> String {
        prefix + householdID.uuidString
    }

    /// ゾーンの名前から家計の UUID を読む。家計のゾーンでなければ nil。
    public static func householdID(fromZoneName name: String) -> UUID? {
        guard name.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(name.dropFirst(prefix.count)))
    }

    /// 家計のゾーンか（頭と UUID の形の両方が合うか）。
    public static func isHouseholdZone(_ name: String) -> Bool {
        householdID(fromZoneName: name) != nil
    }
}

/// 家計のゾーンがサーバーから消えたとき（持ち主が消した・共有をやめた・参加者が抜けた・iCloud の容量の画面で消した・
/// 暗号化したデータをリセットした）に、端末の家計の記録をどうするか。
public enum HouseholdZoneRemoval {
    /// ゾーンが消えた理由（CloudKit の `CKDatabase.DatabaseChange.Deletion.Reason` と、送ったときの `zoneNotFound` を写したもの）。
    public enum Reason: Sendable, Equatable {
        /// 消された（持ち主がほかの端末で家計を消した・共有をやめた・参加者として抜けた）。
        case deleted
        /// 利用者が iCloud の容量の画面などから、このアプリのデータを消した。
        case purged
        /// 利用者が Apple アカウントの暗号化したデータをリセットした（暗号化フィールドの鍵が作り直された）。
        case encryptedDataReset
        /// 送ろうとしたらゾーンが無かった（`zoneNotFound`・`userDeletedZone`）。
        case notFound
    }

    /// 端末で家計を持っている立場。
    public enum Role: Sendable, Equatable {
        /// 家計を作った人（ゾーンは自分の私用データベースにある）。
        case owner
        /// 招待を受け入れた人（ゾーンは共有データベースにある）。
        case participant
    }

    /// 端末ですること。
    public enum Action: Sendable, Equatable {
        /// 端末の家計の記録を消して、利用者に知らせる。
        case removeLocalData
        /// 端末の記録からゾーンを作り直して送り直す（持ち主の暗号化したデータのリセットのときだけ）。
        case reuploadLocalData
    }

    /// 理由と立場から、端末ですることを決める。
    ///
    /// **消えたら端末の記録も消す（削除が勝つ）。** 持ち主が家計を消した・共有をやめたのに、参加者の端末に記録が残り続けると、
    /// 共有をやめたつもりの家計の中身が見え続けるため。送るときにゾーンが無かったときも作り直さない（ほかの端末で消した家計を
    /// 生き返らせないため）。
    /// 例外は持ち主の暗号化したデータのリセットだけ。記録はまだ持ち主のもので、Apple も端末の記録を送り直すことを勧めている
    /// （共有は消えるので、家族はもう一度招待する）。参加者は持ち主のデータを送り直せないので消す。
    public static func action(for reason: Reason, role: Role) -> Action {
        reason == .encryptedDataReset && role == .owner ? .reuploadLocalData : .removeLocalData
    }
}
