/// Provides small assertion and fixture helpers shared by WebPageCLI tests while
/// keeping individual test files focused on the behavior under test.
import Foundation
import XCTest
@testable import WebPageCLI

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
