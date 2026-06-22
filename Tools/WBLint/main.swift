/// Provides the repository lint command used by local development and CI to
/// enforce consistent Swift source layout, required file summaries, line-count
/// limits, and compact function signatures without depending on macOS-only app
/// frameworks.
#if os(Linux)
import Glibc
#else
import Darwin
#endif
import Foundation

private let configuration = LintConfiguration(
	maximumLineCount: 1000,
	minimumFileDocCharacters: 80,
	maximumFileDocCharacters: 500,
	maximumFunctionParameters: 3,
	maximumLineLength: 120
)

private struct LintConfiguration {
	let maximumLineCount: Int
	let minimumFileDocCharacters: Int
	let maximumFileDocCharacters: Int
	let maximumFunctionParameters: Int
	let maximumLineLength: Int
}

private struct Violation: Comparable {
	let rule: LintRule
	let path: String
	let line: Int
	let message: String

	static func < (lhs: Violation, rhs: Violation) -> Bool {
		if lhs.rule != rhs.rule {
			return lhs.rule.sortOrder < rhs.rule.sortOrder
		}
		if lhs.path != rhs.path {
			return lhs.path < rhs.path
		}
		if lhs.line != rhs.line {
			return lhs.line < rhs.line
		}
		return lhs.message < rhs.message
	}
}

private enum LintRule: Int, CaseIterable {
	case utf8
	case fileDoc
	case lineEndings
	case finalNewline
	case fileLength
	case indentation
	case trailingWhitespace
	case lineLength
	case blankLines
	case imports
	case parameters

	var sortOrder: Int {
		rawValue
	}

	var title: String {
		switch self {
		case .utf8:
			return "UTF-8 source files"
		case .fileDoc:
			return "File doc comments"
		case .lineEndings:
			return "LF line endings"
		case .finalNewline:
			return "Final newline"
		case .fileLength:
			return "File length"
		case .indentation:
			return "Tab indentation"
		case .trailingWhitespace:
			return "No trailing whitespace"
		case .lineLength:
			return "Line length"
		case .blankLines:
			return "No repeated blank lines"
		case .imports:
			return "Sorted unique imports"
		case .parameters:
			return "Function parameter count"
		}
	}
}

private struct SourceFile {
	let url: URL
	let relativePath: String
	let text: String
	let lines: [String]
	let codeMask: String
}

private enum LintError: Error, CustomStringConvertible {
	case missingPath(String)
	case unreadableFile(String)

	var description: String {
		switch self {
		case .missingPath(let path):
			return "lint path does not exist: \(path)"
		case .unreadableFile(let path):
			return "file is not valid UTF-8: \(path)"
		}
	}
}

private struct Linter {
	let rootURL: URL
	let configuration: LintConfiguration

	func run(paths: [String]) throws -> [Violation] {
		let files = try swiftFiles(in: paths)
		var violations: [Violation] = []

		for fileURL in files {
			let relativePath = self.relativePath(for: fileURL)
			guard let text = String(data: try Data(contentsOf: fileURL), encoding: .utf8) else {
				violations.append(Violation(
					rule: .utf8,
					path: relativePath,
					line: 1,
					message: "file must be valid UTF-8"
				))
				continue
			}

			let file = SourceFile(
				url: fileURL,
				relativePath: relativePath,
				text: text,
				lines: text.components(separatedBy: "\n"),
				codeMask: SwiftMasker.mask(text)
			)
			violations.append(contentsOf: lint(file))
		}

		return violations.sorted()
	}

	private func lint(_ file: SourceFile) -> [Violation] {
		var violations: [Violation] = []

		violations.append(contentsOf: lintFileDoc(file))
		violations.append(contentsOf: lintLines(file))
		violations.append(contentsOf: lintImports(file))
		violations.append(contentsOf: lintDeclarations(file))

		return violations
	}

