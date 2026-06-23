/// Launches silent, best-effort skill refreshes for the current project without
/// blocking normal browser CLI work.
import Foundation

enum SkillAutoUpdater {
	static func maybeLaunch(for invocation: CLIInvocation) {
		let environment = ProcessInfo.processInfo.environment
		guard shouldLaunch(for: invocation, environment: environment) else {
			return
		}
		guard let executablePath = try? WBUpdater.currentExecutablePath() else {
			return
		}
		launch(executablePath: executablePath, environment: environment)
	}

	static func launch(executablePath: String, environment: [String: String]) {
		guard isEnabled(environment: environment) else {
			return
		}
		guard SkillInstaller.hasOutdatedSkill(options: SkillInstallOptions.autoUpdateDefaults) else {
			return
		}
		let process = Process()
		process.executableURL = URL(fileURLWithPath: executablePath)
		process.arguments = ["install-skill", "--auto-update-existing"]
		process.environment = environment.merging(["WB_SKILL_AUTO_UPDATE": "0"]) { _, new in new }
		if let nullDevice = FileHandle(forWritingAtPath: "/dev/null") {
			process.standardOutput = nullDevice
			process.standardError = nullDevice
		}
		try? process.run()
	}

	static func shouldLaunch(
		for invocation: CLIInvocation,
		environment: [String: String]
	) -> Bool {
		guard isEnabled(environment: environment) else {
			return false
		}
		if case .help = invocation.renderMode {
			return false
		}
		switch invocation.localCommand {
		case .some(.installSkill), .some(.update), .some(.version):
			return false
		case .some(.environment), .none:
			return true
		}
	}

	private static func isEnabled(environment: [String: String]) -> Bool {
		!isExplicitlyOff(environment["WB_SKILL_AUTO_UPDATE"])
			&& !isTruthy(environment["WB_NO_SKILL_AUTO_UPDATE"])
	}

	private static func isExplicitlyOff(_ value: String?) -> Bool {
		guard let normalized = normalizedEnvironmentValue(value) else {
			return false
		}
		return ["0", "false", "no", "off"].contains(normalized)
	}

	private static func isTruthy(_ value: String?) -> Bool {
		guard let normalized = normalizedEnvironmentValue(value) else {
			return false
		}
		return ["1", "true", "yes", "on"].contains(normalized)
	}

	private static func normalizedEnvironmentValue(_ value: String?) -> String? {
		value?
			.trimmingCharacters(in: .whitespacesAndNewlines)
			.lowercased()
			.nilIfEmpty
	}
}
