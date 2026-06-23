/// Covers embedded skill installation behavior without invoking external
/// package managers or agent runtimes.
import Foundation
@testable import WebPageCLI

struct SkillInstallerTests {

	func testInstallSkillCommandParsesTargetsAndMode() throws {
		let install = try CLIParser.parse(["install-skill", "--codex", "--claude"])
		XCTAssertNil(install.request)
		XCTAssertFalse(install.startDaemon)
		guard case .some(.installSkill(let options)) = install.localCommand else {
			return XCTFail("expected install-skill local command")
		}
		XCTAssertEqual(options.mode, .install)
		XCTAssertEqual(options.targets, [.codex, .claude])

		let autoUpdate = try CLIParser.parse(["install-skill", "--auto-update-existing"])
		guard case .some(.installSkill(let autoOptions)) = autoUpdate.localCommand else {
			return XCTFail("expected install-skill local command")
		}
		XCTAssertEqual(autoOptions.mode, .updateExisting)
		XCTAssertEqual(autoOptions.targets, SkillInstallTarget.allBuiltIn)

		let help = try CLIParser.parse(["install-skill", "--help"])
		guard case .help(.installSkill) = help.renderMode else {
			return XCTFail("expected install-skill help")
		}
	}

	func testSkillInstallerInstallsAndDetectsUnchangedTarget() throws {
		try withTemporaryDirectory { directory in
			var options = SkillInstallOptions()
			options.baseDirectory = directory
			options.targets = [.codex]

			let destination = SkillInstallTarget.codex.destination(
				skillName: options.skillName,
				baseDirectory: directory
			)
			let report = try SkillInstaller.install(options: options)

			XCTAssertEqual(report.installed, [destination.path])
			XCTAssertEqual(
				try readText(destination.appendingPathComponent("SKILL.md")),
				EmbeddedSkill.skillText + "\n"
			)
			XCTAssertTrue(
				FileManager.default.isExecutableFile(
					atPath: destination.appendingPathComponent("install.sh").path
				)
			)

			let secondReport = try SkillInstaller.install(options: options)
			XCTAssertEqual(secondReport.unchanged, [destination.path])
		}
	}

	func testSkillInstallerAutoUpdateOnlyTouchesExistingTargets() throws {
		try withTemporaryDirectory { directory in
			let codexDestination = SkillInstallTarget.codex.destination(
				skillName: "wb",
				baseDirectory: directory
			)
			var options = SkillInstallOptions()
			options.baseDirectory = directory
			options.mode = .updateExisting

			XCTAssertFalse(SkillInstaller.hasExistingSkill(options: options))
			XCTAssertFalse(SkillInstaller.hasOutdatedSkill(options: options))

			try FileManager.default.createDirectory(at: codexDestination, withIntermediateDirectories: true)
			try Data("old\n".utf8).write(to: codexDestination.appendingPathComponent("SKILL.md"))
			XCTAssertTrue(SkillInstaller.hasExistingSkill(options: options))
			XCTAssertTrue(SkillInstaller.hasOutdatedSkill(options: options))

			let report = try SkillInstaller.install(options: options)

			XCTAssertEqual(report.updated, [codexDestination.path])
			XCTAssertFalse(SkillInstaller.hasOutdatedSkill(options: options))
			XCTAssertFalse(
				FileManager.default.fileExists(
					atPath: SkillInstallTarget.claude
						.destination(skillName: "wb", baseDirectory: directory)
						.path
				)
			)
			XCTAssertEqual(
				try readText(codexDestination.appendingPathComponent("SKILL.md")),
				EmbeddedSkill.skillText + "\n"
			)
		}
	}

	func testSkillInstallerTreatsMissingExecutableBitAsOutdated() throws {
		try withTemporaryDirectory { directory in
			var options = SkillInstallOptions()
			options.baseDirectory = directory
			options.targets = [.codex]

			_ = try SkillInstaller.install(options: options)
			let destination = SkillInstallTarget.codex.destination(
				skillName: "wb",
				baseDirectory: directory
			)
			let installerURL = destination.appendingPathComponent("install.sh")
			try FileManager.default.setAttributes(
				[.posixPermissions: 0o644],
				ofItemAtPath: installerURL.path
			)

			XCTAssertTrue(SkillInstaller.hasOutdatedSkill(options: options))

			let report = try SkillInstaller.install(options: options)

			XCTAssertEqual(report.updated, [destination.path])
			XCTAssertTrue(FileManager.default.isExecutableFile(atPath: installerURL.path))
			XCTAssertFalse(SkillInstaller.hasOutdatedSkill(options: options))
		}
	}

	func testEmbeddedSkillPayloadMatchesCheckedInFiles() throws {
		let root = try packageRoot()

		XCTAssertEqual(
			try readText(root.appendingPathComponent("skill/SKILL.md")),
			EmbeddedSkill.skillText + "\n"
		)
		XCTAssertEqual(
			try readText(root.appendingPathComponent("skill/install.sh")),
			EmbeddedSkill.installScriptText + "\n"
		)
	}

	func testSkillAutoUpdaterLaunchDecisionSkipsNonProjectCommands() throws {
		let open = try CLIParser.parse(["https://example.com"])
		XCTAssertTrue(SkillAutoUpdater.shouldLaunch(for: open, environment: [:]))
		XCTAssertFalse(
			SkillAutoUpdater.shouldLaunch(
				for: open,
				environment: ["WB_SKILL_AUTO_UPDATE": "off"]
			)
		)

		let update = try CLIParser.parse(["update"])
		XCTAssertFalse(SkillAutoUpdater.shouldLaunch(for: update, environment: [:]))

		let install = try CLIParser.parse(["install-skill", "--codex"])
		XCTAssertFalse(SkillAutoUpdater.shouldLaunch(for: install, environment: [:]))

		let help = try CLIParser.parse(["--help"])
		XCTAssertFalse(SkillAutoUpdater.shouldLaunch(for: help, environment: [:]))
	}

	func testProjectDirectoryUsesNearestGitRoot() throws {
		try withTemporaryDirectory { directory in
			let gitRoot = directory.appendingPathComponent("repo", isDirectory: true)
			let nested = gitRoot.appendingPathComponent("Sources/App", isDirectory: true)
			try FileManager.default.createDirectory(
				at: gitRoot.appendingPathComponent(".git", isDirectory: true),
				withIntermediateDirectories: true
			)
			try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

			XCTAssertEqual(WBConfig.projectDirectory(startingAt: nested), gitRoot.standardizedFileURL)
		}
	}
}

private func readText(_ url: URL) throws -> String {
	try String(contentsOf: url, encoding: .utf8)
}

private func packageRoot() throws -> URL {
	var directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
	for _ in 0..<8 {
		if FileManager.default.fileExists(
			atPath: directory.appendingPathComponent("skill/SKILL.md").path
		) {
			return directory
		}
		directory.deleteLastPathComponent()
	}
	throw WBError.message("could not find package root for embedded skill test")
}
