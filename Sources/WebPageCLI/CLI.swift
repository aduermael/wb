/// Parses command-line arguments into wire requests and local commands for the
/// browser CLI while keeping command validation strict and output behavior
/// deterministic for scripts and agents.
import Foundation

struct CLIInvocation {
	let request: WireRequest?
	let localCommand: LocalCommand?
	let renderMode: RenderMode
	let startDaemon: Bool
	let daemonIdleTimeout: TimeInterval?

	init(request: WireRequest?, renderMode: RenderMode, daemon: DaemonLaunch) {
		self.request = request
		localCommand = nil
		self.renderMode = renderMode
		startDaemon = daemon.shouldStart
		daemonIdleTimeout = daemon.idleTimeout
	}

	init(localCommand: LocalCommand, renderMode: RenderMode) {
		request = nil
		self.localCommand = localCommand
		self.renderMode = renderMode
		startDaemon = false
		daemonIdleTimeout = nil
	}
}

struct DaemonLaunch {
	let shouldStart: Bool
	let idleTimeout: TimeInterval?

	static let disabled = DaemonLaunch(shouldStart: false, idleTimeout: nil)
	static let enabled = DaemonLaunch(shouldStart: true, idleTimeout: nil)

	static func starting(idleTimeout: TimeInterval?) -> DaemonLaunch {
		DaemonLaunch(shouldStart: true, idleTimeout: idleTimeout)
	}
}

enum LocalCommand {
	case environment
	case installSkill(SkillInstallOptions)
	case update
	case version
}

enum RenderMode {
	case silent
	case help(HelpTopic)
	case daemonStatus
	case daemonStart
	case daemonLogPath
	case browserID
	case browsers
	case pageSummary
	case page(PageOutputOptions)
	case interaction
	case value
	case message
}

enum HelpTopic {
	case root
	case environment
	case installSkill
	case update
	case version
	case create
	case list
	case close
	case show
	case hide
	case resize
	case screenshot
	case page
	case click
	case press
	case drag
	case release
	case scroll
	case fill
	case type
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
		if arguments.first == "--version" || arguments.first == "-V" {
			arguments.removeFirst()
			guard arguments.isEmpty else {
				throw WBError.message("unexpected version argument \(arguments[0])")
			}
			return CLIInvocation(localCommand: .version, renderMode: .silent)
		}

		guard let command = arguments.first else {
			return help(.root)
		}

		arguments.removeFirst()

		switch command {
		case "help":
			return try parseHelpCommand(arguments)

		case "env", "environment":
			if arguments.containsHelpFlag {
				return help(.environment)
			}
			guard arguments.isEmpty else {
				throw WBError.message("unexpected env argument \(arguments[0])")
			}
			return CLIInvocation(localCommand: .environment, renderMode: .silent)

		case "install-skill":
			if arguments.containsHelpFlag {
				return help(.installSkill)
			}
			let options = try parseSkillInstallOptions(arguments)
			return CLIInvocation(localCommand: .installSkill(options), renderMode: .silent)

		case "update":
			if arguments.containsHelpFlag {
				return help(.update)
			}
			guard arguments.isEmpty else {
				throw WBError.message("unexpected update argument \(arguments[0])")
			}
			return CLIInvocation(localCommand: .update, renderMode: .silent)

		case "version":
			if arguments.containsHelpFlag {
				return help(.version)
			}
			guard arguments.isEmpty else {
				throw WBError.message("unexpected version argument \(arguments[0])")
			}
			return CLIInvocation(localCommand: .version, renderMode: .silent)

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
				daemon: .enabled
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
				daemon: .enabled
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
				request: WireRequest(command: .browserClose).withBrowser(id),
				renderMode: .message,
				daemon: .enabled
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
				request: WireRequest(command: .browserShow).withBrowser(id),
				renderMode: .silent,
				daemon: .enabled
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
				request: WireRequest(command: .browserHide).withBrowser(id),
				renderMode: .silent,
				daemon: .enabled
			)

