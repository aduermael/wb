/// Resolves local environment directories and persists browser session metadata
/// used to resume browser IDs between independent command invocations.
import Darwin
import Foundation

struct WBConfig: Sendable {
	static let defaultIdleTimeout: TimeInterval = 180

	let directory: URL
	let idleTimeout: TimeInterval

	var sessionsDirectory: URL {
		directory.appendingPathComponent("sessions", isDirectory: true)
	}

	var socketPath: String {
		let environment = ProcessInfo.processInfo.environment
		if let override = environment["WB_SOCKET"].nilIfEmpty ?? environment["WP_SOCKET"].nilIfEmpty {
			return override
		}

		return "/tmp/wb-webpage-\(Darwin.getuid())-\(Self.pathHash(directory.path)).sock"
	}

	var logPath: String {
		let environment = ProcessInfo.processInfo.environment
		return environment["WB_LOG"].nilIfEmpty
			?? environment["WP_LOG"].nilIfEmpty
			?? "/tmp/wb-webpage-\(Darwin.getuid()).log"
	}

	static func current(idleTimeout: TimeInterval? = nil) -> WBConfig {
		let environment = ProcessInfo.processInfo.environment
		let baseURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
		let directory: URL
		if let rawDirectory = environment["WB_DIR"].nilIfEmpty ?? environment["WP_DIR"].nilIfEmpty {
			if rawDirectory.hasPrefix("/") {
				directory = URL(fileURLWithPath: rawDirectory, isDirectory: true)
			} else {
				directory = baseURL.appendingPathComponent(rawDirectory, isDirectory: true)
			}
		} else {
			directory = defaultDirectory(baseURL: baseURL)
		}

		return WBConfig(
			directory: directory.standardizedFileURL,
			idleTimeout: idleTimeout
				?? parseIdleTimeout(environment["WB_IDLE_SECONDS"])
				?? parseIdleTimeout(environment["WP_IDLE_SECONDS"])
				?? defaultIdleTimeout
		)
	}

	static func currentProjectDirectory() -> URL {
		let baseURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
		return projectDirectory(startingAt: baseURL)
	}

	static func projectDirectory(startingAt baseURL: URL) -> URL {
		gitRoot(startingAt: baseURL) ?? baseURL.standardizedFileURL
	}

	private static func defaultDirectory(baseURL: URL) -> URL {
		projectDirectory(startingAt: baseURL).appendingPathComponent(".wb", isDirectory: true)
	}

	private static func gitRoot(startingAt baseURL: URL) -> URL? {
		let fileManager = FileManager.default
		var current = baseURL.standardizedFileURL

		while true {
			if fileManager.fileExists(atPath: current.appendingPathComponent(".git").path) {
				return current
			}

			let parent = current.deletingLastPathComponent()
			if parent.path == current.path {
				return nil
			}
			current = parent
		}
	}

	static func parseIdleTimeout(_ rawValue: String?) -> TimeInterval? {
		guard let rawValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
			return nil
		}

		if rawValue.lowercased() == "off" {
			return 0
		}

		guard let seconds = TimeInterval(rawValue), seconds >= 0 else {
			return nil
		}
		return seconds
	}

	private static func pathHash(_ path: String) -> String {
		var hash: UInt64 = 14_695_981_039_346_656_037
		for byte in path.utf8 {
			hash ^= UInt64(byte)
			hash &*= 1_099_511_628_211
		}
		return String(hash, radix: 16)
	}
}

struct WBEnvironment: Sendable {
	let directory: URL
	let uuid: UUID

	var metadata: WBEnvironmentMetadata {
		WBEnvironmentMetadata(
			directory: directory.path,
			sessionsDirectory: "sessions",
			uuid: uuid.uuidString.lowercased()
		)
	}

	static func loadOrCreate(in directory: URL) throws -> WBEnvironment {
		let fileURL = directory.appendingPathComponent("environment.json")
		let fileManager = FileManager.default

		if fileManager.fileExists(atPath: fileURL.path) {
			return try load(from: fileURL, directory: directory)
		}

		do {
			try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
		} catch {
			throw WBError.message(
				"failed to create environment directory \(directory.path): \(error.localizedDescription)"
			)
		}

		let environment = WBEnvironment(directory: directory, uuid: UUID())
		let file = WBEnvironmentFile(
			schemaVersion: 1,
			sessionsDirectory: "sessions",
			uuid: environment.uuid.uuidString.lowercased(),
			createdAt: Date().iso8601String
		)
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
		let data = try encoder.encode(file)

		if try createFileExclusively(at: fileURL, data: data) {
			return environment
		}

		return try load(from: fileURL, directory: directory)
	}

	private static func createFileExclusively(at fileURL: URL, data: Data) throws -> Bool {
		let flags = O_WRONLY | O_CREAT | O_EXCL
		let mode = mode_t(S_IRUSR | S_IWUSR)
		var fd = Darwin.open(fileURL.path, flags, mode)
		guard fd >= 0 else {
			if errno == EEXIST {
				return false
			}
			throw WBError.posix("open \(fileURL.path)")
		}

		var completed = false
		defer {
			if !completed {
				if fd >= 0 {
					Darwin.close(fd)
				}
				Darwin.unlink(fileURL.path)
			}
		}

		try data.withUnsafeBytes { rawBuffer in
			guard let baseAddress = rawBuffer.baseAddress else {
				return
			}

			var writtenBytes = 0
			while writtenBytes < rawBuffer.count {
				let written = Darwin.write(
					fd,
					baseAddress.advanced(by: writtenBytes),
					rawBuffer.count - writtenBytes
				)

				if written < 0 {
					if errno == EINTR {
						continue
					}
					throw WBError.posix("write \(fileURL.path)")
				}
				if written == 0 {
					throw WBError.message("write \(fileURL.path): wrote zero bytes")
				}

				writtenBytes += written
			}
		}

		let closeResult = Darwin.close(fd)
		fd = -1
		guard closeResult == 0 else {
			throw WBError.posix("close \(fileURL.path)")
		}

		completed = true
		return true
	}

