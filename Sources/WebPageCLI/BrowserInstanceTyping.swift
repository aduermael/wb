/// Implements native and JavaScript text entry for a browser instance while
/// keeping the main instance lifecycle file small.
import Foundation

@available(macOS 26.0, *)
@MainActor
extension BrowserInstance {
	func typeText(
		_ actionReference: String,
		value: String,
		options: TypingExecutionOptions
	) async throws -> InteractionResult {
		switch options.backend {
		case .javaScript:
			return try await typeTextWithJavaScript(
				actionReference,
				value: value,
				options: options
			)
		case .native:
			return try await typeTextWithNativeEvents(
				actionReference,
				value: value,
				options: options
			)
		}
	}

	private func typeTextWithJavaScript(
		_ actionReference: String,
		value: String,
		options: TypingExecutionOptions
	) async throws -> InteractionResult {
		let generation = try beginLifecycleGeneration()
		try await ensureActions(lifecycleGeneration: generation)
		let action = try action(matching: actionReference)
		let previousURL = page.url
		let arguments: [String: Any] = [
			"id": action.id, "value": value,
			"delayMin": options.delayRange.min, "delayMax": options.delayRange.max,
			"rhythm": options.rhythm.rawValue, "speed": options.speed,
		]
		let message = try await callString(
			Self.typeScript,
			arguments: arguments,
			lifecycleGeneration: generation
		)
		try await settleAfterInteraction(from: previousURL, lifecycleGeneration: generation)
		return InteractionResult(message: message, page: try await snapshot(lifecycleGeneration: generation))
	}

	private func typeTextWithNativeEvents(
		_ actionReference: String,
		value: String,
		options: TypingExecutionOptions
	) async throws -> InteractionResult {
		let generation = try beginLifecycleGeneration()
		try await ensureActions(lifecycleGeneration: generation)
		let action = try action(matching: actionReference)
		let previousURL = page.url
		let controller = ensureWindowController()
		controller.attachTransparentlyIfNeeded()
		let preparation = try await callString(
			Self.nativeTypePreparationScript,
			arguments: ["id": action.id],
			lifecycleGeneration: generation
		)
		guard preparation.hasPrefix("prepared") else {
			try await settleAfterInteraction(from: previousURL, lifecycleGeneration: generation)
			return InteractionResult(
				message: preparation,
				page: try await snapshot(lifecycleGeneration: generation)
			)
		}
		let message = try await controller.typeText(
			value,
			options: options,
			clearSelection: preparation != "prepared 0"
		)
		try await settleAfterInteraction(from: previousURL, lifecycleGeneration: generation)
		return InteractionResult(message: message, page: try await snapshot(lifecycleGeneration: generation))
	}
}
