/// Generates embedded wb skill Swift source from checked-in skill files at build time.
import Foundation
import PackagePlugin

@main
struct EmbeddedSkillPlugin: BuildToolPlugin {
	func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
		let generator = try context.tool(named: "EmbeddedSkillGenerator")
		let packageDirectory = context.package.directoryURL
		let skillURL = packageDirectory
			.appendingPathComponent("skill")
			.appendingPathComponent("SKILL.md")
		let installScriptURL = packageDirectory
			.appendingPathComponent("skill")
			.appendingPathComponent("install.sh")
		let outputURL = context.pluginWorkDirectoryURL
			.appendingPathComponent("EmbeddedSkill.generated.swift")

		return [
			.buildCommand(
				displayName: "Generate embedded wb skill payload",
				executable: generator.url,
				arguments: [
					skillURL.path,
					installScriptURL.path,
					outputURL.path,
				],
				inputFiles: [
					skillURL,
					installScriptURL,
				],
				outputFiles: [
					outputURL
				]
			)
		]
	}
}
