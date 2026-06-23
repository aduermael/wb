/// Manages the optional native preview window, application menu, toolbar, and
/// window lifecycle used when a headless browser session is shown interactively.
import AppKit
import Foundation
import SwiftUI
import WebKit

@available(macOS 26.0, *)
@MainActor
enum BrowserApplicationHost {
	private static let appName = "wb"
	private static let applicationActions = BrowserApplicationActions()
	private static let applicationDelegate = BrowserApplicationDelegate()
	private static var isPrepared = false

	static func prepareForDaemon() {
		let application = NSApplication.shared
		_ = application.setActivationPolicy(.accessory)
		prepare(application)
	}

	static func prepareForWindow() -> NSApplication {
		let application = NSApplication.shared
		prepare(application)
		_ = application.setActivationPolicy(.accessory)
		return application
	}

	static func demoteIfNoVisibleWindows() {
		let application = NSApplication.shared
		let hasVisibleWindow = application.windows.contains {
			($0.isVisible || $0.isMiniaturized) && $0.alphaValue > 0
		}
		if !hasVisibleWindow {
			_ = application.setActivationPolicy(.accessory)
		}
	}

	static func pumpEvents(until limit: Date) {
		let application = NSApplication.shared
		while let event = application.nextEvent(
			matching: .any,
			until: limit,
			inMode: RunLoop.Mode.default,
			dequeue: true
		) {
			application.sendEvent(event)
		}
		application.updateWindows()
	}

	static func setQuitHandler(_ handler: @escaping () -> Void) {
		applicationActions.quitHandler = handler
	}

	private static func prepare(_ application: NSApplication) {
		guard !isPrepared else {
			return
		}

		application.delegate = applicationDelegate
		installMainMenu(on: application)
		installApplicationIcon(on: application)
		application.finishLaunching()
		isPrepared = true
	}

	private static func installApplicationIcon(on application: NSApplication) {
		guard let image = NSImage(systemSymbolName: "globe", accessibilityDescription: appName) else {
			return
		}
		application.applicationIconImage = image
	}

	private static func installMainMenu(on application: NSApplication) {
		let mainMenu = NSMenu(title: "Main Menu")

		let applicationMenuItem = NSMenuItem(title: appName, action: nil, keyEquivalent: "")
		mainMenu.addItem(applicationMenuItem)

		let applicationMenu = NSMenu(title: appName)
		applicationMenu.addItem(
			NSMenuItem(
				title: "Hide \(appName)",
				action: #selector(NSApplication.hide(_:)),
				keyEquivalent: "h"
			))
		applicationMenu.addItem(
			NSMenuItem(
				title: "Hide Others",
				action: #selector(NSApplication.hideOtherApplications(_:)),
				keyEquivalent: "h"
			))
		applicationMenu.items.last?.keyEquivalentModifierMask = [.command, .option]
		applicationMenu.addItem(
			NSMenuItem(
				title: "Show All",
				action: #selector(NSApplication.unhideAllApplications(_:)),
				keyEquivalent: ""
			))
		applicationMenu.addItem(.separator())
		let quitItem = NSMenuItem(
			title: "Quit \(appName)",
			action: #selector(BrowserApplicationActions.quit(_:)),
			keyEquivalent: "q"
		)
		quitItem.target = applicationActions
		applicationMenu.addItem(quitItem)
		applicationMenuItem.submenu = applicationMenu

		let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
		mainMenu.addItem(editMenuItem)

		let editMenu = NSMenu(title: "Edit")
		editMenu.addItem(
			NSMenuItem(
				title: "Undo",
				action: Selector(("undo:")),
				keyEquivalent: "z"
			))
		editMenu.addItem(
			NSMenuItem(
				title: "Redo",
				action: Selector(("redo:")),
				keyEquivalent: "Z"
			))
		editMenu.addItem(.separator())
		editMenu.addItem(
			NSMenuItem(
				title: "Cut",
				action: #selector(NSText.cut(_:)),
				keyEquivalent: "x"
			))
		editMenu.addItem(
			NSMenuItem(
				title: "Copy",
				action: #selector(NSText.copy(_:)),
				keyEquivalent: "c"
			))
		editMenu.addItem(
			NSMenuItem(
				title: "Paste",
				action: #selector(NSText.paste(_:)),
				keyEquivalent: "v"
			))
		editMenu.addItem(.separator())
		editMenu.addItem(
			NSMenuItem(
				title: "Select All",
				action: #selector(NSText.selectAll(_:)),
				keyEquivalent: "a"
			))
		editMenuItem.submenu = editMenu

		let windowMenuItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
		mainMenu.addItem(windowMenuItem)

		let windowMenu = NSMenu(title: "Window")
		windowMenu.addItem(
			NSMenuItem(
				title: "Close",
				action: #selector(NSWindow.performClose(_:)),
				keyEquivalent: "w"
			))
		windowMenu.addItem(
			NSMenuItem(
				title: "Minimize",
				action: #selector(NSWindow.performMiniaturize(_:)),
				keyEquivalent: "m"
			))
		windowMenu.addItem(
			NSMenuItem(
				title: "Zoom",
				action: #selector(NSWindow.performZoom(_:)),
				keyEquivalent: ""
			))
		windowMenuItem.submenu = windowMenu

		application.mainMenu = mainMenu
		application.windowsMenu = windowMenu
	}
}

