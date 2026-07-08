/// Controls whether browser pages load all resources or avoid heavyweight
/// payloads during headless automation.
import Foundation
import WebKit

enum BrowserResourceMode: String, Codable, Equatable, Sendable {
	case full
	case lean

	static let `default` = BrowserResourceMode.full

	static func parse(_ rawValue: String) throws -> BrowserResourceMode {
		switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
		case "full":
			return .full
		case "lean":
			return .lean
		default:
			throw WBError.message("unknown resource mode \(rawValue)")
		}
	}

	static func parseEnvironment(_ rawValue: String?) -> BrowserResourceMode? {
		guard let rawValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
			return nil
		}
		return try? parse(rawValue)
	}
}

@available(macOS 26.0, *)
@MainActor
struct BrowserResourceConfiguration {
	let mode: BrowserResourceMode
	let policy: BrowserResourcePolicy
}

@available(macOS 26.0, *)
@MainActor
struct BrowserResourcePolicy {
	let leanContentRuleList: WKContentRuleList?

	static func make() async -> BrowserResourcePolicy {
		let ruleList = await compileLeanContentRuleList()
		if ruleList == nil {
			daemonLog("lean resource content rule list unavailable; continuing without blocking")
		}
		return BrowserResourcePolicy(leanContentRuleList: ruleList)
	}

	func apply(to configuration: WebPage.Configuration, mode: BrowserResourceMode) -> WebPage.Configuration {
		guard mode == .lean, let leanContentRuleList else {
			return configuration
		}

		configuration.userContentController.add(leanContentRuleList)
		return configuration
	}

	private static let leanContentRuleListJSON = """
		[
		  {
		    "trigger": {
		      "url-filter": ".*",
		      "resource-type": ["image", "media", "font"]
		    },
		    "action": {
		      "type": "block"
		    }
		  }
		]
		"""

	private static func compileLeanContentRuleList() async -> WKContentRuleList? {
		await withCheckedContinuation { continuation in
			WKContentRuleListStore.default().compileContentRuleList(
				forIdentifier: "wb-lean-resource-mode-v1",
				encodedContentRuleList: leanContentRuleListJSON
			) { ruleList, error in
				if let error {
					daemonLog(
						"lean resource content rule list compile failed: \(error.localizedDescription)"
					)
				}
				continuation.resume(returning: ruleList)
			}
		}
	}
}
