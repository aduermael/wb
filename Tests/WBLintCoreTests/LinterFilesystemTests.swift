/// Covers WBLintCore filesystem traversal, ignored directories, unreadable UTF-8
/// handling, missing paths, and command-runner status codes.
import Foundation
import XCTest
@testable import WBLintCore

final class LinterFilesystemTests: XCTestCase {
	func testRunDiscoversSwiftFilesAndIgnoresGeneratedDirectories() throws {
		try withLintTemporaryDirectory { root in
			try writeFile(validSwiftSource("A"), to: root.appendingPathComponent("Sources/A.swift"))
			try writeFile(validSwiftSource("B"), to: root.appendingPathComponent("Sources/Nested/B.swift"))
			try writeFile("not swift", to: root.appendingPathComponent("Sources/readme.txt"))
			try writeFile("bad", to: root.appendingPathComponent(".build/Ignored.swift"))
			try writeFile("bad", to: root.appendingPathComponent("dist/Ignored.swift"))

			let violations = try makeLinter(rootURL: root).run(paths: [root.path])
			XCTAssertTrue(violations.isEmpty)
		}
	}

	func testRunReturnsSortedViolationsFromSpecificPaths() throws {
		try withLintTemporaryDirectory { root in
			let b = root.appendingPathComponent("B.swift")
			let a = root.appendingPathComponent("A.swift")
			try writeFile("import Foundation\n", to: b)
			try writeFile("import Foundation\n", to: a)

			let violations = try makeLinter(rootURL: root).run(paths: [b.path, a.path])

			XCTAssertEqual(violations.map(\.path), ["A.swift", "B.swift"])
			XCTAssertEqual(violations.map(\.rule), [.fileDoc, .fileDoc])
		}
	}

	func testRunReportsMissingPathsAndInvalidUTF8() throws {
		try withLintTemporaryDirectory { root in
			assertLintThrowsMessage(
				try makeLinter(rootURL: root).run(paths: ["missing"]),
				"lint path does not exist: missing"
			)

			let invalid = root.appendingPathComponent("Invalid.swift")
			try Data([0xff, 0xfe]).write(to: invalid)

			let violations = try makeLinter(rootURL: root).run(paths: [invalid.path])
			XCTAssertEqual(violations.count, 1)
			XCTAssertEqual(violations[0].rule, .utf8)
			XCTAssertEqual(violations[0].message, "file must be valid UTF-8")
		}
	}

	func testCommandRunnerReturnsSuccessAndFailureCodes() throws {
		try withLintTemporaryDirectory { root in
			try writeFile(defaultValidSwiftSource(), to: root.appendingPathComponent("Valid.swift"))
			XCTAssertEqual(WBLintCommand.run(arguments: [root.path]), 0)

			try writeFile("import Foundation\n", to: root.appendingPathComponent("Invalid.swift"))
			XCTAssertEqual(WBLintCommand.run(arguments: [root.path]), 1)
		}
	}

	private func validSwiftSource(_ name: String) -> String {
		"""
		/// Valid docs for \(name)
		import Foundation
		""" + "\n"
	}

	private func defaultValidSwiftSource() -> String {
		"""
		/// Provides enough documentation to satisfy the repository default lint
		/// configuration in command-runner tests.
		import Foundation
		""" + "\n"
	}
}
