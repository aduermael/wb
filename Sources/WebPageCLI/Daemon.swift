/// Runs and supervises the Unix-domain socket daemon that keeps browser
/// sessions alive across separate CLI invocations.
import Darwin
import Foundation

@available(macOS 26.0, *)
final class DaemonProcess {
	private let socketPath: String
	private let config: WBConfig
	private var server: UnixSocketServer?

	init(config: WBConfig = .current()) {
		self.config = config
		socketPath = config.socketPath
	}

	func run() async throws {
		ProcessInfo.processInfo.disableSuddenTermination()
		ProcessInfo.processInfo.disableAutomaticTermination("wb daemon is running browser sessions")
		let config = self.config
		let socketPath = self.socketPath
		let server = UnixSocketServer(socketPath: socketPath)
		self.server = server
		daemonLog(
			"daemon starting socket=\(socketPath) sessions=\(config.sessionsDirectory.path) "
				+ "idleTimeout=\(config.idleTimeout) log=\(config.logPath)"
		)
		daemonLog("daemon disabled automatic and sudden termination")

		let manager: BrowserManager = try await MainActor.run {
			BrowserApplicationHost.prepareForDaemon()
			return try BrowserManager(config: config)
		}
		await MainActor.run {
			BrowserApplicationHost.setQuitHandler {
				Task { @MainActor in
					daemonLog("daemon quit requested from application menu")
					do {
						try await manager.dumpAllSessions()
					} catch {
						daemonLog("quit dump failed error=\(error.localizedDescription)")
						printError("quit dump failed: \(error.localizedDescription)")
					}
					daemonLog("daemon exiting after application menu quit")
					Darwin.exit(0)
				}
			}
		}
		let activity = DaemonActivity()
		try server.start(activity: activity) { [manager] data in
			await manager.handleWireData(data)
		}
		daemonLog("daemon listening")

		daemonLog("daemon main loop started")
		var lastIdleCheck = Date.distantPast
		while true {
			await BrowserApplicationHost.pumpEvents(until: Date(timeIntervalSinceNow: 0.05))
			try? await Task.sleep(nanoseconds: 10_000_000)

			let now = Date()
			let keptAliveBrowsers = await manager.browserIDsKeepingDaemonAlive()

			guard now.timeIntervalSince(lastIdleCheck) >= 1 else {
				continue
			}
			lastIdleCheck = now

			if activity.isIdle(timeout: config.idleTimeout) {
				if !keptAliveBrowsers.isEmpty {
					daemonLog(
						"idle skipped windowBrowsers=\(keptAliveBrowsers.joined(separator: ","))"
					)
					continue
				}

				do {
					daemonLog("idle timeout reached; dumping sessions")
					try await manager.dumpAllSessions()
				} catch {
					daemonLog("idle dump failed error=\(error.localizedDescription)")
					printError("idle dump failed: \(error.localizedDescription)")
					continue
				}

				let keptAliveBrowsersAfterDump = await manager.browserIDsKeepingDaemonAlive()
				if activity.isIdle(timeout: config.idleTimeout),
					keptAliveBrowsersAfterDump.isEmpty
				{
					daemonLog("daemon exiting after idle dump")
					Darwin.exit(0)
				}
			}
		}
	}
}

final class DaemonActivity: @unchecked Sendable {
	private let lock = NSLock()
	private var inFlightRequests = 0
	private var lastActivityAt = Date()

	func beginRequest() {
		lock.lock()
		defer { lock.unlock() }

		inFlightRequests += 1
		lastActivityAt = Date()
	}

	func endRequest() {
		lock.lock()
		defer { lock.unlock() }

		inFlightRequests = max(0, inFlightRequests - 1)
		lastActivityAt = Date()
	}

	func isIdle(timeout: TimeInterval, now: Date = Date()) -> Bool {
		lock.lock()
		defer { lock.unlock() }

		return timeout > 0 && inFlightRequests == 0 && now.timeIntervalSince(lastActivityAt) >= timeout
	}
}

final class DaemonClient {
	static var defaultSocketPath: String {
		WBConfig.current().socketPath
	}

	private let config: WBConfig
	private let socketPath: String
	private let idleTimeout: TimeInterval?

	init(socketPath: String = DaemonClient.defaultSocketPath, idleTimeout: TimeInterval? = nil) {
		config = WBConfig.current(idleTimeout: idleTimeout)
		self.socketPath = socketPath
		self.idleTimeout = idleTimeout
	}

	func send(_ request: WireRequest, startIfNeeded: Bool = true) throws -> WireResponse {
		if startIfNeeded {
			try ensureCompatibleDaemon()
		}

		do {
			return try sendWithoutStarting(request)
		} catch {
			guard startIfNeeded else {
				throw error
			}

			try startDaemon()
			return try sendWithoutStarting(request)
		}
	}

