/// Covers command-line parsing for every deterministic command shape before
/// requests are handed to the daemon or macOS browser runtime.
import Foundation
@testable import WebPageCLI

struct CLIParserTests {

	func testEmptyArgumentsShowRootHelp() throws {
		let invocation = try CLIParser.parse([])

		XCTAssertNil(invocation.request)
		XCTAssertFalse(invocation.startDaemon)
		guard case .help(.root) = invocation.renderMode else {
			return XCTFail("expected root help")
		}
	}

	func testCreateListAndCloseCommands() throws {
		let create = try CLIParser.parse(["create"])
		XCTAssertEqual(create.request?.command, .browserCreate)
		XCTAssertTrue(create.startDaemon)
		guard case .browserID = create.renderMode else {
			return XCTFail("expected browser id rendering")
		}

		let list = try CLIParser.parse(["ls"])
		XCTAssertEqual(list.request?.command, .browserList)
		guard case .browsers = list.renderMode else {
			return XCTFail("expected browsers rendering")
		}

		let close = try CLIParser.parse(["rm", "a1b2c3d4"])
		XCTAssertEqual(close.request?.command, .browserClose)
		XCTAssertEqual(close.request?.browser, "a1b2c3d4")
		guard case .message = close.renderMode else {
			return XCTFail("expected message rendering")
		}
	}

	func testShowHideAndResizeCommands() throws {
		let show = try CLIParser.parse(["show", "deadbeef"])
		XCTAssertEqual(show.request?.command, .browserShow)
		XCTAssertEqual(show.request?.browser, "deadbeef")
		guard case .silent = show.renderMode else {
			return XCTFail("expected silent rendering")
		}

		let hide = try CLIParser.parse(["hide", "deadbeef"])
		XCTAssertEqual(hide.request?.command, .browserHide)
		XCTAssertEqual(hide.request?.browser, "deadbeef")

		let defaultResize = try CLIParser.parse(["resize", "deadbeef"])
		XCTAssertEqual(defaultResize.request?.command, .browserResize)
		XCTAssertEqual(defaultResize.request?.browser, "deadbeef")
		XCTAssertEqual(defaultResize.request?.windowWidth, BrowserWindowSizing.defaultWidth)
		XCTAssertEqual(defaultResize.request?.windowHeight, BrowserWindowSizing.defaultHeight)
		guard case .message = defaultResize.renderMode else {
			return XCTFail("expected message rendering")
		}

		let explicitResize = try CLIParser.parse(["resize", "deadbeef", "1024", "768"])
		XCTAssertEqual(explicitResize.request?.command, .browserResize)
		XCTAssertEqual(explicitResize.request?.windowWidth, 1024)
		XCTAssertEqual(explicitResize.request?.windowHeight, 768)

		let shortResize = try CLIParser.parse(["resize", "deadbeef", "800", "200"])
		XCTAssertEqual(shortResize.request?.windowWidth, 800)
		XCTAssertEqual(shortResize.request?.windowHeight, 200)

		assertThrowsMessage(
			try CLIParser.parse(["resize", "deadbeef", "99", "600"]),
			"window width must be at least 100"
		)
		assertThrowsMessage(
			try CLIParser.parse(["resize", "deadbeef", "800", "99"]),
			"window height must be at least 100"
		)
		assertThrowsMessage(
			try CLIParser.parse(["resize", "deadbeef", "wide", "600"]),
			"expected integer, got wide"
		)
	}

	func testPositionalOpenNormalizesBrowserIdShape() throws {
		let newBrowser = try CLIParser.parse(["example.com"])
		XCTAssertEqual(newBrowser.request?.command, .open)
		XCTAssertNil(newBrowser.request?.browser)
		XCTAssertEqual(newBrowser.request?.url, "example.com")
		guard case .pageSummary = newBrowser.renderMode else {
			return XCTFail("expected summary rendering")
		}

		let existingBrowser = try CLIParser.parse(["deadbeef", "https://example.com"])
		XCTAssertEqual(existingBrowser.request?.browser, "deadbeef")
		XCTAssertEqual(existingBrowser.request?.url, "https://example.com")

		let waitForResources = try CLIParser.parse([
			"--wait-resources",
			"deadbeef",
			"https://example.com",
			"--resource-timeout=2.5",
		])
		XCTAssertEqual(waitForResources.request?.browser, "deadbeef")
		XCTAssertEqual(waitForResources.request?.waitForResources, true)
		XCTAssertEqual(waitForResources.request?.resourceTimeout, 2.5)

		let timeoutOnly = try CLIParser.parse([
			"example.com",
			"--resource-timeout",
			"1.25",
		])
		XCTAssertEqual(timeoutOnly.request?.waitForResources, true)
		XCTAssertEqual(timeoutOnly.request?.resourceTimeout, 1.25)

		let maxTimeout = try CLIParser.parse([
			"example.com",
			"--resource-timeout",
			String(Int(ResourceLoading.maxTimeout)),
		])
		XCTAssertEqual(maxTimeout.request?.waitForResources, true)
		XCTAssertEqual(maxTimeout.request?.resourceTimeout, ResourceLoading.maxTimeout)

		assertThrowsMessage(
			try CLIParser.parse(["not-an-id", "https://example.com"]), "unknown command not-an-id")
		assertThrowsMessage(try CLIParser.parse(["--bad"]), "unknown command --bad")
		assertThrowsMessage(
			try CLIParser.parse(["example.com", "--resource-timeout", "nope"]),
			"invalid resource timeout nope"
		)
		assertThrowsMessage(
			try CLIParser.parse(["example.com", "--resource-timeout", "-1"]),
			"invalid resource timeout -1"
		)
		assertThrowsMessage(
			try CLIParser.parse([
				"example.com",
				"--resource-timeout",
				String(Int(ResourceLoading.maxTimeout) + 1),
			]),
			"exceeds maximum 100"
		)
	}

