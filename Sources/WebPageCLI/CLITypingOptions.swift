/// Parses text-entry-specific command-line options for the type command while
/// keeping the main CLI parser file below the repository size limit.
import Foundation

struct TypingOptions {
	var min: TimeInterval?
	var max: TimeInterval?
	var backend: TypingBackend?
	var rhythm: TypingRhythm?
	var speed: Double?
}

func parseTypingOptions(_ arguments: inout [String]) throws -> TypingOptions {
	var options = TypingOptions()
	var remaining: [String] = []

	while !arguments.isEmpty {
		let argument = arguments.removeFirst()

		switch argument {
		case "--delay-min":
			let rawDelay = try popTypingOptionValue(from: &arguments, after: argument)
			options.min = try TypingDelay.parse(rawDelay)

		case let option where option.hasPrefix("--delay-min="):
			options.min = try TypingDelay.parse(String(option.dropFirst("--delay-min=".count)))

		case "--delay-max":
			let rawDelay = try popTypingOptionValue(from: &arguments, after: argument)
			options.max = try TypingDelay.parse(rawDelay)

		case let option where option.hasPrefix("--delay-max="):
			options.max = try TypingDelay.parse(String(option.dropFirst("--delay-max=".count)))

		case "--speed":
			let rawSpeed = try popTypingOptionValue(from: &arguments, after: argument)
			options.speed = try TypingSpeed.parse(rawSpeed)

		case let option where option.hasPrefix("--speed="):
			options.speed = try TypingSpeed.parse(String(option.dropFirst("--speed=".count)))

		case "--backend":
			let rawBackend = try popTypingOptionValue(from: &arguments, after: argument)
			options.backend = try TypingBackend.parse(rawBackend)

		case let option where option.hasPrefix("--backend="):
			options.backend = try TypingBackend.parse(String(option.dropFirst("--backend=".count)))

		case "--rhythm":
			let rawRhythm = try popTypingOptionValue(from: &arguments, after: argument)
			options.rhythm = try TypingRhythm.parse(rawRhythm)

		case let option where option.hasPrefix("--rhythm="):
			options.rhythm = try TypingRhythm.parse(String(option.dropFirst("--rhythm=".count)))

		default:
			remaining.append(argument)
		}
	}

	arguments = remaining
	if options.min != nil || options.max != nil {
		_ = try WireRequest(command: .typeText)
			.withTypingDelays(min: options.min, max: options.max)
			.typingDelayRange()
	}
	return options
}

private func popTypingOptionValue(from arguments: inout [String], after option: String) throws -> String {
	guard !arguments.isEmpty else {
		throw WBError.message("missing value after \(option)")
	}
	return arguments.removeFirst()
}