	private func lintFileDoc(_ file: SourceFile) -> [Violation] {
		let firstDocLine = firstDocLine(in: file)
		guard file.lines.count >= firstDocLine else {
			return [Violation(
				rule: .fileDoc,
				path: file.relativePath,
				line: 1,
				message: "file is empty"
			)]
		}

		let firstLine = file.lines[firstDocLine - 1]
		let docText: String?
		if firstLine.hasPrefix("///") {
			docText = lineDocText(file.lines.dropFirst(firstDocLine - 1))
		} else if firstLine.hasPrefix("/**") {
			docText = blockDocText(file.lines.dropFirst(firstDocLine - 1))
		} else {
			return [Violation(
				rule: .fileDoc,
				path: file.relativePath,
				line: firstDocLine,
				message: "file must start with a doc comment of " +
					"\(configuration.minimumFileDocCharacters)-" +
                    "\(configuration.maximumFileDocCharacters) characters"
			)]
		}

		let characterCount = docText?.count ?? 0
		if characterCount < configuration.minimumFileDocCharacters {
			return [Violation(
				rule: .fileDoc,
				path: file.relativePath,
				line: firstDocLine,
				message: "file doc comment is too short: \(characterCount) " +
                    "characters, minimum is \(configuration.minimumFileDocCharacters)"
			)]
		}
		if characterCount > configuration.maximumFileDocCharacters {
			return [Violation(
				rule: .fileDoc,
				path: file.relativePath,
				line: firstDocLine,
				message: "file doc comment is too long: \(characterCount) " +
                    "characters, maximum is \(configuration.maximumFileDocCharacters)"
			)]
		}

		return []
	}

	private func firstDocLine(in file: SourceFile) -> Int {
		let hasSwiftToolsHeader = file.url.lastPathComponent == "Package.swift" &&
			file.lines.first?.hasPrefix("// swift-tools-version:") == true
		return hasSwiftToolsHeader ? 2 : 1
	}

	private func lintLines(_ file: SourceFile) -> [Violation] {
		var violations: [Violation] = []
		let lineCount = file.text.hasSuffix("\n") ? file.lines.count - 1 : file.lines.count

		if file.text.contains("\r\n") || file.text.contains("\r") {
			violations.append(Violation(
				rule: .lineEndings,
				path: file.relativePath,
				line: 1,
				message: "use LF line endings"
			))
		}
		if !file.text.hasSuffix("\n") {
			violations.append(Violation(
				rule: .finalNewline,
				path: file.relativePath,
				line: lineCount,
				message: "file must end with one newline"
			))
		}
		if lineCount > configuration.maximumLineCount {
			violations.append(Violation(
				rule: .fileLength,
				path: file.relativePath,
				line: 1,
				message: "file has \(lineCount) lines; maximum is \(configuration.maximumLineCount)"
			))
		}

		var previousBlankLine = false
		let codeLines = file.codeMask.components(separatedBy: "\n")
		for (offset, line) in file.lines.prefix(lineCount).enumerated() {
			let lineNumber = offset + 1
			let codeLine = offset < codeLines.count ? codeLines[offset] : ""
			let codeTrimmed = codeLine.trimmingCharacters(in: .whitespaces)
			let indentation = line.prefix { $0 == " " || $0 == "\t" }
			if !codeTrimmed.isEmpty && indentation.contains(" ") {
				violations.append(Violation(
					rule: .indentation,
					path: file.relativePath,
					line: lineNumber,
					message: "indentation must use tabs, not spaces"
				))
			}
			if line.last?.isWhitespace == true {
				violations.append(Violation(
					rule: .trailingWhitespace,
					path: file.relativePath,
					line: lineNumber,
					message: "trailing whitespace is not allowed"
				))
			}
			if line.count > configuration.maximumLineLength {
				violations.append(Violation(
					rule: .lineLength,
					path: file.relativePath,
					line: lineNumber,
					message: "line has \(line.count) characters; maximum is \(configuration.maximumLineLength)"
				))
			}

			let isBlankLine = line.trimmingCharacters(in: .whitespaces).isEmpty
			if isBlankLine && previousBlankLine {
				violations.append(Violation(
					rule: .blankLines,
					path: file.relativePath,
					line: lineNumber,
					message: "multiple consecutive blank lines are not allowed"
				))
			}
			previousBlankLine = isBlankLine
		}

		return violations
	}

