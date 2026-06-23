/// Generates embedded wb skill Swift source from checked-in skill files at build time.
import PackagePlugin

@main
struct EmbeddedSkillPlugin: BuildToolPlugin {
	func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
		let generator = try context.tool(named: "EmbeddedSkillGenerator")
		let packageDirectory = context.package.directory
		let skillPath = packageDirectory.appending("skill").appending("SKILL.md")
		let installScriptPath = packageDirectory.appending("skill").appending("install.sh")
		let outputPath = context.pluginWorkDirectory.appending("EmbeddedSkill.generated.swift")

		return [
			.buildCommand(
				displayName: "Generate embedded wb skill payload",
				executable: generator.path,
				arguments: [
					skillPath.string,
					installScriptPath.string,
					outputPath.string,
				],
				inputFiles: [
					skillPath,
					installScriptPath,
				],
				outputFiles: [
					outputPath
				]
			)
		]
	}
}
