import Foundation
import Dispatch
import Darwin
import WebKit

@available(macOS 26.0, *)
@MainActor
final class BrowserManager: @unchecked Sendable {
    private let sessionStore: SessionStore
    private var browsers: [String: BrowserInstance] = [:]

    init(config: WPConfig = .current()) {
        sessionStore = SessionStore(directory: config.sessionsDirectory)
    }

    func handleWireData(_ data: Data) async -> Data {
        do {
            let request = try JSONDecoder().decode(WireRequest.self, from: data)
            let response = try await handle(request)
            return try WireCodec.encode(response)
        } catch {
            return WireCodec.encodeError(error.localizedDescription)
        }
    }

    private func handle(_ request: WireRequest) async throws -> WireResponse {
        switch request.command {
        case .ping:
            return .success(message: "ok")

        case .browserCreate:
            let browser = createBrowser()
            return .success(browser: browser.id)

        case .browserList:
            return .success(browsers: try summaries())

        case .browserClose:
            let id = try request.requiredBrowserID()
            let removedActive = browsers.removeValue(forKey: id) != nil
            let removedDump = sessionStore.exists(id)
            if removedDump {
                try sessionStore.delete(id)
            }

            guard removedActive || removedDump else {
                throw WPError.message("unknown browser \(id)")
            }
            return .success(browser: id, message: "closed")

        case .browserDump:
            let id = try request.requiredBrowserID()
            if let browser = browsers[id] {
                _ = try await dump(browser)
                return .success(browser: id, message: "dumped")
            }

            guard sessionStore.exists(id) else {
                throw WPError.message("unknown browser \(id)")
            }
            _ = try sessionStore.load(id)
            return .success(browser: id, message: "already dumped")

        case .browserResume:
            let browser = try await requireBrowser(request.browser)
            let page = try await browser.snapshot()
            return .success(browser: browser.id, page: page, message: "resumed")

        case .open:
            let url = try request.requiredURL()
            let browserState = try browserForOpen(id: request.browser)
            let page: PageSnapshot
            do {
                page = try await browserState.browser.open(url)
            } catch {
                if browserState.removeOnFailure {
                    browsers.removeValue(forKey: browserState.browser.id)
                }
                throw error
            }
            return .success(browser: browserState.browser.id, page: page)

        case .page:
            let browser = try await requireBrowser(request.browser)
            let page = try await browser.snapshot()
            return .success(browser: browser.id, page: page)

        case .click:
            let browser = try await requireBrowser(request.browser)
            let index = try request.requiredIndex()
            let result = try await browser.click(index)
            return .success(browser: browser.id, page: result.page, message: result.message)

        case .fill:
            let browser = try await requireBrowser(request.browser)
            let index = try request.requiredIndex()
            let value = try request.requiredValue()
            let result = try await browser.fill(index, value: value)
            return .success(browser: browser.id, page: result.page, message: result.message)

        case .submit:
            let browser = try await requireBrowser(request.browser)
            let index = try request.requiredIndex()
            let result = try await browser.submit(index)
            return .success(browser: browser.id, page: result.page, message: result.message)

        case .eval:
            let browser = try await requireBrowser(request.browser)
            let script = try request.requiredScript()
            let value = try await browser.evaluateExpression(script)
            return .success(browser: browser.id, value: value)

        case .js:
            let browser = try await requireBrowser(request.browser)
            let script = try request.requiredScript()
            let value = try await browser.callFunctionBody(script)
            return .success(browser: browser.id, value: value)

        case .text:
            let browser = try await requireBrowser(request.browser)
            let text = try await browser.text(selector: request.selector)
            return .success(browser: browser.id, text: text)

        case .html:
            let browser = try await requireBrowser(request.browser)
            let html = try await browser.html(selector: request.selector)
            return .success(browser: browser.id, html: html)

        case .daemonStop:
            try await dumpAllSessions()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.2) {
                Darwin.exit(0)
            }
            return .success(message: "stopping daemon")
        }
    }

    func dumpAllSessions() async throws {
        for browser in Array(browsers.values) {
            guard browsers[browser.id] != nil else {
                continue
            }
            _ = try await dump(browser)
        }
    }

    private func createBrowser(id requestedID: String? = nil, createdAt: Date = Date(), updatedAt: Date = Date()) -> BrowserInstance {
        let id = requestedID ?? nextBrowserID()

        let browser = BrowserInstance(id: id, createdAt: createdAt, updatedAt: updatedAt)
        browsers[id] = browser
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

    private func browserForOpen(id: String?) throws -> (browser: BrowserInstance, removeOnFailure: Bool) {
        guard let id else {
            return (createBrowser(), true)
        }

        if let browser = browsers[id] {
            return (browser, false)
        }

        guard sessionStore.exists(id) else {
            throw WPError.message("unknown browser \(id)")
        }

        let dump = try sessionStore.load(id)
        let browser = createBrowser(
            id: dump.browser,
            createdAt: dump.createdDate,
            updatedAt: dump.updatedDate
        )
        return (browser, true)
    }

    private func requireBrowser(_ id: String?) async throws -> BrowserInstance {
        let id = try id.nilIfEmpty.unwrap("missing browser id; pass --browser <id> or -b <id>")
        return try await requireBrowser(id)
    }

    private func requireBrowser(_ id: String) async throws -> BrowserInstance {
        if let browser = browsers[id] {
            return browser
        }

        guard sessionStore.exists(id) else {
            throw WPError.message("unknown browser \(id)")
        }

        let dump = try sessionStore.load(id)
        return try await resume(dump)
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
        let dump = await browser.dump()
        try sessionStore.save(dump)
        return dump
    }

    private func resume(_ dump: BrowserDump) async throws -> BrowserInstance {
        if let browser = browsers[dump.browser] {
            return browser
        }

        let browser = createBrowser(
            id: dump.browser,
            createdAt: dump.createdDate,
            updatedAt: dump.updatedDate
        )

        let resumeURL = dump.url ?? dump.snapshot.flatMap { $0.url }
        guard let rawURL = resumeURL.nilIfEmpty,
              let url = URL(string: rawURL) else {
            return browser
        }

        do {
            _ = try await browser.open(url)
            return browser
        } catch {
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
    private let createdAt: Date
    private var updatedAt: Date

    init(id: String, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func open(_ url: URL) async throws -> PageSnapshot {
        actions.removeAll()

        var request = URLRequest(url: url)
        request.attribution = .user

        for try await _ in page.load(request) {}
        await settle()
        updatedAt = Date()

        return try await snapshot()
    }

    func snapshot() async throws -> PageSnapshot {
        let currentActions = try await refreshActions()
        let visibleText = try? await markdownText(maxLength: 6000)
        updatedAt = Date()

        return PageSnapshot(
            browser: id,
            title: page.title,
            url: page.url?.absoluteString,
            loading: page.isLoading,
            progress: page.estimatedProgress,
            text: visibleText,
            actions: currentActions
        )
    }

    func click(_ index: Int) async throws -> InteractionResult {
        try await ensureActions()
        let action = try action(at: index)
        let previousURL = page.url
        let message = try await callString(Self.clickScript, arguments: ["id": action.id])

        await settle()
        if page.url != previousURL {
            actions.removeAll()
        }

        return InteractionResult(message: message, page: try await snapshot())
    }

    func fill(_ index: Int, value: String) async throws -> InteractionResult {
        try await ensureActions()
        let action = try action(at: index)
        let message = try await callString(
            Self.fillScript,
            arguments: ["id": action.id, "value": value]
        )

        return InteractionResult(message: message, page: try await snapshot())
    }

    func submit(_ index: Int) async throws -> InteractionResult {
        try await ensureActions()
        let action = try action(at: index)
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

    func text(selector: String?, maxLength: Int = 12000) async throws -> String {
        try await callString(
            Self.textScript,
            arguments: ["selector": selector as Any, "maxLength": maxLength]
        )
    }

    func html(selector: String?, maxLength: Int = 12000) async throws -> String {
        try await callString(
            Self.htmlScript,
            arguments: ["selector": selector as Any, "maxLength": maxLength]
        )
    }

    func markdownText(maxLength: Int = 12000) async throws -> String {
        try await callString(Self.markdownTextScript, arguments: ["maxLength": maxLength])
    }

    func summary() -> BrowserSummary {
        BrowserSummary(
            browser: id,
            title: page.title.nilIfEmpty,
            url: page.url?.absoluteString,
            loading: page.isLoading,
            progress: page.estimatedProgress,
            actions: actions.count,
            createdAt: createdAt.iso8601String,
            updatedAt: updatedAt.iso8601String,
            dumped: nil,
            dumpedAt: nil
        )
    }

    func dump() async -> BrowserDump {
        let currentSnapshot: PageSnapshot?
        if page.url == nil {
            currentSnapshot = nil
        } else {
            currentSnapshot = try? await snapshot()
        }
        let snapshotURL = currentSnapshot.flatMap { $0.url }

        return BrowserDump(
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

    private func action(at index: Int) throws -> BrowserAction {
        guard let action = actions.first(where: { $0.index == index }) else {
            throw WPError.message("unknown action \(index); run 'wp -b \(id) page' again")
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

    private static let textScript = """
    const root = selector ? document.querySelector(selector) : document.body;
    if (!root) return "";
    const text = (root.innerText || root.textContent || "")
      .replace(/\\n{3,}/g, "\\n\\n")
      .trim();
    return text.slice(0, maxLength);
    """

    private static let htmlScript = """
    const root = selector ? document.querySelector(selector) : document.documentElement;
    if (!root) return "";
    return root.outerHTML.slice(0, maxLength);
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

private struct InteractionResult {
    let message: String
    let page: PageSnapshot
}
