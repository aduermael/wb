/// Parses options for the local skill installer command while keeping the main
/// command parser focused on routing.
import Foundation

func parseSkillInstallOptions(_ rawArguments: [String]) throws -> SkillInstallOptions {
	var arguments = rawArguments
	var options = SkillInstallOptions()
	options.targets = []

	while !arguments.isEmpty {
		let argument = arguments.removeFirst()
		switch argument {
		case "--codex", "--agents", "--openai":
			options.targets.append(.codex)

		case "--claude":
			options.targets.append(.claude)

		case "--grok":
			options.targets.append(.grok)

		case "--all":
			options.targets.append(contentsOf: SkillInstallTarget.allBuiltIn)

		case "--auto-update-existing", "--update-existing":
			options.mode = .updateExisting

		case "--target", "--path":
			let value = try popSkillInstallValue(from: &arguments, after: argument)
			options.targets.append(try parseSkillInstallTarget(value))

		case let option where option.hasPrefix("--target="):
			let value = String(option.dropFirst("--target=".count))
			options.targets.append(try parseSkillInstallTarget(value))

		case let option where option.hasPrefix("--path="):
			let value = String(option.dropFirst("--path=".count))
			options.targets.append(try parseSkillInstallTarget(value))

		case "--name":
			let value = try popSkillInstallValue(from: &arguments, after: argument)
			options.skillName = try parseSkillInstallName(value)

		case let option where option.hasPrefix("--name="):
			let value = String(option.dropFirst("--name=".count))
			options.skillName = try parseSkillInstallName(value)

		default:
			throw WBError.message("unknown install-skill option \(argument)")
		}
	}

	if options.targets.isEmpty {
		options.targets = SkillInstallTarget.allBuiltIn
	}
	return options
}

private func popSkillInstallValue(from arguments: inout [String], after option: String) throws -> String {
	guard !arguments.isEmpty else {
		throw WBError.message("missing value after \(option)")
	}
	return arguments.removeFirst()
}

private func parseSkillInstallTarget(_ rawValue: String) throws -> SkillInstallTarget {
	let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
	guard !value.isEmpty else {
		throw WBError.message("empty install-skill target")
	}

	switch value {
	case "codex", "agents", "openai":
		return .codex
	case "claude":
		return .claude
	case "grok":
		return .grok
	default:
		return .custom(value)
	}
}

private func parseSkillInstallName(_ rawValue: String) throws -> String {
	let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
	guard !value.isEmpty else {
		throw WBError.message("skill name cannot be empty")
	}
	guard !value.contains("/") && !value.contains("\0") else {
		throw WBError.message("skill name cannot contain path separators")
	}
	return value
}
