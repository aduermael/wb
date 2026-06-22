/// Verifies repository lint rules through in-memory Swift snippets so rule
/// behavior is covered without large fixture trees.
import Foundation
import XCTest
@testable import WBLintCore

final class LinterRuleTests: XCTestCase {
	func testRuleTitlesAndViolationSortingAreStable() {
		XCTAssertEqual(LintRule.fileDoc.title, "File doc comments")
		XCTAssertEqual(LintRule.parameters.sortOrder, LintRule.parameters.rawValue)

		let violations = [
			Violation(rule: .lineLength, path: "B.swift", line: 2, message: "b"),
			Violation(rule: .fileDoc, path: "B.swift", line: 2, message: "b"),
			Violation(rule: .fileDoc, path: "A.swift", line: 2, message: "b"),
			Violation(rule: .fileDoc, path: "A.swift", line: 1, message: "z"),
		].sorted()

		XCTAssertEqual(violations.map(\.rule), [.fileDoc, .fileDoc, .fileDoc, .lineLength])
		XCTAssertEqual(violations.map(\.path), ["A.swift", "A.swift", "B.swift", "B.swift"])
		XCTAssertEqual(violations.map(\.line), [1, 2, 2, 2])
	}

	func testFileDocCommentsSupportLineBlockAndPackageHeaderForms() {
		let lineDoc = """
			/// Valid docs
			import Foundation
			""" + "\n"
		XCTAssertTrue(lintSource(lineDoc).isEmpty)

		let blockDoc = """
			/** Valid docs */
			import Foundation
			""" + "\n"
		XCTAssertTrue(lintSource(blockDoc).isEmpty)

		let packageDoc = """
			// swift-tools-version: 6.2
			/// Valid docs
			import PackageDescription
			""" + "\n"
		XCTAssertTrue(lintSource(packageDoc, path: "Package.swift").isEmpty)
	}

	func testFileDocCommentsRejectMissingShortAndLongDocs() {
		let missing = lintSource("import Foundation\n")
		XCTAssertTrue(messages(for: missing, rule: .fileDoc)[0].contains("file must start"))

		let short = lintSource(
			"""
			/// Tiny
			import Foundation
			""")
		XCTAssertTrue(messages(for: short, rule: .fileDoc)[0].contains("too short"))

		let long = lintSource(
			"""
			/// This documentation comment is intentionally longer than eighty characters for testing.
			import Foundation
			""")
		XCTAssertTrue(messages(for: long, rule: .fileDoc)[0].contains("too long"))
	}

	func testLineRulesDetectEndingsWhitespaceLengthBlanksAndFileLength() {
		let longLine = "\tlet longValueName = \"\(String(repeating: "x", count: 90))\"\n"
		let source =
			"/// Valid docs\r\n\tlet value = 1 \n\n\n" + longLine
			+ "\tlet a = 1\n\tlet b = 2\n\tlet c = 3\n"
		let violations = lintSource(source)

		XCTAssertEqual(messages(for: violations, rule: .lineEndings), ["use LF line endings"])
		XCTAssertEqual(
			messages(for: violations, rule: .trailingWhitespace), ["trailing whitespace is not allowed"])
		XCTAssertEqual(
			messages(for: violations, rule: .blankLines),
			["multiple consecutive blank lines are not allowed"])
		XCTAssertEqual(messages(for: violations, rule: .fileLength), ["file has 7 lines; maximum is 6"])
		XCTAssertTrue(messages(for: violations, rule: .lineLength)[0].contains("maximum is 80"))
	}

	func testLineRulesIgnoreIndentationInsideCommentsAndStrings() {
		let source = """
			/// Valid docs
			//   comment indentation is ignored
			let value = "   string indentation is ignored"
			"""

		XCTAssertFalse(lintSource(source).contains { $0.rule == .indentation })
	}

	func testLineRulesDetectMissingFinalNewlineAndSpaceIndentation() {
		let source = """
			/// Valid docs
			  let value = 1
			"""
		let violations = lintSource(String(source.dropLast()))

		XCTAssertEqual(messages(for: violations, rule: .finalNewline), ["file must end with one newline"])
		XCTAssertEqual(messages(for: violations, rule: .indentation), ["indentation must use tabs, not spaces"])
	}

	func testImportRulesDetectUnsortedAndDuplicateImportsWithinBlocks() {
		let keyword = "import"
		let source = """
			/// Valid docs
			\(keyword) XCTest
			\(keyword) Foundation
			\(keyword) Foundation

			func ok() {}
			"""
		let violations = lintSource(source)
		let importMessages = messages(for: violations, rule: .imports)

		XCTAssertTrue(importMessages.contains("imports must be sorted alphabetically within each block"))
		XCTAssertTrue(importMessages.contains("duplicate import import Foundation"))
	}

	func testDeclarationRulesCountTopLevelParametersOnly() {
		let valid = """
			/// Valid docs
			func ok(_ a: (Int, Int), b: [String: (Int, Int)], c: () -> Void) {}
			init(_ value: Result<Int, Error>) {}
			""" + "\n"
		XCTAssertTrue(lintSource(valid).isEmpty)

		let invalid = """
			/// Valid docs
			func tooMany(_ a: Int, b: Int, c: Int, d: Int = 1) {}
			init(a: Int, b: Int, c: Int, d: Int) {}
			let functionName = "func ignored(a: Int, b: Int, c: Int, d: Int)"
			"""
		let violations = lintSource(invalid)

		XCTAssertEqual(
			messages(for: violations, rule: .parameters),
			[
				"function has 4 parameters; maximum is 3",
				"initializer has 4 parameters; maximum is 3",
			])
	}

	func testSwiftMaskerPreservesNewlinesAndMasksCommentsAndStrings() {
		let source = """
			func real(a: Int, b: Int, c: Int, d: Int) {}
			// func comment(a: Int, b: Int, c: Int, d: Int) {}
			let text = "func string(a: Int, b: Int, c: Int, d: Int)"
			/* func block(a: Int, b: Int, c: Int, d: Int) {} */
			"""
		let masked = SwiftMasker.mask(source)

		XCTAssertEqual(masked.filter { $0 == "\n" }.count, source.filter { $0 == "\n" }.count)
		XCTAssertTrue(masked.contains("func real"))
		XCTAssertFalse(masked.contains("func comment"))
		XCTAssertFalse(masked.contains("func string"))
		XCTAssertFalse(masked.contains("func block"))
	}
}
