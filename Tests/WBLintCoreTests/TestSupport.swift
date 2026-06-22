/// Provides small helpers for WBLintCore tests so rule assertions and temporary
/// fixture directories stay readable.
import Foundation
import XCTest
@testable import WBLintCore

let testLintConfiguration = LintConfiguration(
	maximumLineCount: 6,
	minimumFileDocCharacters: 10,
	maximumFileDocCharacters: 80,
	maximumFunctionParameters: 3,
	maximumLineLength: 80
)

func makeLinter(rootURL: URL? = nil) -> Linter {
	Linter(
		rootURL: rootURL ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
		configuration: testLintConfiguration
	)
}

func lintSource(_ text: String, path: String = "Test.swift") -> [Violation] {
	makeLinter().run(source: text, relativePath: path)
}

func messages(for violations: [Violation], rule: LintRule) -> [String] {
	violations
		.filter { $0.rule == rule }
		.map(\.message)
}

func assertLintThrowsMessage<T>(_ expression: @autoclosure () throws -> T, _ expectedMessage: String) {
	do {
		_ = try expression()
		XCTFail("expected error containing \(expectedMessage)")
	} catch {
		XCTAssertTrue(
			String(describing: error).contains(expectedMessage),
			"expected \(error) to contain \(expectedMessage)"
		)
	}
}

func withLintTemporaryDirectory(_ body: (URL) throws -> Void) throws {
	let directory = FileManager.default.temporaryDirectory
		.appendingPathComponent("wblint-tests-\(UUID().uuidString)", isDirectory: true)
	try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
	defer {
		try? FileManager.default.removeItem(at: directory)
	}
	try body(directory)
}

func writeFile(_ text: String, to url: URL) throws {
	try FileManager.default.createDirectory(
		at: url.deletingLastPathComponent(),
		withIntermediateDirectories: true
	)
	try text.write(to: url, atomically: true, encoding: .utf8)
}
