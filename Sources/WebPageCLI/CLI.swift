import Foundation

struct CLIInvocation {
    let request: WireRequest?
    let renderMode: RenderMode
    let startDaemon: Bool
    let daemonIdleTimeout: TimeInterval?

    init(
        request: WireRequest?,
        renderMode: RenderMode,
        startDaemon: Bool,
        daemonIdleTimeout: TimeInterval? = nil
    ) {
        self.request = request
        self.renderMode = renderMode
        self.startDaemon = startDaemon
        self.daemonIdleTimeout = daemonIdleTimeout
    }
}

enum RenderMode {
    case help
    case pageHelp
    case daemonStatus
    case daemonStart
    case browserID
    case browsers
    case browserMessage
    case pageSummary
    case page(PageOutputOptions)
    case interaction
    case value
    case text
    case html
    case message
}

struct PageOutputOptions {
    var includeActionSelectors = false
    var includeActionDetails = false
    var fields: Set<PageField>?

    var hasFullOutputOptions: Bool {
        includeActionSelectors || includeActionDetails || fields != nil
    }
}

struct CLIParser {
    static func parse(_ rawArguments: [String]) throws -> CLIInvocation {
        var arguments = rawArguments
        var browser: String?

        while let first = arguments.first {
            if first == "--help" || first == "-h" {
                return CLIInvocation(request: nil, renderMode: .help, startDaemon: false)
            }

            if first == "--browser" || first == "-b" {
                arguments.removeFirst()
                browser = try arguments.popFirst("missing browser id after \(first)")
                continue
            }

            if first.hasPrefix("--browser=") {
                browser = String(first.dropFirst("--browser=".count))
                arguments.removeFirst()
                continue
            }

            if first.hasPrefix("-b"), first.count > 2 {
                browser = String(first.dropFirst(2))
                arguments.removeFirst()
                continue
            }

            break
        }

        guard let command = arguments.first else {
            return CLIInvocation(request: nil, renderMode: .help, startDaemon: false)
        }

        arguments.removeFirst()

        switch command {
        case "help":
            if arguments.first == "page" {
                return CLIInvocation(request: nil, renderMode: .pageHelp, startDaemon: false)
            }
            return CLIInvocation(request: nil, renderMode: .help, startDaemon: false)

        case "browser":
            return try parseBrowserCommand(browser: browser, arguments: arguments)

        case "daemon":
            return try parseDaemonCommand(arguments)

        case "open", "go":
            var arguments = arguments
            if arguments.containsHelpFlag {
                return CLIInvocation(request: nil, renderMode: .help, startDaemon: false)
            }
            let full = arguments.removeFlag("--full")
            let pageOptions = try parsePageOutputOptions(&arguments)
            let url = try arguments.popFirst("usage: wp open <url>")
            guard arguments.isEmpty else {
                throw WPError.message("unexpected open argument \(arguments[0])")
            }
            if !full && pageOptions.hasFullOutputOptions {
                throw WPError.message("open page output options require --full")
            }
            return CLIInvocation(
                request: WireRequest(command: .open, browser: browser, url: url),
                renderMode: full ? .page(pageOptions) : .pageSummary,
                startDaemon: true,
                daemonIdleTimeout: nil
            )

        case "page":
            if arguments.containsHelpFlag {
                return CLIInvocation(request: nil, renderMode: .pageHelp, startDaemon: false)
            }
            let pageOptions = try parsePageOutputOptions(&arguments)
            guard arguments.isEmpty else {
                throw WPError.message("unknown page option \(arguments[0])")
            }
            return CLIInvocation(
                request: WireRequest(command: .page, browser: browser),
                renderMode: .page(pageOptions),
                startDaemon: true
            )

        case "click":
            let index = try arguments.popInt("usage: wp -b <id> click <action-number>")
            return CLIInvocation(
                request: WireRequest(command: .click, browser: browser, index: index),
                renderMode: .interaction,
                startDaemon: true
            )

        case "fill":
            let index = try arguments.popInt("usage: wp -b <id> fill <action-number> <text>")
            let value = try arguments.joinRemaining("usage: wp -b <id> fill <action-number> <text>")
            return CLIInvocation(
                request: WireRequest(command: .fill, browser: browser, index: index, value: value),
                renderMode: .interaction,
                startDaemon: true
            )

        case "submit":
            let index = try arguments.popInt("usage: wp -b <id> submit <action-number>")
            return CLIInvocation(
                request: WireRequest(command: .submit, browser: browser, index: index),
                renderMode: .interaction,
                startDaemon: true
            )

        case "eval":
            let functionBody = arguments.removeFlag("--body")
            let script = try arguments.joinRemaining("usage: wp -b <id> eval [--body] <javascript>")
            return CLIInvocation(
                request: WireRequest(
                    command: .eval,
                    browser: browser,
                    script: script,
                    functionBody: functionBody ? true : nil
                ),
                renderMode: .value,
                startDaemon: true
            )

        case "text":
            return CLIInvocation(
                request: WireRequest(command: .text, browser: browser, selector: arguments.joinedOrNil()),
                renderMode: .text,
                startDaemon: true
            )

        case "html":
            return CLIInvocation(
                request: WireRequest(command: .html, browser: browser, selector: arguments.joinedOrNil()),
                renderMode: .html,
                startDaemon: true
            )

        default:
            throw WPError.message("unknown command \(command)")
        }
    }