	func isRunning() -> Bool {
		guard let response = try? sendWithoutStarting(WireRequest(command: .ping)) else {
			return false
		}
		return response.ok
			&& response.protocolVersion == WireProtocol.version
			&& ((try? isCompatibleEnvironment(response.environment)) == true)
	}

	private func sendWithoutStarting(_ request: WireRequest) throws -> WireResponse {
		let requestData = try WireCodec.encode(request)
		let responseData = try UnixSocketTransport.roundTrip(
			requestData,
			socketPath: socketPath,
			timeout: responseTimeout(for: request.command)
		)
		return try JSONDecoder().decode(WireResponse.self, from: responseData)
	}

	private func responseTimeout(for command: WireCommand) -> TimeInterval {
		switch command {
		case .ping:
			return 2
		case .daemonStop:
			return 5
		default:
			return 120
		}
	}

	private func ensureCompatibleDaemon() throws {
		let response: WireResponse
		do {
			response = try sendWithoutStarting(WireRequest(command: .ping))
		} catch {
			daemonLog(
				"daemon not reachable or unresponsive; replacing daemon "
					+ "socket=\(socketPath) error=\(error.localizedDescription)"
			)
			try? stopIncompatibleDaemon()
			try startDaemon()
			return
		}

		if response.ok && response.protocolVersion == WireProtocol.version {
			if try isCompatibleEnvironment(response.environment) {
				return
			}

			daemonLog("daemon environment mismatch; replacing daemon socket=\(socketPath)")
			try stopIncompatibleDaemon()
			try startDaemon()
			return
		}

		daemonLog(
			"daemon protocol mismatch current=\(String(describing: response.protocolVersion)) "
				+ "expected=\(WireProtocol.version); replacing"
		)
		try stopIncompatibleDaemon()
		try startDaemon()
	}

	private func isCompatibleEnvironment(_ daemonEnvironment: WBEnvironmentMetadata?) throws -> Bool {
		guard let daemonEnvironment else {
			return false
		}

		let expectedEnvironment = try WBEnvironment.loadOrCreate(in: config.directory).metadata
		return normalizedDirectoryPath(daemonEnvironment.directory)
			== normalizedDirectoryPath(expectedEnvironment.directory)
			&& daemonEnvironment.uuid.lowercased() == expectedEnvironment.uuid.lowercased()
	}

	private func normalizedDirectoryPath(_ path: String) -> String {
		URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path
	}

	private func stopIncompatibleDaemon() throws {
		daemonLog("requesting incompatible daemon stop socket=\(socketPath)")
		_ = try? sendWithoutStarting(WireRequest(command: .daemonStop))

		if waitForDaemonToStop(timeout: 3) {
			daemonLog("incompatible daemon stopped after request")
			return
		}

		// Treat lsof output as untrusted; never signal unrelated user processes.
		let processIDs = processIDsUsingSocket().filter(isManagedDaemonProcess)
		guard !processIDs.isEmpty else {
			daemonLog("no managed daemon process found for stale socket; unlinking socket=\(socketPath)")
			Darwin.unlink(socketPath)
			return
		}

		daemonLog(
			"terminating incompatible daemon "
				+ "pids=\(processIDs.map(String.init).joined(separator: ",")) signal=TERM"
		)
		terminate(processIDs, signal: SIGTERM)
		if waitForDaemonToStop(timeout: 2) {
			daemonLog("incompatible daemon stopped after SIGTERM")
			return
		}

		daemonLog(
			"killing incompatible daemon pids=\(processIDs.map(String.init).joined(separator: ",")) signal=KILL"
		)
		terminate(processIDs, signal: SIGKILL)
		if waitForDaemonToStop(timeout: 1) {
			daemonLog("incompatible daemon stopped after SIGKILL")
			return
		}

		daemonLog("unlinking socket after incompatible daemon replacement failed socket=\(socketPath)")
		Darwin.unlink(socketPath)
	}

	private func waitForDaemonToStop(timeout: TimeInterval) -> Bool {
		let deadline = Date().addingTimeInterval(timeout)
		while Date() < deadline {
			if (try? sendWithoutStarting(WireRequest(command: .ping))) == nil {
				return true
			}

			Thread.sleep(forTimeInterval: 0.1)
		}

		return false
	}

	private func processIDsUsingSocket() -> [pid_t] {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
		process.arguments = ["-t", "-U", socketPath]

		let pipe = Pipe()
		process.standardOutput = pipe
		if let devNull = FileHandle(forWritingAtPath: "/dev/null") {
			process.standardError = devNull
		}

		do {
			try process.run()
			process.waitUntilExit()
		} catch {
			return []
		}

		let data = pipe.fileHandleForReading.readDataToEndOfFile()
		guard let output = String(data: data, encoding: .utf8) else {
			return []
		}

		return
			output
			.split(whereSeparator: \.isNewline)
			.compactMap { pid_t(String($0).trimmingCharacters(in: .whitespacesAndNewlines)) }
	}

