// swift-tools-version: 6.2
/// Defines the WebPageCLI package, including the macOS browser executable and
/// the portable Swift lint executable used by local scripts and continuous
/// integration.
import PackageDescription

var products: [Product] = [
	.library(name: "WBLintCore", targets: ["WBLintCore"]),
	.executable(name: "wblint", targets: ["WBLint"]),
	.executable(name: "wblint-tests", targets: ["WBLintCoreTestRunner"]),
]

var targets: [Target] = [
	.target(name: "WBLintCore"),
	.executableTarget(
		name: "WBLint",
		dependencies: ["WBLintCore"],
		path: "Tools/WBLint"
	),
	.executableTarget(
		name: "WBLintCoreTestRunner",
		dependencies: ["WBLintCore"],
		path: "Tests/WBLintCoreTests"
	),
]

#if os(macOS)
	products.insert(
		contentsOf: [
			.library(name: "WebPageCLI", targets: ["WebPageCLI"]),
			.executable(name: "wb", targets: ["WBExecutable"]),
			.executable(name: "wb-tests", targets: ["WebPageCLITestRunner"]),
		], at: 0)

	targets.insert(
		contentsOf: [
			.target(name: "WebPageCLI"),
			.executableTarget(
				name: "WBExecutable",
				dependencies: ["WebPageCLI"],
				path: "Sources/WBExecutable"
			),
			.executableTarget(
				name: "WebPageCLITestRunner",
				dependencies: ["WebPageCLI"],
				path: "Tests/WebPageCLITests"
			),
		], at: 0)
#endif

let package = Package(
	name: "WebPageCLI",
	platforms: [
		.macOS(.v26)
	],
	products: products,
	targets: targets
)
