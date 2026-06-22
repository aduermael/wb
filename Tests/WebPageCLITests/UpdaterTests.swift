/// Covers the deterministic pieces of update checking without performing
/// network requests or replacing the test executable.
import Foundation
@testable import WebPageCLI

struct UpdaterTests {

	func testUpdateAndVersionCommandsParseAsLocalCommands() throws {
		let update = try CLIParser.parse(["update"])
		XCTAssertNil(update.request)
		XCTAssertFalse(update.startDaemon)
		guard case .some(.update) = update.localCommand else {
			return XCTFail("expected update local command")
		}

		let version = try CLIParser.parse(["--version"])
		XCTAssertNil(version.request)
		guard case .some(.version) = version.localCommand else {
			return XCTFail("expected version local command")
		}

		assertThrowsMessage(try CLIParser.parse(["update", "--bad"]), "unexpected update argument --bad")
	}

	func testUpdateCheckStateThrottlesForTwelveHours() {
		let now = Date(timeIntervalSince1970: 1_704_067_200)

		XCTAssertTrue(UpdateCheckState(lastCheckedAt: nil).shouldCheck(now: now))
		XCTAssertFalse(
			UpdateCheckState(lastCheckedAt: now.addingTimeInterval(-(WBUpdater.checkInterval - 1)))
				.shouldCheck(now: now)
		)
		XCTAssertTrue(
			UpdateCheckState(lastCheckedAt: now.addingTimeInterval(-WBUpdater.checkInterval))
				.shouldCheck(now: now)
		)
	}

	func testUpdateCheckResultNormalizesTagsAndSkipsDevelopmentBuilds() {
		let stale = UpdateCheckResult(currentVersion: "0.1.0", latestTag: "v0.2.0")
		XCTAssertEqual(stale?.currentTag, "v0.1.0")
		XCTAssertEqual(stale?.latestTag, "v0.2.0")
		XCTAssertTrue(stale?.isStale == true)

		let current = UpdateCheckResult(currentVersion: "v0.2.0", latestTag: "0.2.0")
		XCTAssertFalse(current?.isStale == true)
		XCTAssertNil(UpdateCheckResult(currentVersion: "dev", latestTag: "v0.2.0"))
	}

	func testAutomaticUpdateChecksCanBeDisabledWithEnvironment() {
		XCTAssertFalse(WBUpdater.automaticChecksEnabled(environment: ["WB_UPDATE_CHECK": "off"]))
		XCTAssertFalse(WBUpdater.automaticChecksEnabled(environment: ["WB_UPDATE_CHECK": "0"]))
		XCTAssertFalse(WBUpdater.automaticChecksEnabled(environment: ["WB_NO_UPDATE_CHECK": "1"]))
		XCTAssertTrue(WBUpdater.automaticChecksEnabled(environment: ["WB_UPDATE_CHECK": "on"]))
	}

	func testGitHubReleaseDecodesAssets() throws {
		let data = Data(
			"""
			{
			  "tag_name": "v0.2.0",
			  "assets": [
			    {
			      "name": "wb-macos-arm64.tar.gz",
			      "browser_download_url": "https://example.com/wb-macos-arm64.tar.gz"
			    }
			  ]
			}
			""".utf8)

		let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

		XCTAssertEqual(release.tagName, "v0.2.0")
		XCTAssertEqual(
			release.asset(named: "wb-macos-arm64.tar.gz")?.absoluteString,
			"https://example.com/wb-macos-arm64.tar.gz"
		)
		XCTAssertNil(release.asset(named: "missing.tar.gz"))
	}

