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
    case silent
    case help(HelpTopic)
    case daemonStatus
    case daemonStart
    case daemonLogPath
    case browserID
    case browsers
    case browserMessage
    case pageSummary
    case page(PageOutputOptions)
    case interaction
    case value
    case message
}

enum HelpTopic {
    case root
    case create
    case list
    case close
    case dump
    case show
    case hide
    case page
    case click
    case fill
    case submit
    case eval
    case daemon
    case daemonStart
    case daemonStatus
    case daemonStop
    case daemonLog
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

        if arguments.first == "--help" || arguments.first == "-h" {
            return help(.root)
        }

        guard let command = arguments.first else {
            return help(.root)
        }

        arguments.removeFirst()

        switch command {
        case "help":
            return try parseHelpCommand(arguments)

        case "create":
            if arguments.containsHelpFlag {
                return help(.create)
            }
            guard arguments.isEmpty else {
                throw WBError.message("unexpected create argument \(arguments[0])")
            }
            return CLIInvocation(
                request: WireRequest(command: .browserCreate),
                renderMode: .browserID,
                startDaemon: true,
                daemonIdleTimeout: nil
            )

        case "list", "ls":
            if arguments.containsHelpFlag {
                return help(.list)
            }
            guard arguments.isEmpty else {
                throw WBError.message("unexpected list argument \(arguments[0])")
            }
            return CLIInvocation(
                request: WireRequest(command: .browserList),
                renderMode: .browsers,
                startDaemon: true,
                daemonIdleTimeout: nil
            )

        case "close", "delete", "rm":
            if arguments.containsHelpFlag {
                return help(.close)
            }
            let id = try popBrowserID(
                from: &arguments,
                usage: "usage: wb close <id>"
            )
            guard arguments.isEmpty else {
                throw WBError.message("unexpected close argument \(arguments[0])")
            }
            return CLIInvocation(
                request: WireRequest(command: .browserClose, browser: id),
                renderMode: .message,
                startDaemon: true,
                daemonIdleTimeout: nil
            )

        case "dump":
            if arguments.containsHelpFlag {
                return help(.dump)
            }
            let id = try popBrowserID(
                from: &arguments,
                usage: "usage: wb dump <id>"
            )
            guard arguments.isEmpty else {
                throw WBError.message("unexpected dump argument \(arguments[0])")
            }
            return CLIInvocation(
                request: WireRequest(command: .browserDump, browser: id),
                renderMode: .browserMessage,
                startDaemon: true,
                daemonIdleTimeout: nil
            )

        case "show":
            if arguments.containsHelpFlag {
                return help(.show)
            }
            let id = try popBrowserID(
                from: &arguments,
                usage: "usage: wb show <id>"
            )
            guard arguments.isEmpty else {
                throw WBError.message("unexpected show argument \(arguments[0])")
            }
            return CLIInvocation(
                request: WireRequest(command: .browserShow, browser: id),
                renderMode: .silent,
                startDaemon: true,
                daemonIdleTimeout: nil
            )

        case "hide":
            if arguments.containsHelpFlag {
                return help(.hide)
            }
            let id = try popBrowserID(
                from: &arguments,
                usage: "usage: wb hide <id>"
            )
            guard arguments.isEmpty else {
                throw WBError.message("unexpected hide argument \(arguments[0])")
            }
            return CLIInvocation(
                request: WireRequest(command: .browserHide, browser: id),
                renderMode: .silent,
                startDaemon: true,
                daemonIdleTimeout: nil
            )

        case "daemon":
            return try parseDaemonCommand(arguments)

        case "page":
            if arguments.containsHelpFlag {
                return help(.page)
            }
            var arguments = arguments
            let pageOptions = try parsePageOutputOptions(&arguments)
            let id = try popBrowserID(
                from: &arguments,
                usage: "usage: wb page <id> [--fields <list>] [--selectors|--action-details]"
            )
            guard arguments.isEmpty else {
                throw WBError.message("unknown page option \(arguments[0])")
            }
            return CLIInvocation(
                request: WireRequest(command: .page, browser: id),
                renderMode: .page(pageOptions),
                startDaemon: true
            )

        case "click":
            if arguments.containsHelpFlag {
                return help(.click)
            }
            let id = try popBrowserID(
                from: &arguments,
                usage: "usage: wb click <id> <action>"
            )
            let action = try arguments.popFirst("usage: wb click <id> <action>")
            guard arguments.isEmpty else {
                throw WBError.message("unexpected click argument \(arguments[0])")
            }
            return CLIInvocation(
                request: WireRequest(command: .click, browser: id, action: action, index: Int(action)),
                renderMode: .interaction,
                startDaemon: true
            )

        case "fill":
            if arguments.containsHelpFlag {
                return help(.fill)
            }
            let id = try popBrowserID(
                from: &arguments,
                usage: "usage: wb fill <id> <action> <text>"
            )
            let action = try arguments.popFirst("usage: wb fill <id> <action> <text>")
            let value = try arguments.joinRemaining("usage: wb fill <id> <action> <text>")
            return CLIInvocation(
                request: WireRequest(command: .fill, browser: id, action: action, index: Int(action), value: value),
                renderMode: .interaction,
                startDaemon: true
            )

        case "submit":
            if arguments.containsHelpFlag {
                return help(.submit)
            }
            let id = try popBrowserID(
                from: &arguments,
                usage: "usage: wb submit <id> <action>"
            )
            let action = try arguments.popFirst("usage: wb submit <id> <action>")
            guard arguments.isEmpty else {
                throw WBError.message("unexpected submit argument \(arguments[0])")
            }
            return CLIInvocation(
                request: WireRequest(command: .submit, browser: id, action: action, index: Int(action)),
                renderMode: .interaction,
                startDaemon: true
            )

        case "eval":
            if arguments.containsHelpFlag {
                return help(.eval)
            }
            let functionBody = arguments.removeFlag("--body")
            let id = try popBrowserID(
                from: &arguments,
                usage: "usage: wb eval <id> [--body] <javascript>"
            )
            let script = try arguments.joinRemaining("usage: wb eval <id> [--body] <javascript>")
            return CLIInvocation(
                request: WireRequest(
                    command: .eval,
                    browser: id,
                    script: script,
                    functionBody: functionBody ? true : nil
                ),
                renderMode: .value,
                startDaemon: true
            )

        default:
            return try parsePositionalOpen(first: command, rest: arguments)
        }
    }

    private static func parsePositionalOpen(first: String, rest arguments: [String]) throws -> CLIInvocation {
        guard !first.hasPrefix("-") else {
            throw WBError.message("unknown command \(first)")
        }

        let browser: String?
        let url: String
        switch arguments.count {
        case 0:
            browser = nil
            url = first

        case 1:
            guard isBrowserID(first) else {
                throw WBError.message("unknown command \(first)")
            }
            browser = first
            url = arguments[0]

        default:
            throw WBError.message("unexpected URL argument \(arguments[1])")
        }

        return CLIInvocation(
            request: WireRequest(command: .open, browser: browser, url: url),
            renderMode: .pageSummary,
            startDaemon: true,
            daemonIdleTimeout: nil
        )
    }

    private static func help(_ topic: HelpTopic) -> CLIInvocation {
        CLIInvocation(request: nil, renderMode: .help(topic), startDaemon: false)
    }

    private static func parseHelpCommand(_ arguments: [String]) throws -> CLIInvocation {
        var arguments = arguments
        guard let command = arguments.first else {
            return help(.root)
        }
        arguments.removeFirst()

        if command == "daemon" {
            guard let daemonCommand = arguments.first else {
                return help(.daemon)
            }
            switch daemonCommand {
            case "start":
                return help(.daemonStart)
            case "status":
                return help(.daemonStatus)
            case "stop":
                return help(.daemonStop)
            case "log", "logs", "log-path":
                return help(.daemonLog)
            default:
                throw WBError.message("unknown daemon command \(daemonCommand)")
            }
        }

        switch command {
        case "create":
            return help(.create)
        case "list", "ls":
            return help(.list)
        case "close", "delete", "rm":
            return help(.close)
        case "dump":
            return help(.dump)
        case "show":
            return help(.show)
        case "hide":
            return help(.hide)
        case "page":
            return help(.page)
        case "click":
            return help(.click)
        case "fill":
            return help(.fill)
        case "submit":
            return help(.submit)
        case "eval":
            return help(.eval)
        default:
            throw WBError.message("unknown help topic \(command)")
        }
    }

    private static func popBrowserID(
        from arguments: inout [String],
        usage: String
    ) throws -> String {
        return try arguments.popFirst(usage)
    }

    private static func isBrowserID(_ value: String) -> Bool {
        let bytes = value.utf8
        guard bytes.count == 8 else {
            return false
        }
        return bytes.allSatisfy { byte in
            (byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102)
        }
    }

    private static func parseDaemonCommand(_ arguments: [String]) throws -> CLIInvocation {
        guard let command = arguments.first else {
            return help(.daemon)
        }
        if command == "--help" || command == "-h" {
            return help(.daemon)
        }

        switch command {
        case "start":
            var arguments = Array(arguments.dropFirst())
            if arguments.containsHelpFlag {
                return help(.daemonStart)
            }
            let idleTimeout = try parseIdleTimeoutOption(&arguments)
            guard arguments.isEmpty else {
                throw WBError.message("unknown daemon start option \(arguments[0])")
            }
            return CLIInvocation(
                request: WireRequest(command: .ping),
                renderMode: .daemonStart,
                startDaemon: true,
                daemonIdleTimeout: idleTimeout
            )

        case "status":
            let arguments = Array(arguments.dropFirst())
            if arguments.containsHelpFlag {
                return help(.daemonStatus)
            }
            guard arguments.isEmpty else {
                throw WBError.message("unexpected daemon status argument \(arguments[0])")
            }
            return CLIInvocation(
                request: nil,
                renderMode: .daemonStatus,
                startDaemon: false,
                daemonIdleTimeout: nil
            )

        case "log", "logs", "log-path":
            let arguments = Array(arguments.dropFirst())
            if arguments.containsHelpFlag {
                return help(.daemonLog)
            }
            guard arguments.isEmpty else {
                throw WBError.message("unexpected daemon log argument \(arguments[0])")
            }
            return CLIInvocation(
                request: nil,
                renderMode: .daemonLogPath,
                startDaemon: false,
                daemonIdleTimeout: nil
            )

        case "stop":
            let arguments = Array(arguments.dropFirst())
            if arguments.containsHelpFlag {
                return help(.daemonStop)
            }
            guard arguments.isEmpty else {
                throw WBError.message("unexpected daemon stop argument \(arguments[0])")
            }
            return CLIInvocation(
                request: WireRequest(command: .daemonStop),
                renderMode: .message,
                startDaemon: false,
                daemonIdleTimeout: nil
            )

        default:
            throw WBError.message("unknown daemon command \(command)")
        }
    }
}

