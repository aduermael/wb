import Foundation
import Darwin

@main
private struct WB {
    static func main() {
        guard #available(macOS 26.0, *) else {
            printError("wb requires macOS 26.0 or newer.")
            Darwin.exit(1)
        }

        Darwin.signal(SIGPIPE, SIG_IGN)

        Task {
            do {
                try await run()
                Darwin.exit(0)
            } catch let exit as WBExit {
                Darwin.exit(exit.code)
            } catch {
                printError(error.localizedDescription)
                Darwin.exit(1)
            }
        }
        RunLoop.main.run()
    }

    @available(macOS 26.0, *)
    private static func run() async throws {
        var arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.first == "--" {
            arguments.removeFirst()
        }

        if arguments.first == "__daemon" {
            try await DaemonProcess().run()
            return
        }

        let invocation = try CLIParser.parse(arguments)

        switch invocation.renderMode {
        case .help(let topic):
            printHelp(topic)

        case .daemonStatus:
            let client = DaemonClient()
            print(client.isRunning() ? "running" : "not running")

        case .daemonLogPath:
            print(WBConfig.current().logPath)

        default:
            if let localCommand = invocation.localCommand {
                try runLocalCommand(localCommand)
                return
            }

            let request = try invocation.request.unwrap("missing daemon request")
            let client = DaemonClient(idleTimeout: invocation.daemonIdleTimeout)
            let response: WireResponse
            do {
                response = try client.send(request, startIfNeeded: invocation.startDaemon)
            } catch {
                if request.command == .daemonStop {
                    print("not running")
                    return
                }
                throw error
            }
            try render(response, mode: invocation.renderMode)
        }
    }
}
