/// Defines the JSON wire protocol shared by the CLI process and daemon,
/// including request validation helpers, compact response models, and page
/// snapshot payloads.
import Foundation

enum WireProtocol {
	static let version = 37
}

enum DaemonTiming {
	static let commandResponseTimeout: TimeInterval = 120
}

enum ResourceLoading {
	static let defaultTimeout: TimeInterval = 8
	static let quietWindow: TimeInterval = 0.35
	static let responseTimeoutHeadroom: TimeInterval = 20
	static let maxTimeout = DaemonTiming.commandResponseTimeout - responseTimeoutHeadroom

	static func parseTimeout(_ rawValue: String) throws -> TimeInterval {
		guard let timeout = TimeInterval(rawValue) else {
			throw WBError.message("invalid resource timeout \(rawValue)")
		}
		return try validateTimeout(timeout, rawValue: rawValue)
	}

	static func validateTimeout(_ timeout: TimeInterval, rawValue: String? = nil) throws -> TimeInterval {
		let renderedValue = rawValue ?? String(timeout)
		guard timeout.isFinite && timeout >= 0 else {
			throw WBError.message("invalid resource timeout \(renderedValue)")
		}
		guard timeout <= maxTimeout else {
			throw WBError.message(
				"resource timeout \(renderedValue) exceeds maximum \(Int(maxTimeout))"
			)
		}
		return timeout
	}
}

enum InteractionSettling {
	static let defaultTimeout: TimeInterval = 2
	static let quietWindow: TimeInterval = 0.5
	static let pollIntervalNanoseconds: UInt64 = 75_000_000
}

enum ScreenshotCapture {
	static let defaultDelay: TimeInterval = 0.3
	static let maxDelay: TimeInterval = 10

	static func parseDelay(_ rawValue: String) throws -> TimeInterval {
		guard let delay = TimeInterval(rawValue) else {
			throw WBError.message("invalid screenshot capture delay \(rawValue)")
		}
		return try validateDelay(delay, rawValue: rawValue)
	}

	static func validateDelay(_ delay: TimeInterval, rawValue: String? = nil) throws -> TimeInterval {
		let renderedValue = rawValue ?? String(delay)
		guard delay.isFinite && delay >= 0 else {
			throw WBError.message("invalid screenshot capture delay \(renderedValue)")
		}
		guard delay <= maxDelay else {
			throw WBError.message(
				"screenshot capture delay \(renderedValue) exceeds maximum \(Int(maxDelay))"
			)
		}
		return delay
	}
}

enum TypingDelay {
	static let defaultMin: TimeInterval = 0.03
	static let defaultMax: TimeInterval = 0.12
	static let maxDelay: TimeInterval = 5

	static func parse(_ rawValue: String) throws -> TimeInterval {
		guard let delay = TimeInterval(rawValue) else {
			throw WBError.message("invalid typing delay \(rawValue)")
		}
		return try validateSingle(delay, rawValue: rawValue)
	}

	static func validateSingle(_ delay: TimeInterval, rawValue: String? = nil) throws
		-> TimeInterval
	{
		let renderedValue = rawValue ?? String(delay)
		guard delay.isFinite && delay >= 0 else {
			throw WBError.message("invalid typing delay \(renderedValue)")
		}
		guard delay <= maxDelay else {
			throw WBError.message(
				"typing delay \(renderedValue) exceeds maximum \(Int(maxDelay))"
			)
		}
		return delay
	}

	static func validateRange(min: TimeInterval, max: TimeInterval) throws -> TypingDelayRange {
		let min = try validateSingle(min)
		let max = try validateSingle(max)
		guard min <= max else {
			throw WBError.message("typing delay minimum must be less than or equal to maximum")
		}
		return TypingDelayRange(min: min, max: max)
	}
}

enum TypingBackend: String, Codable, Equatable, Sendable {
	case javaScript = "js"
	case native

	static let `default` = TypingBackend.native

