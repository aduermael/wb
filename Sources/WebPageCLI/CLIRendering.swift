/// Renders daemon responses, local command output, and page summaries as the
/// compact human-readable or JSON payloads expected by scripts that drive the
/// browser command-line interface.
import Foundation

func render(_ response: WireResponse, mode: RenderMode) throws {
	if !response.ok {
		if let output = try renderedOutput(response, mode: mode) {
			print(output)
		}
		throw WBExit(code: 1)
	}

	if let output = try renderedOutput(response, mode: mode) {
		print(output)
		return
	}

	switch mode {
	case .silent,
		.daemonStatus:
		break

	case .help(let topic):
		printHelp(topic)
	default:
		break
	}
}

func renderedOutput(_ response: WireResponse, mode: RenderMode) throws -> String? {
	if !response.ok {
		return try compactJSONString(CommandErrorOutput(response: response))
	}

	switch mode {
	case .silent,
		.help,
		.daemonStatus:
		return nil

	case .daemonStart:
		return "running"

	case .daemonLogPath:
		return WBConfig.current().logPath

	case .browserID:
		return try response.browser.unwrap("daemon did not return a browser id")

	case .browsers:
		return try compactJSONString(response.browsers ?? [])

	case .pageSummary:
		let page = try response.page.unwrap("daemon did not return page data")
		return try compactJSONString(
			PageSummaryOutput(
				browser: response.browser,
				message: response.message,
				page: page
			))

	case .page(let options):
		let page = try response.page.unwrap("daemon did not return page data")
		return try compactJSONString(PageOutput(page: page, options: options))

	case .interaction:
		let page = try response.page.unwrap("daemon did not return page data")
		return try compactJSONString(
			PageSummaryOutput(
				browser: response.browser,
				message: response.message,
				page: page
			))

	case .value:
		return response.value ?? ""

	case .message:
		return response.message ?? "ok"
	}
}

func runLocalCommand(_ command: LocalCommand) async throws {
	switch command {
	case .environment:
		let config = WBConfig.current()
		let environment = try WBEnvironment.loadOrCreate(in: config.directory)
		try printJSON(environment.metadata)

	case .update:
		try await WBUpdater.runUpdate()

	case .version:
		print(WBVersion.current)
	}
}

private struct CommandErrorOutput: Encodable {
	let ok = false
	let browser: String?
	let error: String
	let message: String?
	let title: String?
	let url: String?
	let loading: Bool
	let resourcesLoading: Bool
	let progress: Double?
	let resources: Int?
	let htmlBytes: Int?
	let jsonBytes: Int?
	let actions: Int?

	init(response: WireResponse) {
		let page = response.page

		browser = response.browser ?? page?.browser
		error = response.error ?? "request failed"
		message = response.message
		title = page.flatMap { $0.title.nilIfEmpty }
		url = page.flatMap { $0.url } ?? response.url
		loading = page?.loading ?? false
		resourcesLoading = page?.resourcesLoading ?? false
		progress = page?.progress
		resources = page?.resourceCount
		htmlBytes = page?.htmlBytes
		jsonBytes = page.flatMap(defaultPageJSONByteCount)
		actions = page.map { $0.actions.count }
	}
}

private struct PageSummaryOutput: Encodable {
	let browser: String?
	let message: String?
	let title: String?
	let url: String?
	let loading: Bool
	let resourcesLoading: Bool
	let progress: Double?
	let resources: Int?
	let htmlBytes: Int?
	let jsonBytes: Int?
	let actions: Int?

	init(browser: String?, message: String?, page: PageSnapshot?) {
		self.browser = browser ?? page?.browser
		self.message = message
		title = page.flatMap { $0.title.nilIfEmpty }
		url = page.flatMap { $0.url }
		loading = page?.loading ?? false
		resourcesLoading = page?.resourcesLoading ?? false
		progress = page?.progress
		resources = page?.resourceCount
		htmlBytes = page?.htmlBytes
		jsonBytes = page.flatMap(defaultPageJSONByteCount)
		actions = page.map { $0.actions.count }
	}
}

