/// Implements release freshness checks and the local self-update command for
/// the wb executable.
import CryptoKit
import Darwin
import Foundation

struct UpdateCheckState: Codable, Equatable {
	var lastCheckedAt: Date?

	func shouldCheck(now: Date = Date(), interval: TimeInterval = WBUpdater.checkInterval) -> Bool {
		guard let lastCheckedAt else {
			return true
		}
		return now.timeIntervalSince(lastCheckedAt) >= interval
	}
}

struct GitHubRelease: Decodable, Equatable {
	let tagName: String
	let assets: [GitHubReleaseAsset]

	func asset(named name: String) -> URL? {
		assets.first { $0.name == name }?.browserDownloadURL
	}

	private enum CodingKeys: String, CodingKey {
		case assets
		case tagName = "tag_name"
	}
}

struct GitHubReleaseAsset: Decodable, Equatable {
	let name: String
	let browserDownloadURL: URL

	private enum CodingKeys: String, CodingKey {
		case name
		case browserDownloadURL = "browser_download_url"
	}
}

struct UpdateCheckResult: Equatable {
	let currentTag: String
	let latestTag: String

	var isStale: Bool {
		currentTag != latestTag
	}

	init?(currentVersion: String = WBVersion.current, latestTag: String) {
		guard
			let currentTag = WBVersion.normalizedTag(currentVersion),
			let normalizedLatest = WBVersion.normalizedTag(latestTag)
		else {
			return nil
		}
		self.currentTag = currentTag
		self.latestTag = normalizedLatest
	}
}

enum WBInstallConstants {
	static let npmPackageName = "@aduermael_/wb"
}

enum InstallMethod: Equatable {
	case homebrew(brewPath: String)
	case npm(npmPath: String, packageName: String)
	case direct
}

private struct NPMPackageManifest: Decodable {
	let name: String?
}

struct CommandResult {
	let status: Int32
	let output: String
	let errorOutput: String
}

typealias CommandRunner = (_ executablePath: String, _ arguments: [String]) throws -> CommandResult

enum InstallationDetector {
	static func detect(
		executablePath: String,
		environment: [String: String] = ProcessInfo.processInfo.environment,
		runCommand: CommandRunner = ProcessCommand.run
	) -> InstallMethod {
		if let override = environment["WB_UPDATE_INSTALLER"]?.trimmingCharacters(in: .whitespacesAndNewlines)
			.lowercased()
		{
			switch override {
			case "brew", "homebrew":
				if let brewPath = findExecutable(named: "brew", environment: environment) {
					return .homebrew(brewPath: brewPath)
				}
			case "node", "npm":
				if let npmPath = findExecutable(named: "npm", environment: environment) {
					return .npm(npmPath: npmPath, packageName: WBInstallConstants.npmPackageName)
				}
			case "direct", "standalone":
				return .direct
			default:
				break
			}
		}

		if let brewPath = findExecutable(named: "brew", environment: environment),
			isHomebrewExecutable(executablePath: executablePath, brewPath: brewPath, runCommand: runCommand)
		{
			return .homebrew(brewPath: brewPath)
		}

		if let npmPath = findExecutable(named: "npm", environment: environment),
			npmPackageDirectory(containing: executablePath) != nil
		{
			return .npm(npmPath: npmPath, packageName: WBInstallConstants.npmPackageName)
		}

		return .direct
	}

	private static func isHomebrewExecutable(
		executablePath: String,
		brewPath: String,
		runCommand: CommandRunner
	) -> Bool {
		let executableCandidates = canonicalCandidates(for: executablePath)

		if let formulaPrefix = try? runCommand(brewPath, ["--prefix", "wb"]).output
			.trimmingCharacters(in: .whitespacesAndNewlines),
			!formulaPrefix.isEmpty
		{
			let formulaPrefixPath = canonicalPath(formulaPrefix)
			let formulaBinCandidates = canonicalCandidates(for: "\(formulaPrefix)/bin/wb")
			if !executableCandidates.isDisjoint(with: formulaBinCandidates) {
				return true
			}
			if executableCandidates.contains(where: { path in
				path == formulaPrefixPath || path.hasPrefix("\(formulaPrefixPath)/")
			}) {
				return true
			}
		}

		if let brewPrefix = try? runCommand(brewPath, ["--prefix"]).output
			.trimmingCharacters(in: .whitespacesAndNewlines),
			!brewPrefix.isEmpty
		{
			let linkedBinCandidates = canonicalCandidates(for: "\(brewPrefix)/bin/wb")
			if !executableCandidates.isDisjoint(with: linkedBinCandidates) {
				return true
			}
		}

		return false
	}