    private static func parseBrowserCommand(browser: String?, arguments: [String]) throws -> CLIInvocation {
        var arguments = arguments
        let command = try arguments.popFirst("usage: wp browser <create|list|close>")

        switch command {
        case "create":
            return CLIInvocation(
                request: WireRequest(command: .browserCreate),
                renderMode: .browserID,
                startDaemon: true,
                daemonIdleTimeout: nil
            )

        case "list", "ls":
            return CLIInvocation(
                request: WireRequest(command: .browserList),
                renderMode: .browsers,
                startDaemon: true,
                daemonIdleTimeout: nil
            )

        case "close", "delete", "rm":
            let id = arguments.first ?? browser
            return CLIInvocation(
                request: WireRequest(command: .browserClose, browser: id),
                renderMode: .message,
                startDaemon: true,
                daemonIdleTimeout: nil
            )

        case "dump":
            let id = arguments.first ?? browser
            return CLIInvocation(
                request: WireRequest(command: .browserDump, browser: id),
                renderMode: .browserMessage,
                startDaemon: true,
                daemonIdleTimeout: nil
            )

        case "resume":
            let id = arguments.first ?? browser
            return CLIInvocation(
                request: WireRequest(command: .browserResume, browser: id),
                renderMode: .pageSummary,
                startDaemon: true,
                daemonIdleTimeout: nil
            )

        default:
            throw WPError.message("unknown browser command \(command)")
        }
    }

    private static func parseDaemonCommand(_ arguments: [String]) throws -> CLIInvocation {
        guard let command = arguments.first else {
            throw WPError.message("usage: wp daemon <start|status|stop>")
        }

        switch command {
        case "start":
            var arguments = Array(arguments.dropFirst())
            let idleTimeout = try parseIdleTimeoutOption(&arguments)
            guard arguments.isEmpty else {
                throw WPError.message("unknown daemon start option \(arguments[0])")
            }
            return CLIInvocation(
                request: WireRequest(command: .ping),
                renderMode: .daemonStart,
                startDaemon: true,
                daemonIdleTimeout: idleTimeout
            )

        case "status":
            return CLIInvocation(
                request: nil,
                renderMode: .daemonStatus,
                startDaemon: false,
                daemonIdleTimeout: nil
            )

        case "stop":
            return CLIInvocation(
                request: WireRequest(command: .daemonStop),
                renderMode: .message,
                startDaemon: false,
                daemonIdleTimeout: nil
            )

        default:
            throw WPError.message("unknown daemon command \(command)")
        }
    }
}