	private func isManagedDaemonProcess(_ processID: pid_t) -> Bool {
		guard processID > 0 && processID != Darwin.getpid(),
			let command = processCommand(processID)
		else {
			return false
		}

		let executableName = Bundle.main.executableURL?.lastPathComponent ?? "wb"
		let arguments = command.split(whereSeparator: \.isWhitespace)
		let processExecutableName = arguments.first?
			.split(separator: "/")
			.last
			.map(String.init)
		let hasDaemonArgument = arguments.contains { $0 == "__daemon" }

		return hasDaemonArgument && processExecutableName == Optional(executableName)
	}

	private func processCommand(_ processID: pid_t) -> String? {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/bin/ps")
		process.arguments = ["-p", String(processID), "-o", "command="]

		let pipe = Pipe()
		process.standardOutput = pipe
		if let devNull = FileHandle(forWritingAtPath: "/dev/null") {
			process.standardError = devNull
		}

		do {
			try process.run()
			process.waitUntilExit()
		} catch {
			return nil
		}

		guard process.terminationStatus == 0 else {
			return nil
		}

		let data = pipe.fileHandleForReading.readDataToEndOfFile()
		return String(data: data, encoding: .utf8)?
			.trimmingCharacters(in: .whitespacesAndNewlines)
			.nilIfEmpty
	}

	private func terminate(_ processIDs: [pid_t], signal: Int32) {
		for processID in processIDs where processID > 0 && processID != Darwin.getpid() {
			_ = Darwin.kill(processID, signal)
		}
	}

	private func startDaemon() throws {
		guard let executableURL = Bundle.main.executableURL else {
			throw WBError.message("cannot locate current executable")
		}

		daemonLog(
			"starting daemon executable=\(executableURL.path) socket=\(socketPath) "
				+ "sessions=\(config.sessionsDirectory.path) idleTimeout=\(config.idleTimeout) log=\(config.logPath)"
		)
		let process = Process()
		process.executableURL = executableURL
		process.arguments = ["__daemon"]
		var environment = ProcessInfo.processInfo.environment
		environment["WB_DIR"] = config.directory.path
		environment["WB_LOG"] = config.logPath
		environment["WB_SOCKET"] = socketPath
		if let idleTimeout {
			environment["WB_IDLE_SECONDS"] = String(idleTimeout)
		}
		process.environment = environment
		if let devNull = FileHandle(forReadingAtPath: "/dev/null") {
			process.standardInput = devNull
		}

		let logPath = config.logPath
		_ = FileManager.default.createFile(atPath: logPath, contents: nil)
		if let log = FileHandle(forWritingAtPath: logPath) {
			_ = try? log.seekToEnd()
			process.standardOutput = log
			process.standardError = log
		}

		try process.run()
		daemonLog("daemon process launched pid=\(process.processIdentifier)")

		let deadline = Date().addingTimeInterval(5)
		var lastError: Error?
		while Date() < deadline {
			do {
				let response = try sendWithoutStarting(WireRequest(command: .ping))
				if response.ok,
					response.protocolVersion == WireProtocol.version,
					try isCompatibleEnvironment(response.environment)
				{
					daemonLog("daemon ready pid=\(process.processIdentifier)")
					return
				}
			} catch {
				lastError = error
			}

			Thread.sleep(forTimeInterval: 0.1)
		}

		let message = "daemon did not start: \(lastError?.localizedDescription ?? "unknown error")"
		daemonLog(message)
		throw WBError.message(message)
	}
}

private final class UnixSocketServer: @unchecked Sendable {
	private let socketPath: String
	private var fd: Int32 = -1
	private var thread: Thread?

	init(socketPath: String) {
		self.socketPath = socketPath
	}

	deinit {
		if fd >= 0 {
			Darwin.close(fd)
		}
		Darwin.unlink(socketPath)
	}

	func start(
		activity: DaemonActivity,
		handler: @escaping @Sendable (Data) async -> Data
	) throws {
		Darwin.signal(SIGPIPE, SIG_IGN)

		fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
		guard fd >= 0 else {
			throw WBError.posix("socket")
		}

		Darwin.unlink(socketPath)
		var address = try UnixSocketAddress(path: socketPath).address
		let bindResult = withUnsafePointer(to: &address) { pointer in
			pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
				Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
			}
		}
		guard bindResult == 0 else {
			throw WBError.posix("bind \(socketPath)")
		}