	static func parse(_ rawValue: String) throws -> TypingBackend {
		switch rawValue.lowercased() {
		case "js", "javascript":
			return .javaScript
		case "native":
			return .native
		default:
			throw WBError.message("unknown typing backend \(rawValue)")
		}
	}
}

enum TypingRhythm: String, Codable, Equatable, Sendable {
	case flat
	case natural

	static let `default` = TypingRhythm.natural

	static func parse(_ rawValue: String) throws -> TypingRhythm {
		switch rawValue.lowercased() {
		case "flat":
			return .flat
		case "natural", "human":
			return .natural
		default:
			throw WBError.message("unknown typing rhythm \(rawValue)")
		}
	}
}

struct BrowserWindowSize: Equatable, Sendable {
	let width: Int
	let height: Int
}

enum BrowserWindowSizing {
	static let defaultWidth = 800
	static let defaultHeight = 600
	static let minimumWidth = 100
	static let minimumHeight = 100
	static let defaultSize = BrowserWindowSize(width: defaultWidth, height: defaultHeight)

	static func validate(width: Int, height: Int) throws -> BrowserWindowSize {
		guard width >= minimumWidth else {
			throw WBError.message("window width must be at least \(minimumWidth)")
		}
		guard height >= minimumHeight else {
			throw WBError.message("window height must be at least \(minimumHeight)")
		}
		return BrowserWindowSize(width: width, height: height)
	}
}

enum WireCommand: String, Codable, Equatable, Sendable {
	case ping
	case browserCreate
	case browserList
	case browserClose
	case browserShow
	case browserHide
	case browserResize
	case open
	case page
	case click
	case fill
	case typeText = "type"
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
	var waitForResources: Bool? = nil
	var resourceTimeout: TimeInterval? = nil
	var screenshotDelay: TimeInterval? = nil
	var typingDelayMin: TimeInterval? = nil
	var typingDelayMax: TimeInterval? = nil
	var typingBackend: TypingBackend? = nil
	var typingRhythm: TypingRhythm? = nil
	var windowWidth: Int? = nil
	var windowHeight: Int? = nil

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

	func withResourceLoading(waitForResources: Bool, timeout: TimeInterval?) -> WireRequest {
		var request = self
		request.waitForResources = waitForResources ? true : nil
		request.resourceTimeout = timeout
		return request
	}

	func withScreenshotDelay(_ delay: TimeInterval?) -> WireRequest {
		var request = self
		request.screenshotDelay = delay
		return request
	}

	func withTypingDelays(min: TimeInterval?, max: TimeInterval?) -> WireRequest {
		var request = self
		request.typingDelayMin = min
		request.typingDelayMax = max
		return request
	}

	func withTypingBackend(_ backend: TypingBackend?) -> WireRequest {
		var request = self
		request.typingBackend = backend
		return request
	}

	func withTypingRhythm(_ rhythm: TypingRhythm?) -> WireRequest {
		var request = self
		request.typingRhythm = rhythm
		return request
	}

