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
    case daemonStatus
    case daemonStart
    case browserID
    case browsers
    case browserMessage
    case pageSummary
    case page
    case interaction
    case value
    case text
    case html
    case message
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
        case "browser":
            return try parseBrowserCommand(browser: browser, arguments: arguments)

        case "daemon":
            return try parseDaemonCommand(arguments)

        case "open", "go":
            let full = arguments.removeFlag("--full")
            let url = try arguments.popFirst("usage: wp open <url>")
            return CLIInvocation(
                request: WireRequest(command: .open, browser: browser, url: url),
                renderMode: full ? .page : .pageSummary,
                startDaemon: true,
                daemonIdleTimeout: nil
            )

        case "page":
            return CLIInvocation(
                request: WireRequest(command: .page, browser: browser),
                renderMode: .page,
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
            let script = try arguments.joinRemaining("usage: wp -b <id> eval <javascript-expression>")
            return CLIInvocation(
                request: WireRequest(command: .eval, browser: browser, script: script),
                renderMode: .value,
                startDaemon: true
            )

        case "js":
            let script = try arguments.joinRemaining("usage: wp -b <id> js <javascript-function-body>")
            return CLIInvocation(
                request: WireRequest(command: .js, browser: browser, script: script),
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

    case .page:
        try printJSON(try response.page.unwrap("daemon did not return page data"))

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
      wp open --full <url>
      wp --browser <id> open <url>
      wp -b <id> page
      wp -b <id> click <action-number>
      wp -b <id> fill <action-number> <text>
      wp -b <id> submit <action-number>
      wp -b <id> eval <javascript-expression>
      wp -b <id> js <javascript-function-body>
      wp -b <id> text [css-selector]
      wp -b <id> html [css-selector]

      wp daemon start [--idle-timeout <seconds|off>]
      wp daemon status
      wp daemon stop

    Notes:
      - Commands auto-start a local daemon, except daemon status/stop.
      - 'wp open <url>' creates a browser, opens the page, and prints a compact summary.
      - Use 'wp open --full <url>' or 'wp -b <id> page' to print full page snapshots.
      - JSON output is compact and omits false, empty, and null fields.
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
    let actions: Int?

    init(browser: String?, message: String?, page: PageSnapshot?) {
        self.browser = browser ?? page?.browser
        self.message = message
        title = page.flatMap { $0.title.nilIfEmpty }
        url = page.flatMap { $0.url }
        loading = page?.loading ?? false
        progress = page?.progress
        actions = page.map { $0.actions.count }
    }
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

    mutating func removeFlag(_ flag: String) -> Bool {
        guard let index = firstIndex(of: flag) else {
            return false
        }
        remove(at: index)
        return true
    }
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