func render(_ response: WireResponse, mode: RenderMode) throws {
    if !response.ok {
        throw WBError.message(response.error ?? "request failed")
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

    case .message:
        print(response.message ?? "ok")
    }
}

func printHelp(_ topic: HelpTopic) {
    switch topic {
    case .root:
        print("""
        Usage:
          wb [<id>] <url>
          wb create
          wb list
          wb close <id>
          wb dump <id>
          wb show <id>
          wb hide <id>

          wb page <id> [--fields <list>] [--selectors|--action-details]
          wb click <id> <action>
          wb fill <id> <action> <text>
          wb submit <id> <action>
          wb eval <id> [--body] <javascript>

          wb daemon <start|status|log|stop>

        Options:
          -h, --help            Show help.

        Notes:
          - Browsers persist between commands; use wb list to see saved IDs.
          - Dumped browser IDs resume automatically when used.
          - JSON output is compact and omits false, empty, and null fields.
          - Run 'wb <command> --help' for command details.
        """)

    case .create:
        print("""
        Usage:
          wb create

        Creates an empty browser and prints its ID.
        """)

    case .list:
        print("""
        Usage:
          wb list

        Lists active and dumped browsers as compact JSON.
        """)

    case .close:
        print("""
        Usage:
          wb close <id>

        Closes an active browser and deletes any dumped session for that ID.
        """)

    case .dump:
        print("""
        Usage:
          wb dump <id>

        Saves the browser so it can be resumed later.
        """)

    case .show:
        print("""
        Usage:
          wb show <id>

        Shows a lightweight browser window for the browser.
        """)

    case .hide:
        print("""
        Usage:
          wb hide <id>

        Hides the browser window without closing the browser.
        """)

    case .page:
        print("""
        Usage:
          wb page <id> [--fields <list>] [--selectors|--action-details]

        Prints visible page text, page metadata, and actionable elements.

        Options:
          --fields <list>       Comma-separated fields: \(PageField.validList)
          --selectors           Include action CSS selectors.
          --action-details      Include action id, index, tag, type, and selector.

        Notes:
          - Default actions include kind, text, href, and disabled state.
          - Use action numbers by default; use --action-details to get action IDs.
        """)

    case .click:
        print("""
        Usage:
          wb click <id> <action>

        Clicks an action from the latest page output.
        <action> may be a 1-based number or an action ID.
        """)

    case .fill:
        print("""
        Usage:
          wb fill <id> <action> <text>

        Sets the value of an input, textarea, select, or contenteditable action.
        <action> may be a 1-based number or an action ID.
        """)

    case .submit:
        print("""
        Usage:
          wb submit <id> <action>

        Submits the nearest form for an action, or clicks the action if no form exists.
        <action> may be a 1-based number or an action ID.
        """)

    case .eval:
        print("""
        Usage:
          wb eval <id> [--body] <javascript>

        Evaluates JavaScript in the browser and prints the result.

        Options:
          --body                Treat the script as a WebPage.callJavaScript body.
        """)

    case .daemon:
        print("""
        Usage:
          wb daemon start [--idle-timeout <seconds|off>]
          wb daemon status
          wb daemon log
          wb daemon stop

        Controls the local browser daemon.
        """)

    case .daemonStart:
        print("""
        Usage:
          wb daemon start [--idle-timeout <seconds|off>]

        Starts the daemon if it is not running.

        Options:
          --idle-timeout <seconds|off>    Override idle shutdown for this daemon.
        """)

    case .daemonStatus:
        print("""
        Usage:
          wb daemon status

        Prints 'running' or 'not running'.
        """)

    case .daemonLog:
        print("""
        Usage:
          wb daemon log

        Prints the daemon log file path.
        """)

    case .daemonStop:
        print("""
        Usage:
          wb daemon stop

        Dumps active browsers and stops the daemon.
        """)
    }
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
            throw WBError.message(errorMessage)
        }
        return removeFirst()
    }

    mutating func popInt(_ errorMessage: String) throws -> Int {
        let value = try popFirst(errorMessage)
        guard let integer = Int(value) else {
            throw WBError.message("expected integer, got \(value)")
        }
        return integer
    }

    func joinRemaining(_ errorMessage: String) throws -> String {
        let value = joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            throw WBError.message(errorMessage)
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

        guard let parsed = WBConfig.parseIdleTimeout(rawValue) else {
            throw WBError.message("invalid idle timeout \(rawValue)")
        }
        idleTimeout = parsed
    }

    arguments = remaining
    return idleTimeout
}