		case "resize":
			if arguments.containsHelpFlag {
				return help(.resize)
			}
			let resizeUsage = "usage: wb resize <id> [<width> <height>]"
			let id = try popBrowserID(
				from: &arguments,
				usage: resizeUsage
			)
			let size: BrowserWindowSize
			if arguments.isEmpty {
				size = BrowserWindowSizing.defaultSize
			} else {
				let width = try arguments.popInt(resizeUsage)
				let height = try arguments.popInt(resizeUsage)
				guard arguments.isEmpty else {
					throw WBError.message("unexpected resize argument \(arguments[0])")
				}
				size = try BrowserWindowSizing.validate(width: width, height: height)
			}
			return CLIInvocation(
				request: WireRequest(command: .browserResize)
					.withBrowser(id)
					.withWindowSize(size),
				renderMode: .message,
				daemon: .enabled
			)

		case "screenshot":
			if arguments.containsHelpFlag {
				return help(.screenshot)
			}
			var arguments = arguments
			let resourceOptions = try parseResourceLoadingOptions(&arguments)
			let captureDelay = try parseScreenshotCaptureDelayOption(&arguments)
			let screenshotUsage = [
				"usage: wb screenshot <id> <destination.png|destination.jpg>",
				"[--resource-timeout <seconds>]",
				"[--capture-delay <seconds>]",
			].joined(separator: " ")
			let id = try popBrowserID(
				from: &arguments,
				usage: screenshotUsage
			)
			let destination = try arguments.popFirst(screenshotUsage)
			guard arguments.isEmpty else {
				throw WBError.message("unexpected screenshot argument \(arguments[0])")
			}
			try validateScreenshotDestination(destination)
			return CLIInvocation(
				request: WireRequest(command: .screenshot)
					.withBrowser(id)
					.withDestinationPath(absolutePath(for: destination))
					.withResourceLoading(waitForResources: true, timeout: resourceOptions.timeout)
					.withScreenshotDelay(captureDelay),
				renderMode: .message,
				daemon: .enabled
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
				request: WireRequest(command: .page).withBrowser(id),
				renderMode: .page(pageOptions),
				daemon: .enabled
			)

		case "click":
			if arguments.containsHelpFlag {
				return help(.click)
			}
			let id = try popBrowserID(
				from: &arguments,
				usage: "usage: wb click <id> <action>\n       wb click <id> <x> <y>"
			)
			if arguments.count == 2 {
				let x = try arguments[0].parsedDouble("expected x coordinate, got \(arguments[0])")
				let y = try arguments[1].parsedDouble("expected y coordinate, got \(arguments[1])")
				return CLIInvocation(
					request: WireRequest(command: .coordinate)
						.withBrowser(id)
						.withCoordinate("click", point: WirePoint(x: x, y: y)),
					renderMode: .interaction,
					daemon: .enabled
				)
			}
			let action = try arguments.popFirst("usage: wb click <id> <action>")
			guard arguments.isEmpty else {
				throw WBError.message("unexpected click argument \(arguments[0])")
			}
			return CLIInvocation(
				request: WireRequest(command: .click)
					.withBrowser(id)
					.withAction(action),
				renderMode: .interaction,
				daemon: .enabled
			)

		case "press":
			return try parseCoordinatePointCommand(
				name: "press",
				helpTopic: .press,
				arguments: arguments
			)

		case "drag":
			return try parseCoordinatePointCommand(
				name: "drag",
				helpTopic: .drag,
				arguments: arguments
			)

		case "release":
			return try parseCoordinatePointCommand(
				name: "release",
				helpTopic: .release,
				arguments: arguments
			)