	static func npmPackageDirectory(
		containing executablePath: String,
		packageName: String = WBInstallConstants.npmPackageName
	) -> URL? {
		var directory = URL(fileURLWithPath: canonicalPath(executablePath))
			.deletingLastPathComponent()

		while true {
			let manifestURL = directory.appendingPathComponent("package.json")
			if let data = try? Data(contentsOf: manifestURL),
				let manifest = try? JSONDecoder().decode(NPMPackageManifest.self, from: data),
				manifest.name == packageName
			{
				return directory
			}

			let parent = directory.deletingLastPathComponent()
			if parent.path == directory.path {
				return nil
			}
			directory = parent
		}
	}

	static func findExecutable(
		named name: String,
		environment: [String: String] = ProcessInfo.processInfo.environment
	) -> String? {
		if name.contains("/") {
			return FileManager.default.isExecutableFile(atPath: name) ? name : nil
		}

		let pathValue = environment["PATH"] ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
		for directory in pathValue.split(separator: ":", omittingEmptySubsequences: false) {
			let candidate = "\(directory)/\(name)"
			if FileManager.default.isExecutableFile(atPath: candidate) {
				return candidate
			}
		}
		return nil
	}

	private static func canonicalCandidates(for path: String) -> Set<String> {
		[path, canonicalPath(path)]
			.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
			.reduce(into: Set<String>()) { $0.insert($1) }
	}

	private static func canonicalPath(_ path: String) -> String {
		URL(fileURLWithPath: path)
			.standardizedFileURL
			.resolvingSymlinksInPath()
			.path
	}
}

enum ProcessCommand {
	static func run(_ executablePath: String, _ arguments: [String]) throws -> CommandResult {
		try run(executablePath, arguments, captureOutput: true)
	}

	static func runStreaming(_ executablePath: String, _ arguments: [String]) throws {
		_ = try run(executablePath, arguments, captureOutput: false)
	}

	private static func run(
		_ executablePath: String,
		_ arguments: [String],
		captureOutput: Bool
	) throws -> CommandResult {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: executablePath)
		process.arguments = arguments

		let outputPipe = captureOutput ? Pipe() : nil
		let errorPipe = captureOutput ? Pipe() : nil
		if let outputPipe, let errorPipe {
			process.standardOutput = outputPipe
			process.standardError = errorPipe
		}

		do {
			try process.run()
		} catch {
			throw WBError.message("failed to run \(executablePath): \(error.localizedDescription)")
		}
		process.waitUntilExit()

		let output = outputPipe.map(readPipe) ?? ""
		let errorOutput = errorPipe.map(readPipe) ?? ""
		let result = CommandResult(
			status: process.terminationStatus,
			output: output,
			errorOutput: errorOutput
		)
		guard result.status == 0 else {
			throw WBError.message(commandFailureMessage(executablePath, arguments, result: result))
		}
		return result
	}

	private static func readPipe(_ pipe: Pipe) -> String {
		let data = pipe.fileHandleForReading.readDataToEndOfFile()
		return String(data: data, encoding: .utf8) ?? ""
	}

	private static func commandFailureMessage(
		_ executablePath: String,
		_ arguments: [String],
		result: CommandResult
	) -> String {
		let command = ([executablePath] + arguments).joined(separator: " ")
		let detail = result.errorOutput.nilIfEmpty ?? result.output.nilIfEmpty
		if let detail {
			return
				"\(command) failed with exit \(result.status): \(detail.trimmingCharacters(in: .whitespacesAndNewlines))"
		}
		return "\(command) failed with exit \(result.status)"
	}
}

enum WBUpdater {
	static let checkInterval: TimeInterval = 12 * 60 * 60
	static let defaultRepository = "aduermael/wb"

	static func maybePrintStaleNotice() async {
		guard WBVersion.isReleaseBuild else {
			return
		}

		let environment = ProcessInfo.processInfo.environment
		guard automaticChecksEnabled(environment: environment) else {
			return
		}

		let stateURL = defaultStateURL()
		let now = Date()
		let state = loadState(from: stateURL) ?? UpdateCheckState()
		guard state.shouldCheck(now: now) else {
			return
		}

		do {
			let release = try await latestRelease(
				repository: repository(from: environment),
				timeout: 2
			)
			try? saveState(UpdateCheckState(lastCheckedAt: now), to: stateURL)
			guard let result = UpdateCheckResult(latestTag: release.tagName), result.isStale else {
				return
			}
			writeUpdateNotice(result)
		} catch {
			try? saveState(UpdateCheckState(lastCheckedAt: now), to: stateURL)
		}
	}

