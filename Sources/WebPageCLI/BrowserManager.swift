import Foundation
import Dispatch
import Darwin
import WebKit

@available(macOS 26.0, *)
@MainActor
final class BrowserManager: @unchecked Sendable {
    private var browsers: [String: BrowserInstance] = [:]
    private var nextID = 1000

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
            return .success(browsers: summaries())

        case .browserClose:
            let id = try request.requiredBrowserID()
            guard browsers.removeValue(forKey: id) != nil else {
                throw WPError.message("unknown browser \(id)")
            }
            return .success(browser: id, message: "closed")

        case .open:
            let browser = try browserOrCreate(id: request.browser)
            let url = try request.requiredURL()
            let page = try await browser.open(url)
            return .success(browser: browser.id, page: page)

        case .page:
            let browser = try requireBrowser(request.browser)
            let page = try await browser.snapshot()
            return .success(browser: browser.id, page: page)

        case .click:
            let browser = try requireBrowser(request.browser)
            let index = try request.requiredIndex()
            let result = try await browser.click(index)
            return .success(browser: browser.id, page: result.page, message: result.message)

        case .fill:
            let browser = try requireBrowser(request.browser)
            let index = try request.requiredIndex()
            let value = try request.requiredValue()
            let result = try await browser.fill(index, value: value)
            return .success(browser: browser.id, page: result.page, message: result.message)

        case .submit:
            let browser = try requireBrowser(request.browser)
            let index = try request.requiredIndex()
            let result = try await browser.submit(index)
            return .success(browser: browser.id, page: result.page, message: result.message)

        case .eval:
            let browser = try requireBrowser(request.browser)
            let script = try request.requiredScript()
            let value = try await browser.evaluateExpression(script)
            return .success(browser: browser.id, value: value)

        case .js:
            let browser = try requireBrowser(request.browser)
            let script = try request.requiredScript()
            let value = try await browser.callFunctionBody(script)
            return .success(browser: browser.id, value: value)

        case .text:
            let browser = try requireBrowser(request.browser)
            let text = try await browser.text(selector: request.selector)
            return .success(browser: browser.id, text: text)

        case .html:
            let browser = try requireBrowser(request.browser)
            let html = try await browser.html(selector: request.selector)
            return .success(browser: browser.id, html: html)

        case .daemonStop:
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.2) {
                Darwin.exit(0)
            }
            return .success(message: "stopping daemon")
        }
    }

    private func createBrowser() -> BrowserInstance {
        let id = String(nextID)
        nextID += 1

        let browser = BrowserInstance(id: id)
        browsers[id] = browser
        return browser
    }

    private func browserOrCreate(id: String?) throws -> BrowserInstance {
        if let id {
            return try requireBrowser(id)
        }
        return createBrowser()
    }

    private func requireBrowser(_ id: String?) throws -> BrowserInstance {
        let id = try id.nilIfEmpty.unwrap("missing browser id; pass --browser <id> or -b <id>")
        return try requireBrowser(id)
    }

    private func requireBrowser(_ id: String) throws -> BrowserInstance {
        guard let browser = browsers[id] else {
            throw WPError.message("unknown browser \(id)")
        }
        return browser
    }

    private func summaries() -> [BrowserSummary] {
        browsers.values
            .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
            .map { $0.summary() }
    }
}

@available(macOS 26.0, *)
@MainActor
private final class BrowserInstance {
    let id: String

    private let page = WebPage()
    private var actions: [BrowserAction] = []
    private let createdAt = Date()
    private var updatedAt = Date()

    init(id: String) {
        self.id = id
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
        let visibleText = try? await text(selector: nil, maxLength: 6000)
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

    func summary() -> BrowserSummary {
        BrowserSummary(
            browser: id,
            title: page.title.nilIfEmpty,
            url: page.url?.absoluteString,
            loading: page.isLoading,
            progress: page.estimatedProgress,
            actions: actions.count,
            createdAt: createdAt.iso8601String,
            updatedAt: updatedAt.iso8601String
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
        try? await Task.sleep(nanoseconds: 250_000_000)

        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            if !page.isLoading {
                let readyState = try? await callString("return document.readyState;")
                if readyState == "interactive" || readyState == "complete" {
                    return
                }
            }

            try? await Task.sleep(nanoseconds: 250_000_000)
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

      if (tag === "textarea" || el.isContentEditable) return "fill";
      if (tag === "select") return "select";
      if (tag === "form") return "form";
      if (tag === "input") {
        if (["text", "search", "email", "url", "tel", "password", "number"].includes(type || "text")) {
          return "fill";
        }
        return "click";
      }
      return "click";
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
