import Combine
import XCTest
@testable import ClipboardFolderUI

@MainActor
final class VolumeRecoveryDialogTests: XCTestCase {
    func testRemountInvokesActionAndPostsSuccessNotification() async {
        let remountStarted = expectation(description: "remount started")
        let successNotification = expectation(description: "success notification")

        let observer = NotificationCenter.default.addObserver(
            forName: .clipboardFolderVolumeRecoveryRemountSucceeded,
            object: nil,
            queue: nil
        ) { _ in
            successNotification.fulfill()
        }

        let model = VolumeRecoveryDialogModel(
            reason: "Clipboard volume unavailable.",
            remountAction: {
                remountStarted.fulfill()
            },
            quitAction: {}
        )

        model.remount()

        await fulfillment(of: [remountStarted, successNotification], timeout: 2.0)
        NotificationCenter.default.removeObserver(observer)
    }

    func testRemountFailureSetsFailedPhase() async {
        let failure = NSError(
            domain: "VolumeRecoveryDialogTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "remount failed"]
        )

        let failureReached = expectation(description: "failure reached")
        var cancellable: AnyCancellable?

        let model = VolumeRecoveryDialogModel(
            reason: "Clipboard volume unavailable.",
            remountAction: {
                throw failure
            },
            quitAction: {}
        )

        cancellable = model.$phase.sink { phase in
            if case .failed(let message) = phase, message == failure.localizedDescription {
                failureReached.fulfill()
            }
        }

        model.remount()

        await fulfillment(of: [failureReached], timeout: 2.0)
        cancellable?.cancel()

        if case .failed(let message) = model.phase {
            XCTAssertEqual(message, failure.localizedDescription)
        } else {
            XCTFail("Expected failure phase")
        }
    }
}