@available(macOS 26.0, *)
@MainActor
private final class BrowserApplicationDelegate: NSObject, NSApplicationDelegate {
	func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
		return false
	}

	func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
		daemonLog("application should terminate requested -> cancel")
		return .terminateCancel
	}

	func applicationWillTerminate(_ notification: Notification) {
		daemonLog("application will terminate")
	}
}

@available(macOS 26.0, *)
@MainActor
private final class BrowserApplicationActions: NSObject {
	var quitHandler: (() -> Void)?

	@objc func quit(_ sender: Any?) {
		if let quitHandler {
			quitHandler()
		} else {
			NSApplication.shared.terminate(sender)
		}
	}
}

private func rectDebugDescription(_ rect: NSRect) -> String {
	String(
		format: "x=%.1f,y=%.1f,w=%.1f,h=%.1f",
		Double(rect.origin.x),
		Double(rect.origin.y),
		Double(rect.width),
		Double(rect.height)
	)
}

private enum BrowserWindowMetrics {
	static let minimumSize = NSSize(
		width: CGFloat(BrowserWindowSizing.minimumWidth),
		height: CGFloat(BrowserWindowSizing.minimumHeight)
	)
	static let screenPadding: CGFloat = 40

	static func nsSize(_ size: BrowserWindowSize) -> NSSize {
		NSSize(width: CGFloat(size.width), height: CGFloat(size.height))
	}
}

@available(macOS 26.0, *)
@MainActor
private final class BrowserPanel: NSPanel {
	override var canBecomeKey: Bool {
		true
	}

	override var canBecomeMain: Bool {
		true
	}
}

@available(macOS 26.0, *)
@MainActor
struct BrowserWindowNavigationCallbacks {
	let started: () -> Int
	let completed: (Int) -> Void
}

@available(macOS 26.0, *)
@MainActor
final class BrowserWindowController: NSObject, NSWindowDelegate {
	private let browserID: String
	private let page: WebPage
	private let navigationCallbacks: BrowserWindowNavigationCallbacks
	private var preferredSize = BrowserWindowSizing.defaultSize
	private var window: NSWindow?
	private var isHiddenByCommand = false

	init(
		browserID: String,
		page: WebPage,
		navigationCallbacks: BrowserWindowNavigationCallbacks
	) {
		self.browserID = browserID
		self.page = page
		self.navigationCallbacks = navigationCallbacks
	}

	var isVisible: Bool {
		guard let window else {
			return false
		}
		return !isHiddenByCommand && window.alphaValue > 0 && (window.isVisible || window.isMiniaturized)
	}

