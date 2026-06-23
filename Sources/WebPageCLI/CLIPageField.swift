/// Defines the filterable page-output fields accepted by the CLI parser and
/// renderer, keeping field validation shared across help text, option parsing,
/// and JSON encoding.
import Foundation

enum PageField: String, CaseIterable, Hashable {
	case actions
	case browser
	case htmlBytes
	case jsonBytes
	case loading
	case progress
	case resourceCount
	case resources
	case resourcesLoading
	case text
	case title
	case url

	static var validList: String {
		allCases.map(\.rawValue).joined(separator: ",")
	}

	static func parseList(_ rawValue: String) throws -> Set<PageField> {
		let names =
			rawValue
			.split(separator: ",")
			.map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
			.filter { !$0.isEmpty }

		guard !names.isEmpty else {
			throw WBError.message("--fields requires at least one field")
		}

		var fields: Set<PageField> = []
		for name in names {
			guard let field = PageField(rawValue: name) else {
				throw WBError.message("unknown page field \(name); valid fields: \(validList)")
			}
			fields.insert(field)
		}
		return fields
	}
}