	func testPageOptionsCanAppearBeforeBrowserId() throws {
		let invocation = try CLIParser.parse([
			"page",
			"--fields",
			"title,url,actions",
			"--action-details",
			"deadbeef",
		])

		XCTAssertEqual(invocation.request?.command, .page)
		XCTAssertEqual(invocation.request?.browser, "deadbeef")
		guard case .page(let options) = invocation.renderMode else {
			return XCTFail("expected page rendering")
		}
		XCTAssertTrue(options.includeActionDetails)
		XCTAssertTrue(options.includeActionSelectors)
		XCTAssertEqual(options.fields, [.title, .url, .actions])

		let legacyAliases = try CLIParser.parse([
			"page",
			"--fields",
			"images,imageCount",
			"deadbeef",
		])
		guard case .page(let legacyOptions) = legacyAliases.renderMode else {
			return XCTFail("expected page rendering")
		}
		XCTAssertEqual(legacyOptions.fields, [.resources, .resourceCount])
	}

	func testClickFillSubmitAndEvalCommands() throws {
		let clickAction = try CLIParser.parse(["click", "deadbeef", "3"])
		XCTAssertEqual(clickAction.request?.command, .click)
		XCTAssertEqual(clickAction.request?.action, "3")
		XCTAssertEqual(clickAction.request?.index, 3)

		let clickCoordinate = try CLIParser.parse(["click", "deadbeef", "12.5", "4"])
		XCTAssertEqual(clickCoordinate.request?.command, .coordinate)
		XCTAssertEqual(clickCoordinate.request?.coordinateAction, "click")
		XCTAssertEqual(clickCoordinate.request?.x, 12.5)
		XCTAssertEqual(clickCoordinate.request?.y, 4)

		let fill = try CLIParser.parse(["fill", "deadbeef", "search", "hello", "world"])
		XCTAssertEqual(fill.request?.command, .fill)
		XCTAssertEqual(fill.request?.action, "search")
		XCTAssertEqual(fill.request?.value, "hello world")

		let type = try CLIParser.parse([
			"type",
			"deadbeef",
			"search",
			"hello",
			"world",
			"--backend=native",
			"--rhythm=natural",
			"--speed",
			"3.5",
			"--delay-min=0.01",
			"--delay-max",
			"0.02",
		])
		XCTAssertEqual(type.request?.command, .typeText)
		XCTAssertEqual(type.request?.action, "search")
		XCTAssertEqual(type.request?.value, "hello world")
		XCTAssertEqual(type.request?.typingDelayMin, 0.01)
		XCTAssertEqual(type.request?.typingDelayMax, 0.02)
		XCTAssertEqual(type.request?.typingBackend, .native)
		XCTAssertEqual(type.request?.typingRhythm, .natural)
		XCTAssertEqual(type.request?.typingSpeed, 3.5)

		let typeAliasOptions = try CLIParser.parse([
			"type",
			"deadbeef",
			"search",
			"value",
			"--native",
			"--natural",
		])
		XCTAssertEqual(typeAliasOptions.request?.typingBackend, .native)
		XCTAssertEqual(typeAliasOptions.request?.typingRhythm, .natural)

		let typeMinOnly = try CLIParser.parse([
			"type",
			"deadbeef",
			"search",
			"value",
			"--delay-min",
			"0.2",
		])
		XCTAssertEqual(try typeMinOnly.request?.typingDelayRange(), TypingDelayRange(min: 0.2, max: 0.2))

		let typeSpeedEquals = try CLIParser.parse([
			"type",
			"deadbeef",
			"search",
			"value",
			"--speed=4",
		])
		XCTAssertEqual(typeSpeedEquals.request?.typingSpeed, 4)

		let submit = try CLIParser.parse(["submit", "deadbeef", "form-id"])
		XCTAssertEqual(submit.request?.command, .submit)
		XCTAssertEqual(submit.request?.action, "form-id")

		let evaluation = try CLIParser.parse(["eval", "deadbeef", "--body", "return 1"])
		XCTAssertEqual(evaluation.request?.command, .eval)
		XCTAssertEqual(evaluation.request?.script, "return 1")
		XCTAssertEqual(evaluation.request?.functionBody, true)
		guard case .value = evaluation.renderMode else {
			return XCTFail("expected value rendering")
		}

		assertThrowsMessage(
			try CLIParser.parse([
				"type",
				"deadbeef",
				"search",
				"value",
				"--delay-min",
				"0.2",
				"--delay-max",
				"0.1",
			]),
			"typing delay minimum must be less than or equal to maximum"
		)
		assertThrowsMessage(
			try CLIParser.parse([
				"type",
				"deadbeef",
				"search",
				"value",
				"--backend",
				"robot",
			]),
			"unknown typing backend robot"
		)
		assertThrowsMessage(
			try CLIParser.parse([
				"type",
				"deadbeef",
				"search",
				"value",
				"--rhythm",
				"robot",
			]),
			"unknown typing rhythm robot"
		)
		assertThrowsMessage(
			try CLIParser.parse([
				"type",
				"deadbeef",
				"search",
				"value",
				"--speed",
				"0",
			]),
			"invalid typing speed 0"
		)
	}