	var isVisibleForScreenshotCapture: Bool {
		guard let window else {
			return false
		}
		return window.isVisible || window.isMiniaturized
	}

	var hasAttachedWindowForScreenshotCapture: Bool {
		window != nil
	}

	var keepsDaemonAlive: Bool {
		window != nil && !isHiddenByCommand
	}

	func show() {
		daemonLog("window show requested browser=\(browserID)")
		isHiddenByCommand = false
		let application = BrowserApplicationHost.prepareForWindow()
		application.unhide(nil)

		let window = window ?? makeWindow()
		window.collectionBehavior = Self.previewCollectionBehavior
		window.level = .floating
		makeVisible(window)
		application.activate(ignoringOtherApps: true)
		window.makeKeyAndOrderFront(nil)
		window.orderFrontRegardless()
		daemonLog(
			"window shown browser=\(browserID) visible=\(window.isVisible) "
				+ "miniaturized=\(window.isMiniaturized) key=\(window.isKeyWindow) "
				+ "main=\(window.isMainWindow) appActive=\(application.isActive) "
				+ "panel=\(window is NSPanel)"
		)
	}

	func hide() {
		daemonLog("window hide requested browser=\(browserID)")
		isHiddenByCommand = true
		if let window {
			makeTransparent(window)
			window.displayIfNeeded()
		}
		BrowserApplicationHost.demoteIfNoVisibleWindows()
	}

	func attachTransparentlyIfNeeded() {
		let wasCreated = window == nil
		let window = window ?? makeWindow()
		if isHiddenByCommand || !window.isVisible || window.alphaValue == 0 {
			isHiddenByCommand = true
			makeTransparent(window)
			if wasCreated {
				window.orderBack(nil)
			}
			window.displayIfNeeded()
		}
		window.contentView?.layoutSubtreeIfNeeded()
		BrowserApplicationHost.pumpEvents(until: Date().addingTimeInterval(0.08))
	}

	func typeText(
		_ text: String,
		options: TypingExecutionOptions,
		clearSelection: Bool
	) async throws -> String {
		if clearSelection {
			try sendKey(.backspace)
		}

		let characters = Array(text)
		var previousCharacter: Character?
		for character in characters {
			try await sleep(
				for: options.delayRange,
				rhythm: options.rhythm,
				after: previousCharacter
			)
			try sendKey(.character(String(character)))
			previousCharacter = character
		}

		BrowserApplicationHost.pumpEvents(until: Date().addingTimeInterval(0.05))
		let count = characters.count
		return "typed \(count) character\(count == 1 ? "" : "s")"
	}

	func resize(to size: BrowserWindowSize) {
		preferredSize = size
		guard let window else {
			daemonLog("window resize stored browser=\(browserID) size=\(size.width)x\(size.height)")
			return
		}

		let shouldRestoreVisibleWindow =
			!isHiddenByCommand && window.isVisible && !window.isMiniaturized
		let previousCenter = CGPoint(x: window.frame.midX, y: window.frame.midY)
		var frame = frame(forContentSize: size, centeredAt: previousCenter, in: window)
		frame = constrainFrameToVisibleScreen(frame, for: window)
		window.setFrame(frame, display: shouldRestoreVisibleWindow)
		window.contentView?.layoutSubtreeIfNeeded()
		if shouldRestoreVisibleWindow {
			let application = BrowserApplicationHost.prepareForWindow()
			application.unhide(nil)
			window.collectionBehavior = Self.previewCollectionBehavior
			window.level = .floating
			makeVisible(window)
			application.activate(ignoringOtherApps: true)
			window.makeKeyAndOrderFront(nil)
			window.orderFrontRegardless()
			window.displayIfNeeded()
		}
		daemonLog(
			"window resized browser=\(browserID) frame=(\(rectDebugDescription(frame))) "
				+ "restoreVisible=\(shouldRestoreVisibleWindow) visible=\(window.isVisible)"
		)
	}