	private func lintImports(_ file: SourceFile) -> [Violation] {
		var violations: [Violation] = []
		var importBlocks: [[(line: Int, value: String)]] = []
		var currentBlock: [(line: Int, value: String)] = []

		for (offset, line) in file.lines.enumerated() {
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			if trimmed.hasPrefix("import ") {
				currentBlock.append((offset + 1, trimmed))
			} else if !currentBlock.isEmpty {
				importBlocks.append(currentBlock)
				currentBlock = []
			}
		}
		if !currentBlock.isEmpty {
			importBlocks.append(currentBlock)
		}

		for block in importBlocks {
			let imports = block.map(\.value)
			if imports != imports.sorted() {
				violations.append(Violation(
					rule: .imports,
					path: file.relativePath,
					line: block[0].line,
					message: "imports must be sorted alphabetically within each block"
				))
			}
			let duplicates = Set(imports.filter { value in imports.filter { $0 == value }.count > 1 })
			for duplicate in duplicates.sorted() {
				violations.append(Violation(
					rule: .imports,
					path: file.relativePath,
					line: block[0].line,
					message: "duplicate import \(duplicate)"
				))
			}
		}

		return violations
	}

	private func lintDeclarations(_ file: SourceFile) -> [Violation] {
		DeclarationScanner(
			file: file,
			configuration: configuration
		).violations()
	}

	private func swiftFiles(in paths: [String]) throws -> [URL] {
		var files: Set<URL> = []

		for path in paths {
			let url = URL(fileURLWithPath: path, relativeTo: rootURL).standardizedFileURL
			var isDirectory: ObjCBool = false
			guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
				throw LintError.missingPath(path)
			}

			if isDirectory.boolValue {
				for file in try swiftFiles(inDirectory: url) {
					files.insert(file)
				}
			} else if url.pathExtension == "swift" {
				files.insert(url)
			}
		}

		return files.sorted { relativePath(for: $0) < relativePath(for: $1) }
	}

	private func swiftFiles(inDirectory directoryURL: URL) throws -> [URL] {
		guard let enumerator = FileManager.default.enumerator(
			at: directoryURL,
			includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
			options: [.skipsPackageDescendants]
		) else {
			return []
		}

		var files: [URL] = []
		for case let fileURL as URL in enumerator {
			let name = fileURL.lastPathComponent
			if ignoredDirectoryNames.contains(name) {
				enumerator.skipDescendants()
				continue
			}

			let values = try fileURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
			if values.isDirectory == true {
				continue
			}
			if values.isRegularFile == true && fileURL.pathExtension == "swift" {
				files.append(fileURL.standardizedFileURL)
			}
		}
		return files
	}

	private func relativePath(for url: URL) -> String {
		let path = url.standardizedFileURL.path
		let rootPath = rootURL.standardizedFileURL.path
		guard path.hasPrefix(rootPath + "/") else {
			return path
		}
		return String(path.dropFirst(rootPath.count + 1))
	}
}

private let ignoredDirectoryNames: Set<String> = [
	".build",
	".git",
	".swiftpm",
	".wb",
	"DerivedData",
    "dist"
]

