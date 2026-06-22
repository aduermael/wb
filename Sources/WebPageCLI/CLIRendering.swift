/// Renders daemon responses, local command output, and page summaries as the
/// compact human-readable or JSON payloads expected by scripts that drive the
/// browser command-line interface.
import Foundation

func render(_ response: WireResponse, mode: RenderMode) throws {
	if !response.ok {
		try printJSON(CommandErrorOutput(response: response))
		throw WBExit(code: 1)
	}

	switch mode {
	case .silent:
		break

	case .help(let topic):
		printHelp(topic)

	case .daemonStatus:
		break

	case .daemonStart:
		print("running")

	case .daemonLogPath:
		print(WBConfig.current().logPath)

	case .browserID:
		print(try response.browser.unwrap("daemon did not return a browser id"))

	case .browsers:
		try printJSON(response.browsers ?? [])

	case .pageSummary:
		let page = try response.page.unwrap("daemon did not return page data")
		try printJSON(PageSummaryOutput(
			browser: response.browser,
			message: response.message,
			page: page
		))

	case .page(let options):
		let page = try response.page.unwrap("daemon did not return page data")
		try printJSON(PageOutput(page: page, options: options))

	case .interaction:
		let page = try response.page.unwrap("daemon did not return page data")
		try printJSON(PageSummaryOutput(
			browser: response.browser,
			message: response.message,
			page: page
		))

	case .value:
		print(response.value ?? "")

	case .message:
		print(response.message ?? "ok")
	}
}

func runLocalCommand(_ command: LocalCommand) throws {
	let config = WBConfig.current()
	let environment = try WBEnvironment.loadOrCreate(in: config.directory)

	switch command {
	case .environment:
		try printJSON(environment.metadata)
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
	let progress: Double?
	let images: Int?
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
		progress = page?.progress
		images = page?.imageCount
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
	let progress: Double?
	let images: Int?
	let htmlBytes: Int?
	let jsonBytes: Int?
	let actions: Int?

	init(browser: String?, message: String?, page: PageSnapshot?) {
		self.browser = browser ?? page?.browser
		self.message = message
		title = page.flatMap { $0.title.nilIfEmpty }
		url = page.flatMap { $0.url }
		loading = page?.loading ?? false
		progress = page?.progress
		images = page?.imageCount
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
	let progress: Double
	let imageCount: Int?
	let images: [PageImageOutput]
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
		progress = page.progress
		imageCount = page.imageCount
		images = page.images.map { PageImageOutput(image: $0) }
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
		try encode(progress, for: .progress, in: &container)
		try encode(imageCount, for: .imageCount, in: &container)
		try encode(images, for: .images, in: &container)
		try encode(htmlBytes, for: .htmlBytes, in: &container)
		try encode(jsonBytes, for: .jsonBytes, in: &container)
		try encode(text, for: .text, in: &container)
		try encode(actions, for: .actions, in: &container)
	}

	private enum CodingKeys: String, CodingKey {
		case actions
		case browser
		case htmlBytes
		case imageCount
		case images
		case jsonBytes
		case loading
		case progress
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

private struct PageImageOutput: Encodable {
	let index: Int
	let url: String
	let alt: String?

	init(image: BrowserImage) {
		index = image.index
		url = image.url
		alt = image.alt.nilIfEmpty
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
