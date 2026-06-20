import AppKit
import CoreTransferable
import Foundation
import Dispatch
import Darwin
import WebKit

@available(macOS 26.0, *)
@MainActor
final class BrowserManager: @unchecked Sendable {
    private let sessionStore: SessionStore
    private var browsers: [String: BrowserInstance] = [:]

    init(config: WBConfig = .current()) {
        sessionStore = SessionStore(directory: config.sessionsDirectory)
    }

    func handleWireData(_ data: Data) async -> Data {
        do {
            let request = try JSONDecoder().decode(WireRequest.self, from: data)
            daemonLog("request command=\(request.command.rawValue) browser=\(request.browser ?? "-")")
            let response = try await handle(request)
            daemonLog("response command=\(request.command.rawValue) ok=\(response.ok) browser=\(response.browser ?? "-")")
            return try WireCodec.encode(response)
        } catch {
            daemonLog("request failed error=\(error.localizedDescription)")
            return WireCodec.encodeError(error.localizedDescription)
        }
    }

    private func handle(_ request: WireRequest) async throws -> WireResponse {
        switch request.command {
        case .ping:
            return .success(message: "ok")

        case .browserCreate:
            let browser = createBrowser()
            scheduleAutosave(browser, reason: "create")
            daemonLog("browser created id=\(browser.id)")
            return .success(browser: browser.id)

        case .browserList:
            return .success(browsers: try summaries())

        case .browserClose:
            let id = try request.requiredBrowserID()
            let removedBrowser = browsers.removeValue(forKey: id)
            removedBrowser?.closeWindow()
            let removedActive = removedBrowser != nil
            let removedDump = sessionStore.exists(id)
            if removedDump {
                try sessionStore.delete(id)
            }

            guard removedActive || removedDump else {
                throw unknownBrowser(id)
            }
            daemonLog("browser closed id=\(id) removedActive=\(removedActive) removedDump=\(removedDump)")
            return .success(browser: id, message: "closed")

        case .browserDump:
            let id = try request.requiredBrowserID()
            if let browser = browsers[id] {
                _ = try await dump(browser)
                return .success(browser: id, message: "dumped")
            }

            guard sessionStore.exists(id) else {
                throw unknownBrowser(id)
            }
            _ = try sessionStore.load(id)
            return .success(browser: id, message: "already dumped")

        case .browserShow:
            let browser = try await showBrowser(request.browser)
            return .success(browser: browser.id)

        case .browserHide:
            let browser = try await requireBrowser(request.browser)
            browser.hideWindow()
            return .success(browser: browser.id)

        case .open:
            let url = try request.requiredURL()
            let browserState = try browserForOpen(id: request.browser)
            let page: PageSnapshot
            do {
                page = try await browserState.browser.open(url)
            } catch {
                daemonLog(
                    "open failed browser=\(browserState.browser.id) createdForOpen=\(browserState.createdForOpen) " +
                    "error=\(error.localizedDescription)"
                )
                let failedPage = await browserState.browser.bestEffortSnapshot(fallbackURL: url.absoluteString)
                scheduleAutosave(browserState.browser, reason: "open-failed")
                return .failure(
                    error.localizedDescription,
                    browser: browserState.browser.id,
                    page: failedPage,
                    url: url.absoluteString
                )
            }
            scheduleAutosave(browserState.browser, reason: "open")
            return .success(browser: browserState.browser.id, page: page)

        case .page:
            let browser = try await requireBrowser(request.browser)
            let page = try await browser.snapshot()
            return .success(browser: browser.id, page: page)

        case .click:
            let browser = try await requireBrowser(request.browser)
            let action = try request.requiredAction()
            let result = try await browser.click(action)
            scheduleAutosave(browser, reason: "click")
            return .success(browser: browser.id, page: result.page, message: result.message)

        case .fill:
            let browser = try await requireBrowser(request.browser)
            let action = try request.requiredAction()
            let value = try request.requiredValue()
            let result = try await browser.fill(action, value: value)
            scheduleAutosave(browser, reason: "fill")
            return .success(browser: browser.id, page: result.page, message: result.message)

        case .submit:
            let browser = try await requireBrowser(request.browser)
            let action = try request.requiredAction()
            let result = try await browser.submit(action)
            scheduleAutosave(browser, reason: "submit")
            return .success(browser: browser.id, page: result.page, message: result.message)

        case .eval:
            let browser = try await requireBrowser(request.browser)
            let script = try request.requiredScript()
            let value: String
            if request.functionBody == true {
                value = try await browser.callFunctionBody(script)
            } else {
                value = try await browser.evaluateExpression(script)
            }
            scheduleAutosave(browser, reason: "eval")
            return .success(browser: browser.id, value: value)

        case .screenshot:
            let browser = try await requireBrowser(request.browser)
            let path = try request.requiredDestinationPath()
            let result = try await browser.screenshot(to: path)
            return .success(browser: browser.id, message: "saved \(result.path)")

        case .coordinate:
            let browser = try await requireBrowser(request.browser)
            let action = try BrowserCoordinateAction(request: request)
            let result = try await browser.coordinateAction(action)
            scheduleAutosave(browser, reason: action.name)
            return .success(browser: browser.id, page: result.page, message: result.message)

        case .daemonStop:
            daemonLog("daemon stop requested")
            try await dumpAllSessions()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.2) {
                daemonLog("daemon exiting after stop request")
                Darwin.exit(0)
            }
            return .success(message: "stopping daemon")
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

    private func createBrowser(id requestedID: String? = nil, createdAt: Date = Date(), updatedAt: Date = Date()) -> BrowserInstance {
        let id = requestedID ?? nextBrowserID()

        let browser = BrowserInstance(id: id, createdAt: createdAt, updatedAt: updatedAt)
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
        try sessionStore.save(dump)
        daemonLog("dump saved id=\(browser.id) url=\(dump.url ?? "-")")
        return dump
    }

    private func scheduleAutosave(_ browser: BrowserInstance, reason: String) {
        Task { @MainActor in
            await autosave(browser, reason: reason)
        }
    }

    private func autosave(_ browser: BrowserInstance, reason: String) async {
        daemonLog("autosave start id=\(browser.id) reason=\(reason)")
        do {
            _ = try await dump(browser)
            daemonLog("autosave complete id=\(browser.id) reason=\(reason)")
        } catch {
            daemonLog("autosave failed id=\(browser.id) reason=\(reason) error=\(error.localizedDescription)")
        }
    }

    private func unknownBrowser(_ id: String) -> WBError {
        let activeIDs = browsers.keys.sorted().joined(separator: ",").nilIfEmpty ?? "-"
        let dumpedIDs = sessionStore.browserIDs().joined(separator: ",").nilIfEmpty ?? "-"
        daemonLog(
            "unknown browser id=\(id) active=\(activeIDs) dumped=\(dumpedIDs) " +
            "sessions=\(sessionStore.directory.path)"
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

        daemonLog("resume start id=\(dump.browser) showingWindow=\(showingWindow) url=\(dump.url ?? dump.snapshot?.url ?? "-")")
        let browser = createBrowser(
            id: dump.browser,
            createdAt: dump.createdDate,
            updatedAt: dump.updatedDate
        )

        if showingWindow {
            browser.showWindow()
        }

        let resumeURL = dump.url ?? dump.snapshot.flatMap { $0.url }
        guard let rawURL = resumeURL.nilIfEmpty,
              let url = URL(string: rawURL) else {
            daemonLog("resume has no URL id=\(dump.browser)")
            return browser
        }

        do {
            _ = try await browser.open(url)
            scheduleAutosave(browser, reason: showingWindow ? "show-resume" : "resume")
            daemonLog("resume loaded id=\(dump.browser) url=\(rawURL)")
            return browser
        } catch {
            daemonLog("resume failed id=\(dump.browser) error=\(error.localizedDescription)")
            browser.closeWindow()
            browsers.removeValue(forKey: dump.browser)
            throw error
        }
    }
}

@available(macOS 26.0, *)
@MainActor
private final class BrowserInstance {
    let id: String

    private let page = WebPage()
    private var actions: [BrowserAction] = []
    private var windowController: BrowserWindowController?
    private let createdAt: Date
    private var updatedAt: Date

    init(id: String, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
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
            title: page.title,
            url: page.url?.absoluteString ?? fallbackURL,
            loading: page.isLoading,
            progress: page.estimatedProgress,
            imageCount: stats?.imageCount,
            images: stats?.images ?? [],
            htmlBytes: stats?.htmlBytes,
            text: visibleText,
            actions: currentActions
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

    func markdownText(maxLength: Int = 12000) async throws -> String {
        try await callString(Self.markdownTextScript, arguments: ["maxLength": maxLength])
    }

    func pageStats() async throws -> PageDOMStats {
        let json = try await callString(Self.pageStatsScript)
        let data = Data(json.utf8)
        return try JSONDecoder().decode(PageDOMStats.self, from: data)
    }

    func viewportSize() async throws -> CGSize {
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
        let pngData = try await page.exported(as: .image(
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
        daemonLog("browser dump snapshot start id=\(id) url=\(page.url?.absoluteString ?? "-")")
        let currentSnapshot: PageSnapshot?
        if page.url == nil {
            currentSnapshot = nil
        } else {
            currentSnapshot = try? await snapshot()
        }
        let snapshotURL = currentSnapshot.flatMap { $0.url }

        let dump = BrowserDump(
            schemaVersion: 1,
            browser: id,
            title: (currentSnapshot?.title ?? page.title).nilIfEmpty,
            url: snapshotURL ?? page.url?.absoluteString,
            loading: currentSnapshot?.loading ?? page.isLoading,
            progress: currentSnapshot?.progress ?? page.estimatedProgress,
            actions: currentSnapshot?.actions.count ?? actions.count,
            createdAt: createdAt.iso8601String,
            updatedAt: updatedAt.iso8601String,
            dumpedAt: Date().iso8601String,
            snapshot: currentSnapshot
        )
        daemonLog("browser dump snapshot complete id=\(id) url=\(dump.url ?? "-") snapshot=\(currentSnapshot != nil)")
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
           let action = actions.first(where: { $0.index == index }) {
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

    private static let listActionsScript = """
    const candidates = Array.from(document.querySelectorAll([
      "a[href]",
      "button",
      "input",
      "textarea",
      "select",
      "form",
      "summary",
      "label",
      "[role='button']",
      "[role='link']",
      "[onclick]",
      "[tabindex]"
    ].join(",")));

    function isVisible(el) {
      const style = window.getComputedStyle(el);
      const rect = el.getBoundingClientRect();
      if (!style || style.visibility === "hidden" || style.display === "none") {
        return false;
      }
      if (el.tagName.toLowerCase() === "input" && (el.type || "").toLowerCase() === "hidden") {
        return false;
      }
      return rect.width > 0 && rect.height > 0;
    }

    function readableName(el) {
      const text = (el.innerText || el.textContent || "").replace(/\\s+/g, " ").trim();
      return (
        el.getAttribute("aria-label") ||
        el.getAttribute("title") ||
        el.getAttribute("alt") ||
        el.getAttribute("placeholder") ||
        text ||
        el.getAttribute("value") ||
        el.getAttribute("name") ||
        el.href ||
        el.action ||
        ""
      );
    }

    function selectorFor(el) {
      const cssEscape = window.CSS && CSS.escape ? CSS.escape : (value) => String(value).replace(/[^a-zA-Z0-9_-]/g, "\\\\$&");
      if (el.id) {
        return "#" + cssEscape(el.id);
      }

      const parts = [];
      let current = el;
      while (current && current.nodeType === Node.ELEMENT_NODE && parts.length < 5) {
        let part = current.tagName.toLowerCase();
        if (current.classList.length > 0) {
          part += "." + Array.from(current.classList).slice(0, 2).map(cssEscape).join(".");
        }
        const parent = current.parentElement;
        if (parent) {
          const siblings = Array.from(parent.children).filter((child) => child.tagName === current.tagName);
          if (siblings.length > 1) {
            part += `:nth-of-type(${siblings.indexOf(current) + 1})`;
          }
        }
        parts.unshift(part);
        current = parent;
      }
      return parts.join(" > ");
    }

    function kindFor(el) {
      const tag = el.tagName.toLowerCase();
      const type = (el.getAttribute("type") || "").toLowerCase();
      const role = (el.getAttribute("role") || "").toLowerCase();

      if (tag === "textarea" || el.isContentEditable) return "fill";
      if (tag === "select") return "selector";
      if (tag === "form") return "form";
      if (tag === "a" || role === "link") return "link";
      if (tag === "input") {
        if (["text", "search", "email", "url", "tel", "password", "number"].includes(type || "text")) {
          return "fill";
        }
        if (["checkbox", "radio"].includes(type)) {
          return "toggle";
        }
        return "button";
      }
      return "button";
    }

    const now = Date.now().toString(36);
    const actions = candidates
      .filter(isVisible)
      .slice(0, 100)
      .map((el, index) => {
        const id = `wkcli-${now}-${index}`;
        el.setAttribute("data-wkcli-id", id);
        const tag = el.tagName.toLowerCase();
        return {
          index: index + 1,
          id,
          kind: kindFor(el),
          tag,
          type: (el.getAttribute("type") || "").toLowerCase(),
          text: readableName(el).slice(0, 160),
          href: el.href || el.action || "",
          disabled: Boolean(el.disabled || el.getAttribute("aria-disabled") === "true"),
          selector: selectorFor(el)
        };
      });

    return JSON.stringify(actions);
    """

    private static let findElementScript = """
    function wkcliFind(id) {
      return Array.from(document.querySelectorAll("[data-wkcli-id]"))
        .find((el) => el.getAttribute("data-wkcli-id") === id);
    }
    """

    private static let clickScript = findElementScript + """

    const el = wkcliFind(id);
    if (!el) return "not found; run page again";
    if (el.disabled || el.getAttribute("aria-disabled") === "true") return "element is disabled";
    el.scrollIntoView({ block: "center", inline: "center" });
    el.focus({ preventScroll: true });
    el.click();
    return "clicked " + (el.innerText || el.value || el.href || el.tagName).toString().trim().slice(0, 120);
    """

    private static let fillScript = findElementScript + """

    const el = wkcliFind(id);
    if (!el) return "not found; run page again";
    el.scrollIntoView({ block: "center", inline: "center" });
    el.focus({ preventScroll: true });

    if (el.isContentEditable) {
      el.textContent = value;
    } else if ("value" in el) {
      el.value = value;
    } else {
      return "element cannot be filled";
    }

    el.dispatchEvent(new Event("input", { bubbles: true }));
    el.dispatchEvent(new Event("change", { bubbles: true }));
    return "filled";
    """

    private static let submitScript = findElementScript + """

    const el = wkcliFind(id);
    if (!el) return "not found; run page again";

    const form = el.tagName.toLowerCase() === "form" ? el : (el.form || el.closest("form"));
    if (!form) {
      el.click();
      return "no form found; clicked element instead";
    }

    const type = (el.getAttribute("type") || "").toLowerCase();
    const submitter = ["button", "input"].includes(el.tagName.toLowerCase()) && type === "submit" ? el : undefined;
    if (form.requestSubmit) {
      if (submitter) {
        form.requestSubmit(submitter);
      } else {
        form.requestSubmit();
      }
    } else {
      form.submit();
    }
    return "submitted form";
    """

    private static let pageStatsScript = """
    const html = document.documentElement ? document.documentElement.outerHTML : "";
    const htmlBytes = typeof TextEncoder === "function"
      ? new TextEncoder().encode(html).length
      : new Blob([html]).size;
    const imageElements = Array.from(document.querySelectorAll("img"));
    const images = imageElements
      .map((img, index) => ({
        index: index + 1,
        url: String(img.currentSrc || img.src || img.getAttribute("src") || "").trim(),
        alt: String(img.getAttribute("alt") || "").trim()
      }))
      .filter((image) => image.url)
      .slice(0, 250);
    return JSON.stringify({
      imageCount: imageElements.length,
      images,
      htmlBytes
    });
    """

    private static let viewportSizeScript = """
    const root = document.documentElement;
    const body = document.body;
    const width = Math.max(
      1,
      Math.floor(window.innerWidth || root?.clientWidth || body?.clientWidth || 1024)
    );
    const height = Math.max(
      1,
      Math.floor(window.innerHeight || root?.clientHeight || body?.clientHeight || 768)
    );
    return JSON.stringify({ width, height });
    """

    private static let coordinateActionScript = """
    const actionName = String(action || "");
    const clientX = Number(x);
    const clientY = Number(y);
    const scrollDeltaX = Number(deltaX || 0);
    const scrollDeltaY = Number(deltaY || 0);

    if (!Number.isFinite(clientX) || !Number.isFinite(clientY)) {
      return "coordinates must be finite numbers";
    }
    if (clientX < 0 || clientY < 0 || clientX >= window.innerWidth || clientY >= window.innerHeight) {
      return `coordinate x=${clientX},y=${clientY} is outside viewport width=${window.innerWidth} height=${window.innerHeight}`;
    }

    function targetAtPoint() {
      return document.elementFromPoint(clientX, clientY) || document.body || document.documentElement;
    }

    function targetName(el) {
      if (!el) return "page";
      const label = (
        el.getAttribute?.("aria-label") ||
        el.getAttribute?.("title") ||
        el.innerText ||
        el.textContent ||
        el.id ||
        el.tagName ||
        "element"
      ).toString().replace(/\\s+/g, " ").trim();
      return label.slice(0, 80) || (el.tagName || "element").toLowerCase();
    }

    function pointerEvent(type, target, extra = {}) {
      const init = {
        bubbles: true,
        cancelable: true,
        composed: true,
        view: window,
        clientX,
        clientY,
        screenX: window.screenX + clientX,
        screenY: window.screenY + clientY,
        button: 0,
        buttons: extra.buttons ?? 0,
        pointerId: 1,
        pointerType: "mouse",
        isPrimary: true,
        detail: extra.detail ?? 0
      };
      const EventClass = typeof PointerEvent === "function" ? PointerEvent : MouseEvent;
      return target.dispatchEvent(new EventClass(type, init));
    }

    function mouseEvent(type, target, extra = {}) {
      return target.dispatchEvent(new MouseEvent(type, {
        bubbles: true,
        cancelable: true,
        composed: true,
        view: window,
        clientX,
        clientY,
        screenX: window.screenX + clientX,
        screenY: window.screenY + clientY,
        button: 0,
        buttons: extra.buttons ?? 0,
        detail: extra.detail ?? 0
      }));
    }

    function focusIfPossible(target) {
      if (target && typeof target.focus === "function") {
        try { target.focus({ preventScroll: true }); } catch (_) { try { target.focus(); } catch (_) {} }
      }
    }

    function press(target) {
      window.__wbCoordinatePointer = { target, moved: false };
      focusIfPossible(target);
      pointerEvent("pointerdown", target, { buttons: 1 });
      mouseEvent("mousedown", target, { buttons: 1, detail: 1 });
    }

    function drag(target) {
      const state = window.__wbCoordinatePointer;
      const dispatchTarget = state?.target || target;
      if (state) state.moved = true;
      pointerEvent("pointermove", dispatchTarget, { buttons: 1 });
      mouseEvent("mousemove", dispatchTarget, { buttons: 1 });
    }

    function release(target) {
      const state = window.__wbCoordinatePointer;
      const dispatchTarget = state?.target || target;
      pointerEvent("pointerup", dispatchTarget, { buttons: 0 });
      mouseEvent("mouseup", dispatchTarget, { buttons: 0, detail: 1 });
      if (!state?.moved) {
        mouseEvent("click", dispatchTarget, { buttons: 0, detail: 1 });
      }
      window.__wbCoordinatePointer = null;
    }

    function nearestScrollable(start) {
      let el = start;
      while (el && el !== document.documentElement) {
        const style = window.getComputedStyle(el);
        const overflowX = style.overflowX || "";
        const overflowY = style.overflowY || "";
        const canScrollX = /(auto|scroll|overlay)/.test(overflowX) && el.scrollWidth > el.clientWidth;
        const canScrollY = /(auto|scroll|overlay)/.test(overflowY) && el.scrollHeight > el.clientHeight;
        if (canScrollX || canScrollY) {
          return el;
        }
        el = el.parentElement;
      }
      return document.scrollingElement || document.documentElement;
    }

    function scrollAt(target) {
      if (!Number.isFinite(scrollDeltaX) || !Number.isFinite(scrollDeltaY)) {
        return "scroll deltas must be finite numbers";
      }
      target.dispatchEvent(new WheelEvent("wheel", {
        bubbles: true,
        cancelable: true,
        composed: true,
        view: window,
        clientX,
        clientY,
        deltaX: scrollDeltaX,
        deltaY: scrollDeltaY,
        deltaMode: WheelEvent.DOM_DELTA_PIXEL
      }));
      const scroller = nearestScrollable(target);
      scroller.scrollBy({ left: scrollDeltaX, top: scrollDeltaY, behavior: "auto" });
      return `scrolled x=${clientX},y=${clientY} by deltaX=${scrollDeltaX},deltaY=${scrollDeltaY}`;
    }

    const target = targetAtPoint();
    if (!target) return "no element at coordinate";

    switch (actionName) {
    case "click":
      press(target);
      release(target);
      return `clicked ${targetName(target)} at x=${clientX},y=${clientY}`;
    case "press":
      press(target);
      return `pressed ${targetName(target)} at x=${clientX},y=${clientY}`;
    case "drag":
      drag(target);
      return `dragged ${targetName(target)} to x=${clientX},y=${clientY}`;
    case "release":
      release(target);
      return `released ${targetName(target)} at x=${clientX},y=${clientY}`;
    case "scroll":
      return scrollAt(target);
    default:
      return `unknown coordinate action ${actionName}`;
    }
    """

    private static let markdownTextScript = """
    const max = Number(maxLength) || 12000;
    const root = document.body;
    if (!root) return "";

    const blocks = new Set([
      "address", "article", "aside", "blockquote", "br", "dd", "details", "dialog",
      "div", "dl", "dt", "fieldset", "figcaption", "figure", "footer", "form",
      "h1", "h2", "h3", "h4", "h5", "h6", "header", "hr", "li", "main", "nav",
      "ol", "p", "pre", "section", "table", "tbody", "td", "tfoot", "th", "thead",
      "tr", "ul"
    ]);
    const skipped = new Set(["canvas", "head", "noscript", "script", "style", "svg", "template"]);
    let output = "";

    function hidden(el) {
      const style = window.getComputedStyle(el);
      const rect = el.getBoundingClientRect();
      return !style || style.visibility === "hidden" || style.display === "none" ||
        (rect.width === 0 && rect.height === 0);
    }

    function appendText(value) {
      if (output.length >= max) return;

      const normalized = String(value || "").replace(/\\s+/g, " ").trim();
      if (!normalized) return;

      if (output && !/[\\s\\n]$/.test(output) && !/^[\\s.,;:!?)]/.test(normalized)) {
        output += " ";
      }
      output += normalized;
    }

    function newline() {
      output = output.replace(/[ \\t]+$/g, "");
      if (!output || output.endsWith("\\n\\n")) return;
      output += output.endsWith("\\n") ? "\\n" : "\\n\\n";
    }

    function plainText(node) {
      if (node.nodeType === Node.TEXT_NODE) {
        return node.nodeValue || "";
      }
      if (node.nodeType !== Node.ELEMENT_NODE) {
        return "";
      }

      const el = node;
      const tag = el.tagName.toLowerCase();
      if (tag === "br") {
        return "\\n";
      }
      if (skipped.has(tag) || hidden(el)) {
        return "";
      }

      return Array.from(el.childNodes)
        .map(plainText)
        .join(" ")
        .replace(/\\s+/g, " ")
        .trim();
    }

    function escapeLabel(value) {
      return value.replace(/[\\[\\]]/g, "\\\\$&").trim();
    }

    function escapeURL(value) {
      return value.split(")").join("%29").trim();
    }

    function walk(node) {
      if (output.length >= max) return;

      if (node.nodeType === Node.TEXT_NODE) {
        appendText(node.nodeValue);
        return;
      }
      if (node.nodeType !== Node.ELEMENT_NODE) {
        return;
      }

      const el = node;
      const tag = el.tagName.toLowerCase();
      if (tag === "br") {
        output += "\\n";
        return;
      }
      if (skipped.has(tag) || hidden(el)) {
        return;
      }

      if (blocks.has(tag)) {
        newline();
      }

      if (tag === "a" && el.href) {
        const label = plainText(el);
        if (label) {
          appendText(`[${escapeLabel(label)}](${escapeURL(el.href)})`);
          return;
        }
      }

      for (const child of Array.from(el.childNodes)) {
        walk(child);
        if (output.length >= max) break;
      }

      if (blocks.has(tag)) {
        newline();
      }
    }

    walk(root);
    return output
      .replace(/[ \\t]+\\n/g, "\\n")
      .replace(/\\n{3,}/g, "\\n\\n")
      .trim()
      .slice(0, max);
    """

    private static let evalScript = """
    const value = eval(source);
    if (typeof value === "undefined") return "undefined";
    if (value === null) return "null";
    if (typeof value === "object") {
      try { return JSON.stringify(value, null, 2); } catch (error) {}
    }
    return String(value);
    """
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
                  ) else {
                throw WBError.message("failed to encode JPEG screenshot")
            }
            return jpegData
        }
    }
}

private struct InteractionResult {
    let message: String
    let page: PageSnapshot
}

private struct ScreenshotOutput {
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
