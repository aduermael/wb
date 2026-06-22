/// Owns one WebKit page, optional preview window, page snapshots, JavaScript
/// helpers, screenshots, and coordinate-based interactions for the browser
/// daemon.
import AppKit
import CoreTransferable
import Foundation
import WebKit

@available(macOS 26.0, *)
@MainActor
final class BrowserInstance {
	let id: String

	private let page: WebPage
	private var actions: [BrowserAction] = []
	private var windowController: BrowserWindowController?
	private let createdAt: Date
	private var updatedAt: Date

	init(identity: BrowserInstanceIdentity, websiteDataStore: WKWebsiteDataStore) {
		id = identity.id
		var configuration = WebPage.Configuration()
		configuration.websiteDataStore = websiteDataStore
		page = WebPage(configuration: configuration)
		createdAt = identity.createdAt
		updatedAt = identity.updatedAt
	}

	func open(_ url: URL) async throws -> PageSnapshot {
		daemonLog("browser open start id=\(id) url=\(url.absoluteString)")
		actions.removeAll()

		var request = URLRequest(url: url)
		request.attribution = .user

		do {
			for try await _ in page.load(request) {}
			await settle()
			updatedAt = Date()
		} catch {
			updatedAt = Date()
			throw error
		}

		let pageSnapshot = try await snapshot(fallbackURL: url.absoluteString)
		daemonLog("browser open complete id=\(id) url=\(pageSnapshot.url ?? "-") title=\(pageSnapshot.title)")
		return pageSnapshot
	}

	func snapshot(fallbackURL: String? = nil) async throws -> PageSnapshot {
		let currentActions = try await refreshActions()
		return await snapshot(actions: currentActions, fallbackURL: fallbackURL)
	}

	func bestEffortSnapshot(fallbackURL: String? = nil) async -> PageSnapshot {
		let currentActions = (try? await refreshActions()) ?? []
		return await snapshot(actions: currentActions, fallbackURL: fallbackURL)
	}

	private func snapshot(actions currentActions: [BrowserAction], fallbackURL: String?) async -> PageSnapshot {
		let visibleText = try? await markdownText(maxLength: 6000)
		let stats = try? await pageStats()
		updatedAt = Date()

		return PageSnapshot(
			browser: id,
			state: PageSnapshotState(
				title: page.title,
				url: page.url?.absoluteString ?? fallbackURL,
				loading: page.isLoading,
				progress: page.estimatedProgress
			),
			content: PageSnapshotContent(
				imageCount: stats?.imageCount,
				images: stats?.images ?? [],
				htmlBytes: stats?.htmlBytes,
				text: visibleText,
				actions: currentActions
			)
		)
	}

	func click(_ actionReference: String) async throws -> InteractionResult {
		try await ensureActions()
		let action = try action(matching: actionReference)
		let previousURL = page.url
		let message = try await callString(Self.clickScript, arguments: ["id": action.id])

		await settle()
		if page.url != previousURL {
			actions.removeAll()
		}

		return InteractionResult(message: message, page: try await snapshot())
	}

	func fill(_ actionReference: String, value: String) async throws -> InteractionResult {
		try await ensureActions()
		let action = try action(matching: actionReference)
		let message = try await callString(
			Self.fillScript,
			arguments: ["id": action.id, "value": value]
		)

		return InteractionResult(message: message, page: try await snapshot())
	}

	func submit(_ actionReference: String) async throws -> InteractionResult {
		try await ensureActions()
		let action = try action(matching: actionReference)
		let previousURL = page.url
		let message = try await callString(Self.submitScript, arguments: ["id": action.id])

		await settle()
		if page.url != previousURL {
			actions.removeAll()
		}

		return InteractionResult(message: message, page: try await snapshot())
	}

	func evaluateExpression(_ expression: String) async throws -> String {
		try await callString(Self.evalScript, arguments: ["source": expression])
	}

	func callFunctionBody(_ functionBody: String) async throws -> String {
		let value = try await page.callJavaScript(functionBody)
		return printable(value)
	}

	private func markdownText(maxLength: Int = 12000) async throws -> String {
		try await callString(Self.markdownTextScript, arguments: ["maxLength": maxLength])
	}

	private func pageStats() async throws -> PageDOMStats {
		let json = try await callString(Self.pageStatsScript)
		let data = Data(json.utf8)
		return try JSONDecoder().decode(PageDOMStats.self, from: data)
	}