private struct PageOutput: Encodable {
	let browser: String
	let title: String?
	let url: String?
	let loading: Bool
	let resourcesLoading: Bool
	let progress: Double
	let resourceCount: Int?
	let resources: [PageResourceOutput]
	let htmlBytes: Int?
	let jsonBytes: Int?
	let text: String?
	let actions: [PageActionOutput]
	private let fields: Set<PageField>?

	init(page: PageSnapshot, options: PageOutputOptions, includeJSONBytes: Bool = true) {
		browser = page.browser
		title = page.title.nilIfEmpty
		url = page.url
		loading = page.loading
		resourcesLoading = page.resourcesLoading
		progress = page.progress
		resourceCount = page.resourceCount
		resources = page.resources.map { PageResourceOutput(resource: $0) }
		htmlBytes = page.htmlBytes
		jsonBytes = includeJSONBytes ? defaultPageJSONByteCount(page) : nil
		text = page.text.nilIfEmpty
		actions = page.actions.map { PageActionOutput(action: $0, options: options) }
		fields = options.fields
	}

	func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)

		try encode(browser, for: .browser, in: &container)
		try encode(title, for: .title, in: &container)
		try encode(url, for: .url, in: &container)
		try encode(loading, for: .loading, in: &container)
		try encode(resourcesLoading, for: .resourcesLoading, in: &container)
		try encode(progress, for: .progress, in: &container)
		try encode(resourceCount, for: .resourceCount, in: &container)
		try encode(resources, for: .resources, in: &container)
		try encode(htmlBytes, for: .htmlBytes, in: &container)
		try encode(jsonBytes, for: .jsonBytes, in: &container)
		try encode(text, for: .text, in: &container)
		try encode(actions, for: .actions, in: &container)
	}

	private enum CodingKeys: String, CodingKey {
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
	}

	private func includes(_ key: CodingKeys) -> Bool {
		guard let fields else {
			return true
		}
		guard let field = PageField(rawValue: key.rawValue) else {
			return true
		}
		return fields.contains(field)
	}

	private func encode<T: Encodable>(
		_ value: T,
		for key: CodingKeys,
		in container: inout KeyedEncodingContainer<CodingKeys>
	) throws {
		guard includes(key) else {
			return
		}
		try container.encode(value, forKey: key)
	}
}

private struct PageActionOutput: Encodable {
	let id: String?
	let index: Int
	let kind: String
	let tag: String?
	let type: String?
	let text: String
	let href: String?
	let disabled: Bool
	let selector: String?

	init(action: BrowserAction, options: PageOutputOptions) {
		id = options.includeActionDetails ? action.id : nil
		index = action.index
		kind = action.outputKind
		tag = options.includeActionDetails ? action.tag : nil
		type = options.includeActionDetails ? action.type.nilIfEmpty : nil
		text = action.text
		href = action.href.nilIfEmpty
		disabled = action.disabled
		selector = (options.includeActionSelectors || options.includeActionDetails) ? action.selector : nil
	}
}

private struct PageResourceOutput: Encodable {
	let index: Int
	let type: String
	let url: String
	let alt: String?

	init(resource: BrowserResource) {
		index = resource.index
		type = resource.type
		url = resource.url
		alt = resource.alt.nilIfEmpty
	}
}

private extension BrowserAction {
	var outputKind: String {
		switch kind {
		case "click":
			return href.nilIfEmpty == nil ? "button" : "link"
		case "select":
			return "selector"
		default:
			return kind
		}
	}
}

private func defaultPageJSONByteCount(_ page: PageSnapshot) -> Int? {
	let output = PageOutput(
		page: page,
		options: PageOutputOptions(),
		includeJSONBytes: false
	)
	guard let json = try? compactJSONString(output) else {
		return nil
	}
	return json.utf8.count
}