	func testInstallationDetectorIdentifiesHomebrewExecutable() throws {
		try withTemporaryDirectory { directory in
			let brewDirectory = directory.appendingPathComponent("bin", isDirectory: true)
			try FileManager.default.createDirectory(at: brewDirectory, withIntermediateDirectories: true)

			let brewPath = brewDirectory.appendingPathComponent("brew")
			try Data("#!/bin/sh\n".utf8).write(to: brewPath)
			try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: brewPath.path)

			let formulaPrefix =
				directory
				.appendingPathComponent("Cellar", isDirectory: true)
				.appendingPathComponent("wb", isDirectory: true)
				.appendingPathComponent("0.2.0", isDirectory: true)
			let executable =
				formulaPrefix
				.appendingPathComponent("bin", isDirectory: true)
				.appendingPathComponent("wb")
			try FileManager.default.createDirectory(
				at: executable.deletingLastPathComponent(),
				withIntermediateDirectories: true
			)
			try Data().write(to: executable)
			try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

			let method = InstallationDetector.detect(
				executablePath: executable.path,
				environment: ["PATH": brewDirectory.path],
				runCommand: { path, arguments in
					XCTAssertEqual(path, brewPath.path)
					switch arguments {
					case ["--prefix", "wb"]:
						return CommandResult(
							status: 0, output: "\(formulaPrefix.path)\n", errorOutput: "")
					case ["--prefix"]:
						return CommandResult(
							status: 0, output: "\(directory.path)\n", errorOutput: "")
					default:
						return CommandResult(
							status: 1, output: "", errorOutput: "unexpected arguments")
					}
				}
			)

			guard case .homebrew(let detectedBrewPath) = method else {
				return XCTFail("expected Homebrew install method")
			}
			XCTAssertEqual(detectedBrewPath, brewPath.path)
		}
	}

	func testInstallationDetectorIdentifiesNPMExecutable() throws {
		try withTemporaryDirectory { directory in
			let binDirectory = directory.appendingPathComponent("bin", isDirectory: true)
			try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)

			let npmPath = binDirectory.appendingPathComponent("npm")
			try Data("#!/bin/sh\n".utf8).write(to: npmPath)
			try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: npmPath.path)

			let packageDirectory =
				directory
				.appendingPathComponent("lib", isDirectory: true)
				.appendingPathComponent("node_modules", isDirectory: true)
				.appendingPathComponent("@aduermael_", isDirectory: true)
				.appendingPathComponent("wb", isDirectory: true)
			let executable =
				packageDirectory
				.appendingPathComponent("npm", isDirectory: true)
				.appendingPathComponent("bin", isDirectory: true)
				.appendingPathComponent("wb")

			try FileManager.default.createDirectory(
				at: executable.deletingLastPathComponent(),
				withIntermediateDirectories: true
			)
			try Data("{\"name\":\"@aduermael_/wb\"}\n".utf8).write(
				to: packageDirectory.appendingPathComponent("package.json")
			)
			try Data().write(to: executable)
			try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

			let method = InstallationDetector.detect(
				executablePath: executable.path,
				environment: ["PATH": binDirectory.path],
				runCommand: { _, _ in
					CommandResult(status: 1, output: "", errorOutput: "unexpected command")
				}
			)

			guard case .npm(let detectedNPMPath, let packageName) = method else {
				return XCTFail("expected npm install method")
			}
			XCTAssertEqual(detectedNPMPath, npmPath.path)
			XCTAssertEqual(packageName, "@aduermael_/wb")
			XCTAssertEqual(
				InstallationDetector.npmPackageDirectory(containing: executable.path)?.path,
				packageDirectory.path
			)
		}
	}

	func testInstallationDetectorAllowsNPMOverride() throws {
		try withTemporaryDirectory { directory in
			let binDirectory = directory.appendingPathComponent("bin", isDirectory: true)
			try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)

			let npmPath = binDirectory.appendingPathComponent("npm")
			try Data("#!/bin/sh\n".utf8).write(to: npmPath)
			try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: npmPath.path)

			let method = InstallationDetector.detect(
				executablePath: directory.appendingPathComponent("wb").path,
				environment: [
					"PATH": binDirectory.path,
					"WB_UPDATE_INSTALLER": "npm",
				]
			)

			guard case .npm(let detectedNPMPath, let packageName) = method else {
				return XCTFail("expected npm install method")
			}
			XCTAssertEqual(detectedNPMPath, npmPath.path)
			XCTAssertEqual(packageName, "@aduermael_/wb")
		}
	}
}