		case "scroll":
			if arguments.containsHelpFlag {
				return help(.scroll)
			}
			let id = try popBrowserID(
				from: &arguments,
				usage: "usage: wb scroll <id> <x> <y> <deltaX> <deltaY>"
			)
			let x = try arguments.popDouble("usage: wb scroll <id> <x> <y> <deltaX> <deltaY>")
			let y = try arguments.popDouble("usage: wb scroll <id> <x> <y> <deltaX> <deltaY>")
			let deltaX = try arguments.popDouble("usage: wb scroll <id> <x> <y> <deltaX> <deltaY>")
			let deltaY = try arguments.popDouble("usage: wb scroll <id> <x> <y> <deltaX> <deltaY>")
			guard arguments.isEmpty else {
				throw WBError.message("unexpected scroll argument \(arguments[0])")
			}
			return CLIInvocation(
				request: WireRequest(command: .coordinate)
					.withBrowser(id)
					.withCoordinate(
						"scroll",
						point: WirePoint(x: x, y: y),
						delta: WireDelta(x: deltaX, y: deltaY)
					),
				renderMode: .interaction,
				daemon: .enabled
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
				request: WireRequest(command: .fill)
					.withBrowser(id)
					.withAction(action)
					.withValue(value),
				renderMode: .interaction,
				daemon: .enabled
			)

		case "type":
			if arguments.containsHelpFlag {
				return help(.type)
			}
			var arguments = arguments
			let typingOptions = try parseTypingOptions(&arguments)
			let usage =
				"usage: wb type <id> <action> <text> [--backend js|native] "
				+ "[--rhythm flat|natural] [--delay-min <seconds>] [--delay-max <seconds>]"
			let id = try popBrowserID(
				from: &arguments,
				usage: usage
			)
			let action = try arguments.popFirst(usage)
			let value = try arguments.joinRemaining(usage)
			return CLIInvocation(
				request: WireRequest(command: .typeText)
					.withBrowser(id)
					.withAction(action)
					.withValue(value)
					.withTypingDelays(min: typingOptions.min, max: typingOptions.max)
					.withTypingBackend(typingOptions.backend)
					.withTypingRhythm(typingOptions.rhythm),
				renderMode: .interaction,
				daemon: .enabled
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
				request: WireRequest(command: .submit)
					.withBrowser(id)
					.withAction(action),
				renderMode: .interaction,
				daemon: .enabled
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
				request: WireRequest(command: .eval)
					.withBrowser(id)
					.withScript(script, functionBody: functionBody ? true : nil),
				renderMode: .value,
				daemon: .enabled
			)

