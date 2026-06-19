import Foundation

struct CLIInvocation {
    let request: WireRequest?
    let renderMode: RenderMode
    let startDaemon: Bool
}

enum RenderMode {
    case help
    case daemonStatus
    case browserID
    case browsers
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
            let url = try arguments.popFirst("usage: wp open <url>")
            return CLIInvocation(
                request: WireRequest(command: .open, browser: browser, url: url),
                renderMode: .page,
                startDaemon: true
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
                startDaemon: true
            )

        case "list", "ls":
            return CLIInvocation(
                request: WireRequest(command: .browserList),
                renderMode: .browsers,
                startDaemon: true
            )

        case "close", "delete", "rm":
            let id = arguments.first ?? browser
            return CLIInvocation(
                request: WireRequest(command: .browserClose, browser: id),
                renderMode: .message,
                startDaemon: true
            )

        default:
            throw WPError.message("unknown browser command \(command)")
        }
    }

    private static func parseDaemonCommand(_ arguments: [String]) throws -> CLIInvocation {
        guard let command = arguments.first else {
            throw WPError.message("usage: wp daemon <status|stop>")
        }

        switch command {
        case "status":
            return CLIInvocation(request: nil, renderMode: .daemonStatus, startDaemon: false)

        case "stop":
            return CLIInvocation(
                request: WireRequest(command: .daemonStop),
                renderMode: .message,
                startDaemon: false
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

    case .browserID:
        print(try response.browser.unwrap("daemon did not return a browser id"))

    case .browsers:
        try printJSON(response.browsers ?? [])

    case .page:
        try printJSON(try response.page.unwrap("daemon did not return page data"))

    case .interaction:
        try printJSON(InteractionOutput(
            browser: response.browser,
            message: response.message,
            page: response.page
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

      wp open <url>
      wp --browser <id> open <url>
      wp -b <id> page
      wp -b <id> click <action-number>
      wp -b <id> fill <action-number> <text>
      wp -b <id> submit <action-number>
      wp -b <id> eval <javascript-expression>
      wp -b <id> js <javascript-function-body>
      wp -b <id> text [css-selector]
      wp -b <id> html [css-selector]

      wp daemon status
      wp daemon stop

    Notes:
      - Commands auto-start a local daemon, except daemon status/stop.
      - 'wp open <url>' creates a new browser, opens the page, and prints page JSON.
      - 'wp -b <id> page' refreshes actions and prints page JSON.
    """)
}

private struct InteractionOutput: Encodable {
    let browser: String?
    let message: String?
    let page: PageSnapshot?
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
}
