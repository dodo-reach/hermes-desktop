import Foundation
@testable import HermesPhoneKit
import XCTest

final class AsyncOperationErrorPolicyTests: XCTestCase {
    func testCancellationErrorIsNotUserFacing() {
        let error = CancellationError()

        XCTAssertTrue(AsyncOperationErrorPolicy.isCancellation(error))
        XCTAssertNil(AsyncOperationErrorPolicy.userFacingMessage(for: error))
    }

    func testBridgedCancellationErrorIsNotUserFacing() {
        let error = NSError(domain: "Swift.CancellationError", code: 1)

        XCTAssertTrue(AsyncOperationErrorPolicy.isCancellation(error))
        XCTAssertNil(AsyncOperationErrorPolicy.userFacingMessage(for: error))
    }

    func testOrdinaryErrorRemainsUserFacing() {
        let error = NSError(domain: "HermesPhoneKitTests", code: 7, userInfo: [
            NSLocalizedDescriptionKey: "Connection failed"
        ])

        XCTAssertFalse(AsyncOperationErrorPolicy.isCancellation(error))
        XCTAssertEqual(AsyncOperationErrorPolicy.userFacingMessage(for: error), "Connection failed")
    }
}
