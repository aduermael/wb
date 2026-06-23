/// Installs or updates the embedded wb agent skill in supported local agent
/// skill directories without involving the browser daemon.
import Foundation

enum SkillInstallMode: Equatable {
	case install
	case updateExisting
}

enum SkillInstallTarget: Equatable {
	case codex
	case claude
	case grok
	case custom(String)

	static let allBuiltIn: [SkillInstallTarget] = [.codex, .claude, .grok]

	var displayName: String {
		switch self {
		case .codex:
			return "codex"
		case .claude:
			return "claude"
		case .grok:
			return "grok"
		case .custom(let path):
			return path
		}
	}

	func destination(skillName: String, baseDirectory: URL) -> URL {
		switch self {
		case .codex:
			return
				baseDirectory
				.appendingPathComponent(".agents", isDirectory: true)
				.appendingPathComponent("skills", isDirectory: true)
				.appendingPathComponent(skillName, isDirectory: true)

		case .claude:
			return
				baseDirectory
				.appendingPathComponent(".claude", isDirectory: true)
				.appendingPathComponent("skills", isDirectory: true)
				.appendingPathComponent(skillName, isDirectory: true)

		case .grok:
			return
				baseDirectory
				.appendingPathComponent(".grok", isDirectory: true)
				.appendingPathComponent("skills", isDirectory: true)
				.appendingPathComponent(skillName, isDirectory: true)

		case .custom(let path):
			return Self.url(for: path, baseDirectory: baseDirectory)
		}
	}

	private static func url(for path: String, baseDirectory: URL) -> URL {
		let expanded = NSString(string: path).expandingTildeInPath
		if expanded.hasPrefix("/") {
			return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
		}
		return URL(fileURLWithPath: expanded, relativeTo: baseDirectory).standardizedFileURL
	}
}

struct SkillInstallOptions: Equatable {
	var targets = SkillInstallTarget.allBuiltIn
	var mode = SkillInstallMode.install
	var skillName = "wb"
	var baseDirectory = WBConfig.currentProjectDirectory()

	static var autoUpdateDefaults: SkillInstallOptions {
		var options = SkillInstallOptions()
		options.mode = .updateExisting
		return options
	}
}

struct SkillInstallReport: Equatable {
	var installed: [String] = []
	var updated: [String] = []
	var unchanged: [String] = []
	var skipped: [String] = []

	var didTouchAnyTarget: Bool {
		!installed.isEmpty || !updated.isEmpty || !unchanged.isEmpty
	}
}

enum SkillInstaller {
	static func run(options: SkillInstallOptions) throws {
		let report = try install(options: options)
		printReport(report, mode: options.mode)
	}

	static func install(options: SkillInstallOptions) throws -> SkillInstallReport {
		var report = SkillInstallReport()
		for target in deduplicated(options.targets) {
			let destination = target.destination(
				skillName: options.skillName,
				baseDirectory: options.baseDirectory
			)
			let status = try installTarget(destination, mode: options.mode)
			report.record(status, path: destination.path)
		}
		return report
	}

	static func hasExistingSkill(options: SkillInstallOptions) -> Bool {
		deduplicated(options.targets).contains { target in
			let destination = target.destination(
				skillName: options.skillName,
				baseDirectory: options.baseDirectory
			)
			let skillURL = destination.appendingPathComponent("SKILL.md", isDirectory: false)
			return FileManager.default.fileExists(atPath: skillURL.path)
		}
	}

	static func hasOutdatedSkill(options: SkillInstallOptions) -> Bool {
		deduplicated(options.targets).contains { target in
			let destination = target.destination(
				skillName: options.skillName,
				baseDirectory: options.baseDirectory
			)
			return isOutdatedExistingTarget(destination)
		}
	}

	private static func installTarget(_ destination: URL, mode: SkillInstallMode) throws -> SkillInstallStatus {
		let skillURL = destination.appendingPathComponent("SKILL.md", isDirectory: false)
		let hadSkill = FileManager.default.fileExists(atPath: skillURL.path)

		if mode == .updateExisting && !hadSkill {
			return .skipped
		}

		try ensureDirectory(destination)

		let installerURL = destination.appendingPathComponent("install.sh", isDirectory: false)
		let skillChanged = try writeIfNeeded(EmbeddedSkill.skillData, to: skillURL)
		let installerChanged = try writeIfNeeded(EmbeddedSkill.installScriptData, to: installerURL)
		let permissionChanged = try makeExecutableIfNeeded(installerURL)

		if !skillChanged && !installerChanged && !permissionChanged {
			return .unchanged
		}
		return hadSkill ? .updated : .installed
	}

	private static func ensureDirectory(_ destination: URL) throws {
		var isDirectory = ObjCBool(false)
		let exists = FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory)
		if exists {
			guard isDirectory.boolValue else {
				throw WBError.message(
					"cannot install skill at \(destination.path); a file already exists")
			}
			return
		}
		try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
	}

	private static func writeIfNeeded(_ data: Data, to destination: URL) throws -> Bool {
		if let existing = try? Data(contentsOf: destination), existing == data {
			return false
		}
		try data.write(to: destination, options: .atomic)
		return true
	}

	private static func makeExecutableIfNeeded(_ destination: URL) throws -> Bool {
		guard !FileManager.default.isExecutableFile(atPath: destination.path) else {
			return false
		}
		try FileManager.default.setAttributes(
			[.posixPermissions: 0o755],
			ofItemAtPath: destination.path
		)
		return true
	}

	private static func isOutdatedExistingTarget(_ destination: URL) -> Bool {
		let skillURL = destination.appendingPathComponent("SKILL.md", isDirectory: false)
		guard FileManager.default.fileExists(atPath: skillURL.path) else {
			return false
		}
		let installerURL = destination.appendingPathComponent("install.sh", isDirectory: false)
		return dataDiffers(EmbeddedSkill.skillData, from: skillURL)
			|| dataDiffers(EmbeddedSkill.installScriptData, from: installerURL)
			|| !FileManager.default.isExecutableFile(atPath: installerURL.path)
	}

	private static func dataDiffers(_ data: Data, from url: URL) -> Bool {
		guard let existing = try? Data(contentsOf: url) else {
			return true
		}
		return existing != data
	}

	private static func deduplicated(_ targets: [SkillInstallTarget]) -> [SkillInstallTarget] {
		var seen: Set<String> = []
		var result: [SkillInstallTarget] = []
		for target in targets {
			let key = target.displayName
			if seen.insert(key).inserted {
				result.append(target)
			}
		}
		return result
	}

	private static func printReport(_ report: SkillInstallReport, mode: SkillInstallMode) {
		if !report.installed.isEmpty {
			printList("Installed wb skill:", report.installed)
		}
		if !report.updated.isEmpty {
			printList("Updated wb skill:", report.updated)
		}
		if !report.unchanged.isEmpty {
			printList("wb skill already up to date:", report.unchanged)
		}
		if mode == .updateExisting && !report.didTouchAnyTarget {
			print("No existing wb skill folders found; nothing installed.")
		}
	}

	private static func printList(_ title: String, _ paths: [String]) {
		print(title)
		for path in paths {
			print("  \(path)")
		}
	}
}

private enum SkillInstallStatus {
	case installed
	case updated
	case unchanged
	case skipped
}

private extension SkillInstallReport {
	mutating func record(_ status: SkillInstallStatus, path: String) {
		switch status {
		case .installed:
			installed.append(path)
		case .updated:
			updated.append(path)
		case .unchanged:
			unchanged.append(path)
		case .skipped:
			skipped.append(path)
		}
	}
}
