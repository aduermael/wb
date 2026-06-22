// swift-tools-version: 6.2
/// Defines the WebPageCLI package, including the macOS browser executable and
/// the portable Swift lint executable used by local scripts and continuous
/// integration.
import PackageDescription

var products: [Product] = [
	.library(name: "WBLintCore", targets: ["WBLintCore"]),
	.executable(name: "wblint", targets: ["WBLint"]),
]

var targets: [Target] = [
	.target(name: "WBLintCore"),
	.executableTarget(
		name: "WBLint",
		dependencies: ["WBLintCore"],
		path: "Tools/WBLint"
	),
	.testTarget(
		name: "WBLintCoreTests",
		dependencies: ["WBLintCore"]
	),
]

#if os(macOS)
	products.insert(
		contentsOf: [
			.library(name: "WebPageCLI", targets: ["WebPageCLI"]),
			.executable(name: "wb", targets: ["WBExecutable"]),
		], at: 0)

	targets.insert(
		contentsOf: [
			.target(name: "WebPageCLI"),
			.executableTarget(
				name: "WBExecutable",
				dependencies: ["WebPageCLI"],
				path: "Sources/WBExecutable"
			),
			.testTarget(
				name: "WebPageCLITests",
				dependencies: ["WebPageCLI"]
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
