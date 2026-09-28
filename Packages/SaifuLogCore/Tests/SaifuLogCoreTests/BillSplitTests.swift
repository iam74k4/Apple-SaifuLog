import Testing
@testable import SaifuLogCore

@Suite("割り勘")
struct BillSplitTests {
    @Test("割り切れるとき")
    func evenSplit() throws {
        let split = try #require(BillSplit(total: 12_000, count: 4))
        #expect(split.share == 3_000)
        #expect(split.advance == 9_000)
        #expect(split.note == "4人で割り勘・総額 ¥12,000・立替 ¥9,000")
    }

    @Test("割り切れないときは端数を自分が持つ")
    func unevenSplit() throws {
        let split = try #require(BillSplit(total: 1_000, count: 3))
        #expect(split.share == 334)
        #expect(split.advance == 666)
        #expect(split.share + split.advance == split.total)
    }

    @Test("割り勘として成り立たない値は nil", arguments: [(12_000, 1), (12_000, 0), (0, 4), (-100, 2)])
    func invalid(total: Int, count: Int) {
        #expect(BillSplit(total: total, count: count) == nil)
    }
}
