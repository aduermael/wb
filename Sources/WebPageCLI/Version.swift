/// Stores build metadata used by update checks. Release packaging rewrites this
/// value temporarily so shipped binaries can compare themselves to GitHub tags.
import Foundation

enum WBVersion {
	static let current = "dev"

	static var isReleaseBuild: Bool {
		normalizedTag(current) != nil
	}

	static var currentTag: String? {
		normalizedTag(current)
	}

	static func normalizedTag(_ version: String) -> String? {
		let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty, trimmed != "dev" else {
			return nil
		}
		return trimmed.hasPrefix("v") ? trimmed : "v\(trimmed)"
	}
}
