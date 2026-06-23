/// Tests field parsing, wire request validation, response construction, codec
/// behavior, and page snapshot compatibility models.
import Foundation
@testable import WebPageCLI

struct PageFieldAndProtocolTests {

	func testPageFieldListParsingTrimsAndDeduplicatesNames() throws {
		XCTAssertEqual(
			PageField.validList,
			"actions,browser,htmlBytes,jsonBytes,loading,progress,resourceCount,resources,"
				+ "resourcesLoading,text,title,url"
		)
		XCTAssertEqual(try PageField.parseList(" title, url,actions,title "), [.title, .url, .actions])
		XCTAssertEqual(
			try PageField.parseList(" images, imageCount, resources "),
			[.resources, .resourceCount]
		)

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
			.withResourceLoading(waitForResources: true, timeout: 3.5)
			.withTypingDelays(min: 0.01, max: 0.02)

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
		XCTAssertEqual(request.waitForResources, true)
		XCTAssertEqual(try request.resourceWaitTimeout(default: 8), 3.5)
		XCTAssertEqual(
			try request.typingDelayRange(),
			TypingDelayRange(min: 0.01, max: 0.02)
		)

		assertThrowsMessage(try WireRequest(command: .page).requiredBrowserID(), "missing browser id")
		assertThrowsMessage(try WireRequest(command: .eval).requiredScript(), "missing JavaScript")
		assertThrowsMessage(try WireRequest(command: .click).requiredAction(), "missing action number or ID")
	}

	func testResourceTimeoutValidationAndWaitSemantics() throws {
		let defaultRequest = WireRequest(command: .open)
		XCTAssertFalse(defaultRequest.waitsForResources())
		XCTAssertEqual(try defaultRequest.resourceWaitTimeout(default: 8), 8)

		let timeoutOnly = WireRequest(command: .open)
			.withResourceLoading(waitForResources: false, timeout: 2)
		XCTAssertTrue(timeoutOnly.waitsForResources())
		XCTAssertEqual(try timeoutOnly.resourceWaitTimeout(default: 8), 2)

		try WireRequest(command: .open)
			.withResourceLoading(waitForResources: true, timeout: ResourceLoading.maxTimeout)
			.validateResourceLoading()

		assertThrowsMessage(
			try WireRequest(command: .open)
				.withResourceLoading(waitForResources: true, timeout: -0.25)
				.validateResourceLoading(),
			"invalid resource timeout -0.25"
		)
		assertThrowsMessage(
			try WireRequest(command: .open)
				.withResourceLoading(
					waitForResources: true,
					timeout: ResourceLoading.maxTimeout + 0.001
				)
				.validateResourceLoading(),
			"exceeds maximum 100"
		)
	}

