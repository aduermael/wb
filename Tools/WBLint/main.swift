/// Starts the repository linter executable by delegating all rule evaluation to
/// the testable WBLintCore library target.
#if os(Linux)
	import Glibc
#else
	import Darwin
#endif
import Foundation
import WBLintCore

let status = WBLintCommand.run(arguments: Array(CommandLine.arguments.dropFirst()))
exit(status)
