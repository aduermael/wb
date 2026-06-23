/// Handles daemon wire requests, browser lifecycle management, session resume,
/// autosave, and response construction for the persistent browser process.
import Darwin
import Dispatch
import Foundation
import WebKit

@available(macOS 26.0, *)
@MainActor
final class BrowserManager: @unchecked Sendable {
	private let environment: WBEnvironment
	private let sessionStore: SessionStore
	private let websiteDataStore: WKWebsiteDataStore
	private var browsers: [String: BrowserInstance] = [:]

	init(config: WBConfig = .current()) throws {
		environment = try WBEnvironment.loadOrCreate(in: config.directory)
		sessionStore = SessionStore(directory: config.sessionsDirectory)
		websiteDataStore = WKWebsiteDataStore(forIdentifier: environment.uuid)
		daemonLog(
			"environment loaded directory=\(environment.directory.path) "
				+ "uuid=\(environment.uuid.uuidString.lowercased())"
		)
	}

	func handleWireData(_ data: Data) async -> Data {
		do {
			let request = try JSONDecoder().decode(WireRequest.self, from: data)
			try request.validateResourceLoading()
			try request.validateTypingDelays()
			try request.validateWindowSize()
			daemonLog("request command=\(request.command.rawValue) browser=\(request.browser ?? "-")")
			let response = try await handle(request)
			daemonLog(
				"response command=\(request.command.rawValue) ok=\(response.ok) "
					+ "browser=\(response.browser ?? "-")"
			)
			return try WireCodec.encode(response)
		} catch {
			daemonLog("request failed error=\(error.localizedDescription)")
			return WireCodec.encodeError(error.localizedDescription)
		}
	}