	static func runUpdate() async throws {
		guard WBVersion.isReleaseBuild else {
			throw WBError.message(
				"wb update is available for release builds only; install the latest release with install.sh"
			)
		}

		let executablePath = try currentExecutablePath()
		let environment = ProcessInfo.processInfo.environment
		let method = InstallationDetector.detect(executablePath: executablePath, environment: environment)

		switch method {
		case .homebrew(let brewPath):
			try updateWithHomebrew(brewPath: brewPath)

		case .npm(let npmPath, let packageName):
			try updateWithNPM(npmPath: npmPath, packageName: packageName)

		case .direct:
			try await updateDirectInstall(
				executablePath: executablePath,
				repository: repository(from: environment)
			)
		}
	}

	static func automaticChecksEnabled(environment: [String: String]) -> Bool {
		!isExplicitlyOff(environment["WB_UPDATE_CHECK"]) && !isTruthy(environment["WB_NO_UPDATE_CHECK"])
	}

	static func loadState(from url: URL) -> UpdateCheckState? {
		guard let data = try? Data(contentsOf: url) else {
			return nil
		}
		return try? JSONDecoder().decode(UpdateCheckState.self, from: data)
	}

	static func saveState(_ state: UpdateCheckState, to url: URL) throws {
		try FileManager.default.createDirectory(
			at: url.deletingLastPathComponent(),
			withIntermediateDirectories: true
		)
		let data = try JSONEncoder().encode(state)
		try data.write(to: url, options: .atomic)
	}

	static func repository(from environment: [String: String]) -> String {
		environment["WB_REPO"].nilIfEmpty ?? defaultRepository
	}

	static func releaseAssetName() throws -> String {
		#if arch(arm64)
			return "wb-macos-arm64.tar.gz"
		#elseif arch(x86_64)
			return "wb-macos-x86_64.tar.gz"
		#else
			throw WBError.message("unsupported CPU architecture for wb updates")
		#endif
	}

	private static func updateWithHomebrew(brewPath: String) throws {
		print("Updating wb with Homebrew...")
		try ProcessCommand.runStreaming(brewPath, ["update"])
		try ProcessCommand.runStreaming(brewPath, ["upgrade", "wb"])
		print("Homebrew update completed.")
	}

	private static func updateWithNPM(npmPath: String, packageName: String) throws {
		print("Updating wb with npm...")
		try ProcessCommand.runStreaming(npmPath, ["install", "-g", "\(packageName)@latest"])
		print("npm update completed.")
	}

	private static func updateDirectInstall(executablePath: String, repository: String) async throws {
		let release = try await latestRelease(repository: repository, timeout: 60)
		guard let result = UpdateCheckResult(latestTag: release.tagName) else {
			throw WBError.message("could not compare current wb version with latest release")
		}
		guard result.isStale else {
			print("wb is already up to date (\(result.currentTag)).")
			try? saveState(UpdateCheckState(lastCheckedAt: Date()), to: defaultStateURL())
			return
		}

		let assetName = try releaseAssetName()
		guard let assetURL = release.asset(named: assetName) else {
			throw WBError.message("latest release \(result.latestTag) does not include \(assetName)")
		}

		print("Updating wb from \(result.currentTag) to \(result.latestTag)...")
		let archiveData = try await data(from: assetURL, timeout: 60)
		if let checksumURL = release.asset(named: "\(assetName).sha256") {
			let checksumData = try await data(from: checksumURL, timeout: 30)
			try verifySHA256(data: archiveData, checksumData: checksumData, assetName: assetName)
		}

		let tempDirectory = FileManager.default.temporaryDirectory
			.appendingPathComponent("wb-update-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
		defer {
			try? FileManager.default.removeItem(at: tempDirectory)
		}

		let archiveURL = tempDirectory.appendingPathComponent(assetName)
		try archiveData.write(to: archiveURL, options: .atomic)
		_ = try ProcessCommand.run(
			"/usr/bin/tar",
			["-xzf", archiveURL.path, "-C", tempDirectory.path]
		)

		let extractedBinary = tempDirectory.appendingPathComponent("wb")
		guard FileManager.default.isExecutableFile(atPath: extractedBinary.path) else {
			throw WBError.message("release asset did not contain an executable wb binary")
		}

		try installBinary(from: extractedBinary.path, to: executablePath)
		print("Updated wb to \(result.latestTag) at \(executablePath).")
		try? saveState(UpdateCheckState(lastCheckedAt: Date()), to: defaultStateURL())
	}

	private static func latestRelease(repository: String, timeout: TimeInterval) async throws -> GitHubRelease {
		let url = try githubAPIURL(repository: repository)
		let data = try await data(from: url, timeout: timeout)
		return try JSONDecoder().decode(GitHubRelease.self, from: data)
	}

	private static func data(from url: URL, timeout: TimeInterval) async throws -> Data {
		var request = URLRequest(url: url, timeoutInterval: timeout)
		request.setValue("wb", forHTTPHeaderField: "User-Agent")
		let (data, response) = try await URLSession.shared.data(for: request)
		if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
			throw WBError.message("request to \(url.absoluteString) failed with HTTP \(http.statusCode)")
		}
		return data
	}