	func withWindowSize(_ size: BrowserWindowSize) -> WireRequest {
		var request = self
		request.windowWidth = size.width
		request.windowHeight = size.height
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

	func waitsForResources(implicit: Bool = false) -> Bool {
		implicit || waitForResources == true || resourceTimeout != nil
	}

	func resourceWaitTimeout(default defaultTimeout: TimeInterval) throws -> TimeInterval {
		try ResourceLoading.validateTimeout(resourceTimeout ?? defaultTimeout)
	}

	func screenshotCaptureDelay(default defaultDelay: TimeInterval) throws -> TimeInterval {
		try ScreenshotCapture.validateDelay(screenshotDelay ?? defaultDelay)
	}

	func typingDelayRange() throws -> TypingDelayRange {
		let min =
			typingDelayMin
			?? typingDelayMax.map { Swift.min(TypingDelay.defaultMin, $0) }
			?? TypingDelay.defaultMin
		let max =
			typingDelayMax
			?? typingDelayMin.map { Swift.max($0, TypingDelay.defaultMax) }
			?? TypingDelay.defaultMax
		return try TypingDelay.validateRange(
			min: min,
			max: max
		)
	}

	func typingBackendValue() -> TypingBackend {
		typingBackend ?? TypingBackend.default
	}

	func typingRhythmValue() -> TypingRhythm {
		typingRhythm ?? TypingRhythm.default
	}

	func windowSize(default defaultSize: BrowserWindowSize = BrowserWindowSizing.defaultSize) throws
		-> BrowserWindowSize
	{
		switch (windowWidth, windowHeight) {
		case (.none, .none):
			return defaultSize
		case (.none, .some):
			throw WBError.message("missing window width")
		case (.some, .none):
			throw WBError.message("missing window height")
		case (.some(let width), .some(let height)):
			return try BrowserWindowSizing.validate(width: width, height: height)
		}
	}

	func validateResourceLoading() throws {
		let requestsResourceLoading = waitForResources == true || resourceTimeout != nil
		if requestsResourceLoading && command != .open && command != .screenshot {
			throw WBError.message(
				"resource loading options are only supported for open and screenshot commands"
			)
		}
		if let resourceTimeout {
			_ = try ResourceLoading.validateTimeout(resourceTimeout)
		}
		if screenshotDelay != nil && command != .screenshot {
			throw WBError.message(
				"screenshot capture delay is only supported for screenshot commands"
			)
		}
		if let screenshotDelay {
			_ = try ScreenshotCapture.validateDelay(screenshotDelay)
		}
	}

	func validateTypingDelays() throws {
		let requestsTypingDelays = typingDelayMin != nil || typingDelayMax != nil
		let requestsTypingBackend = typingBackend != nil
		let requestsTypingRhythm = typingRhythm != nil
		if requestsTypingDelays && command != .typeText {
			throw WBError.message("typing delay options are only supported for type command")
		}
		if requestsTypingBackend && command != .typeText {
			throw WBError.message("typing backend option is only supported for type command")
		}
		if requestsTypingRhythm && command != .typeText {
			throw WBError.message("typing rhythm option is only supported for type command")
		}
		if requestsTypingDelays || command == .typeText {
			_ = try typingDelayRange()
		}
	}

	func validateWindowSize() throws {
		let requestsWindowSize = windowWidth != nil || windowHeight != nil
		if requestsWindowSize && command != .browserResize {
			throw WBError.message("window size options are only supported for resize command")
		}
		if command == .browserResize {
			_ = try windowSize()
		}
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

struct TypingDelayRange: Equatable, Sendable {
	let min: TimeInterval
	let max: TimeInterval
}

struct TypingExecutionOptions: Sendable {
	let delayRange: TypingDelayRange
	let backend: TypingBackend
	let rhythm: TypingRhythm
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
	let resourcesLoading: Bool
	let progress: Double
	let resourceCount: Int?
	let resources: [BrowserResource]
	let htmlBytes: Int?
	let text: String?
	let actions: [BrowserAction]

	init(browser: String, state: PageSnapshotState, content: PageSnapshotContent) {
		self.browser = browser
		title = state.title
		url = state.url
		loading = state.loading
		resourcesLoading = state.resourcesLoading
		progress = state.progress
		resourceCount = content.resourceCount
		resources = content.resources
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
		resourcesLoading =
			try container.decodeIfPresent(Bool.self, forKey: .resourcesLoading) ?? false
		progress = try container.decode(Double.self, forKey: .progress)
		htmlBytes = try container.decodeIfPresent(Int.self, forKey: .htmlBytes)
		text = try container.decodeIfPresent(String.self, forKey: .text)
		actions = try container.decode([BrowserAction].self, forKey: .actions)

		if container.contains(.resources) {
			let decodedResources = try container.decode([BrowserResource].self, forKey: .resources)
			resources = decodedResources
			resourceCount =
				try container.decodeIfPresent(Int.self, forKey: .resourceCount)
				?? decodedResources.count
		} else if let decodedImages = try? container.decode([BrowserImage].self, forKey: .images) {
			resources = decodedImages.map(\.resource)
			resourceCount =
				try container.decodeIfPresent(Int.self, forKey: .resourceCount)
				?? container.decodeIfPresent(Int.self, forKey: .imageCount)
				?? decodedImages.count
		} else {
			let legacyImageCount = try container.decodeIfPresent(Int.self, forKey: .images)
			resources = []
			resourceCount =
				try container.decodeIfPresent(Int.self, forKey: .resourceCount)
				?? container.decodeIfPresent(Int.self, forKey: .imageCount)
				?? legacyImageCount
		}
	}

	func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)

		try container.encode(browser, forKey: .browser)
		try container.encode(title, forKey: .title)
		try container.encodeIfPresent(url, forKey: .url)
		try container.encode(loading, forKey: .loading)
		try container.encode(resourcesLoading, forKey: .resourcesLoading)
		try container.encode(progress, forKey: .progress)
		try container.encodeIfPresent(resourceCount, forKey: .resourceCount)
		try container.encode(resources, forKey: .resources)
		try container.encodeIfPresent(htmlBytes, forKey: .htmlBytes)
		try container.encodeIfPresent(text, forKey: .text)
		try container.encode(actions, forKey: .actions)
	}

	private enum CodingKeys: String, CodingKey {
		case actions
		case browser
		case htmlBytes
		case resourceCount
		case resources
		case resourcesLoading
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
	let resourcesLoading: Bool
	let progress: Double
}

struct PageSnapshotContent: Sendable {
	let resourceCount: Int?
	let resources: [BrowserResource]
	let htmlBytes: Int?
	let text: String?
	let actions: [BrowserAction]
}

struct PageLoadStatus: Decodable, Sendable {
	let readyState: String
	let pendingRequests: Int
	let pendingResources: Int
	let quietFor: TimeInterval

	init(
		readyState: String,
		pendingRequests: Int = 0,
		quietFor: TimeInterval = ResourceLoading.quietWindow
	) {
		self.readyState = readyState
		self.pendingRequests = max(0, pendingRequests)
		self.pendingResources = 0
		self.quietFor = max(0, quietFor)
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		readyState = try container.decode(String.self, forKey: .readyState)
		pendingRequests = max(
			0,
			try container.decodeIfPresent(Int.self, forKey: .pendingRequests) ?? 0
		)
		pendingResources = max(
			0,
			try container.decodeIfPresent(Int.self, forKey: .pendingResources) ?? 0
		)
		quietFor = max(
			0,
			try container.decodeIfPresent(TimeInterval.self, forKey: .quietFor)
				?? ResourceLoading.quietWindow
		)
	}

	var pageLoading: Bool {
		readyState != "interactive" && readyState != "complete"
	}

	var pendingWork: Int {
		pendingRequests + pendingResources
	}

	func resourcesLoading(
		webKitLoading: Bool,
		quietWindow: TimeInterval = ResourceLoading.quietWindow
	) -> Bool {
		pageLoading
			|| readyState != "complete"
			|| webKitLoading
			|| pendingWork > 0
			|| quietFor < quietWindow
	}

	func interactionSettled(
		webKitLoading: Bool,
		quietWindow: TimeInterval = InteractionSettling.quietWindow
	) -> Bool {
		!pageLoading
			&& !webKitLoading
			&& pendingWork == 0
			&& quietFor >= quietWindow
	}

	private enum CodingKeys: String, CodingKey {
		case pendingRequests
		case pendingResources
		case quietFor
		case readyState
	}
}

struct BrowserResource: Codable, Sendable {
	let index: Int
	let type: String
	let url: String
	let alt: String?
}

struct BrowserImage: Codable, Sendable {
	let index: Int
	let url: String
	let alt: String?
}

private extension BrowserImage {
	var resource: BrowserResource {
		BrowserResource(index: index, type: "image", url: url, alt: alt)
	}
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