	func testCoordinateCommandsRejectInvalidNumbers() throws {
		let press = try CLIParser.parse(["press", "deadbeef", "1", "2"])
		XCTAssertEqual(press.request?.coordinateAction, "press")
		XCTAssertEqual(press.request?.x, 1)
		XCTAssertEqual(press.request?.y, 2)

		let scroll = try CLIParser.parse(["scroll", "deadbeef", "1", "2", "-3", "4.5"])
		XCTAssertEqual(scroll.request?.coordinateAction, "scroll")
		XCTAssertEqual(scroll.request?.deltaX, -3)
		XCTAssertEqual(scroll.request?.deltaY, 4.5)

		assertThrowsMessage(try CLIParser.parse(["drag", "deadbeef", "nan", "2"]), "expected number, got nan")
		assertThrowsMessage(
			try CLIParser.parse(["scroll", "deadbeef", "1", "2", "inf", "4"]), "expected number, got inf")
	}

	func testScreenshotAndDaemonCommands() throws {
		let bareScreenshot = try CLIParser.parse([
			"screenshot",
			"deadbeef",
			"shot.png",
		])
		XCTAssertEqual(bareScreenshot.request?.command, .screenshot)
		XCTAssertEqual(bareScreenshot.request?.browser, "deadbeef")
		XCTAssertTrue(bareScreenshot.request?.destinationPath?.hasSuffix("/shot.png") == true)
		XCTAssertEqual(bareScreenshot.request?.waitForResources, true)
		XCTAssertNil(bareScreenshot.request?.resourceTimeout)
		XCTAssertNil(bareScreenshot.request?.screenshotDelay)

		let screenshot = try CLIParser.parse([
			"screenshot",
			"deadbeef",
			"shot.PNG",
			"--resource-timeout",
			"4",
			"--capture-delay",
			"0.25",
		])
		XCTAssertEqual(screenshot.request?.command, .screenshot)
		XCTAssertEqual(screenshot.request?.browser, "deadbeef")
		XCTAssertTrue(screenshot.request?.destinationPath?.hasSuffix("/shot.PNG") == true)
		XCTAssertEqual(screenshot.request?.waitForResources, true)
		XCTAssertEqual(screenshot.request?.resourceTimeout, 4)
		XCTAssertEqual(screenshot.request?.screenshotDelay, 0.25)

		assertThrowsMessage(
			try CLIParser.parse(["screenshot", "deadbeef", "shot.gif"]),
			"screenshot destination must end in .png, .jpg, or .jpeg"
		)
		assertThrowsMessage(
			try CLIParser.parse(["screenshot", "deadbeef", "shot.png", "--capture-delay", "nope"]),
			"invalid screenshot capture delay nope"
		)
		assertThrowsMessage(
			try CLIParser.parse(["screenshot", "deadbeef", "shot.png", "--capture-delay", "-1"]),
			"invalid screenshot capture delay -1"
		)
		assertThrowsMessage(
			try CLIParser.parse([
				"screenshot",
				"deadbeef",
				"shot.png",
				"--capture-delay",
				String(Int(ScreenshotCapture.maxDelay) + 1),
			]),
			"exceeds maximum 10"
		)

		let daemonStart = try CLIParser.parse(["daemon", "start", "--idle-timeout=0.25"])
		XCTAssertEqual(daemonStart.request?.command, .ping)
		XCTAssertTrue(daemonStart.startDaemon)
		XCTAssertEqual(daemonStart.daemonIdleTimeout, 0.25)

		let daemonOff = try CLIParser.parse(["daemon", "start", "--idle-timeout", "off"])
		XCTAssertEqual(daemonOff.daemonIdleTimeout, 0)

		let daemonStop = try CLIParser.parse(["daemon", "stop"])
		XCTAssertEqual(daemonStop.request?.command, .daemonStop)
		XCTAssertFalse(daemonStop.startDaemon)
	}
}