	private func viewportSize() async throws -> CGSize {
		let json = try await callString(Self.viewportSizeScript)
		let data = Data(json.utf8)
		let size = try JSONDecoder().decode(BrowserViewportSize.self, from: data)
		guard size.width > 0 && size.height > 0 else {
			throw WBError.message("page viewport has no size")
		}
		return CGSize(width: CGFloat(size.width), height: CGFloat(size.height))
	}

	func screenshot(to path: String) async throws -> ScreenshotOutput {
		guard page.url != nil else {
			throw WBError.message("browser has no loaded page")
		}

		let format = try ScreenshotFormat(path: path)
		let viewport = try await viewportSize()
		let pngData = try await page.exported(
			as: .image(
				region: .rect(CGRect(origin: .zero, size: viewport)),
				allowTransparentBackground: false,
				snapshotWidth: viewport.width,
				afterScreenUpdates: true
			))
		let imageData = try format.encodedData(fromPNG: pngData)

		let url = URL(fileURLWithPath: path).standardizedFileURL
		try FileManager.default.createDirectory(
			at: url.deletingLastPathComponent(),
			withIntermediateDirectories: true
		)
		try imageData.write(to: url, options: [.atomic])
		daemonLog("screenshot saved id=\(id) path=\(url.path) bytes=\(imageData.count) format=\(format.name)")
		return ScreenshotOutput(path: url.path, bytes: imageData.count, format: format.name)
	}

	func coordinateAction(_ coordinateAction: BrowserCoordinateAction) async throws -> InteractionResult {
		guard page.url != nil else {
			throw WBError.message("browser has no loaded page")
		}

		let previousURL = page.url
		let message = try await callString(
			Self.coordinateActionScript,
			arguments: coordinateAction.javascriptArguments
		)
		await settle()
		if page.url != previousURL {
			actions.removeAll()
		}

		return InteractionResult(message: message, page: try await snapshot())
	}

	func summary() -> BrowserSummary {
		BrowserSummary(
			browser: id,
			title: page.title.nilIfEmpty,
			url: page.url?.absoluteString,
			loading: page.isLoading,
			progress: page.estimatedProgress,
			actions: actions.count,
			visible: isWindowVisible ? true : nil,
			createdAt: createdAt.iso8601String,
			updatedAt: updatedAt.iso8601String,
			dumped: nil,
			dumpedAt: nil
		)
	}

	func dump() async -> BrowserDump {
		daemonLog("browser dump metadata start id=\(id) url=\(page.url?.absoluteString ?? "-")")
		let actionCount: Int
		if page.url == nil {
			actionCount = actions.count
		} else {
			let refreshedActions = try? await refreshActions()
			actionCount = refreshedActions?.count ?? actions.count
		}

		let dump = BrowserDump(
			schemaVersion: 1,
			browser: id,
			title: page.title.nilIfEmpty,
			url: page.url?.absoluteString,
			loading: page.isLoading,
			progress: page.estimatedProgress,
			actions: actionCount,
			createdAt: createdAt.iso8601String,
			updatedAt: updatedAt.iso8601String,
			dumpedAt: Date().iso8601String,
			snapshot: nil
		)
		daemonLog("browser dump metadata complete id=\(id) url=\(dump.url ?? "-") actions=\(actionCount)")
		return dump
	}

	var isWindowVisible: Bool {
		windowController?.isVisible == true
	}

	var keepsDaemonAlive: Bool {
		windowController?.keepsDaemonAlive == true
	}

	func showWindow() {
		daemonLog("browser show window id=\(id)")
		if windowController == nil {
			windowController = BrowserWindowController(browserID: id, page: page)
		}
		windowController?.show()
	}

	func hideWindow() {
		daemonLog("browser hide window id=\(id)")
		windowController?.hide()
	}

	func closeWindow() {
		daemonLog("browser close window id=\(id)")
		windowController?.close()
		windowController = nil
	}

	private func ensureActions() async throws {
		if actions.isEmpty {
			_ = try await refreshActions()
		}
	}

	private func refreshActions() async throws -> [BrowserAction] {
		guard page.url != nil else {
			actions = []
			return []
		}

		let json = try await callString(Self.listActionsScript)
		let data = Data(json.utf8)
		actions = try JSONDecoder().decode([BrowserAction].self, from: data)
		return actions
	}