	func testResourceLoadingValidationRejectsUnsupportedCommands() throws {
		try WireRequest(command: .open)
			.withResourceLoading(waitForResources: true, timeout: nil)
			.validateResourceLoading()
		try WireRequest(command: .screenshot)
			.withResourceLoading(waitForResources: true, timeout: ResourceLoading.defaultTimeout)
			.withScreenshotDelay(ScreenshotCapture.defaultDelay)
			.validateResourceLoading()
		try WireRequest(command: .page)
			.withResourceLoading(waitForResources: false, timeout: nil)
			.validateResourceLoading()
		XCTAssertEqual(
			try WireRequest(command: .screenshot)
				.screenshotCaptureDelay(default: ScreenshotCapture.defaultDelay),
			ScreenshotCapture.defaultDelay
		)
		XCTAssertEqual(
			try WireRequest(command: .screenshot)
				.withScreenshotDelay(0)
				.screenshotCaptureDelay(default: ScreenshotCapture.defaultDelay),
			0
		)
		let decodedFalse = try JSONDecoder().decode(
			WireRequest.self,
			from: Data(#"{"command":"page","waitForResources":false}"#.utf8)
		)
		XCTAssertEqual(decodedFalse.waitForResources, false)
		try decodedFalse.validateResourceLoading()

		assertThrowsMessage(
			try WireRequest(command: .page)
				.withResourceLoading(waitForResources: true, timeout: nil)
				.validateResourceLoading(),
			"resource loading options are only supported for open and screenshot commands"
		)
		assertThrowsMessage(
			try WireRequest(command: .click)
				.withResourceLoading(waitForResources: false, timeout: 1)
				.validateResourceLoading(),
			"resource loading options are only supported for open and screenshot commands"
		)
		assertThrowsMessage(
			try WireRequest(command: .page)
				.withScreenshotDelay(0.3)
				.validateResourceLoading(),
			"screenshot capture delay is only supported for screenshot commands"
		)
		assertThrowsMessage(
			try WireRequest(command: .screenshot)
				.withScreenshotDelay(-0.1)
				.validateResourceLoading(),
			"invalid screenshot capture delay -0.1"
		)
		assertThrowsMessage(
			try WireRequest(command: .screenshot)
				.withScreenshotDelay(ScreenshotCapture.maxDelay + 0.1)
				.validateResourceLoading(),
			"exceeds maximum 10"
		)
	}

	func testTypingDelayValidation() throws {
		let defaults = try WireRequest(command: .typeText).typingDelayRange()
		XCTAssertEqual(defaults, TypingDelayRange(min: TypingDelay.defaultMin, max: TypingDelay.defaultMax))

		try WireRequest(command: .typeText)
			.withTypingDelays(min: 0, max: 0.01)
			.validateTypingDelays()
		XCTAssertEqual(
			try WireRequest(command: .typeText)
				.withTypingDelays(min: 0.2, max: nil)
				.typingDelayRange(),
			TypingDelayRange(min: 0.2, max: 0.2)
		)
		XCTAssertEqual(
			try WireRequest(command: .typeText)
				.withTypingDelays(min: nil, max: 0.01)
				.typingDelayRange(),
			TypingDelayRange(min: 0.01, max: 0.01)
		)

		assertThrowsMessage(
			try WireRequest(command: .fill)
				.withTypingDelays(min: 0, max: 0.01)
				.validateTypingDelays(),
			"typing delay options are only supported for type command"
		)
		assertThrowsMessage(
			try WireRequest(command: .typeText)
				.withTypingDelays(min: -0.01, max: 0.01)
				.validateTypingDelays(),
			"invalid typing delay -0.01"
		)
		assertThrowsMessage(
			try WireRequest(command: .typeText)
				.withTypingDelays(min: 0, max: TypingDelay.maxDelay + 0.01)
				.validateTypingDelays(),
			"exceeds maximum 5"
		)
		assertThrowsMessage(
			try WireRequest(command: .typeText)
				.withTypingDelays(min: 0.2, max: 0.1)
				.validateTypingDelays(),
			"typing delay minimum must be less than or equal to maximum"
		)
	}

	func testWindowSizeValidation() throws {
		XCTAssertEqual(
			try WireRequest(command: .browserResize).windowSize(),
			BrowserWindowSizing.defaultSize
		)

		let resize = WireRequest(command: .browserResize)
			.withWindowSize(BrowserWindowSize(width: 1024, height: 768))
		XCTAssertEqual(try resize.windowSize(), BrowserWindowSize(width: 1024, height: 768))
		try resize.validateWindowSize()
		try WireRequest(command: .browserResize)
			.withWindowSize(BrowserWindowSize(width: 800, height: 200))
			.validateWindowSize()

		assertThrowsMessage(
			try WireRequest(command: .browserResize)
				.withWindowSize(BrowserWindowSize(width: 99, height: 600))
				.validateWindowSize(),
			"window width must be at least 100"
		)
		assertThrowsMessage(
			try WireRequest(command: .browserResize)
				.withWindowSize(BrowserWindowSize(width: 800, height: 99))
				.validateWindowSize(),
			"window height must be at least 100"
		)
		assertThrowsMessage(
			try WireRequest(command: .page)
				.withWindowSize(BrowserWindowSize(width: 800, height: 600))
				.validateWindowSize(),
			"window size options are only supported for resize command"
		)

		var missingWidth = WireRequest(command: .browserResize)
		missingWidth.windowHeight = 600
		assertThrowsMessage(try missingWidth.validateWindowSize(), "missing window width")

		var missingHeight = WireRequest(command: .browserResize)
		missingHeight.windowWidth = 800
		assertThrowsMessage(try missingHeight.validateWindowSize(), "missing window height")
	}

	func testPageLoadStatusTracksPageResourceAndQuietStates() throws {
		let loading = PageLoadStatus(readyState: "loading", quietFor: 2)
		XCTAssertTrue(loading.pageLoading)
		XCTAssertTrue(loading.resourcesLoading(webKitLoading: false))

		let interactive = PageLoadStatus(readyState: "interactive", quietFor: 2)
		XCTAssertFalse(interactive.pageLoading)
		XCTAssertTrue(interactive.resourcesLoading(webKitLoading: false))

		let pending = PageLoadStatus(readyState: "complete", pendingRequests: 1, quietFor: 2)
		XCTAssertTrue(pending.resourcesLoading(webKitLoading: false))

		let pendingResourceJSON = Data(
			#"{"readyState":"complete","pendingResources":1,"quietFor":2}"#.utf8)
		let pendingResource = try JSONDecoder().decode(PageLoadStatus.self, from: pendingResourceJSON)
		XCTAssertTrue(pendingResource.resourcesLoading(webKitLoading: false))

		let noisy = PageLoadStatus(readyState: "complete", quietFor: 0.1)
		XCTAssertTrue(noisy.resourcesLoading(webKitLoading: false))

		let webKitLoading = PageLoadStatus(readyState: "complete", quietFor: 2)
		XCTAssertTrue(webKitLoading.resourcesLoading(webKitLoading: true))

		let settled = PageLoadStatus(readyState: "complete", quietFor: 2)
		XCTAssertFalse(settled.resourcesLoading(webKitLoading: false))

		let legacyJSON = Data(#"{"readyState":"complete"}"#.utf8)
		let decoded = try JSONDecoder().decode(PageLoadStatus.self, from: legacyJSON)
		XCTAssertFalse(decoded.resourcesLoading(webKitLoading: false))
	}

	func testPageLoadStatusInteractionSettlingUsesShortQuietCriteria() throws {
		let interactive = PageLoadStatus(readyState: "interactive", quietFor: 1)
		XCTAssertTrue(interactive.interactionSettled(webKitLoading: false))

		let complete = PageLoadStatus(readyState: "complete", quietFor: 1)
		XCTAssertTrue(complete.interactionSettled(webKitLoading: false))
		XCTAssertFalse(complete.interactionSettled(webKitLoading: true))

		let loading = PageLoadStatus(readyState: "loading", quietFor: 1)
		XCTAssertFalse(loading.interactionSettled(webKitLoading: false))

		let pending = PageLoadStatus(readyState: "complete", pendingRequests: 1, quietFor: 1)
		XCTAssertFalse(pending.interactionSettled(webKitLoading: false))

		let noisy = PageLoadStatus(readyState: "complete", quietFor: 0.1)
		XCTAssertFalse(noisy.interactionSettled(webKitLoading: false))
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

	func testPageSnapshotDecodesCurrentResourcesAndLegacyImagePayloads() throws {
		let current = try JSONEncoder().encode(makePageSnapshot())
		let decodedCurrent = try JSONDecoder().decode(PageSnapshot.self, from: current)
		XCTAssertEqual(decodedCurrent.resources.count, 3)
		XCTAssertEqual(decodedCurrent.resourceCount, 3)
		XCTAssertEqual(decodedCurrent.resources[1].type, "image")

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
		XCTAssertEqual(decodedLegacy.resources.count, 0)
		XCTAssertEqual(decodedLegacy.resourceCount, 7)
		XCTAssertEqual(decodedLegacy.title, "Legacy")

		let legacyImageArrayJSON = Data(
			"""
			{
			  "actions": [],
			  "browser": "deadbeef",
			  "htmlBytes": 9,
			  "images": [
			    {"index": 1, "url": "https://example.com/legacy.png", "alt": "Legacy image"}
			  ],
			  "loading": false,
			  "progress": 1.0,
			  "text": "Legacy",
			  "title": "Legacy",
			  "url": "https://example.com"
			}
			""".utf8)
		let decodedLegacyImageArray = try JSONDecoder().decode(PageSnapshot.self, from: legacyImageArrayJSON)
		XCTAssertEqual(decodedLegacyImageArray.resources.count, 1)
		XCTAssertEqual(decodedLegacyImageArray.resources[0].type, "image")
		XCTAssertEqual(decodedLegacyImageArray.resourceCount, 1)

		let malformedCurrentJSON = Data(
			"""
			{
			  "actions": [],
			  "browser": "deadbeef",
			  "images": [
			    {"index": 1, "url": "https://example.com/legacy.png", "alt": "Legacy image"}
			  ],
			  "loading": false,
			  "progress": 1.0,
			  "resources": "not an array",
			  "title": "Malformed",
			  "url": "https://example.com"
			}
			""".utf8)
		do {
			_ = try JSONDecoder().decode(PageSnapshot.self, from: malformedCurrentJSON)
			XCTFail("expected malformed current resources to fail")
		} catch {
			XCTAssertTrue(!error.localizedDescription.isEmpty)
		}
	}
}