	private static func githubAPIURL(repository: String) throws -> URL {
		let parts = repository.split(separator: "/", omittingEmptySubsequences: true)
		guard parts.count == 2 else {
			throw WBError.message("WB_REPO must be owner/name")
		}
		var components = URLComponents()
		components.scheme = "https"
		components.host = "api.github.com"
		components.path = "/repos/\(parts[0])/\(parts[1])/releases/latest"
		guard let url = components.url else {
			throw WBError.message("invalid GitHub repository \(repository)")
		}
		return url
	}

	private static func verifySHA256(data: Data, checksumData: Data, assetName: String) throws {
		let checksumText = String(data: checksumData, encoding: .utf8) ?? ""
		guard let expected = checksumText.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).first
		else {
			throw WBError.message("empty checksum for \(assetName)")
		}

		let actual = SHA256.hash(data: data)
			.map { String(format: "%02x", $0) }
			.joined()
		guard actual.lowercased() == expected.lowercased() else {
			throw WBError.message("checksum mismatch for \(assetName)")
		}
	}

	private static func installBinary(from sourcePath: String, to destinationPath: String) throws {
		do {
			try ProcessCommand.runStreaming(
				"/usr/bin/install", ["-m", "0755", sourcePath, destinationPath])
		} catch {
			guard canUseSudo else {
				throw error
			}
			print(
				"Installing to \(destinationPath) requires admin permissions; sudo may prompt for your password."
			)
			try ProcessCommand.runStreaming(
				"/usr/bin/sudo",
				["/usr/bin/install", "-m", "0755", sourcePath, destinationPath]
			)
		}
	}

	private static var canUseSudo: Bool {
		Darwin.isatty(STDIN_FILENO) == 1 && FileManager.default.isExecutableFile(atPath: "/usr/bin/sudo")
	}

	private static func currentExecutablePath() throws -> String {
		var size: UInt32 = 0
		_ = _NSGetExecutablePath(nil, &size)
		var buffer = [CChar](repeating: 0, count: Int(size) + 1)
		guard _NSGetExecutablePath(&buffer, &size) == 0 else {
			throw WBError.message("could not resolve current executable path")
		}
		let length = buffer.firstIndex(of: 0) ?? buffer.count
		let bytes = buffer.prefix(length).map { UInt8(bitPattern: $0) }
		let path = String(decoding: bytes, as: UTF8.self)
		if path.hasPrefix("/") {
			return URL(fileURLWithPath: path).standardizedFileURL.path
		}
		return URL(
			fileURLWithPath: path,
			relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
		)
		.standardizedFileURL
		.path
	}

	private static func defaultStateURL() -> URL {
		let base =
			FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
			?? FileManager.default.temporaryDirectory
		return
			base
			.appendingPathComponent("wb", isDirectory: true)
			.appendingPathComponent("update-check.json")
	}

	private static func writeUpdateNotice(_ result: UpdateCheckResult) {
		let message =
			"wb \(result.latestTag) is available (current \(result.currentTag)). Run 'wb update' to upgrade.\n"
		FileHandle.standardError.write(Data(message.utf8))
	}

	private static func isExplicitlyOff(_ value: String?) -> Bool {
		guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
			return false
		}
		return ["0", "false", "no", "off"].contains(normalized)
	}

	private static func isTruthy(_ value: String?) -> Bool {
		guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
			return false
		}
		return ["1", "true", "yes", "on"].contains(normalized)
	}
}
