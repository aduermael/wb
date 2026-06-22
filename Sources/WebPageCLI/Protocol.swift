/// Defines the JSON wire protocol shared by the CLI process and daemon,
/// including request validation helpers, compact response models, and page
/// snapshot payloads.
import Foundation

enum WireProtocol {
	static let version = 29
}

enum WireCommand: String, Codable, Equatable, Sendable {
	case ping
	case browserCreate
	case browserList
	case browserClose
	case browserShow
	case browserHide
	case open
	case page
	case click
	case fill
	case submit
	case eval
	case screenshot
	case coordinate
	case daemonStop
}

struct WireRequest: Codable, Sendable {
	var command: WireCommand
	var browser: String? = nil
	var url: String? = nil
	var script: String? = nil
	var functionBody: Bool? = nil
	var action: String? = nil
	var index: Int? = nil
	var value: String? = nil
	var destinationPath: String? = nil
	var coordinateAction: String? = nil
	var x: Double? = nil
	var y: Double? = nil
	var deltaX: Double? = nil
	var deltaY: Double? = nil

	init(command: WireCommand) {
		self.command = command
	}

	func withBrowser(_ browser: String?) -> WireRequest {
		var request = self
		request.browser = browser
		return request
	}

	func withURL(_ url: String?) -> WireRequest {
		var request = self
		request.url = url
		return request
	}

	func withScript(_ script: String, functionBody: Bool?) -> WireRequest {
		var request = self
		request.script = script
		request.functionBody = functionBody
		return request
	}

	func withAction(_ action: String) -> WireRequest {
		var request = self
		request.action = action
		request.index = Int(action)
		return request
	}

	func withValue(_ value: String) -> WireRequest {
		var request = self
		request.value = value
		return request
	}

	func withDestinationPath(_ path: String) -> WireRequest {
		var request = self
		request.destinationPath = path
		return request
	}

	func withCoordinate(_ action: String, point: WirePoint, delta: WireDelta? = nil) -> WireRequest {
		var request = self
		request.coordinateAction = action
		request.x = point.x
		request.y = point.y
		request.deltaX = delta?.x
		request.deltaY = delta?.y
		return request
	}

	func requiredBrowserID() throws -> String {
		try browser.nilIfEmpty.unwrap("missing browser id")
	}

	func requiredURL() throws -> URL {
		let rawURL = try url.nilIfEmpty.unwrap("missing URL")
		let normalized = rawURL.contains("://") ? rawURL : "https://\(rawURL)"
		guard let url = URL(string: normalized) else {
			throw WBError.message("invalid URL: \(rawURL)")
		}
		return url
	}

	func requiredScript() throws -> String {
		try script.nilIfEmpty.unwrap("missing JavaScript")
	}

	func requiredAction() throws -> String {
		if let action = action.nilIfEmpty {
			return action
		}
		if let index {
			return String(index)
		}
		throw WBError.message("missing action number or ID")
	}

	func requiredValue() throws -> String {
		try value.unwrap("missing value")
	}

	func requiredDestinationPath() throws -> String {
		try destinationPath.nilIfEmpty.unwrap("missing destination path")
	}

	func requiredCoordinateAction() throws -> String {
		try coordinateAction.nilIfEmpty.unwrap("missing coordinate action")
	}

	func requiredX() throws -> Double {
		try x.unwrap("missing x coordinate")
	}

	func requiredY() throws -> Double {
		try y.unwrap("missing y coordinate")
	}

	func requiredDeltaX() throws -> Double {
		try deltaX.unwrap("missing x scroll delta")
	}

	func requiredDeltaY() throws -> Double {
		try deltaY.unwrap("missing y scroll delta")
	}
}

struct WirePoint: Sendable {
	let x: Double
	let y: Double
}

struct WireDelta: Sendable {
	let x: Double
	let y: Double
}

struct WireResponse: Codable, Sendable {
	var protocolVersion: Int?
	var ok: Bool
	var browser: String?
	var browsers: [BrowserSummary]?
	var environment: WBEnvironmentMetadata?
	var page: PageSnapshot?
	var value: String?
	var message: String?
	var error: String?
	var url: String?

	static func success() -> WireResponse {
		WireResponse(
			protocolVersion: WireProtocol.version,
			ok: true,
			browser: nil,
			browsers: nil,
			environment: nil,
			page: nil,
			value: nil,
			message: nil,
			error: nil,
			url: nil
		)
	}

	static func failure(_ message: String) -> WireResponse {
		WireResponse(
			protocolVersion: WireProtocol.version,
			ok: false,
			browser: nil,
			browsers: nil,
			environment: nil,
			page: nil,
			value: nil,
			message: nil,
			error: message,
			url: nil
		)
	}

