// swift-tools-version: 6.2
/// Defines the WebPageCLI package, including the macOS browser executable and
/// the portable Swift lint executable used by local scripts and continuous
/// integration.
import PackageDescription

let package = Package(
	name: "WebPageCLI",
	platforms: [
		.macOS(.v26)
	],
	products: [
		.executable(name: "wb", targets: ["WebPageCLI"]),
		.executable(name: "wblint", targets: ["WBLint"])
	],
	targets: [
		.executableTarget(name: "WebPageCLI"),
		.executableTarget(
			name: "WBLint",
			path: "Tools/WBLint"
		)
	]
)
