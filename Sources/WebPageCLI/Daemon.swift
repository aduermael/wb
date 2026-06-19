import Foundation
import Darwin

@available(macOS 26.0, *)
final class DaemonProcess {
    private let socketPath: String
    private var server: UnixSocketServer?

    init(socketPath: String = DaemonClient.defaultSocketPath) {
        self.socketPath = socketPath
    }

    func run() async throws {
        let manager = await MainActor.run {
            BrowserManager()
        }
        let server = UnixSocketServer(socketPath: socketPath)
        self.server = server
        try server.start { [manager] data in
            await manager.handleWireData(data)
        }

        while true {
            try await Task.sleep(nanoseconds: 3_600_000_000_000)
        }
    }
}

final class DaemonClient {
    static var defaultSocketPath: String {
        ProcessInfo.processInfo.environment["WP_SOCKET"]
            ?? "/tmp/wp-webpage-\(Darwin.getuid()).sock"
    }

    private let socketPath: String

    init(socketPath: String = DaemonClient.defaultSocketPath) {
        self.socketPath = socketPath
    }

    func send(_ request: WireRequest, startIfNeeded: Bool = true) throws -> WireResponse {
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
        (try? sendWithoutStarting(WireRequest(command: .ping)))?.ok == true
    }

    private func sendWithoutStarting(_ request: WireRequest) throws -> WireResponse {
        let requestData = try WireCodec.encode(request)
        let responseData = try UnixSocketTransport.roundTrip(requestData, socketPath: socketPath)
        return try JSONDecoder().decode(WireResponse.self, from: responseData)
    }

    private func startDaemon() throws {
        guard let executableURL = Bundle.main.executableURL else {
            throw WPError.message("cannot locate current executable")
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["__daemon"]
        if let devNull = FileHandle(forReadingAtPath: "/dev/null") {
            process.standardInput = devNull
        }

        let logPath = "/tmp/wp-webpage-\(Darwin.getuid()).log"
        _ = FileManager.default.createFile(atPath: logPath, contents: nil)
        if let log = FileHandle(forWritingAtPath: logPath) {
            try? log.seekToEnd()
            process.standardOutput = log
            process.standardError = log
        }

        try process.run()

        let deadline = Date().addingTimeInterval(5)
        var lastError: Error?
        while Date() < deadline {
            do {
                let response = try sendWithoutStarting(WireRequest(command: .ping))
                if response.ok {
                    return
                }
            } catch {
                lastError = error
            }

            Thread.sleep(forTimeInterval: 0.1)
        }

        throw WPError.message("daemon did not start: \(lastError?.localizedDescription ?? "unknown error")")
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

    func start(handler: @escaping @Sendable (Data) async -> Data) throws {
        Darwin.signal(SIGPIPE, SIG_IGN)

        fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw WPError.posix("socket")
        }

        Darwin.unlink(socketPath)
        var address = try UnixSocketAddress(path: socketPath).address
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            throw WPError.posix("bind \(socketPath)")
        }

        guard Darwin.listen(fd, 16) == 0 else {
            throw WPError.posix("listen")
        }

        let serverFD = fd
        thread = Thread {
            Self.acceptLoop(fd: serverFD, handler: handler)
        }
        thread?.name = "wp-webpage-daemon"
        thread?.start()
    }

    private static func acceptLoop(fd: Int32, handler: @escaping @Sendable (Data) async -> Data) {
        while true {
            let clientFD = Darwin.accept(fd, nil, nil)
            if clientFD < 0 {
                if errno == EINTR {
                    continue
                }
                printError(WPError.posix("accept").localizedDescription)
                return
            }

            let requestData: Data
            do {
                requestData = try UnixSocketTransport.readMessage(from: clientFD)
            } catch {
                let responseData = WireCodec.encodeError(error.localizedDescription)
                try? UnixSocketTransport.writeMessage(responseData, to: clientFD)
                Darwin.close(clientFD)
                continue
            }

            Task {
                let responseData = await handler(requestData)
                do {
                    try UnixSocketTransport.writeMessage(responseData, to: clientFD)
                } catch {
                    printError(error.localizedDescription)
                }
                Darwin.close(clientFD)
            }
        }
    }
}

private enum UnixSocketTransport {
    static func roundTrip(_ data: Data, socketPath: String) throws -> Data {
        Darwin.signal(SIGPIPE, SIG_IGN)

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw WPError.posix("socket")
        }
        defer { Darwin.close(fd) }

        var address = try UnixSocketAddress(path: socketPath).address
        let connectResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else {
            throw WPError.posix("connect \(socketPath)")
        }

        try writeMessage(data, to: fd)
        return try readMessage(from: fd)
    }

    static func readMessage(from fd: Int32) throws -> Data {
        var data = Data()
        var byte: UInt8 = 0

        while true {
            let count = withUnsafeMutableBytes(of: &byte) {
                Darwin.read(fd, $0.baseAddress, 1)
            }

            if count == 0 {
                if data.isEmpty {
                    throw WPError.message("connection closed")
                }
                return data
            }

            if count < 0 {
                if errno == EINTR {
                    continue
                }
                throw WPError.posix("read")
            }

            if byte == 10 {
                return data
            }

            data.append(contentsOf: [byte])
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
                    throw WPError.posix("write")
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
            throw WPError.message("socket path is too long: \(path)")
        }

        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: pathBytes)
        }
    }
}