		default:
			return try parsePositionalOpen(first: command, rest: arguments)
		}
	}

	private static func parsePositionalOpen(first: String, rest arguments: [String]) throws -> CLIInvocation {
		var arguments = [first] + arguments
		let resourceOptions = try parseResourceLoadingOptions(&arguments)

		guard let first = arguments.first else {
			throw WBError.message("missing URL")
		}
		arguments.removeFirst()

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
			request: WireRequest(command: .open)
				.withBrowser(browser)
				.withURL(url)
				.withResourceLoading(
					waitForResources: resourceOptions.waitForResources,
					timeout: resourceOptions.timeout
				),
			renderMode: .pageSummary,
			daemon: .enabled
		)
	}

	private static func help(_ topic: HelpTopic) -> CLIInvocation {
		CLIInvocation(request: nil, renderMode: .help(topic), daemon: .disabled)
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
		case "env", "environment":
			return help(.environment)
		case "install-skill":
			return help(.installSkill)
		case "update":
			return help(.update)
		case "version":
			return help(.version)
		case "create":
			return help(.create)
		case "list", "ls":
			return help(.list)
		case "close", "delete", "rm":
			return help(.close)
		case "show":
			return help(.show)
		case "hide":
			return help(.hide)
		case "resize":
			return help(.resize)
		case "screenshot":
			return help(.screenshot)
		case "page":
			return help(.page)
		case "click":
			return help(.click)
		case "press":
			return help(.press)
		case "drag":
			return help(.drag)
		case "release":
			return help(.release)
		case "scroll":
			return help(.scroll)
		case "fill":
			return help(.fill)
		case "type":
			return help(.type)
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

	private static func parseCoordinatePointCommand(
		name: String,
		helpTopic: HelpTopic,
		arguments: [String]
	) throws -> CLIInvocation {
		var arguments = arguments
		if arguments.containsHelpFlag {
			return help(helpTopic)
		}
		let id = try popBrowserID(
			from: &arguments,
			usage: "usage: wb \(name) <id> <x> <y>"
		)
		let x = try arguments.popDouble("usage: wb \(name) <id> <x> <y>")
		let y = try arguments.popDouble("usage: wb \(name) <id> <x> <y>")
		guard arguments.isEmpty else {
			throw WBError.message("unexpected \(name) argument \(arguments[0])")
		}
		return CLIInvocation(
			request: WireRequest(command: .coordinate)
				.withBrowser(id)
				.withCoordinate(name, point: WirePoint(x: x, y: y)),
			renderMode: .interaction,
			daemon: .enabled
		)
	}

	private static func validateScreenshotDestination(_ path: String) throws {
		let pathExtension = URL(fileURLWithPath: path)
			.pathExtension
			.lowercased()
		guard ["png", "jpg", "jpeg"].contains(pathExtension) else {
			throw WBError.message("screenshot destination must end in .png, .jpg, or .jpeg")
		}
	}

	private static func absolutePath(for path: String) -> String {
		let expanded = NSString(string: path).expandingTildeInPath
		let url: URL
		if expanded.hasPrefix("/") {
			url = URL(fileURLWithPath: expanded)
		} else {
			url = URL(
				fileURLWithPath: expanded,
				relativeTo: URL(
					fileURLWithPath: FileManager.default.currentDirectoryPath,
					isDirectory: true
				)
			)
		}
		return url.standardizedFileURL.path
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
				daemon: .starting(idleTimeout: idleTimeout)
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
				daemon: .disabled
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
				daemon: .disabled
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
				daemon: .disabled
			)

		default:
			throw WBError.message("unknown daemon command \(command)")
		}
	}
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

	mutating func popDouble(_ errorMessage: String) throws -> Double {
		let value = try popFirst(errorMessage)
		return try value.parsedDouble("expected number, got \(value)")
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

private extension String {
	func parsedDouble(_ errorMessage: String) throws -> Double {
		guard let value = Double(self), value.isFinite else {
			throw WBError.message(errorMessage)
		}
		return value
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

private struct ResourceLoadingOptions {
	var waitForResources = false
	var timeout: TimeInterval?
}

private func parseResourceLoadingOptions(_ arguments: inout [String]) throws -> ResourceLoadingOptions {
	var options = ResourceLoadingOptions()
	var remaining: [String] = []

	while !arguments.isEmpty {
		let argument = arguments.removeFirst()
		let rawTimeout: String?

		switch argument {
		case "--wait-resources", "--wait-for-resources":
			options.waitForResources = true
			continue

		case "--resource-timeout", "--resources-timeout":
			rawTimeout = try arguments.popFirst("missing value after \(argument)")

		case let option where option.hasPrefix("--resource-timeout="):
			rawTimeout = String(option.dropFirst("--resource-timeout=".count))

		case let option where option.hasPrefix("--resources-timeout="):
			rawTimeout = String(option.dropFirst("--resources-timeout=".count))

		default:
			remaining.append(argument)
			continue
		}

		let timeout = try ResourceLoading.parseTimeout(rawTimeout ?? "")
		options.timeout = timeout
		options.waitForResources = true
	}

	arguments = remaining
	return options
}

private func parseScreenshotCaptureDelayOption(_ arguments: inout [String]) throws -> TimeInterval? {
	var delay: TimeInterval?
	var remaining: [String] = []

	while !arguments.isEmpty {
		let argument = arguments.removeFirst()
		let rawDelay: String?

		switch argument {
		case "--capture-delay", "--screenshot-delay":
			rawDelay = try arguments.popFirst("missing value after \(argument)")

		case let option where option.hasPrefix("--capture-delay="):
			rawDelay = String(option.dropFirst("--capture-delay=".count))

		case let option where option.hasPrefix("--screenshot-delay="):
			rawDelay = String(option.dropFirst("--screenshot-delay=".count))

		default:
			remaining.append(argument)
			continue
		}

		delay = try ScreenshotCapture.parseDelay(rawDelay ?? "")
	}

	arguments = remaining
	return delay
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
