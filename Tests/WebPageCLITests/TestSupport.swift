/// Provides small assertion and fixture helpers shared by WebPageCLI tests while
/// keeping individual test files focused on the behavior under test.
#if os(Linux)
	import Glibc
#else
	import Darwin
#endif
import Foundation
@testable import WebPageCLI

enum TestHarness {
	nonisolated(unsafe) private static var failures: [String] = []
	nonisolated(unsafe) private static var currentTest = ""

	static func run(_ name: String, _ body: () throws -> Void) {
		currentTest = name
		let failureCount = failures.count
		do {
			try body()
		} catch {
			record("threw \(error)")
		}

		if failures.count == failureCount {
			print("\(Terminal.green("✓")) \(name)")
		} else {
			print("\(Terminal.red("✗")) \(name)")
		}
	}

	static func record(_ message: String) {
		let prefix = currentTest.isEmpty ? "test failure" : currentTest
		let failure = "\(prefix): \(message)"
		failures.append(failure)
		FileHandle.standardError.write(Data("\(Terminal.red(failure))\n".utf8))
	}

	static func finish() {
		if failures.isEmpty {
			print("WebPageCLI tests passed")
			exit(0)
		}

		print("\(Terminal.red("WebPageCLI tests failed: \(failures.count)"))")
		exit(1)
	}
}

private enum Terminal {
	private static let reset = "\u{001B}[0m"

	static func green(_ text: String) -> String {
		color("32", text)
	}

	static func red(_ text: String) -> String {
		color("31", text)
	}

	private static func color(_ code: String, _ text: String) -> String {
		guard ProcessInfo.processInfo.environment["NO_COLOR"] == nil else {
			return text
		}
		return "\u{001B}[\(code)m\(text)\(reset)"
	}
}

func assertThrowsMessage<T>(_ expression: @autoclosure () throws -> T, _ expectedMessage: String) {
	do {
		_ = try expression()
		XCTFail("expected error containing \(expectedMessage)")
	} catch {
		XCTAssertTrue(
			error.localizedDescription.contains(expectedMessage),
			"expected \(error.localizedDescription) to contain \(expectedMessage)"
		)
	}
}

func XCTAssertEqual<T: Equatable>(
	_ actual: @autoclosure () throws -> T,
	_ expected: @autoclosure () throws -> T,
	_ message: @autoclosure () -> String = ""
) {
	do {
		let actualValue = try actual()
		let expectedValue = try expected()
		if actualValue != expectedValue {
			TestHarness.record("\(actualValue) is not equal to \(expectedValue) \(message())")
		}
	} catch {
		TestHarness.record("assert equal threw \(error) \(message())")
	}
}

func XCTAssertTrue(
	_ expression: @autoclosure () throws -> Bool,
	_ message: @autoclosure () -> String = ""
) {
	do {
		if try !expression() {
			TestHarness.record("expected true \(message())")
		}
	} catch {
		TestHarness.record("assert true threw \(error) \(message())")
	}
}

func XCTAssertFalse(
	_ expression: @autoclosure () throws -> Bool,
	_ message: @autoclosure () -> String = ""
) {
	do {
		if try expression() {
			TestHarness.record("expected false \(message())")
		}
	} catch {
		TestHarness.record("assert false threw \(error) \(message())")
	}
}

func XCTAssertNil<T>(
	_ expression: @autoclosure () throws -> T?,
	_ message: @autoclosure () -> String = ""
) {
	do {
		if try expression() != nil {
			TestHarness.record("expected nil \(message())")
		}
	} catch {
		TestHarness.record("assert nil threw \(error) \(message())")
	}
}

func XCTFail(_ message: String) {
	TestHarness.record(message)
}

func makePageSnapshot() -> PageSnapshot {
	PageSnapshot(
		browser: "deadbeef",
		state: PageSnapshotState(
			title: "Example",
			url: "https://example.com",
			loading: false,
			progress: 1
		),
		content: PageSnapshotContent(
			imageCount: 2,
			images: [
				BrowserImage(index: 1, url: "https://example.com/image.png", alt: "Example image"),
				BrowserImage(index: 2, url: "https://example.com/blank.png", alt: ""),
			],
			htmlBytes: 128,
			text: "Example text",
			actions: [
				BrowserAction(
					index: 1,
					id: "wkcli-1",
					kind: "click",
					tag: "a",
					type: "",
					text: "More",
					href: "https://example.com/more",
					disabled: false,
					selector: "a.more"
				),
				BrowserAction(
					index: 2,
					id: "wkcli-2",
					kind: "select",
					tag: "select",
					type: "",
					text: "Choice",
					href: "",
					disabled: true,
					selector: "select"
				),
			]
		)
	)
}

func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
	let directory = FileManager.default.temporaryDirectory
		.appendingPathComponent("wb-tests-\(UUID().uuidString)", isDirectory: true)
	try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
	defer {
		try? FileManager.default.removeItem(at: directory)
	}
	try body(directory)
}