	func close() {
		daemonLog("window close requested browser=\(browserID)")
		isHiddenByCommand = true
		window?.delegate = nil
		window?.contentViewController = nil
		window?.close()
		window = nil
		BrowserApplicationHost.demoteIfNoVisibleWindows()
		daemonLog("window closed browser=\(browserID)")
	}

	func windowWillClose(_ notification: Notification) {
		daemonLog("window will close browser=\(browserID)")
		isHiddenByCommand = true
		if let closingWindow = notification.object as? NSWindow {
			closingWindow.delegate = nil
			closingWindow.contentViewController = nil
		}
		window = nil
		Task { @MainActor in
			BrowserApplicationHost.demoteIfNoVisibleWindows()
		}
	}

	private func makeWindow() -> NSWindow {
		let window = BrowserPanel(
			contentRect: NSRect(origin: .zero, size: BrowserWindowMetrics.nsSize(preferredSize)),
			styleMask: [
				.titled,
				.closable,
				.miniaturizable,
				.resizable,
			],
			backing: .buffered,
			defer: false
		)
		window.title = "wb \(browserID)"
		window.minSize = BrowserWindowMetrics.minimumSize
		window.level = .floating
		window.collectionBehavior = Self.previewCollectionBehavior
		window.isFloatingPanel = true
		window.hidesOnDeactivate = false
		window.becomesKeyOnlyIfNeeded = false
		window.isReleasedWhenClosed = false
		window.tabbingMode = .disallowed
		window.delegate = self
		window.contentViewController = NSHostingController(
			rootView: BrowserWindowView(
				page: page,
				navigationCallbacks: navigationCallbacks
			)
		)
		positionWindow(window)
		self.window = window
		daemonLog("window created browser=\(browserID)")
		return window
	}

	private static var previewCollectionBehavior: NSWindow.CollectionBehavior {
		[
			.canJoinAllSpaces,
			.fullScreenAuxiliary,
		]
	}

	private func positionWindow(_ window: NSWindow) {
		guard let screen = NSScreen.main ?? NSScreen.screens.first else {
			let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
			window.setFrame(
				frame(forContentSize: preferredSize, centeredAt: center, in: window),
				display: false
			)
			window.center()
			daemonLog("window positioned browser=\(browserID) fallback=center no-screen")
			return
		}

		let visibleFrame = screen.visibleFrame
		let preferredFrameSize = frameSize(forContentSize: preferredSize, in: window)
		let maxWidth = max(
			BrowserWindowMetrics.minimumSize.width,
			visibleFrame.width - BrowserWindowMetrics.screenPadding
		)
		let maxHeight = max(
			BrowserWindowMetrics.minimumSize.height,
			visibleFrame.height - BrowserWindowMetrics.screenPadding
		)
		let width = min(max(BrowserWindowMetrics.minimumSize.width, preferredFrameSize.width), maxWidth)
		let height = min(max(BrowserWindowMetrics.minimumSize.height, preferredFrameSize.height), maxHeight)
		let frame = NSRect(
			x: visibleFrame.midX - width / 2,
			y: visibleFrame.midY - height / 2,
			width: width,
			height: height
		)
		window.setFrame(frame, display: false)
		daemonLog(
			"window positioned browser=\(browserID) frame=(\(rectDebugDescription(frame))) "
				+ "screen=\(screen.localizedName)"
		)
	}

	private func frameSize(forContentSize size: BrowserWindowSize, in window: NSWindow) -> NSSize {
		let contentRect = NSRect(origin: .zero, size: BrowserWindowMetrics.nsSize(size))
		return window.frameRect(forContentRect: contentRect).size
	}

	private func frame(
		forContentSize size: BrowserWindowSize,
		centeredAt center: CGPoint,
		in window: NSWindow
	) -> NSRect {
		let frameSize = frameSize(forContentSize: size, in: window)
		return NSRect(
			x: center.x - frameSize.width / 2,
			y: center.y - frameSize.height / 2,
			width: frameSize.width,
			height: frameSize.height
		)
	}

