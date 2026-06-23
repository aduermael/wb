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
	private var previewWindowSize = BrowserWindowSizing.defaultSize
	private var navigationObserverTask: Task<Void, Never>?
	private var navigationSequence = 0
	private var navigationObservation = NavigationObservationState()
	private var isClosed = false
	private var isScreenshotCaptureInProgress = false
	private var lifecycleGeneration = 0
	private let createdAt: Date
	private var updatedAt: Date

	init(identity: BrowserInstanceIdentity, websiteDataStore: WKWebsiteDataStore) {
		id = identity.id
		var configuration = WebPage.Configuration()
		configuration.websiteDataStore = websiteDataStore
		let userContentController = WKUserContentController()
		userContentController.addUserScript(
			WKUserScript(
				source: Self.resourceTrackerScript,
				injectionTime: .atDocumentStart,
				forMainFrameOnly: false
			))
		configuration.userContentController = userContentController
		page = WebPage(configuration: configuration)
		createdAt = identity.createdAt
		updatedAt = identity.updatedAt
	}

	func open(
		_ url: URL,
		waitForResources: Bool = false,
		resourceTimeout: TimeInterval = ResourceLoading.defaultTimeout
	) async throws -> PageSnapshot {
		let generation = try beginLifecycleGeneration()
		daemonLog("browser open start id=\(id) url=\(url.absoluteString)")
		actions.removeAll()

		var request = URLRequest(url: url)
		request.attribution = .user

		do {
			try await load(
				request,
				resourceWait: BrowserResourceWait(
					enabled: waitForResources,
					timeout: resourceTimeout
				),
				lifecycleGeneration: generation
			)
			try ensureOpen(generation)
			updatedAt = Date()
		} catch {
			updatedAt = Date()
			throw error
		}

		let pageSnapshot = try await snapshot(
			fallbackURL: url.absoluteString,
			lifecycleGeneration: generation
		)
		try ensureOpen(generation)
		daemonLog(
			"browser open complete id=\(id) url=\(pageSnapshot.url ?? "-") "
				+ "title=\(pageSnapshot.title) resourcesLoading=\(pageSnapshot.resourcesLoading)"
		)
		return pageSnapshot
	}

	func snapshot(fallbackURL: String? = nil) async throws -> PageSnapshot {
		let generation = try lifecycleToken()
		return try await snapshot(fallbackURL: fallbackURL, lifecycleGeneration: generation)
	}

	func bestEffortSnapshot(fallbackURL: String? = nil) async -> PageSnapshot {
		guard !isClosed else {
			return closedSnapshot(fallbackURL: fallbackURL)
		}
		let generation = lifecycleGeneration
		let currentActions = (try? await refreshActions(lifecycleGeneration: generation)) ?? []
		let pageSnapshot = try? await snapshot(
			actions: currentActions,
			fallbackURL: fallbackURL,
			lifecycleGeneration: generation
		)
		return pageSnapshot ?? closedSnapshot(fallbackURL: fallbackURL)
	}

	private func snapshot(
		fallbackURL: String?,
		lifecycleGeneration generation: Int
	) async throws -> PageSnapshot {
		let currentActions = try await refreshActions(lifecycleGeneration: generation)
		return try await snapshot(
			actions: currentActions,
			fallbackURL: fallbackURL,
			lifecycleGeneration: generation
		)
	}

	private func snapshot(
		actions currentActions: [BrowserAction],
		fallbackURL: String?,
		lifecycleGeneration generation: Int
	) async throws -> PageSnapshot {
		try ensureOpen(generation)
		let visibleText = try? await markdownText(maxLength: 6000, lifecycleGeneration: generation)
		try ensureOpen(generation)
		let stats = try? await pageStats(lifecycleGeneration: generation)
		try ensureOpen(generation)
		let status = try? await loadStatus(lifecycleGeneration: generation)
		try ensureOpen(generation)
		updatedAt = Date()
		let loading = status?.pageLoading ?? page.isLoading
		let resourcesLoading =
			status.map { $0.resourcesLoading(webKitLoading: page.isLoading) }
			?? page.isLoading

		return PageSnapshot(
			browser: id,
			state: PageSnapshotState(
				title: page.title,
				url: page.url?.absoluteString ?? fallbackURL,
				loading: loading,
				resourcesLoading: resourcesLoading,
				progress: page.estimatedProgress
			),
			content: PageSnapshotContent(
				resourceCount: stats?.resourceCount,
				resources: stats?.resources ?? [],
				htmlBytes: stats?.htmlBytes,
				text: visibleText,
				actions: currentActions
			)
		)
	}

	private func closedSnapshot(fallbackURL: String?) -> PageSnapshot {
		PageSnapshot(
			browser: id,
			state: PageSnapshotState(
				title: page.title,
				url: page.url?.absoluteString ?? fallbackURL,
				loading: false,
				resourcesLoading: false,
				progress: page.estimatedProgress
			),
			content: PageSnapshotContent(
				resourceCount: nil,
				resources: [],
				htmlBytes: nil,
				text: nil,
				actions: []
			)
		)
	}

	func click(_ actionReference: String) async throws -> InteractionResult {
		let generation = try beginLifecycleGeneration()
		try await ensureActions(lifecycleGeneration: generation)
		let action = try action(matching: actionReference)
		let previousURL = page.url
		let message = try await callString(
			Self.clickScript,
			arguments: ["id": action.id],
			lifecycleGeneration: generation
		)

		try await settleAfterInteraction(from: previousURL, lifecycleGeneration: generation)
		if page.url != previousURL {
			actions.removeAll()
		}

		return InteractionResult(
			message: message,
			page: try await snapshot(lifecycleGeneration: generation)
		)
	}

	func fill(_ actionReference: String, value: String) async throws -> InteractionResult {
		let generation = try beginLifecycleGeneration()
		try await ensureActions(lifecycleGeneration: generation)
		let action = try action(matching: actionReference)
		let previousURL = page.url
		let message = try await callString(
			Self.fillScript,
			arguments: ["id": action.id, "value": value],
			lifecycleGeneration: generation
		)
		try await settleAfterInteraction(from: previousURL, lifecycleGeneration: generation)
		if page.url != previousURL {
			actions.removeAll()
		}

		return InteractionResult(
			message: message,
			page: try await snapshot(lifecycleGeneration: generation)
		)
	}

	func typeText(_ actionReference: String, value: String, delayRange: TypingDelayRange) async throws
		-> InteractionResult
	{
		let generation = try beginLifecycleGeneration()
		try await ensureActions(lifecycleGeneration: generation)
		let action = try action(matching: actionReference)
		let previousURL = page.url
		let arguments: [String: Any] = [
			"id": action.id, "value": value,
			"delayMin": delayRange.min, "delayMax": delayRange.max,
		]
		let message = try await callString(
			Self.typeScript, arguments: arguments, lifecycleGeneration: generation)
		try await settleAfterInteraction(from: previousURL, lifecycleGeneration: generation)
		return InteractionResult(message: message, page: try await snapshot(lifecycleGeneration: generation))
	}

	func submit(_ actionReference: String) async throws -> InteractionResult {
		let generation = try beginLifecycleGeneration()
		try await ensureActions(lifecycleGeneration: generation)
		let action = try action(matching: actionReference)
		let previousURL = page.url
		let message = try await callString(
			Self.submitScript,
			arguments: ["id": action.id],
			lifecycleGeneration: generation
		)

		try await settleAfterInteraction(from: previousURL, lifecycleGeneration: generation)
		if page.url != previousURL {
			actions.removeAll()
		}

		return InteractionResult(
			message: message,
			page: try await snapshot(lifecycleGeneration: generation)
		)
	}

	func evaluateExpression(_ expression: String) async throws -> String {
		let generation = try lifecycleToken()
		return try await callString(
			Self.evalScript,
			arguments: ["source": expression],
			lifecycleGeneration: generation
		)
	}

	func callFunctionBody(_ functionBody: String) async throws -> String {
		let generation = try lifecycleToken()
		try ensureOpen(generation)
		let value = try await page.callJavaScript(functionBody)
		try ensureOpen(generation)
		return printable(value)
	}

	private func markdownText(
		maxLength: Int = 12000,
		lifecycleGeneration generation: Int
	) async throws -> String {
		try await callString(
			Self.markdownTextScript,
			arguments: ["maxLength": maxLength],
			lifecycleGeneration: generation
		)
	}

	private func pageStats(lifecycleGeneration generation: Int) async throws -> PageDOMStats {
		let json = try await callString(Self.pageStatsScript, lifecycleGeneration: generation)
		let data = Data(json.utf8)
		return try JSONDecoder().decode(PageDOMStats.self, from: data)
	}

	private func loadStatus(lifecycleGeneration generation: Int? = nil) async throws -> PageLoadStatus {
		let json = try await callString(Self.loadStatusScript, lifecycleGeneration: generation)
		let data = Data(json.utf8)
		return try JSONDecoder().decode(PageLoadStatus.self, from: data)
	}

	private func viewportSize(lifecycleGeneration generation: Int) async throws -> CGSize {
		let json = try await callString(Self.viewportSizeScript, lifecycleGeneration: generation)
		let data = Data(json.utf8)
		let size = try JSONDecoder().decode(BrowserViewportSize.self, from: data)
		guard size.width > 0 && size.height > 0 else {
			throw WBError.message("page viewport has no size")
		}
		return CGSize(width: CGFloat(size.width), height: CGFloat(size.height))
	}

	func screenshot(
		to path: String,
		resourceTimeout: TimeInterval = ResourceLoading.defaultTimeout,
		captureDelay: TimeInterval = ScreenshotCapture.defaultDelay
	) async throws -> ScreenshotOutput {
		try beginScreenshotCapture()
		defer {
			endScreenshotCapture()
		}

		let generation = try beginLifecycleGeneration()
		guard page.url != nil else {
			throw WBError.message("browser has no loaded page")
		}

		let format = try ScreenshotFormat(path: path)
		let viewport = try await viewportSize(lifecycleGeneration: generation)
		let pngData: Data
		if shouldUseScreenshotRenderHost {
			daemonLog("screenshot attaching internal render host id=\(id)")
			windowController?.detachHiddenWindowForScreenshotRenderHost()
			let renderHost = ScreenshotRenderHost(page: page, viewport: viewport)
			pngData = try await renderHost.withAttached {
				try await prepareForScreenshotCapture(
					resourceTimeout: resourceTimeout,
					captureDelay: captureDelay,
					lifecycleGeneration: generation
				)
				return try await exportScreenshotPNG(
					viewport: viewport,
					lifecycleGeneration: generation
				)
			}
		} else {
			try await prepareForScreenshotCapture(
				resourceTimeout: resourceTimeout,
				captureDelay: captureDelay,
				lifecycleGeneration: generation
			)
			pngData = try await exportScreenshotPNG(
				viewport: viewport,
				lifecycleGeneration: generation
			)
		}
		let imageData = try format.encodedData(fromPNG: pngData)
		try ensureOpen(generation)

		let url = URL(fileURLWithPath: path).standardizedFileURL
		try ensureOpen(generation)
		try FileManager.default.createDirectory(
			at: url.deletingLastPathComponent(),
			withIntermediateDirectories: true
		)
		try ensureOpen(generation)
		try imageData.write(to: url, options: [.atomic])
		try ensureOpen(generation)
		daemonLog("screenshot saved id=\(id) path=\(url.path) bytes=\(imageData.count) format=\(format.name)")
		return ScreenshotOutput(path: url.path, bytes: imageData.count, format: format.name)
	}

	private var shouldUseScreenshotRenderHost: Bool {
		windowController?.hasAttachedWindowForScreenshotCapture != true
	}

	private func exportScreenshotPNG(
		viewport: CGSize,
		lifecycleGeneration generation: Int
	) async throws -> Data {
		let pngData = try await page.exported(
			as: .image(
				region: .rect(CGRect(origin: .zero, size: viewport)),
				allowTransparentBackground: false,
				snapshotWidth: viewport.width,
				afterScreenUpdates: true
			))
		try ensureOpen(generation)
		return pngData
	}

	func coordinateAction(_ coordinateAction: BrowserCoordinateAction) async throws -> InteractionResult {
		let generation = try beginLifecycleGeneration()
		guard page.url != nil else {
			throw WBError.message("browser has no loaded page")
		}

		let previousURL = page.url
		let message = try await callString(
			Self.coordinateActionScript,
			arguments: coordinateAction.javascriptArguments,
			lifecycleGeneration: generation
		)
		try await settleAfterInteraction(from: previousURL, lifecycleGeneration: generation)
		if page.url != previousURL {
			actions.removeAll()
		}

		return InteractionResult(
			message: message,
			page: try await snapshot(lifecycleGeneration: generation)
		)
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
		let generation = try? lifecycleToken()
		let actionCount: Int
		if page.url == nil {
			actionCount = actions.count
		} else if let generation {
			let refreshedActions = try? await refreshActions(lifecycleGeneration: generation)
			actionCount = refreshedActions?.count ?? actions.count
		} else {
			actionCount = actions.count
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
			snapshot: nil,
			windowWidth: previewWindowSize.width,
			windowHeight: previewWindowSize.height
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
			let controller = BrowserWindowController(
				browserID: id,
				page: page,
				navigationCallbacks: BrowserWindowNavigationCallbacks(
					started: { [weak self] in
						self?.previewNavigationStarted() ?? 0
					},
					completed: { [weak self] generation in
						self?.previewNavigationCompleted(generation)
					}
				)
			)
			controller.resize(to: previewWindowSize)
			windowController = controller
		}
		windowController?.show()
	}

	func resizeWindow(to size: BrowserWindowSize) {
		daemonLog("browser resize window id=\(id) size=\(size.width)x\(size.height)")
		previewWindowSize = size
		windowController?.resize(to: size)
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

	func close() {
		guard !isClosed else {
			closeWindow()
			return
		}
		isClosed = true
		lifecycleGeneration += 1
		cancelNavigationObserver()
		closeWindow()
	}

	private func ensureActions(lifecycleGeneration generation: Int) async throws {
		if actions.isEmpty {
			_ = try await refreshActions(lifecycleGeneration: generation)
		}
	}

	private func refreshActions(lifecycleGeneration generation: Int) async throws -> [BrowserAction] {
		try ensureOpen(generation)
		guard page.url != nil else {
			actions = []
			return []
		}

		let json = try await callString(Self.listActionsScript, lifecycleGeneration: generation)
		let data = Data(json.utf8)
		try ensureOpen(generation)
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
		arguments: [String: Any] = [:],
		lifecycleGeneration generation: Int? = nil
	) async throws -> String {
		try ensureOpen(generation)
		let result = try await page.callJavaScript(functionBody, arguments: arguments)
		try ensureOpen(generation)
		if let string = result as? String {
			return string
		}
		return printable(result)
	}

	private func load(
		_ request: URLRequest,
		resourceWait: BrowserResourceWait,
		lifecycleGeneration generation: Int
	) async throws {
		try await observeNavigationUntilHTMLReady(request, lifecycleGeneration: generation)
		if resourceWait.enabled {
			try await waitForResources(timeout: resourceWait.timeout, lifecycleGeneration: generation)
		}
	}

	private func observeNavigationUntilHTMLReady(
		_ request: URLRequest,
		lifecycleGeneration generation: Int
	) async throws {
		try ensureOpen(generation)
		let sequence = beginNavigationObservation(request)
		do {
			let committed = try await waitForNavigationCommit(
				sequence: sequence,
				timeout: ResourceLoading.defaultTimeout,
				lifecycleGeneration: generation
			)
			if committed {
				try await waitForCommittedPageHTML(
					sequence: sequence,
					timeout: ResourceLoading.defaultTimeout,
					lifecycleGeneration: generation
				)
			}
		} catch {
			if navigationSequence == sequence {
				cancelNavigationObserver()
			}
			throw error
		}
	}

	private func beginNavigationObservation(_ request: URLRequest) -> Int {
		cancelNavigationObserver()
		navigationSequence += 1
		let sequence = navigationSequence
		navigationObservation = NavigationObservationState()
		navigationObserverTask = Task { @MainActor [self] in
			do {
				for try await event in page.load(request) {
					if Task.isCancelled || navigationSequence != sequence {
						return
					}
					switch event {
					case .committed:
						navigationObservation.committed = true
						_ = try? await loadStatus()
					default:
						continue
					}
				}
				guard !Task.isCancelled && navigationSequence == sequence else {
					return
				}
				navigationObservation.finished = true
			} catch {
				guard !Task.isCancelled && navigationSequence == sequence else {
					return
				}
				navigationObservation.error = error
				navigationObservation.finished = true
			}
		}
		return sequence
	}

	private func cancelNavigationObserver() {
		navigationObserverTask?.cancel()
		navigationObserverTask = nil
		navigationSequence += 1
		navigationObservation.error = CancellationError()
		navigationObservation.finished = true
	}

	private func waitForNavigationCommit(
		sequence: Int,
		timeout: TimeInterval,
		lifecycleGeneration generation: Int
	) async throws -> Bool {
		let deadline = Date().addingTimeInterval(timeout)
		while Date() < deadline {
			try Task.checkCancellation()
			try ensureCurrentNavigation(sequence: sequence, lifecycleGeneration: generation)
			if let error = navigationObservation.error {
				throw error
			}
			if navigationObservation.committed {
				return true
			}
			if navigationObservation.finished {
				return false
			}

			try await Task.sleep(nanoseconds: 50_000_000)
		}
		try ensureCurrentNavigation(sequence: sequence, lifecycleGeneration: generation)
		throw WBError.message("timed out waiting for navigation to commit")
	}

	private func waitForCommittedPageHTML(
		sequence: Int,
		timeout: TimeInterval,
		lifecycleGeneration generation: Int
	) async throws {
		let deadline = Date().addingTimeInterval(timeout)
		while Date() < deadline {
			try Task.checkCancellation()
			try ensureCurrentNavigation(sequence: sequence, lifecycleGeneration: generation)
			if let error = navigationObservation.error {
				throw error
			}
			if let status = try? await loadStatus(lifecycleGeneration: generation) {
				try ensureCurrentNavigation(sequence: sequence, lifecycleGeneration: generation)
				if !status.pageLoading {
					return
				}
			}
			if navigationObservation.finished {
				return
			}

			try await Task.sleep(nanoseconds: 100_000_000)
		}
		try ensureCurrentNavigation(sequence: sequence, lifecycleGeneration: generation)
		throw WBError.message("timed out waiting for page HTML readiness")
	}

	private func ensureCurrentNavigation(sequence: Int, lifecycleGeneration generation: Int) throws {
		try ensureOpen(generation)
		if navigationSequence != sequence {
			throw CancellationError()
		}
	}

	private func settleAfterInteraction(from startingURL: URL?, lifecycleGeneration generation: Int) async throws {
		let deadline = Date().addingTimeInterval(InteractionSettling.defaultTimeout)
		var lastURL = startingURL
		var quietSince: Date?
		while Date() < deadline {
			try Task.checkCancellation()
			try ensureOpen(generation)
			let status = try? await loadStatus(lifecycleGeneration: generation)
			try ensureOpen(generation)
			let webKitLoading = page.isLoading
			if page.url != lastURL {
				lastURL = page.url
				quietSince = nil
			}
			let settled = status?.interactionSettled(webKitLoading: webKitLoading) ?? !webKitLoading
			if settled {
				let now = Date()
				if quietSince == nil {
					quietSince = now
				}
				if let quietStart = quietSince,
					now.timeIntervalSince(quietStart) >= InteractionSettling.quietWindow
				{
					return
				}
			} else {
				quietSince = nil
			}

			guard await sleepForPolling(nanoseconds: InteractionSettling.pollIntervalNanoseconds) else {
				return
			}
		}
		try ensureOpen(generation)
	}

	private func waitForResources(timeout: TimeInterval, lifecycleGeneration generation: Int) async throws {
		let deadline = Date().addingTimeInterval(timeout)
		while Date() < deadline {
			try Task.checkCancellation()
			try ensureOpen(generation)
			if let status = try? await loadStatus(lifecycleGeneration: generation) {
				try ensureOpen(generation)
				if !status.pageLoading && !status.resourcesLoading(webKitLoading: page.isLoading) {
					return
				}
			}

			guard await sleepForPolling(nanoseconds: 250_000_000) else {
				return
			}
		}
		try ensureOpen(generation)
	}

	private func waitForScreenshotCaptureDelay(
		_ delay: TimeInterval,
		lifecycleGeneration generation: Int
	) async throws {
		try ensureOpen(generation)
		guard delay > 0 else {
			return
		}
		try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
		try ensureOpen(generation)
	}

	private func prepareForScreenshotCapture(
		resourceTimeout: TimeInterval,
		captureDelay: TimeInterval,
		lifecycleGeneration generation: Int
	) async throws {
		let budget = ScreenshotCaptureWaitBudget(
			resourceTimeout: resourceTimeout,
			captureDelay: captureDelay
		)
		try ensureOpen(generation)
		try await prepareScreenshotLayout(lifecycleGeneration: generation)
		try await waitForScreenshotResources(budget: budget, lifecycleGeneration: generation)
		try await waitForScreenshotFonts(budget: budget, lifecycleGeneration: generation)
		try await prepareScreenshotLayout(lifecycleGeneration: generation)
		let producedFrames = try await waitForScreenshotAnimationFrames(
			frameCount: ScreenshotRenderSettling.frameCount,
			timeout: budget.timeout(
				cappedAt: ScreenshotRenderSettling.frameTimeout,
				includingResourceBudget: false
			),
			lifecycleGeneration: generation
		)
		if !producedFrames {
			try await completeStuckScreenshotAnimations(lifecycleGeneration: generation)
		}
		try await prepareScreenshotLayout(lifecycleGeneration: generation)
		try await waitForScreenshotResources(budget: budget, lifecycleGeneration: generation)
		try await waitForScreenshotFonts(budget: budget, lifecycleGeneration: generation)
		try await waitForScreenshotCaptureDelay(
			budget.timeout(cappedAt: captureDelay, includingResourceBudget: false),
			lifecycleGeneration: generation
		)
		try await prepareScreenshotLayout(dispatchResize: false, lifecycleGeneration: generation)
	}

	private func waitForScreenshotResources(
		budget: ScreenshotCaptureWaitBudget,
		lifecycleGeneration generation: Int
	) async throws {
		let timeout = budget.timeout(cappedAt: nil, includingResourceBudget: true)
		guard timeout > 0 else {
			try ensureOpen(generation)
			return
		}
		try await waitForResources(timeout: timeout, lifecycleGeneration: generation)
	}

	private func waitForScreenshotFonts(
		budget: ScreenshotCaptureWaitBudget,
		lifecycleGeneration generation: Int
	) async throws {
		try await waitForScreenshotFonts(
			timeout: budget.timeout(
				cappedAt: ScreenshotRenderSettling.fontTimeout,
				includingResourceBudget: false
			),
			lifecycleGeneration: generation
		)
	}

	private func prepareScreenshotLayout(
		dispatchResize: Bool = true,
		lifecycleGeneration generation: Int
	) async throws {
		_ = try await callString(
			Self.screenshotPrepareLayoutScript,
			arguments: ["dispatchResize": dispatchResize],
			lifecycleGeneration: generation
		)
		try ensureOpen(generation)
	}

	private func waitForScreenshotFonts(
		timeout: TimeInterval,
		lifecycleGeneration generation: Int
	) async throws {
		try ensureOpen(generation)
		guard timeout > 0 else {
			return
		}
		let result = try await callString(
			Self.screenshotWaitForFontsScript,
			arguments: ["timeoutMs": ScreenshotRenderSettling.milliseconds(timeout)],
			lifecycleGeneration: generation
		)
		try ensureOpen(generation)
		daemonLog("screenshot fonts id=\(id) result=\(result)")
		switch result {
		case "ready", "unavailable", "timeout":
			return
		case "error":
			throw WBError.message("failed waiting for screenshot fonts")
		default:
			throw WBError.message("unexpected screenshot font wait result \(result)")
		}
	}

	private func waitForScreenshotAnimationFrames(
		frameCount: Int,
		timeout: TimeInterval,
		lifecycleGeneration generation: Int
	) async throws -> Bool {
		let json = try await callString(
			Self.screenshotWaitForAnimationFramesScript,
			arguments: [
				"frameCount": frameCount,
				"timeoutMs": ScreenshotRenderSettling.milliseconds(timeout),
			],
			lifecycleGeneration: generation
		)
		try ensureOpen(generation)
		let data = Data(json.utf8)
		let result = try JSONDecoder().decode(ScreenshotAnimationFrameWaitResult.self, from: data)
		daemonLog(
			"screenshot render frames id=\(id) completed=\(result.completed) "
				+ "frames=\(result.frames) reason=\(result.reason)"
		)
		return result.completed
	}

	private func completeStuckScreenshotAnimations(lifecycleGeneration generation: Int) async throws {
		let result = try await callString(
			Self.screenshotCompleteStuckAnimationsScript,
			lifecycleGeneration: generation
		)
		try ensureOpen(generation)
		daemonLog("screenshot completed stuck animations id=\(id) result=\(result)")
	}

	private func sleepForPolling(nanoseconds: UInt64) async -> Bool {
		do {
			try await Task.sleep(nanoseconds: nanoseconds)
			return true
		} catch {
			return false
		}
	}

	private func snapshot(lifecycleGeneration generation: Int) async throws -> PageSnapshot {
		try await snapshot(fallbackURL: nil, lifecycleGeneration: generation)
	}

	private func lifecycleToken() throws -> Int {
		try ensureOpen()
		return lifecycleGeneration
	}

	private func beginLifecycleGeneration() throws -> Int {
		try ensureOpen()
		lifecycleGeneration += 1
		return lifecycleGeneration
	}

	private func beginScreenshotCapture() throws {
		try ensureOpen()
		guard !isScreenshotCaptureInProgress else {
			throw WBError.message("screenshot already in progress for browser \(id)")
		}
		isScreenshotCaptureInProgress = true
	}

	private func endScreenshotCapture() {
		isScreenshotCaptureInProgress = false
	}

	private func previewNavigationStarted() -> Int {
		guard !isClosed else {
			return lifecycleGeneration
		}
		cancelNavigationObserver()
		actions.removeAll()
		lifecycleGeneration += 1
		updatedAt = Date()
		daemonLog("preview navigation started id=\(id) generation=\(lifecycleGeneration)")
		return lifecycleGeneration
	}

	private func previewNavigationCompleted(_ startedGeneration: Int) {
		guard !isClosed else {
			return
		}
		guard startedGeneration == lifecycleGeneration else {
			daemonLog(
				"preview navigation completed stale id=\(id) "
					+ "startedGeneration=\(startedGeneration) generation=\(lifecycleGeneration)"
			)
			return
		}
		actions.removeAll()
		lifecycleGeneration += 1
		updatedAt = Date()
		daemonLog(
			"preview navigation completed id=\(id) startedGeneration=\(startedGeneration) "
				+ "generation=\(lifecycleGeneration)"
		)
	}

	private func ensureOpen(_ generation: Int? = nil) throws {
		guard !isClosed else {
			throw WBError.message("browser closed")
		}
		if let generation, generation != lifecycleGeneration {
			throw WBError.message("browser page changed during command")
		}
	}

}

struct BrowserInstanceIdentity {
	let id: String
	let createdAt: Date
	let updatedAt: Date
}

private struct NavigationObservationState {
	var committed = false
	var finished = false
	var error: Error?
}

private struct BrowserResourceWait {
	let enabled: Bool
	let timeout: TimeInterval
}

struct InteractionResult { let message: String; let page: PageSnapshot }

struct ScreenshotOutput { let path: String; let bytes: Int; let format: String }

private struct PageDOMStats: Decodable, Sendable {
	let resourceCount: Int; let resources: [BrowserResource]; let htmlBytes: Int
}

private struct BrowserViewportSize: Decodable, Sendable { let width: Double; let height: Double }