func render(_ response: WireResponse, mode: RenderMode) throws {
    if !response.ok {
        throw WPError.message(response.error ?? "request failed")
    }

    switch mode {
    case .help:
        printUsage()

    case .pageHelp:
        printPageUsage()

    case .daemonStatus:
        break

    case .daemonStart:
        print("running")

    case .browserID:
        print(try response.browser.unwrap("daemon did not return a browser id"))

    case .browsers:
        try printJSON(response.browsers ?? [])

    case .browserMessage:
        try printJSON(BrowserMessageOutput(
            browser: response.browser,
            message: response.message
        ))

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

    case .text:
        print(response.text ?? "")

    case .html:
        print(response.html ?? "")

    case .message:
        print(response.message ?? "ok")
    }
}

func printUsage() {
    print("""
    Usage:
      wp browser create
      wp browser list
      wp browser close <id>
      wp browser dump <id>
      wp browser resume <id>

      wp open <url>
      wp open --full [--fields <list>] [--selectors|--action-details] <url>
      wp --browser <id> open <url>
      wp -b <id> page [--fields <list>] [--selectors|--action-details]
      wp -b <id> click <action-number>
      wp -b <id> fill <action-number> <text>
      wp -b <id> submit <action-number>
      wp -b <id> eval [--body] <javascript>
      wp -b <id> text [css-selector]
      wp -b <id> html [css-selector]

      wp daemon start [--idle-timeout <seconds|off>]
      wp daemon status
      wp daemon stop

    Notes:
      - Commands auto-start a local daemon, except daemon status/stop.
      - 'wp open <url>' creates a browser, opens the page, and prints a compact summary.
      - Use 'wp page --help' to see the page JSON shape and filterable fields.
      - Use '--selectors' to show action CSS selectors and '--action-details' for raw action metadata.
      - JSON output is compact and omits false, empty, and null fields.
    """)
}

func printPageUsage() {
    let fields = PageField.allCases.map(\.rawValue).joined(separator: ",")
    print("""
    Usage:
      wp -b <id> page [--fields <list>] [--selectors|--action-details]
      wp open --full [--fields <list>] [--selectors|--action-details] <url>

    Options:
      --fields <list>       Comma-separated top-level fields to print.
      --selectors           Include action CSS selectors.
      --action-details      Include action id, index, tag, type, and selector.

    Page JSON:
      {
        "actions": [
          {
            "disabled": false,
            "href": "https://example.com/",
            "id": "wkcli-...",
            "index": 1,
            "kind": "link|button|fill|form|selector|toggle",
            "selector": "main a",
            "tag": "a",
            "text": "Visible label",
            "type": "text"
          }
        ],
        "browser": "a3f19c0b",
        "htmlBytes": 12345,
        "images": 3,
        "jsonBytes": 6789,
        "loading": false,
        "progress": 1.0,
        "text": "Visible markdown-like text",
        "title": "Page title",
        "url": "https://example.com/"
      }

    Fields:
      \(fields)

    Notes:
      - JSON output omits false, empty, and null fields.
      - Default actions omit id, index, tag, type, and selector unless requested.
      - images is document.images.length.
      - htmlBytes is the UTF-8 size of document.documentElement.outerHTML.
      - jsonBytes is the UTF-8 size of the default full page JSON, excluding jsonBytes itself.

    Examples:
      wp -b a3f19c0b page --fields title,url,images,htmlBytes,jsonBytes
      wp -b a3f19c0b page --fields actions --action-details
    """)
}

private struct BrowserMessageOutput: Encodable {
    let browser: String?
    let message: String?
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
        images = page?.images
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
    let images: Int?
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
        images = page.images
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
    let index: Int?
    let kind: String
    let tag: String?
    let type: String?
    let text: String
    let href: String?
    let disabled: Bool
    let selector: String?