		guard Darwin.listen(fd, 16) == 0 else {
			throw WBError.posix("listen")
		}

		let serverFD = fd
		thread = Thread {
			Self.acceptLoop(fd: serverFD, activity: activity, handler: handler)
		}
		thread?.name = "wb-webpage-daemon"
		thread?.start()
	}

	private static func acceptLoop(
		fd: Int32,
		activity: DaemonActivity,
		handler: @escaping @Sendable (Data) async -> Data
	) {
		while true {
			let clientFD = Darwin.accept(fd, nil, nil)
			if clientFD < 0 {
				if errno == EINTR {
					continue
				}
				printError(WBError.posix("accept").localizedDescription)
				return
			}
			activity.beginRequest()

			let requestData: Data
			do {
				requestData = try UnixSocketTransport.readMessage(from: clientFD)
			} catch {
				let responseData = WireCodec.encodeError(error.localizedDescription)
				_ = try? UnixSocketTransport.writeMessage(responseData, to: clientFD)
				Darwin.close(clientFD)
				activity.endRequest()
				continue
			}

			Task {
				defer {
					Darwin.close(clientFD)
					activity.endRequest()
				}

				let responseData = await handler(requestData)
				do {
					try UnixSocketTransport.writeMessage(responseData, to: clientFD)
				} catch {
					printError(error.localizedDescription)
				}
			}
		}
	}
}

private enum UnixSocketTransport {
	static func roundTrip(_ data: Data, socketPath: String, timeout: TimeInterval? = nil) throws -> Data {
		Darwin.signal(SIGPIPE, SIG_IGN)

		let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
		guard fd >= 0 else {
			throw WBError.posix("socket")
		}
		defer { Darwin.close(fd) }

		var address = try UnixSocketAddress(path: socketPath).address
		let connectResult = withUnsafePointer(to: &address) { pointer in
			pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
				Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
			}
		}
		guard connectResult == 0 else {
			throw WBError.posix("connect \(socketPath)")
		}

		try writeMessage(data, to: fd)
		return try readMessage(from: fd, timeout: timeout)
	}

	static func readMessage(from fd: Int32, timeout: TimeInterval? = nil) throws -> Data {
		var data = Data()
		var byte: UInt8 = 0
		let deadline = timeout.map { Date().addingTimeInterval($0) }

		while true {
			if let deadline {
				try waitUntilReadable(fd: fd, deadline: deadline)
			}

			let count = withUnsafeMutableBytes(of: &byte) {
				Darwin.read(fd, $0.baseAddress, 1)
			}

			if count == 0 {
				if data.isEmpty {
					throw WBError.message("connection closed")
				}
				return data
			}

			if count < 0 {
				if errno == EINTR {
					continue
				}
				throw WBError.posix("read")
			}

			if byte == 10 {
				return data
			}

			data.append(contentsOf: [byte])
		}
	}

	private static func waitUntilReadable(fd: Int32, deadline: Date) throws {
		while true {
			let remaining = deadline.timeIntervalSinceNow
			guard remaining > 0 else {
				throw WBError.message("timed out waiting for daemon response")
			}

			var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
			let milliseconds = min(Int(remaining * 1000), Int(Int32.max))
			let result = Darwin.poll(&descriptor, 1, Int32(max(1, milliseconds)))

			if result > 0 {
				return
			}
			if result == 0 {
				throw WBError.message("timed out waiting for daemon response")
			}
			if errno == EINTR {
				continue
			}
			throw WBError.posix("poll")
		}
	}

	static func writeMessage(_ data: Data, to fd: Int32) throws {
		var message = data
		message.append(contentsOf: [10])
		try writeAll(message, to: fd)
	}

	static func writeAll(_ data: Data, to fd: Int32) throws {
		try data.withUnsafeBytes { rawBuffer in
			guard let baseAddress = rawBuffer.baseAddress else {
				return
			}

			var sent = 0
			while sent < rawBuffer.count {
				let written = Darwin.write(
					fd,
					baseAddress.advanced(by: sent),
					rawBuffer.count - sent
				)

				if written < 0 {
					if errno == EINTR {
						continue
					}
					throw WBError.posix("write")
				}

				sent += written
			}
		}
	}
}

private struct UnixSocketAddress {
	var address = sockaddr_un()

	init(path: String) throws {
		let pathBytes = Array(path.utf8) + [0]
		let capacity = MemoryLayout.size(ofValue: address.sun_path)
		guard pathBytes.count <= capacity else {
			throw WBError.message("socket path is too long: \(path)")
		}

		address.sun_family = sa_family_t(AF_UNIX)
		withUnsafeMutableBytes(of: &address.sun_path) { buffer in
			buffer.copyBytes(from: pathBytes)
		}
	}
}