	private func constrainFrameToVisibleScreen(_ frame: NSRect, for window: NSWindow) -> NSRect {
		guard let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first else {
			return frame
		}

		let visibleFrame = screen.visibleFrame
		var constrained = frame
		if constrained.width <= visibleFrame.width {
			constrained.origin.x = min(
				max(constrained.minX, visibleFrame.minX),
				visibleFrame.maxX - constrained.width
			)
		} else {
			constrained.origin.x = visibleFrame.minX
		}

		if constrained.height <= visibleFrame.height {
			constrained.origin.y = min(
				max(constrained.minY, visibleFrame.minY),
				visibleFrame.maxY - constrained.height
			)
		} else {
			constrained.origin.y = visibleFrame.minY
		}
		return constrained
	}

	private func makeVisible(_ window: NSWindow) {
		window.alphaValue = 1
		window.ignoresMouseEvents = false
		window.hasShadow = true
	}

	private func makeTransparent(_ window: NSWindow) {
		window.alphaValue = 0
		window.ignoresMouseEvents = true
		window.hasShadow = false
	}

	private func sleep(
		for delayRange: TypingDelayRange,
		rhythm: TypingRhythm,
		after previousCharacter: Character?
	) async throws {
		let baseDelay = Double.random(in: delayRange.min...delayRange.max)
		let multiplier = rhythm == .natural ? naturalDelayMultiplier(after: previousCharacter) : 1
		let delay = min(TypingDelay.maxDelay, baseDelay * multiplier)
		try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
	}

	private func naturalDelayMultiplier(after character: Character?) -> Double {
		guard let character else {
			return 1
		}
		let text = String(character)
		if text == "\n" || text == "\r" {
			return Double.random(in: 3...4.5)
		}
		if ".!?".contains(text) {
			return Double.random(in: 2.6...4)
		}
		if ",;:".contains(text) {
			return Double.random(in: 1.8...2.7)
		}
		if text.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
			return Double.random(in: 1.25...1.9)
		}
		return Double.random(in: 0.85...1.2)
	}

	private func sendKey(_ key: NativeTypingKey) throws {
		guard let window else {
			throw WBError.message("native typing window is not attached")
		}
		let down = try event(type: .keyDown, key: key, window: window)
		let up = try event(type: .keyUp, key: key, window: window)
		window.sendEvent(down)
		window.sendEvent(up)
		BrowserApplicationHost.pumpEvents(until: Date().addingTimeInterval(0.003))
	}

	private func event(type: NSEvent.EventType, key: NativeTypingKey, window: NSWindow) throws
		-> NSEvent
	{
		guard
			let event = NSEvent.keyEvent(
				with: type,
				location: .zero,
				modifierFlags: key.modifiers,
				timestamp: ProcessInfo.processInfo.systemUptime,
				windowNumber: window.windowNumber,
				context: nil,
				characters: key.characters,
				charactersIgnoringModifiers: key.charactersIgnoringModifiers,
				isARepeat: false,
				keyCode: key.keyCode
			)
		else {
			throw WBError.message("could not create native key event")
		}
		return event
	}
}

@available(macOS 26.0, *)
@MainActor
private struct BrowserWindowView: View {
	let page: WebPage
	let navigationCallbacks: BrowserWindowNavigationCallbacks

	@State private var address = ""

