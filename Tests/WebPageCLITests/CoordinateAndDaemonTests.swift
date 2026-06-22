/// Covers pure coordinate-action request translation and daemon activity timing
/// without opening WebKit pages or Unix sockets.
import Foundation
@testable import WebPageCLI

struct CoordinateAndDaemonTests {

	func testCoordinateActionBuildsClickPressDragAndRelease() throws {
		let names = ["click", "press", "drag", "release"]

		for name in names {
			let action = try BrowserCoordinateAction(
				request: WireRequest(command: .coordinate)
					.withCoordinate(name, point: WirePoint(x: 10, y: 20)))

			XCTAssertEqual(action.name, name)
			XCTAssertEqual(Double(action.point.x), 10)
			XCTAssertEqual(Double(action.point.y), 20)
			XCTAssertEqual(action.javascriptArguments["action"] as? String, name)
			XCTAssertEqual(action.javascriptArguments["x"] as? Double, 10)
			XCTAssertEqual(action.javascriptArguments["y"] as? Double, 20)
			XCTAssertNil(action.javascriptArguments["deltaX"])
		}
	}

	func testCoordinateActionBuildsScrollWithDeltas() throws {
		let request = WireRequest(command: .coordinate)
			.withCoordinate("scroll", point: WirePoint(x: 1, y: 2), delta: WireDelta(x: -3, y: 4))
		let action = try BrowserCoordinateAction(request: request)

		XCTAssertEqual(action.name, "scroll")
		XCTAssertEqual(Double(action.point.x), 1)
		XCTAssertEqual(Double(action.point.y), 2)
		XCTAssertEqual(action.javascriptArguments["deltaX"] as? Double, -3)
		XCTAssertEqual(action.javascriptArguments["deltaY"] as? Double, 4)
	}

	func testCoordinateActionRejectsMissingAndUnknownActions() {
		assertThrowsMessage(
			try BrowserCoordinateAction(request: WireRequest(command: .coordinate)),
			"missing coordinate action"
		)
		assertThrowsMessage(
			try BrowserCoordinateAction(
				request: WireRequest(command: .coordinate)
					.withCoordinate("zoom", point: WirePoint(x: 1, y: 2))),
			"unknown coordinate action zoom"
		)
		assertThrowsMessage(
			try BrowserCoordinateAction(
				request: WireRequest(command: .coordinate)
					.withCoordinate("scroll", point: WirePoint(x: 1, y: 2))),
			"missing x scroll delta"
		)
	}

	func testDaemonActivityTracksInFlightRequestsAndTimeouts() {
		let activity = DaemonActivity()
		let start = Date(timeIntervalSince1970: 100)

		XCTAssertFalse(activity.isIdle(timeout: 0, now: start.addingTimeInterval(10)))
		XCTAssertFalse(activity.isIdle(timeout: 5, now: start))
		XCTAssertTrue(activity.isIdle(timeout: 0.001, now: Date().addingTimeInterval(1)))

		activity.beginRequest()
		XCTAssertFalse(activity.isIdle(timeout: 0.001, now: Date().addingTimeInterval(1)))
		activity.endRequest()
		XCTAssertFalse(activity.isIdle(timeout: 5, now: Date()))
	}
}
