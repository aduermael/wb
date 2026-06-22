/// Exercises environment metadata, idle-timeout parsing, browser dump summaries,
/// and session persistence in isolated temporary directories.
import Foundation
@testable import WebPageCLI

struct SessionStoreTests {

	func testIdleTimeoutParsing() {
		XCTAssertNil(WBConfig.parseIdleTimeout(nil))
		XCTAssertNil(WBConfig.parseIdleTimeout(""))
		XCTAssertNil(WBConfig.parseIdleTimeout("abc"))
		XCTAssertNil(WBConfig.parseIdleTimeout("-1"))
		XCTAssertEqual(WBConfig.parseIdleTimeout(" off "), 0)
		XCTAssertEqual(WBConfig.parseIdleTimeout("1.5"), 1.5)
	}

	func testEnvironmentLoadOrCreatePersistsStableMetadata() throws {
		try withTemporaryDirectory { directory in
			let environment = try WBEnvironment.loadOrCreate(in: directory)
			let reloaded = try WBEnvironment.loadOrCreate(in: directory)

			XCTAssertEqual(environment.uuid, reloaded.uuid)
			XCTAssertEqual(environment.metadata.directory, directory.path)
			XCTAssertEqual(environment.metadata.sessionsDirectory, "sessions")
			XCTAssertEqual(environment.metadata.uuid, environment.uuid.uuidString.lowercased())
		}
	}

	func testSessionStoreSaveLoadListAndDelete() throws {
		try withTemporaryDirectory { directory in
			let store = SessionStore(directory: directory)
			let first = makeDump(browser: "0000000a", title: "A")
			let second = makeDump(browser: "0000000b", title: "B")

			try store.save(second)
			try store.save(first)
			try Data("{}".utf8).write(to: directory.appendingPathComponent("not-valid.json"))

			XCTAssertTrue(store.exists("0000000a"))
			XCTAssertFalse(store.exists("notvalid"))
			XCTAssertEqual(store.browserIDs(), ["0000000a", "0000000b"])
			XCTAssertEqual(try store.load("0000000a").title, "A")
			XCTAssertEqual(
				try store.load("0000000a").windowSize,
				BrowserWindowSize(width: 1000, height: 800)
			)
			XCTAssertEqual(try store.dumps().map(\.browser), ["0000000a", "0000000b"])

			try store.delete("0000000a")
			XCTAssertFalse(store.exists("0000000a"))
			XCTAssertEqual(store.browserIDs(), ["0000000b"])
		}
	}

	func testSessionStoreRejectsBadBrowserIdsAndMismatchedDumps() throws {
		try withTemporaryDirectory { directory in
			let store = SessionStore(directory: directory)
			assertThrowsMessage(try store.load("bad"), "invalid browser id bad")

			let mismatch = makeDump(browser: "0000000a", title: "A")
			let data = try JSONEncoder().encode(mismatch)
			try data.write(to: directory.appendingPathComponent("0000000b.json"))

			assertThrowsMessage(try store.load("0000000b"), "browser id mismatch in session 0000000b")
		}
	}

	func testBrowserDumpSummaryUsesSnapshotFallbacksAndDates() {
		let dump = BrowserDump(
			schemaVersion: 1,
			browser: "0000000a",
			title: nil,
			url: nil,
			loading: true,
			progress: 0.5,
			actions: 9,
			createdAt: "2024-01-01T00:00:00Z",
			updatedAt: "bad date",
			dumpedAt: "2024-01-01T00:00:01Z",
			snapshot: makePageSnapshot()
		)

		let summary = dump.summary()
		XCTAssertEqual(summary.title, "Example")
		XCTAssertEqual(summary.url, "https://example.com")
		XCTAssertEqual(summary.actions, 2)
		XCTAssertEqual(summary.dumped, true)
		XCTAssertEqual(summary.dumpedAt, "2024-01-01T00:00:01Z")
		XCTAssertEqual(dump.createdDate.iso8601String, "2024-01-01T00:00:00Z")
		XCTAssertEqual(dump.updatedDate.iso8601String, "2024-01-01T00:00:00Z")
	}

	private func makeDump(browser: String, title: String) -> BrowserDump {
		BrowserDump(
			schemaVersion: 1,
			browser: browser,
			title: title,
			url: "https://example.com/\(browser)",
			loading: false,
			progress: 1,
			actions: 1,
			createdAt: "2024-01-01T00:00:00Z",
			updatedAt: "2024-01-01T00:00:01Z",
			dumpedAt: "2024-01-01T00:00:02Z",
			snapshot: nil,
			windowWidth: 1000,
			windowHeight: 800
		)
	}
}
