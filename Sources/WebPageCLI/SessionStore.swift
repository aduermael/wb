import Foundation
import Darwin

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

    static func current(idleTimeout: TimeInterval? = nil) -> WBConfig {
        let environment = ProcessInfo.processInfo.environment
        let rawDirectory = environment["WB_DIR"].nilIfEmpty ?? environment["WP_DIR"].nilIfEmpty ?? "wb"
        let baseURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let directory: URL
        if rawDirectory.hasPrefix("/") {
            directory = URL(fileURLWithPath: rawDirectory, isDirectory: true)
        } else {
            directory = baseURL.appendingPathComponent(rawDirectory, isDirectory: true)
        }

        return WBConfig(
            directory: directory.standardizedFileURL,
            idleTimeout: idleTimeout
                ?? parseIdleTimeout(environment["WB_IDLE_SECONDS"])
                ?? parseIdleTimeout(environment["WP_IDLE_SECONDS"])
                ?? defaultIdleTimeout
        )
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

struct SessionStore: Sendable {
    let directory: URL

    func browserIDs() -> [String] {
        guard let files = try? sessionFiles() else {
            return []
        }

        return files
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
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(dump)
        try data.write(to: fileURL(for: dump.browser), options: [.atomic])
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
}
