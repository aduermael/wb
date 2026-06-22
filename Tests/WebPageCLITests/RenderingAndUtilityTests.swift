/// Verifies compact JSON utilities and the string-rendering seam used by CLI
/// output without requiring stdout capture.
import Foundation
@testable import WebPageCLI

struct RenderingAndUtilityTests {

	func testOptionalAndStringHelpers() throws {
		let missing: String? = nil
		assertThrowsMessage(try missing.unwrap("missing value"), "missing value")

		let empty: String? = ""
		let value: String? = "value"
		XCTAssertNil(empty.nilIfEmpty)
		XCTAssertNil("".nilIfEmpty)
		XCTAssertEqual(value.nilIfEmpty, "value")
		XCTAssertEqual("value".nilIfEmpty, "value")
	}

	func testISO8601HelpersRoundTripStableDates() throws {
		let date = Date(timeIntervalSince1970: 1_704_067_200)
		let rendered = date.iso8601String
		XCTAssertEqual(rendered.iso8601Date?.timeIntervalSince1970, date.timeIntervalSince1970)
		XCTAssertNil("not a date".iso8601Date)
	}

	func testPrintableHandlesCommonJavaScriptBridgeValues() throws {
		XCTAssertEqual(printable(nil), "nil")
		XCTAssertEqual(printable(NSNull()), "null")
		XCTAssertEqual(printable("hello"), "hello")
		XCTAssertEqual(printable(NSNumber(value: 7)), "7")

		let object = ["b": 2, "a": 1]
		let rendered = printable(object)
		XCTAssertTrue(rendered.contains("\"a\" : 1"))
		XCTAssertTrue(rendered.contains("\"b\" : 2"))
	}

	func testCompactJSONStringSortsKeysAndPrunesDefaults() throws {
		struct Payload: Encodable {
			let ok: Bool
			let hidden: Bool
			let empty: String
			let values: [Int]
			let nested: [String: String]
			let progress: Double
		}

		let rendered = try compactJSONString(
			Payload(
				ok: false,
				hidden: false,
				empty: "",
				values: [],
				nested: [:],
				progress: 1
			))

		XCTAssertEqual(rendered, "{\"ok\":false,\"progress\":1.0}")
	}

	func testRenderedOutputForSummaryPageAndActions() throws {
		let response = WireResponse.success()
			.withBrowser("deadbeef")
			.withMessage("clicked More")
			.withPage(makePageSnapshot())

		let summary = try renderedOutput(response, mode: .pageSummary)
		XCTAssertTrue(summary?.contains("\"actions\":2") == true)
		XCTAssertTrue(summary?.contains("\"browser\":\"deadbeef\"") == true)
		XCTAssertTrue(summary?.contains("\"htmlBytes\":128") == true)
		XCTAssertTrue(summary?.contains("\"images\":2") == true)
		XCTAssertTrue(summary?.contains("\"jsonBytes\":") == true)
		XCTAssertTrue(summary?.contains("\"message\":\"clicked More\"") == true)
		XCTAssertTrue(summary?.contains("\"url\":\"https:\\/\\/example.com\"") == true)

		let page = try renderedOutput(
			response,
			mode: .page(PageOutputOptions(includeActionSelectors: false, includeActionDetails: true))
		)
		XCTAssertTrue(page?.contains("\"id\":\"wkcli-1\"") == true)
		XCTAssertTrue(page?.contains("\"kind\":\"link\"") == true)
		XCTAssertTrue(page?.contains("\"kind\":\"selector\"") == true)
		XCTAssertTrue(page?.contains("\"selector\":\"a.more\"") == true)
		XCTAssertTrue(page?.contains("\"alt\":\"Example image\"") == true)

		let filtered = try renderedOutput(
			response,
			mode: .page(PageOutputOptions(fields: [.title, .actions]))
		)
		XCTAssertTrue(filtered?.contains("\"actions\":") == true)
		XCTAssertTrue(filtered?.contains("\"title\":\"Example\"") == true)
		XCTAssertTrue(filtered?.contains("\"kind\":\"link\"") == true)
		XCTAssertTrue(filtered?.contains("\"href\":\"https:\\/\\/example.com\\/more\"") == true)
		XCTAssertTrue(filtered?.contains("\"kind\":\"selector\"") == true)
		XCTAssertTrue(filtered?.contains("\"url\":") == false)
		XCTAssertTrue(filtered?.contains("\"images\":") == false)
	}

	func testRenderedOutputForSimpleModesAndErrors() throws {
		XCTAssertEqual(
			try renderedOutput(WireResponse.success().withBrowser("deadbeef"), mode: .browserID), "deadbeef"
		)
		XCTAssertEqual(try renderedOutput(WireResponse.success().withValue(nil), mode: .value), "")
		XCTAssertEqual(try renderedOutput(WireResponse.success().withMessage(nil), mode: .message), "ok")
		XCTAssertEqual(try renderedOutput(WireResponse.success(), mode: .daemonStart), "running")
		XCTAssertNil(try renderedOutput(WireResponse.success(), mode: .silent))

		let error = WireResponse.failure("navigation failed")
			.withBrowser("deadbeef")
			.withPage(makePageSnapshot())
		let renderedError = try renderedOutput(error, mode: .pageSummary)
		XCTAssertTrue(renderedError?.contains("\"ok\":false") == true)
		XCTAssertTrue(renderedError?.contains("\"error\":\"navigation failed\"") == true)
		XCTAssertTrue(renderedError?.contains("\"browser\":\"deadbeef\"") == true)
	}
}