	private func handle(_ request: WireRequest) async throws -> WireResponse {
		switch request.command {
		case .ping:
			return WireResponse.success()
				.withEnvironment(environment.metadata)
				.withMessage("ok")

		case .browserCreate:
			let browser = createBrowser()
			scheduleAutosave(browser, reason: "create")
			daemonLog("browser created id=\(browser.id)")
			return WireResponse.success().withBrowser(browser.id)

		case .browserList:
			return WireResponse.success().withBrowsers(try summaries())

		case .browserClose:
			let id = try request.requiredBrowserID()
			let removedBrowser = browsers.removeValue(forKey: id)
			removedBrowser?.close()
			let removedActive = removedBrowser != nil
			let removedDump = sessionStore.exists(id)
			if removedDump {
				try sessionStore.delete(id)
			}

			guard removedActive || removedDump else {
				throw unknownBrowser(id)
			}
			daemonLog("browser closed id=\(id) removedActive=\(removedActive) removedDump=\(removedDump)")
			return WireResponse.success()
				.withBrowser(id)
				.withMessage("closed")

		case .browserShow:
			let browser = try await showBrowser(request.browser)
			return WireResponse.success().withBrowser(browser.id)

		case .browserHide:
			let browser = try await requireBrowser(request.browser)
			browser.hideWindow()
			return WireResponse.success().withBrowser(browser.id)

		case .browserResize:
			let browser = try await requireBrowser(request.browser)
			let size = try request.windowSize()
			browser.resizeWindow(to: size)
			scheduleAutosave(browser, reason: "resize")
			return WireResponse.success()
				.withBrowser(browser.id)
				.withMessage("resized \(size.width)x\(size.height)")

		case .open:
			let url = try request.requiredURL()
			let browserState = try browserForOpen(id: request.browser)
			let resourceTimeout = try request.resourceWaitTimeout(default: ResourceLoading.defaultTimeout)
			let page: PageSnapshot
			do {
				page = try await browserState.browser.open(
					url,
					waitForResources: request.waitsForResources(),
					resourceTimeout: resourceTimeout
				)
			} catch {
				daemonLog(
					"open failed browser=\(browserState.browser.id) createdForOpen=\(browserState.createdForOpen) "
						+ "error=\(error.localizedDescription)"
				)
				try ensureActive(browserState.browser, context: "open-failed")
				let failedPage = await browserState.browser.bestEffortSnapshot(
					fallbackURL: url.absoluteString)
				try ensureActive(browserState.browser, context: "open-failed-snapshot")
				scheduleAutosave(browserState.browser, reason: "open-failed")
				return WireResponse.failure(error.localizedDescription)
					.withBrowser(browserState.browser.id)
					.withPage(failedPage)
					.withURL(url.absoluteString)
			}
			try ensureActive(browserState.browser, context: "open")
			scheduleAutosave(browserState.browser, reason: "open")
			return WireResponse.success()
				.withBrowser(browserState.browser.id)
				.withPage(page)

		case .waitResources:
			let browser = try await requireBrowser(request.browser)
			let page = try await browser.waitForResourcesSnapshot(
				timeout: try request.resourceWaitTimeout(
					default: ResourceLoading.waitCommandDefaultTimeout)
			)
			try ensureActive(browser, context: "wait-resources")
			return WireResponse.success()
				.withBrowser(browser.id)
				.withPage(page)

		case .page:
			let browser = try await requireBrowser(request.browser)
			let page: PageSnapshot
			if request.waitsForResources() {
				page = try await browser.waitForResourcesSnapshot(
					timeout: try request.resourceWaitTimeout(
						default: ResourceLoading.waitCommandDefaultTimeout)
				)
			} else {
				page = try await browser.snapshot()
			}
			try ensureActive(browser, context: "page")
			return WireResponse.success()
				.withBrowser(browser.id)
				.withPage(page)

		case .click:
			let browser = try await requireBrowser(request.browser)
			let action = try request.requiredAction()
			let result = try await browser.click(action)
			try ensureActive(browser, context: "click")
			scheduleAutosave(browser, reason: "click")
			return WireResponse.success()
				.withBrowser(browser.id)
				.withPage(result.page)
				.withMessage(result.message)

		case .fill:
			let browser = try await requireBrowser(request.browser)
			let action = try request.requiredAction()
			let value = try request.requiredValue()
			let result = try await browser.fill(action, value: value)
			try ensureActive(browser, context: "fill")
			scheduleAutosave(browser, reason: "fill")
			return WireResponse.success()
				.withBrowser(browser.id)
				.withPage(result.page)
				.withMessage(result.message)

		case .typeText:
			let browser = try await requireBrowser(request.browser)
			let action = try request.requiredAction()
			let value = try request.requiredValue()
			let result = try await browser.typeText(
				action,
				value: value,
				options: TypingExecutionOptions(
					delayRange: try request.typingDelayRange(),
					backend: request.typingBackendValue(),
					rhythm: request.typingRhythmValue(),
					speed: try request.typingSpeedValue()
				)
			)
			try ensureActive(browser, context: "type")
			scheduleAutosave(browser, reason: "type")
			return WireResponse.success()
				.withBrowser(browser.id)
				.withPage(result.page)
				.withMessage(result.message)

		case .submit:
			let browser = try await requireBrowser(request.browser)
			let action = try request.requiredAction()
			let result = try await browser.submit(action)
			try ensureActive(browser, context: "submit")
			scheduleAutosave(browser, reason: "submit")
			return WireResponse.success()
				.withBrowser(browser.id)
				.withPage(result.page)
				.withMessage(result.message)

		case .eval:
			let browser = try await requireBrowser(request.browser)
			let script = try request.requiredScript()
			let value: String
			if request.functionBody == true {
				value = try await browser.callFunctionBody(script)
			} else {
				value = try await browser.evaluateExpression(script)
			}
			try ensureActive(browser, context: "eval")
			scheduleAutosave(browser, reason: "eval")
			return WireResponse.success()
				.withBrowser(browser.id)
				.withValue(value)

		case .screenshot:
			let browser = try await requireBrowser(request.browser)
			let path = try request.requiredDestinationPath()
			let result = try await browser.screenshot(
				to: path,
				resourceTimeout: try request.resourceWaitTimeout(
					default: ResourceLoading.defaultTimeout),
				captureDelay: try request.screenshotCaptureDelay(
					default: ScreenshotCapture.defaultDelay)
			)
			try ensureActive(browser, context: "screenshot")
			return WireResponse.success()
				.withBrowser(browser.id)
				.withMessage("saved \(result.path)")

		case .coordinate:
			let browser = try await requireBrowser(request.browser)
			let action = try BrowserCoordinateAction(request: request)
			let result = try await browser.coordinateAction(action)
			try ensureActive(browser, context: action.name)
			scheduleAutosave(browser, reason: action.name)
			return WireResponse.success()
				.withBrowser(browser.id)
				.withPage(result.page)
				.withMessage(result.message)

		case .daemonStop:
			daemonLog("daemon stop requested")
			try await dumpAllSessions()
			DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.2) {
				daemonLog("daemon exiting after stop request")
				Darwin.exit(0)
			}
			return WireResponse.success().withMessage("stopping daemon")
		}
	}

	func dumpAllSessions() async throws {
		daemonLog("dump all sessions count=\(browsers.count)")
		for browser in Array(browsers.values) {
			guard browsers[browser.id] != nil else {
				continue
			}
			_ = try await dump(browser)
		}
		daemonLog("dump all sessions complete")
	}

	func browserIDsKeepingDaemonAlive() -> [String] {
		browsers.values
			.filter { $0.keepsDaemonAlive }
			.map(\.id)
			.sorted()
	}

	private func createBrowser(
		id requestedID: String? = nil,
		createdAt: Date = Date(),
		updatedAt: Date = Date()
	) -> BrowserInstance {
		let id = requestedID ?? nextBrowserID()

		let browser = BrowserInstance(
			identity: BrowserInstanceIdentity(
				id: id,
				createdAt: createdAt,
				updatedAt: updatedAt
			),
			websiteDataStore: websiteDataStore
		)
		browsers[id] = browser
		daemonLog("browser instance registered id=\(id)")
		return browser
	}

	private func nextBrowserID() -> String {
		while true {
			let id = UUID()
				.uuidString
				.replacingOccurrences(of: "-", with: "")
				.prefix(8)
				.lowercased()

			if browsers[String(id)] == nil && !sessionStore.exists(String(id)) {
				return String(id)
			}
		}
	}

	private func browserForOpen(id: String?) throws -> (browser: BrowserInstance, createdForOpen: Bool) {
		guard let id else {
			daemonLog("open requested without browser; creating browser")
			return (createBrowser(), true)
		}

		if let browser = browsers[id] {
			daemonLog("open using active browser id=\(id)")
			return (browser, false)
		}

		guard sessionStore.exists(id) else {
			throw unknownBrowser(id)
		}

		let dump = try sessionStore.load(id)
		daemonLog("open using dumped browser id=\(id)")
		let browser = createBrowser(
			id: dump.browser,
			createdAt: dump.createdDate,
			updatedAt: dump.updatedDate
		)
		return (browser, true)
	}

	private func requireBrowser(_ id: String?) async throws -> BrowserInstance {
		let id = try id.nilIfEmpty.unwrap("missing browser id")
		return try await requireBrowser(id)
	}

	private func requireBrowser(_ id: String) async throws -> BrowserInstance {
		if let browser = browsers[id] {
			return browser
		}

		guard sessionStore.exists(id) else {
			throw unknownBrowser(id)
		}

		let dump = try sessionStore.load(id)
		return try await resume(dump)
	}

	private func showBrowser(_ id: String?) async throws -> BrowserInstance {
		let id = try id.nilIfEmpty.unwrap("missing browser id")
		if let browser = browsers[id] {
			browser.showWindow()
			daemonLog("show active browser id=\(id)")
			return browser
		}

		guard sessionStore.exists(id) else {
			throw unknownBrowser(id)
		}

		let dump = try sessionStore.load(id)
		daemonLog("show dumped browser id=\(id)")
		return try await resume(dump, showingWindow: true)
	}

	private func summaries() throws -> [BrowserSummary] {
		var summariesByID: [String: BrowserSummary] = [:]

		for dump in try sessionStore.dumps() {
			summariesByID[dump.browser] = dump.summary()
		}

		for browser in browsers.values {
			summariesByID[browser.id] = browser.summary()
		}

		return summariesByID.values.sorted {
			$0.browser.localizedStandardCompare($1.browser) == .orderedAscending
		}
	}

	private func dump(_ browser: BrowserInstance) async throws -> BrowserDump {
		daemonLog("dump browser id=\(browser.id)")
		let dump = await browser.dump()
		try ensureActive(browser, context: "dump")
		try sessionStore.save(dump)
		daemonLog("dump saved id=\(browser.id) url=\(dump.url ?? "-")")
		return dump
	}

	private func scheduleAutosave(_ browser: BrowserInstance, reason: String) {
		guard isActive(browser) else {
			daemonLog("autosave skipped inactive id=\(browser.id) reason=\(reason)")
			return
		}
		Task { @MainActor in
			await autosave(browser, reason: reason)
		}
	}

	private func autosave(_ browser: BrowserInstance, reason: String) async {
		guard isActive(browser) else {
			daemonLog("autosave skipped inactive id=\(browser.id) reason=\(reason)")
			return
		}
		daemonLog("autosave start id=\(browser.id) reason=\(reason)")
		do {
			let dump = await browser.dump()
			guard isActive(browser) else {
				daemonLog("autosave skipped removed id=\(browser.id) reason=\(reason)")
				return
			}
			try sessionStore.save(dump)
			daemonLog("autosave complete id=\(browser.id) reason=\(reason)")
		} catch {
			daemonLog(
				"autosave failed id=\(browser.id) reason=\(reason) error=\(error.localizedDescription)")
		}
	}

	private func isActive(_ browser: BrowserInstance) -> Bool {
		guard let active = browsers[browser.id] else {
			return false
		}
		return active === browser
	}

	private func ensureActive(_ browser: BrowserInstance, context: String) throws {
		guard isActive(browser) else {
			daemonLog("browser inactive after \(context) id=\(browser.id)")
			throw WBError.message("browser closed")
		}
	}

	private func unknownBrowser(_ id: String) -> WBError {
		let activeIDs = browsers.keys.sorted().joined(separator: ",").nilIfEmpty ?? "-"
		let dumpedIDs = sessionStore.browserIDs().joined(separator: ",").nilIfEmpty ?? "-"
		daemonLog(
			"unknown browser id=\(id) active=\(activeIDs) dumped=\(dumpedIDs) "
				+ "sessions=\(sessionStore.directory.path)"
		)
		return WBError.message("unknown browser \(id)")
	}

	private func resume(_ dump: BrowserDump, showingWindow: Bool = false) async throws -> BrowserInstance {
		if let browser = browsers[dump.browser] {
			if showingWindow {
				browser.showWindow()
			}
			daemonLog("resume skipped active id=\(dump.browser) showingWindow=\(showingWindow)")
			return browser
		}

		daemonLog(
			"resume start id=\(dump.browser) showingWindow=\(showingWindow) "
				+ "url=\(dump.url ?? dump.snapshot?.url ?? "-")"
		)
		let browser = createBrowser(
			id: dump.browser,
			createdAt: dump.createdDate,
			updatedAt: dump.updatedDate
		)
		if let windowSize = dump.windowSize {
			browser.resizeWindow(to: windowSize)
		}

		if showingWindow {
			browser.showWindow()
		}

		let resumeURL = dump.url ?? dump.snapshot.flatMap { $0.url }
		guard let rawURL = resumeURL.nilIfEmpty,
			let url = URL(string: rawURL)
		else {
			daemonLog("resume has no URL id=\(dump.browser)")
			return browser
		}

		do {
			_ = try await browser.open(url)
			try ensureActive(browser, context: "resume")
			scheduleAutosave(browser, reason: showingWindow ? "show-resume" : "resume")
			daemonLog("resume loaded id=\(dump.browser) url=\(rawURL)")
			return browser
		} catch {
			daemonLog("resume failed id=\(dump.browser) error=\(error.localizedDescription)")
			browser.close()
			if let active = browsers[dump.browser], active === browser {
				browsers.removeValue(forKey: dump.browser)
			}
			throw error
		}
	}
}