	private static func load(from fileURL: URL, directory: URL) throws -> WBEnvironment {
		do {
			let data = try Data(contentsOf: fileURL)
			let file = try JSONDecoder().decode(WBEnvironmentFile.self, from: data)
			guard let uuid = UUID(uuidString: file.uuid) else {
				throw WBError.message("invalid environment UUID in \(fileURL.path)")
			}
			return WBEnvironment(directory: directory, uuid: uuid)
		} catch let error as WBError {
			throw error
		} catch {
			throw WBError.message(
				"failed to load environment UUID from \(fileURL.path): \(error.localizedDescription)"
			)
		}
	}
}

struct WBEnvironmentMetadata: Codable, Sendable {
	let directory: String
	let sessionsDirectory: String
	let uuid: String
}

private struct WBEnvironmentFile: Codable {
	let schemaVersion: Int
	let sessionsDirectory: String?
	let uuid: String
	let createdAt: String?
}

struct SessionStore: Sendable {
	let directory: URL

	func browserIDs() -> [String] {
		guard let files = try? sessionFiles() else {
			return []
		}

		return
			files
			.map { $0.deletingPathExtension().lastPathComponent }
			.filter(Self.isValidBrowserID)
	}

	func dumps() throws -> [BrowserDump] {
		try sessionFiles()
			.filter { Self.isValidBrowserID($0.deletingPathExtension().lastPathComponent) }
			.map { try load(from: $0) }
			.sorted { $0.browser.localizedStandardCompare($1.browser) == .orderedAscending }
	}

	func exists(_ browser: String) -> Bool {
		guard let fileURL = try? fileURL(for: browser) else {
			return false
		}
		return FileManager.default.fileExists(atPath: fileURL.path)
	}

	func load(_ browser: String) throws -> BrowserDump {
		try load(from: fileURL(for: browser))
	}

	func save(_ dump: BrowserDump) throws {
		do {
			try FileManager.default.createDirectory(
				at: directory,
				withIntermediateDirectories: true
			)
		} catch {
			throw WBError.message(
				"failed to create session directory \(directory.path): \(error.localizedDescription)"
			)
		}

		let encoder = JSONEncoder()
		encoder.outputFormatting = [.sortedKeys]
		let data = try encoder.encode(dump)
		let destination = try fileURL(for: dump.browser)
		do {
			try data.write(to: destination, options: [.atomic])
		} catch {
			throw WBError.message(
				"failed to save browser \(dump.browser) to \(destination.path): \(error.localizedDescription)"
			)
		}
	}

	func delete(_ browser: String) throws {
		let url = try fileURL(for: browser)
		guard FileManager.default.fileExists(atPath: url.path) else {
			return
		}
		try FileManager.default.removeItem(at: url)
	}

	private func load(from url: URL) throws -> BrowserDump {
		let data = try Data(contentsOf: url)
		let dump = try JSONDecoder().decode(BrowserDump.self, from: data)
		guard Self.isValidBrowserID(dump.browser) else {
			throw WBError.message("invalid browser id \(dump.browser)")
		}
		let fileBrowser = url.deletingPathExtension().lastPathComponent
		guard dump.browser == fileBrowser else {
			throw WBError.message("browser id mismatch in session \(fileBrowser)")
		}
		return dump
	}

	private func sessionFiles() throws -> [URL] {
		guard FileManager.default.fileExists(atPath: directory.path) else {
			return []
		}

		return try FileManager.default.contentsOfDirectory(
			at: directory,
			includingPropertiesForKeys: nil
		).filter { $0.pathExtension == "json" }
	}

	private func fileURL(for browser: String) throws -> URL {
		guard Self.isValidBrowserID(browser) else {
			throw WBError.message("invalid browser id \(browser)")
		}
		return directory.appendingPathComponent(browser).appendingPathExtension("json")
	}

	private static func isValidBrowserID(_ browser: String) -> Bool {
		let bytes = browser.utf8
		guard bytes.count == 8 else {
			return false
		}

		return bytes.allSatisfy { byte in
			(byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102)
		}
	}
}

struct BrowserDump: Codable, Sendable {
	let schemaVersion: Int
	let browser: String
	let title: String?
	let url: String?
	let loading: Bool
	let progress: Double
	let actions: Int
	let createdAt: String
	let updatedAt: String
	let dumpedAt: String
	let snapshot: PageSnapshot?
	var windowWidth: Int? = nil
	var windowHeight: Int? = nil

	func summary() -> BrowserSummary {
		let snapshotTitle = snapshot.flatMap { $0.title.nilIfEmpty }
		let snapshotURL = snapshot.flatMap { $0.url }

		return BrowserSummary(
			browser: browser,
			title: title ?? snapshotTitle,
			url: url ?? snapshotURL,
			loading: loading,
			progress: progress,
			actions: snapshot?.actions.count ?? actions,
			visible: nil,
			createdAt: createdAt,
			updatedAt: updatedAt,
			dumped: true,
			dumpedAt: dumpedAt
		)
	}

	var createdDate: Date {
		createdAt.iso8601Date ?? Date()
	}

	var updatedDate: Date {
		updatedAt.iso8601Date ?? createdDate
	}

	var windowSize: BrowserWindowSize? {
		guard let windowWidth, let windowHeight else {
			return nil
		}
		return try? BrowserWindowSizing.validate(width: windowWidth, height: windowHeight)
	}
}
