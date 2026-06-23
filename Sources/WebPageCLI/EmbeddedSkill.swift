/// Stores the agent skill files carried inside the wb binary for local skill
/// installation without requiring network access or a checkout.
import Foundation

enum EmbeddedSkill {
	static var skillText: String {
		EmbeddedSkillPayload.skillText
	}

	static var installScriptText: String {
		EmbeddedSkillPayload.installScriptText
	}

	static var skillData: Data {
		Data((skillText + "\n").utf8)
	}

	static var installScriptData: Data {
		Data((installScriptText + "\n").utf8)
	}
}