private func lineDocText(_ lines: ArraySlice<String>) -> String {
	lines
		.prefix { $0.hasPrefix("///") }
		.map { line in
			String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
		}
		.joined(separator: " ")
		.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func blockDocText(_ lines: ArraySlice<String>) -> String {
	var parts: [String] = []
	for line in lines {
		let cleaned = line
			.replacingOccurrences(of: "/**", with: "")
			.replacingOccurrences(of: "*/", with: "")
			.trimmingCharacters(in: .whitespaces)
		parts.append(cleaned)
		if line.contains("*/") {
			break
		}
	}
	return parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
}

private struct DeclarationScanner {
	let file: SourceFile
	let configuration: LintConfiguration

	func violations() -> [Violation] {
		let characters = Array(file.codeMask)
		var violations: [Violation] = []
		var index = characters.startIndex

		while index < characters.endIndex {
			if matchesKeyword("func", at: index, in: characters) {
				if let violation = lintCallable(kind: "function", keywordStart: index, in: characters) {
					violations.append(violation)
				}
				index = characters.index(index, offsetBy: 4)
			} else if matchesKeyword("init", at: index, in: characters) {
				if let violation = lintCallable(kind: "initializer", keywordStart: index, in: characters) {
					violations.append(violation)
				}
				index = characters.index(index, offsetBy: 4)
			} else {
				characters.formIndex(after: &index)
			}
		}

		return violations
	}

	private func lintCallable(kind: String, keywordStart: Int, in characters: [Character]) -> Violation? {
		guard let openParen = declarationOpenParen(after: keywordStart, in: characters),
				let closeParen = matchingCloseParen(from: openParen, in: characters) else {
			return nil
		}

		let parameterCount = countParameters(from: openParen + 1, to: closeParen, in: characters)
		guard parameterCount > configuration.maximumFunctionParameters else {
			return nil
		}

		return Violation(
			rule: .parameters,
			path: file.relativePath,
			line: lineNumber(at: keywordStart, in: characters),
			message: "\(kind) has \(parameterCount) parameters; maximum is \(configuration.maximumFunctionParameters)"
		)
	}

	private func declarationOpenParen(after keywordStart: Int, in characters: [Character]) -> Int? {
		var index = keywordStart
		var angleDepth = 0
		while index < characters.count {
			let character = characters[index]
			if character == "(" && angleDepth == 0 {
				return index
			}
			if character == "\n" || character == "{" || character == "=" {
				return nil
			}
			if character == "<" {
				angleDepth += 1
			} else if character == ">" && angleDepth > 0 {
				angleDepth -= 1
			}
			index += 1
		}
		return nil
	}

	private func matchingCloseParen(from openParen: Int, in characters: [Character]) -> Int? {
		var depth = 0
		var index = openParen
		while index < characters.count {
			if characters[index] == "(" {
				depth += 1
			} else if characters[index] == ")" {
				depth -= 1
				if depth == 0 {
					return index
				}
			}
			index += 1
		}
		return nil
	}

	private func countParameters(from start: Int, to end: Int, in characters: [Character]) -> Int {
		var index = start
		var nestingDepth = 0
		var hasParameterContent = false
		var parameterCount = 0

		while index < end {
			let character = characters[index]
			if character == "," && nestingDepth == 0 {
				parameterCount += 1
				hasParameterContent = false
			} else {
				if character == "(" || character == "[" || character == "<" {
					nestingDepth += 1
				} else if (character == ")" || character == "]" || character == ">") && nestingDepth > 0 {
					nestingDepth -= 1
				}
				if !character.isWhitespace {
					hasParameterContent = true
				}
			}
			index += 1
		}

		return hasParameterContent ? parameterCount + 1 : parameterCount
	}

	private func lineNumber(at target: Int, in characters: [Character]) -> Int {
		var line = 1
		for index in characters.indices where index < target {
			if characters[index] == "\n" {
				line += 1
			}
		}
		return line
	}

	private func matchesKeyword(_ keyword: String, at index: Int, in characters: [Character]) -> Bool {
		let keywordCharacters = Array(keyword)
		guard index + keywordCharacters.count <= characters.count else {
			return false
		}
		for offset in keywordCharacters.indices where characters[index + offset] != keywordCharacters[offset] {
			return false
		}

		let before = index > 0 ? characters[index - 1] : " "
		let afterIndex = index + keywordCharacters.count
		let after = afterIndex < characters.count ? characters[afterIndex] : " "
		return !isIdentifierCharacter(before) && !isIdentifierCharacter(after)
	}

	private func isIdentifierCharacter(_ character: Character) -> Bool {
		character == "_" || character.isLetter || character.isNumber
	}
}

private enum SwiftMasker {
	static func mask(_ text: String) -> String {
		let characters = Array(text)
		var output = Array(repeating: Character(" "), count: characters.count)
		var index = 0

		while index < characters.count {
			if characters[index] == "\n" {
				output[index] = "\n"
				index += 1
				continue
			}
			if starts(with: "//", at: index, in: characters) {
				index = copyLineComment(from: index, characters: characters, output: &output)
				continue
			}
			if starts(with: "/*", at: index, in: characters) {
				index = copyBlockComment(from: index, characters: characters, output: &output)
				continue
			}
			if startsStringLiteral(at: index, in: characters) {
				index = copyStringLiteral(from: index, characters: characters, output: &output)
				continue
			}

			output[index] = characters[index]
			index += 1
		}

		return String(output)
	}

	private static func copyLineComment(
		from start: Int,
		characters: [Character],
		output: inout [Character]
	) -> Int {
		var index = start
		while index < characters.count {
			if characters[index] == "\n" {
				output[index] = "\n"
				return index + 1
			}
			index += 1
		}
		return index
	}

	private static func copyBlockComment(
		from start: Int,
		characters: [Character],
		output: inout [Character]
	) -> Int {
		var index = start
		var depth = 0
		while index < characters.count {
			if characters[index] == "\n" {
				output[index] = "\n"
			}
			if starts(with: "/*", at: index, in: characters) {
				depth += 1
				index += 2
				continue
			}
			if starts(with: "*/", at: index, in: characters) {
				depth -= 1
				index += 2
				if depth == 0 {
					return index
				}
				continue
			}
			index += 1
		}
		return index
	}

	private static func copyStringLiteral(
		from start: Int,
		characters: [Character],
		output: inout [Character]
	) -> Int {
		let delimiterCount = rawDelimiterCount(at: start, in: characters)
		let quoteIndex = start + delimiterCount
		let isMultiline = starts(with: "\"\"\"", at: quoteIndex, in: characters)
		var index = quoteIndex + (isMultiline ? 3 : 1)

		while index < characters.count {
			if characters[index] == "\n" {
				output[index] = "\n"
			}
			if isMultiline {
				let closingDelimiter = "\"\"\"" + String(repeating: "#", count: delimiterCount)
				if starts(with: closingDelimiter, at: index, in: characters) {
					return index + 3 + delimiterCount
				}
			} else if delimiterCount > 0 {
				let closingDelimiter = "\"" + String(repeating: "#", count: delimiterCount)
				if starts(with: closingDelimiter, at: index, in: characters) {
					return index + 1 + delimiterCount
				}
			} else if characters[index] == "\"" && !isEscapedQuote(at: index, in: characters) {
				return index + 1
			}
			index += 1
		}

		return index
	}

	private static func rawDelimiterCount(at start: Int, in characters: [Character]) -> Int {
		var index = start
		var count = 0
		while index < characters.count && characters[index] == "#" {
			count += 1
			index += 1
		}
		return count
	}

	private static func isEscapedQuote(at index: Int, in characters: [Character]) -> Bool {
		guard index > 0 else {
			return false
		}

		var slashCount = 0
		var slashIndex = index - 1
		while slashIndex >= 0 && characters[slashIndex] == "\\" {
			slashCount += 1
			slashIndex -= 1
		}
		return !slashCount.isMultiple(of: 2)
	}

	private static func startsStringLiteral(at index: Int, in characters: [Character]) -> Bool {
		let delimiterCount = rawDelimiterCount(at: index, in: characters)
		let quoteIndex = index + delimiterCount
		return quoteIndex < characters.count && characters[quoteIndex] == "\""
	}

	private static func starts(with string: String, at index: Int, in characters: [Character]) -> Bool {
		let pattern = Array(string)
		guard index + pattern.count <= characters.count else {
			return false
		}
		for offset in pattern.indices where characters[index + offset] != pattern[offset] {
			return false
		}
		return true
	}
}

let arguments = Array(CommandLine.arguments.dropFirst())
private let rootURL = arguments.first.map {
	URL(fileURLWithPath: $0).standardizedFileURL
} ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).standardizedFileURL
let paths = arguments.isEmpty ? [rootURL.path] : arguments

do {
	let violations = try Linter(rootURL: rootURL, configuration: configuration).run(paths: paths)
	LintReport(violations: violations).print()
	if violations.isEmpty {
		exit(0)
	} else {
		throw ExitCode.failure
	}
} catch let exitCode as ExitCode {
	exit(exitCode.rawValue)
} catch {
	fputs("lint failed: \(error)\n", stderr)
	exit(1)
}

private struct ExitCode: Error {
	let rawValue: Int32

	static let failure = ExitCode(rawValue: 1)
}

private struct LintReport {
	let violations: [Violation]

	func print() {
		let violationsByRule = Dictionary(grouping: violations, by: \.rule)

		for rule in LintRule.allCases {
			let ruleViolations = violationsByRule[rule, default: []].sorted()
			if ruleViolations.isEmpty {
				Swift.print("\(Terminal.green("✓")) \(rule.title)")
			} else {
				Swift.print("\(Terminal.red("✗")) \(rule.title)")
				for violation in ruleViolations {
					Swift.print("  \(violation.path):\(violation.line): \(violation.message)")
				}
			}
		}
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