	var body: some View {
		VStack(spacing: 0) {
			HStack(spacing: 8) {
				Button(action: goBack) {
					Label("Back", systemImage: "chevron.left")
						.labelStyle(.iconOnly)
				}
				.disabled(page.backForwardList.backList.isEmpty)
				.help("Back")

				Button(action: goForward) {
					Label("Forward", systemImage: "chevron.right")
						.labelStyle(.iconOnly)
				}
				.disabled(page.backForwardList.forwardList.isEmpty)
				.help("Forward")

				Button(action: reload) {
					Label("Reload", systemImage: "arrow.clockwise")
						.labelStyle(.iconOnly)
				}
				.disabled(page.url == nil)
				.help("Reload")

				TextField("URL", text: $address)
					.textFieldStyle(.roundedBorder)
					.onSubmit(openAddress)
			}
			.controlSize(.small)
			.padding(.horizontal, 10)
			.padding(.vertical, 8)

			ProgressView(value: page.estimatedProgress)
				.progressViewStyle(.linear)
				.frame(height: 2)
				.opacity(page.isLoading ? 1 : 0)

			Divider()

			WebView(page)
				.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
		.frame(
			minWidth: BrowserWindowMetrics.minimumSize.width,
			minHeight: BrowserWindowMetrics.minimumSize.height
		)
		.onAppear {
			syncAddress()
		}
		.onChange(of: page.url) { _, _ in
			syncAddress()
		}
	}

	private func syncAddress() {
		address = page.url?.absoluteString ?? ""
	}

	private func goBack() {
		guard let item = page.backForwardList.backList.last else {
			return
		}

		let generation = navigationCallbacks.started()
		Task { @MainActor in
			defer {
				navigationCallbacks.completed(generation)
			}
			do {
				for try await _ in page.load(item) {}
			} catch {}
		}
	}

	private func goForward() {
		guard let item = page.backForwardList.forwardList.first else {
			return
		}

		let generation = navigationCallbacks.started()
		Task { @MainActor in
			defer {
				navigationCallbacks.completed(generation)
			}
			do {
				for try await _ in page.load(item) {}
			} catch {}
		}
	}

	private func reload() {
		let generation = navigationCallbacks.started()
		Task { @MainActor in
			defer {
				navigationCallbacks.completed(generation)
			}
			do {
				for try await _ in page.reload(fromOrigin: false) {}
			} catch {}
		}
	}

	private func openAddress() {
		let rawAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !rawAddress.isEmpty else {
			return
		}

		let normalizedAddress = rawAddress.contains("://") ? rawAddress : "https://\(rawAddress)"
		guard let url = URL(string: normalizedAddress) else {
			syncAddress()
			return
		}

		var request = URLRequest(url: url)
		request.attribution = .user

		let generation = navigationCallbacks.started()
		Task { @MainActor in
			defer {
				navigationCallbacks.completed(generation)
			}
			do {
				for try await _ in page.load(request) {}
			} catch {}
		}
	}
}

private struct NativeTypingKey {
	let characters: String
	let charactersIgnoringModifiers: String
	let keyCode: UInt16
	let modifiers: NSEvent.ModifierFlags

	static let backspace = NativeTypingKey(
		characters: "\u{7F}",
		charactersIgnoringModifiers: "\u{7F}",
		keyCode: 51,
		modifiers: []
	)

	static func character(_ character: String) -> NativeTypingKey {
		let normalized = character == "\n" ? "\r" : character
		return NativeTypingKey(
			characters: normalized,
			charactersIgnoringModifiers: normalized,
			keyCode: keyCode(for: character),
			modifiers: []
		)
	}

	private static func keyCode(for character: String) -> UInt16 {
		if character == "\n" {
			return 36
		}
		return keyCodes[character.lowercased()] ?? 0
	}

	private static let keyCodes: [String: UInt16] = [
		"a": 0,
		"s": 1,
		"d": 2,
		"f": 3,
		"h": 4,
		"g": 5,
		"z": 6,
		"x": 7,
		"c": 8,
		"v": 9,
		"b": 11,
		"q": 12,
		"w": 13,
		"e": 14,
		"r": 15,
		"y": 16,
		"t": 17,
		"1": 18,
		"2": 19,
		"3": 20,
		"4": 21,
		"6": 22,
		"5": 23,
		"=": 24,
		"9": 25,
		"7": 26,
		"-": 27,
		"8": 28,
		"0": 29,
		"]": 30,
		"o": 31,
		"u": 32,
		"[": 33,
		"i": 34,
		"p": 35,
		"l": 37,
		"j": 38,
		"'": 39,
		"k": 40,
		";": 41,
		"\\": 42,
		",": 43,
		"/": 44,
		"n": 45,
		"m": 46,
		".": 47,
		"`": 50,
		" ": 49,
		"\t": 48,
	]
}
