/// Covers command-line parsing for every deterministic command shape before
/// requests are handed to the daemon or macOS browser runtime.
import Foundation
import XCTest
@testable import WebPageCLI

final class CLIParserTests: XCTestCase {
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

		assertThrowsMessage(
			try CLIParser.parse(["not-an-id", "https://example.com"]), "unknown command not-an-id")
		assertThrowsMessage(try CLIParser.parse(["--bad"]), "unknown command --bad")
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
		let screenshot = try CLIParser.parse(["screenshot", "deadbeef", "shot.PNG"])
		XCTAssertEqual(screenshot.request?.command, .screenshot)
		XCTAssertEqual(screenshot.request?.browser, "deadbeef")
		XCTAssertTrue(screenshot.request?.destinationPath?.hasSuffix("/shot.PNG") == true)

		assertThrowsMessage(
			try CLIParser.parse(["screenshot", "deadbeef", "shot.gif"]),
			"screenshot destination must end in .png, .jpg, or .jpeg"
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
