/// Provides a short-lived, non-interactive WebView attachment used only when a
/// headless page is render-suspended before screenshot capture.
import AppKit
import Foundation
import SwiftUI
import WebKit

@available(macOS 26.0, *)
@MainActor
final class ScreenshotRenderHost {
	private let page: WebPage
	private let viewport: CGSize
	private var window: NSWindow?

	init(page: WebPage, viewport: CGSize) {
		self.page = page
		self.viewport = CGSize(
			width: max(1, viewport.width),
			height: max(1, viewport.height)
		)
	}

	func withAttached<T>(_ operation: () async throws -> T) async throws -> T {
		attach()
		defer {
			close()
		}
		return try await operation()
	}

	private func attach() {
		BrowserApplicationHost.prepareForDaemon()
		let window = makeWindow()
		self.window = window
		window.orderFrontRegardless()
		window.contentView?.layoutSubtreeIfNeeded()
		window.displayIfNeeded()
		BrowserApplicationHost.pumpEvents(until: Date().addingTimeInterval(0.12))
	}

	private func close() {
		guard let window else {
			return
		}
		window.orderOut(nil)
		window.contentViewController = nil
		window.close()
		self.window = nil
		BrowserApplicationHost.demoteIfNoVisibleWindows()
	}

	private func makeWindow() -> NSWindow {
		let window = ScreenshotRenderPanel(
			contentRect: renderHostFrame(),
			styleMask: [.borderless, .nonactivatingPanel],
			backing: .buffered,
			defer: false
		)
		window.title = "wb screenshot render host"
		window.backgroundColor = .white
		window.isOpaque = true
		window.alphaValue = 1
		window.hasShadow = false
		window.ignoresMouseEvents = true
		window.isReleasedWhenClosed = false
		window.tabbingMode = .disallowed
		window.collectionBehavior = [
			.canJoinAllSpaces,
			.fullScreenAuxiliary,
			.ignoresCycle,
			.stationary,
			.transient,
		]
		window.contentViewController = NSHostingController(
			rootView: ScreenshotRenderHostView(page: page, viewport: viewport)
		)
		return window
	}

	private func renderHostFrame() -> NSRect {
		let screenFrame = (NSScreen.main ?? NSScreen.screens.first)?.frame ?? .zero
		let padding: CGFloat = 200
		return NSRect(
			x: screenFrame.minX - viewport.width - padding,
			y: screenFrame.minY - viewport.height - padding,
			width: viewport.width,
			height: viewport.height
		)
	}
}

@available(macOS 26.0, *)
@MainActor
private final class ScreenshotRenderPanel: NSPanel {
	override var canBecomeKey: Bool {
		false
	}

	override var canBecomeMain: Bool {
		false
	}
}

@available(macOS 26.0, *)
@MainActor
private struct ScreenshotRenderHostView: View {
	let page: WebPage
	let viewport: CGSize

	var body: some View {
		WebView(page)
			.frame(width: viewport.width, height: viewport.height)
	}
}