	func withBrowser(_ browser: String?) -> WireResponse {
		var response = self
		response.browser = browser
		return response
	}

	func withBrowsers(_ browsers: [BrowserSummary]) -> WireResponse {
		var response = self
		response.browsers = browsers
		return response
	}

	func withEnvironment(_ environment: WBEnvironmentMetadata?) -> WireResponse {
		var response = self
		response.environment = environment
		return response
	}

	func withPage(_ page: PageSnapshot?) -> WireResponse {
		var response = self
		response.page = page
		return response
	}

	func withValue(_ value: String?) -> WireResponse {
		var response = self
		response.value = value
		return response
	}

	func withMessage(_ message: String?) -> WireResponse {
		var response = self
		response.message = message
		return response
	}

	func withURL(_ url: String?) -> WireResponse {
		var response = self
		response.url = url
		return response
	}
}

struct BrowserSummary: Codable, Sendable {
	let browser: String
	let title: String?
	let url: String?
	let loading: Bool
	let progress: Double
	let actions: Int
	let visible: Bool?
	let createdAt: String
	let updatedAt: String
	let dumped: Bool?
	let dumpedAt: String?
}

struct PageSnapshot: Codable, Sendable {
	let browser: String
	let title: String
	let url: String?
	let loading: Bool
	let progress: Double
	let imageCount: Int?
	let images: [BrowserImage]
	let htmlBytes: Int?
	let text: String?
	let actions: [BrowserAction]

	init(browser: String, state: PageSnapshotState, content: PageSnapshotContent) {
		self.browser = browser
		title = state.title
		url = state.url
		loading = state.loading
		progress = state.progress
		imageCount = content.imageCount
		images = content.images
		htmlBytes = content.htmlBytes
		text = content.text
		actions = content.actions
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)

		browser = try container.decode(String.self, forKey: .browser)
		title = try container.decode(String.self, forKey: .title)
		url = try container.decodeIfPresent(String.self, forKey: .url)
		loading = try container.decode(Bool.self, forKey: .loading)
		progress = try container.decode(Double.self, forKey: .progress)
		htmlBytes = try container.decodeIfPresent(Int.self, forKey: .htmlBytes)
		text = try container.decodeIfPresent(String.self, forKey: .text)
		actions = try container.decode([BrowserAction].self, forKey: .actions)

		if let decodedImages = try? container.decode([BrowserImage].self, forKey: .images) {
			images = decodedImages
			imageCount = try container.decodeIfPresent(Int.self, forKey: .imageCount) ?? decodedImages.count
		} else {
			let legacyImageCount = try container.decodeIfPresent(Int.self, forKey: .images)
			images = []
			imageCount = try container.decodeIfPresent(Int.self, forKey: .imageCount) ?? legacyImageCount
		}
	}

	func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)

		try container.encode(browser, forKey: .browser)
		try container.encode(title, forKey: .title)
		try container.encodeIfPresent(url, forKey: .url)
		try container.encode(loading, forKey: .loading)
		try container.encode(progress, forKey: .progress)
		try container.encodeIfPresent(imageCount, forKey: .imageCount)
		try container.encode(images, forKey: .images)
		try container.encodeIfPresent(htmlBytes, forKey: .htmlBytes)
		try container.encodeIfPresent(text, forKey: .text)
		try container.encode(actions, forKey: .actions)
	}

	private enum CodingKeys: String, CodingKey {
		case actions
		case browser
		case htmlBytes
		case imageCount
		case images
		case loading
		case progress
		case text
		case title
		case url
	}
}

struct PageSnapshotState: Sendable {
	let title: String
	let url: String?
	let loading: Bool
	let progress: Double
}

struct PageSnapshotContent: Sendable {
	let imageCount: Int?
	let images: [BrowserImage]
	let htmlBytes: Int?
	let text: String?
	let actions: [BrowserAction]
}

struct BrowserImage: Codable, Sendable {
	let index: Int
	let url: String
	let alt: String?
}

struct BrowserAction: Codable, Sendable {
	let index: Int
	let id: String
	let kind: String
	let tag: String
	let type: String
	let text: String
	let href: String
	let disabled: Bool
	let selector: String?
}

enum WireCodec {
	static func encode<T: Encodable>(_ value: T) throws -> Data {
		try JSONEncoder().encode(value)
	}

	static func encodeError(_ message: String) -> Data {
		(try? encode(WireResponse.failure(message))) ?? Data()
	}
}
