import Foundation
import Testing
import UIKit
@testable import SaifuLog

/// 共有のシートを出してから閉じるまでの状態（ShareSheetPresenter.Coordinator）。UIKit のシートは出さず、知らせの順だけを確かめる。
@MainActor
struct ShareSheetCoordinatorTests {
    typealias Coordinator = ShareSheetPresenter.Coordinator

    /// Coordinator と、終えた知らせ（シートを出せたか）の記録。
    @MainActor
    final class Fixture {
        var finished: [Bool] = []
        lazy var coordinator = Coordinator(onFinish: { [unowned self] in finished.append($0) })
    }

    static let first = URL(filePath: "/tmp/CSVExport/A/saifulog-20260928.csv")
    static let second = URL(filePath: "/tmp/CSVExport/B/saifulog-20260928.csv")

    /// 閉じた知らせが二度来ても（シートを閉じたときと、先の画面を閉じたときなど）、終えるのは一度だけ（ファイルを消すのは一度）。
    @Test func finishNotifiesOnlyOnce() {
        let fixture = Fixture()
        fixture.coordinator.begin(Self.first)
        #expect(fixture.coordinator.didPresent(Self.first))

        fixture.coordinator.finish(sheetWasShown: true)
        fixture.coordinator.finish(sheetWasShown: true)

        #expect(fixture.finished == [true])
        #expect(fixture.coordinator.isPresenting == false)
    }

    /// 出し終えた知らせを受けていれば、待ち終えても終えない（シートは出ていて、利用者が先を選んでいる）。
    @Test func fallbackAfterPresentDoesNothing() {
        let fixture = Fixture()
        fixture.coordinator.begin(Self.first)
        #expect(fixture.coordinator.didPresent(Self.first))

        fixture.coordinator.finishIfNotPresented(Self.first, isShowing: false)

        #expect(fixture.finished.isEmpty)
        #expect(fixture.coordinator.isPresenting)
    }

    /// 出し終えた知らせがまだでも、UIKit の上で出している途中なら終えない（実機で最初のシートを出すのが遅いとき）。
    @Test func fallbackWhileSheetIsStillAppearingDoesNothing() {
        let fixture = Fixture()
        fixture.coordinator.begin(Self.first)

        fixture.coordinator.finishIfNotPresented(Self.first, isShowing: true)

        #expect(fixture.finished.isEmpty)
        #expect(fixture.coordinator.didPresent(Self.first))
    }

    /// 出し終えた知らせが無く、UIKit の上でも出ていなければ、出せなかったものとして終える。
    @Test func fallbackWhenSheetWasNotShownFinishesAsNotShown() {
        let fixture = Fixture()
        fixture.coordinator.begin(Self.first)

        fixture.coordinator.finishIfNotPresented(Self.first, isShowing: false)

        #expect(fixture.finished == [false])
    }

    /// 出せなかったものとして片づけた後に、遅れてシートが出てきたら、閉じさせる（渡すファイルはもう無い）。
    @Test func latePresentAfterGivingUpAsksToDismiss() {
        let fixture = Fixture()
        fixture.coordinator.begin(Self.first)
        fixture.coordinator.finishIfNotPresented(Self.first, isShowing: false)

        #expect(fixture.coordinator.didPresent(Self.first) == false)
        // その後に閉じた知らせが来ても、二度は終えない。
        fixture.coordinator.finish(sheetWasShown: true)
        #expect(fixture.finished == [false])
    }

    /// 前のファイルの待ちが、次に書き出したファイルのシートを終えない。
    @Test func fallbackForPreviousFileIgnoresNewExport() {
        let fixture = Fixture()
        fixture.coordinator.begin(Self.first)
        fixture.coordinator.finish(sheetWasShown: true)
        fixture.coordinator.begin(Self.second)

        fixture.coordinator.finishIfNotPresented(Self.first, isShowing: false)
        #expect(fixture.coordinator.didPresent(Self.first) == false)

        #expect(fixture.finished == [true])
        #expect(fixture.coordinator.isPresenting)
        #expect(fixture.coordinator.didPresent(Self.second))
    }

    /// 閉じた知らせの中身と、閉じたとみなすか。
    struct CompletionCase: Sendable, CustomTestStringConvertible {
        let activityType: UIActivity.ActivityType?
        let completed: Bool
        let isStillPresented: Bool
        let closed: Bool
        let testDescription: String
    }

    /// 選んだ先の画面でやめたとき（シートは出たまま）は、閉じたとみなさない。続けて別の先を選べるよう、ファイルを残す。
    @Test(arguments: [
        CompletionCase(activityType: nil, completed: false, isStillPresented: false, closed: true, testDescription: "シートを閉じた"),
        CompletionCase(
            activityType: nil, completed: false, isStillPresented: true, closed: true,
            testDescription: "シートを閉じた（閉じる動きの前に知らせが来た）"
        ),
        CompletionCase(
            activityType: .mail, completed: true, isStillPresented: true, closed: true,
            testDescription: "メールで渡し終えた（この後にシートは閉じる）"
        ),
        CompletionCase(
            activityType: .mail, completed: false, isStillPresented: true, closed: false,
            testDescription: "メールの画面でやめて、シートに戻った"
        ),
        CompletionCase(
            activityType: .message, completed: false, isStillPresented: true, closed: false,
            testDescription: "メッセージの画面でやめて、シートに戻った"
        ),
        CompletionCase(
            activityType: .mail, completed: false, isStillPresented: false, closed: true,
            testDescription: "先の画面でやめたが、シートはもう出ていない"
        ),
    ])
    func sheetHasClosed(_ testCase: CompletionCase) {
        #expect(Coordinator.sheetHasClosed(
            activityType: testCase.activityType, completed: testCase.completed, isStillPresented: testCase.isStillPresented
        ) == testCase.closed)
    }
}
