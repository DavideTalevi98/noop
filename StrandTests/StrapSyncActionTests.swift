import XCTest
@testable import Strand

/// Tap-routing matrix for the Polar-style strap sync chrome. Mirrors Android StrapSyncActionTest.
final class StrapSyncActionTests: XCTestCase {

    func testBackfillingWinsRegardlessOfLink() {
        XCTAssertEqual(StrapSyncAction.resolve(connected: true, bonded: true, backfilling: true), .syncing)
        XCTAssertEqual(StrapSyncAction.resolve(connected: false, bonded: false, backfilling: true), .syncing)
    }

    func testOfflineWhenDisconnected() {
        XCTAssertEqual(StrapSyncAction.resolve(connected: false, bonded: false, backfilling: false), .offline)
        XCTAssertEqual(StrapSyncAction.resolve(connected: false, bonded: true, backfilling: false), .offline)
    }

    func testPairingWhenConnectedButNotBonded() {
        XCTAssertEqual(StrapSyncAction.resolve(connected: true, bonded: false, backfilling: false), .pairing)
    }

    func testReadyWhenConnectedBondedIdle() {
        XCTAssertEqual(StrapSyncAction.resolve(connected: true, bonded: true, backfilling: false), .ready)
    }

    func testFlashCompleteWhenOffloadEndsCleanly() {
        XCTAssertTrue(StrapSyncAction.shouldFlashComplete(wasBackfilling: true, backfilling: false, lastSyncError: nil))
    }

    func testNoFlashWhenStillBackfillingOrErrored() {
        XCTAssertFalse(StrapSyncAction.shouldFlashComplete(wasBackfilling: true, backfilling: true, lastSyncError: nil))
        XCTAssertFalse(StrapSyncAction.shouldFlashComplete(wasBackfilling: true, backfilling: false, lastSyncError: "timeout"))
        XCTAssertFalse(StrapSyncAction.shouldFlashComplete(wasBackfilling: false, backfilling: false, lastSyncError: nil))
    }
}
