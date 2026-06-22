/// Tests field parsing, wire request validation, response construction, codec
/// behavior, and page snapshot compatibility models.
import Foundation
@testable import WebPageCLI

struct PageFieldAndProtocolTests {

	func testPageFieldListParsingTrimsAndDeduplicatesNames() throws {
		XCTAssertEqual(
			PageField.validList,
			"actions,browser,htmlBytes,imageCount,images,jsonBytes,loading,progress,text,title,url")
		XCTAssertEqual(try PageField.parseList(" title, url,actions,title "), [.title, .url, .actions])

		assertThrowsMessage(try PageField.parseList(" ,, "), "--fields requires at least one field")
		assertThrowsMessage(try PageField.parseList("title,bogus"), "unknown page field bogus")
	}

	func testWireRequestBuilderAndRequiredValues() throws {
		let request = WireRequest(command: .fill)
			.withBrowser("deadbeef")
			.withURL("example.com")
			.withScript("return 1", functionBody: true)
			.withAction("42")
			.withValue("")
			.withDestinationPath("/tmp/shot.png")
			.withCoordinate("scroll", point: WirePoint(x: 1.5, y: 2), delta: WireDelta(x: -3, y: 4))

		XCTAssertEqual(try request.requiredBrowserID(), "deadbeef")
		XCTAssertEqual(try request.requiredURL().absoluteString, "https://example.com")
		XCTAssertEqual(try request.requiredScript(), "return 1")
		XCTAssertEqual(try request.requiredAction(), "42")
		XCTAssertEqual(request.index, 42)
		XCTAssertEqual(try request.requiredValue(), "")
		XCTAssertEqual(try request.requiredDestinationPath(), "/tmp/shot.png")
		XCTAssertEqual(try request.requiredCoordinateAction(), "scroll")
		XCTAssertEqual(try request.requiredX(), 1.5)
		XCTAssertEqual(try request.requiredY(), 2)
		XCTAssertEqual(try request.requiredDeltaX(), -3)
		XCTAssertEqual(try request.requiredDeltaY(), 4)

		assertThrowsMessage(try WireRequest(command: .page).requiredBrowserID(), "missing browser id")
		assertThrowsMessage(try WireRequest(command: .eval).requiredScript(), "missing JavaScript")
		assertThrowsMessage(try WireRequest(command: .click).requiredAction(), "missing action number or ID")
	}

	func testWireResponsesPreserveProtocolVersionAndBuilderFields() throws {
		let success = WireResponse.success()
			.withBrowser("deadbeef")
			.withBrowsers([])
			.withEnvironment(
				WBEnvironmentMetadata(directory: "/tmp/wb", sessionsDirectory: "sessions", uuid: "abc")
			)
			.withPage(makePageSnapshot())
			.withValue("42")
			.withMessage("ok")
			.withURL("https://example.com")

		XCTAssertEqual(success.protocolVersion, WireProtocol.version)
		XCTAssertTrue(success.ok)
		XCTAssertEqual(success.browser, "deadbeef")
		XCTAssertEqual(success.value, "42")
		XCTAssertEqual(success.message, "ok")
		XCTAssertEqual(success.url, "https://example.com")
		XCTAssertEqual(success.environment?.sessionsDirectory, "sessions")

		let failure = WireResponse.failure("broken")
		XCTAssertEqual(failure.protocolVersion, WireProtocol.version)
		XCTAssertFalse(failure.ok)
		XCTAssertEqual(failure.error, "broken")
	}

	func testWireCodecRoundTripsResponsesAndErrors() throws {
		let encoded = try WireCodec.encode(WireResponse.success().withBrowser("deadbeef"))
		let decoded = try JSONDecoder().decode(WireResponse.self, from: encoded)
		XCTAssertEqual(decoded.browser, "deadbeef")
		XCTAssertEqual(decoded.protocolVersion, WireProtocol.version)

		let errorData = WireCodec.encodeError("failed")
		let error = try JSONDecoder().decode(WireResponse.self, from: errorData)
		XCTAssertFalse(error.ok)
		XCTAssertEqual(error.error, "failed")
	}

	func testPageSnapshotDecodesCurrentAndLegacyImagePayloads() throws {
		let current = try JSONEncoder().encode(makePageSnapshot())
		let decodedCurrent = try JSONDecoder().decode(PageSnapshot.self, from: current)
		XCTAssertEqual(decodedCurrent.images.count, 2)
		XCTAssertEqual(decodedCurrent.imageCount, 2)

		let legacyJSON = Data(
			"""
			{
			  "actions": [],
			  "browser": "deadbeef",
			  "htmlBytes": 9,
			  "images": 7,
			  "loading": false,
			  "progress": 1.0,
			  "text": "Legacy",
			  "title": "Legacy",
			  "url": "https://example.com"
			}
			""".utf8)
		let decodedLegacy = try JSONDecoder().decode(PageSnapshot.self, from: legacyJSON)
		XCTAssertEqual(decodedLegacy.images.count, 0)
		XCTAssertEqual(decodedLegacy.imageCount, 7)
		XCTAssertEqual(decodedLegacy.title, "Legacy")
	}
}