    init(action: BrowserAction, options: PageOutputOptions) {
        id = options.includeActionDetails ? action.id : nil
        index = options.includeActionDetails ? action.index : nil
        kind = action.outputKind
        tag = options.includeActionDetails ? action.tag : nil
        type = options.includeActionDetails ? action.type.nilIfEmpty : nil
        text = action.text
        href = action.href.nilIfEmpty
        disabled = action.disabled
        selector = (options.includeActionSelectors || options.includeActionDetails) ? action.selector : nil
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

enum PageField: String, CaseIterable, Hashable {
    case actions
    case browser
    case htmlBytes
    case images
    case jsonBytes
    case loading
    case progress
    case text
    case title
    case url

    static var validList: String {
        allCases.map(\.rawValue).joined(separator: ",")
    }

    static func parseList(_ rawValue: String) throws -> Set<PageField> {
        let names = rawValue
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !names.isEmpty else {
            throw WPError.message("--fields requires at least one field")
        }

        var fields: Set<PageField> = []
        for name in names {
            guard let field = PageField(rawValue: name) else {
                throw WPError.message("unknown page field \(name); valid fields: \(validList)")
            }
            fields.insert(field)
        }
        return fields
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

private extension Array where Element == String {
    mutating func popFirst(_ errorMessage: String) throws -> String {
        guard !isEmpty else {
            throw WPError.message(errorMessage)
        }
        return removeFirst()
    }

    mutating func popInt(_ errorMessage: String) throws -> Int {
        let value = try popFirst(errorMessage)
        guard let integer = Int(value) else {
            throw WPError.message("expected integer, got \(value)")
        }
        return integer
    }

    func joinRemaining(_ errorMessage: String) throws -> String {
        let value = joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            throw WPError.message(errorMessage)
        }
        return value
    }

    func joinedOrNil() -> String? {
        joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var containsHelpFlag: Bool {
        contains("--help") || contains("-h")
    }

    mutating func removeFlag(_ flag: String) -> Bool {
        guard let index = firstIndex(of: flag) else {
            return false
        }
        remove(at: index)
        return true
    }
}

private func parsePageOutputOptions(_ arguments: inout [String]) throws -> PageOutputOptions {
    var options = PageOutputOptions()
    var remaining: [String] = []

    while !arguments.isEmpty {
        let argument = arguments.removeFirst()
        switch argument {
        case "--selectors", "--selector":
            options.includeActionSelectors = true

        case "--action-details", "--details", "--verbose":
            options.includeActionDetails = true
            options.includeActionSelectors = true

        case "--fields", "--field":
            let rawFields = try arguments.popFirst("missing value after \(argument)")
            options.fields = try PageField.parseList(rawFields)

        case let option where option.hasPrefix("--fields="):
            let rawFields = String(option.dropFirst("--fields=".count))
            options.fields = try PageField.parseList(rawFields)

        case let option where option.hasPrefix("--field="):
            let rawFields = String(option.dropFirst("--field=".count))
            options.fields = try PageField.parseList(rawFields)

        default:
            remaining.append(argument)
        }
    }

    arguments = remaining
    return options
}

private func parseIdleTimeoutOption(_ arguments: inout [String]) throws -> TimeInterval? {
    var idleTimeout: TimeInterval?
    var remaining: [String] = []

    while !arguments.isEmpty {
        let argument = arguments.removeFirst()
        let rawValue: String

        if argument == "--idle-timeout" {
            rawValue = try arguments.popFirst("missing value after --idle-timeout")
        } else if argument.hasPrefix("--idle-timeout=") {
            rawValue = String(argument.dropFirst("--idle-timeout=".count))
        } else {
            remaining.append(argument)
            continue
        }

        guard let parsed = WPConfig.parseIdleTimeout(rawValue) else {
            throw WPError.message("invalid idle timeout \(rawValue)")
        }
        idleTimeout = parsed
    }

    arguments = remaining
    return idleTimeout
}
