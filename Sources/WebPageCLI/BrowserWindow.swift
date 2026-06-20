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
        let hasVisibleWindow = application.windows.contains { $0.isVisible || $0.isMiniaturized }
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
        applicationMenu.addItem(NSMenuItem(
            title: "Hide \(appName)",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        ))
        applicationMenu.addItem(NSMenuItem(
            title: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        ))
        applicationMenu.items.last?.keyEquivalentModifierMask = [.command, .option]
        applicationMenu.addItem(NSMenuItem(
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

        let windowMenuItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        mainMenu.addItem(windowMenuItem)

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(
            title: "Close",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        ))
        windowMenu.addItem(NSMenuItem(
            title: "Minimize",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        ))
        windowMenu.addItem(NSMenuItem(
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
final class BrowserWindowController: NSObject, NSWindowDelegate {
    private let browserID: String
    private let page: WebPage
    private var window: NSWindow?
    private var isHiddenByCommand = false

    init(browserID: String, page: WebPage) {
        self.browserID = browserID
        self.page = page
    }

    var isVisible: Bool {
        guard let window else {
            return false
        }
        return window.isVisible || window.isMiniaturized
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
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        daemonLog(
            "window shown browser=\(browserID) visible=\(window.isVisible) " +
            "miniaturized=\(window.isMiniaturized) key=\(window.isKeyWindow) " +
            "main=\(window.isMainWindow) appActive=\(application.isActive) " +
            "panel=\(window is NSPanel)"
        )
    }

    func hide() {
        daemonLog("window hide requested browser=\(browserID)")
        isHiddenByCommand = true
        window?.orderOut(nil)
        BrowserApplicationHost.demoteIfNoVisibleWindows()
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
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 700),
            styleMask: [
                .titled,
                .closable,
                .miniaturizable,
                .resizable,
                .nonactivatingPanel,
            ],
            backing: .buffered,
            defer: false
        )
        window.title = "wb \(browserID)"
        window.minSize = NSSize(width: 420, height: 300)
        window.level = .floating
        window.collectionBehavior = Self.previewCollectionBehavior
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = false
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: BrowserWindowView(page: page)
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
            window.center()
            daemonLog("window positioned browser=\(browserID) fallback=center no-screen")
            return
        }

        let visibleFrame = screen.visibleFrame
        let width = min(max(420, window.frame.width), max(420, visibleFrame.width - 40))
        let height = min(max(300, window.frame.height), max(300, visibleFrame.height - 40))
        let frame = NSRect(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.midY - height / 2,
            width: width,
            height: height
        )
        window.setFrame(frame, display: false)
        daemonLog(
            "window positioned browser=\(browserID) frame=(\(rectDebugDescription(frame))) " +
            "screen=\(screen.localizedName)"
        )
    }
}

@available(macOS 26.0, *)
@MainActor
private struct BrowserWindowView: View {
    let page: WebPage

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
        .frame(minWidth: 420, minHeight: 300)
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

        Task { @MainActor in
            do {
                for try await _ in page.load(item) {}
            } catch {}
        }
    }

    private func goForward() {
        guard let item = page.backForwardList.forwardList.first else {
            return
        }

        Task { @MainActor in
            do {
                for try await _ in page.load(item) {}
            } catch {}
        }
    }

    private func reload() {
        Task { @MainActor in
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

        Task { @MainActor in
            do {
                for try await _ in page.load(request) {}
            } catch {}
        }
    }
}