	private func action(matching reference: String) throws -> BrowserAction {
		if let index = Int(reference),
			let action = actions.first(where: { $0.index == index })
		{
			return action
		}

		guard let action = actions.first(where: { $0.id == reference }) else {
			throw WBError.message("unknown action \(reference); run 'wb page \(id)' again")
		}
		return action
	}

	private func callString(
		_ functionBody: String,
		arguments: [String: Any] = [:]
	) async throws -> String {
		let result = try await page.callJavaScript(functionBody, arguments: arguments)
		if let string = result as? String {
			return string
		}
		return printable(result)
	}

	private func settle() async {
		_ = try? await Task.sleep(nanoseconds: 250_000_000)

		let deadline = Date().addingTimeInterval(8)
		while Date() < deadline {
			if !page.isLoading {
				let readyState = try? await callString("return document.readyState;")
				if readyState == "interactive" || readyState == "complete" {
					return
				}
			}

			_ = try? await Task.sleep(nanoseconds: 250_000_000)
		}
	}

}

struct BrowserInstanceIdentity {
	let id: String
	let createdAt: Date
	let updatedAt: Date
}

enum BrowserCoordinateAction {
	case click(CGPoint)
	case press(CGPoint)
	case drag(CGPoint)
	case release(CGPoint)
	case scroll(point: CGPoint, deltaX: Double, deltaY: Double)

	init(request: WireRequest) throws {
		let action = try request.requiredCoordinateAction()
		let point = CGPoint(
			x: CGFloat(try request.requiredX()),
			y: CGFloat(try request.requiredY())
		)

		switch action {
		case "click":
			self = .click(point)
		case "press":
			self = .press(point)
		case "drag":
			self = .drag(point)
		case "release":
			self = .release(point)
		case "scroll":
			self = .scroll(
				point: point,
				deltaX: try request.requiredDeltaX(),
				deltaY: try request.requiredDeltaY()
			)
		default:
			throw WBError.message("unknown coordinate action \(action)")
		}
	}

	var name: String {
		switch self {
		case .click:
			return "click"
		case .press:
			return "press"
		case .drag:
			return "drag"
		case .release:
			return "release"
		case .scroll:
			return "scroll"
		}
	}

	var point: CGPoint {
		switch self {
		case .click(let point),
			.press(let point),
			.drag(let point),
			.release(let point):
			return point
		case .scroll(let point, _, _):
			return point
		}
	}

	var javascriptArguments: [String: Any] {
		var arguments: [String: Any] = [
			"action": name,
			"x": Double(point.x),
			"y": Double(point.y),
		]

		if case .scroll(_, let deltaX, let deltaY) = self {
			arguments["deltaX"] = deltaX
			arguments["deltaY"] = deltaY
		}

		return arguments
	}
}

private enum ScreenshotFormat {
	case png
	case jpeg

	init(path: String) throws {
		switch URL(fileURLWithPath: path).pathExtension.lowercased() {
		case "png":
			self = .png
		case "jpg", "jpeg":
			self = .jpeg
		default:
			throw WBError.message("screenshot destination must end in .png, .jpg, or .jpeg")
		}
	}

	var name: String {
		switch self {
		case .png:
			return "png"
		case .jpeg:
			return "jpeg"
		}
	}

	func encodedData(fromPNG pngData: Data) throws -> Data {
		switch self {
		case .png:
			return pngData
		case .jpeg:
			guard let image = NSImage(data: pngData),
				let tiffData = image.tiffRepresentation,
				let bitmap = NSBitmapImageRep(data: tiffData),
				let jpegData = bitmap.representation(
					using: .jpeg,
					properties: [.compressionFactor: 0.9]
				)
			else {
				throw WBError.message("failed to encode JPEG screenshot")
			}
			return jpegData
		}
	}
}

struct InteractionResult {
	let message: String
	let page: PageSnapshot
}

struct ScreenshotOutput {
	let path: String
	let bytes: Int
	let format: String
}

private struct PageDOMStats: Decodable, Sendable {
	let imageCount: Int
	let images: [BrowserImage]
	let htmlBytes: Int
}

private struct BrowserViewportSize: Decodable, Sendable {
	let width: Double
	let height: Double
}
