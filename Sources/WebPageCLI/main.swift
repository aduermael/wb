import Foundation
import Dispatch
import WebKit

@available(macOS 26.0, *)
@MainActor
private final class BrowserShell {
    private let page = WebPage()
    private var actions: [BrowserAction] = []

    func run() async {
        printIntro()

        while true {
            guard let line = await readPromptLine("webpage> ") else {
                print()
                break
            }

            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                continue
            }

            let shouldContinue = await handle(trimmed)
            if !shouldContinue {
                break
            }
        }
    }

    private func handle(_ line: String) async -> Bool {
        let parts = splitCommand(line)
        guard let rawCommand = parts.first else {
            return true
        }

        let command = rawCommand.lowercased()
        do {
            switch command {
            case "open", "go":
                guard parts.count >= 2, let url = makeURL(parts[1]) else {
                    print("usage: open <url>")
                    return true
                }
                try await load(url)

            case "reload":
                try await reload()

            case "stop":
                page.stopLoading()
                print("stopped")

            case "state":
                printState()

            case "actions", "ls":
                try await listActions()

            case "click":
                guard let index = commandIndex(parts) else {
                    print("usage: click <action-number>")
                    return true
                }
                try await click(index)

            case "fill":
                guard let index = commandIndex(parts), parts.count >= 3 else {
                    print("usage: fill <action-number> <text>")
                    return true
                }
                let value = parts.dropFirst(2).joined(separator: " ")
                try await fill(index, value: value)

            case "submit":
                guard let index = commandIndex(parts) else {
                    print("usage: submit <action-number>")
                    return true
                }
                try await submit(index)

            case "text":
                let selector = parts.dropFirst().joined(separator: " ").nilIfEmpty
                try await printText(selector: selector)

            case "html":
                let selector = parts.dropFirst().joined(separator: " ").nilIfEmpty
                try await printHTML(selector: selector)

            case "eval":
                let expression = tail(afterFirstTokenIn: line)
                guard !expression.isEmpty else {
                    print("usage: eval <javascript-expression>")
                    return true
                }
                try await evaluateExpression(expression)

            case "js":
                let functionBody = tail(afterFirstTokenIn: line)
                guard !functionBody.isEmpty else {
                    print("usage: js <javascript-function-body>")
                    print("example: js return document.title;")
                    return true
                }
                try await runJavaScript(functionBody)

            case "wait":
                await settle()
                printState()

            case "help", "?":
                printHelp()

            case "quit", "exit":
                return false

            default:
                print("unknown command: \(command)")
                print("type 'help' for commands")
            }
        } catch {
            print("error: \(error.localizedDescription)")
        }

        return true
    }

    private func load(_ url: URL) async throws {
        print("loading \(url.absoluteString)")
        actions.removeAll()

        var request = URLRequest(url: url)
        request.attribution = .user

        for try await event in page.load(request) {
            print("  \(eventLabel(event))")
        }

        printState()
    }

    private func reload() async throws {
        print("reloading")
        actions.removeAll()

        for try await event in page.reload() {
            print("  \(eventLabel(event))")
        }

        printState()
    }

    private func printState() {
        let url = page.url?.absoluteString ?? "(none)"
        let loading = page.isLoading ? "yes" : "no"
        let progress = Int((page.estimatedProgress * 100).rounded())

        print("title: \(page.title.nilIfEmpty ?? "(untitled)")")
        print("url: \(url)")
        print("loading: \(loading), progress: \(progress)%")
    }

    private func listActions() async throws {
        let json = try await callString(Self.listActionsScript)
        let data = Data(json.utf8)
        actions = try JSONDecoder().decode([BrowserAction].self, from: data)

        if actions.isEmpty {
            print("no obvious actions found")
            return
        }

        for action in actions {
            let disabled = action.disabled ? " disabled" : ""
            let href = action.href.nilIfEmpty.map { " -> \($0.clipped(to: 70))" } ?? ""
            let label = (action.text.nilIfEmpty ?? action.selector ?? "(no label)")
                .singleLine
                .clipped(to: 80)
            let number = String(action.index).leftPadded(to: 3)
            let kind = action.kind.rightPadded(to: 6)
            print("\(number). [\(kind)] \(label)\(href)\(disabled)")
        }
    }

    private func click(_ index: Int) async throws {
        let action = try action(at: index)
        let previousURL = page.url
        let result = try await callString(
            Self.clickScript,
            arguments: ["id": action.id]
        )
        print(result)
        await settle()
        if page.url != previousURL {
            actions.removeAll()
            printState()
        }
    }

    private func fill(_ index: Int, value: String) async throws {
        let action = try action(at: index)
        let result = try await callString(
            Self.fillScript,
            arguments: ["id": action.id, "value": value]
        )
        print(result)
    }

    private func submit(_ index: Int) async throws {
        let action = try action(at: index)
        let previousURL = page.url
        let result = try await callString(
            Self.submitScript,
            arguments: ["id": action.id]
        )
        print(result)
        await settle()
        if page.url != previousURL {
            actions.removeAll()
            printState()
        }
    }

    private func printText(selector: String?) async throws {
        let result = try await callString(
            Self.textScript,
            arguments: ["selector": selector as Any, "maxLength": 6000]
        )
        print(result)
    }

    private func printHTML(selector: String?) async throws {
        let result = try await callString(
            Self.htmlScript,
            arguments: ["selector": selector as Any, "maxLength": 6000]
        )
        print(result)
    }

    private func evaluateExpression(_ expression: String) async throws {
        let result = try await callString(
            Self.evalScript,
            arguments: ["source": expression]
        )
        print(result)
    }

    private func runJavaScript(_ functionBody: String) async throws {
        let result = try await page.callJavaScript(functionBody)
        print(printable(result))
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

    private func action(at index: Int) throws -> BrowserAction {
        guard let action = actions.first(where: { $0.index == index }) else {
            throw ShellError.message("unknown action \(index); run 'actions' again")
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

    private func eventLabel(_ event: WebPage.NavigationEvent) -> String {
        switch event {
        case .startedProvisionalNavigation:
            return "navigation started"
        case .receivedServerRedirect:
            return "server redirect"
        case .committed:
            return "content committed"
        case .finished:
            return "navigation finished"
        @unknown default:
            return "\(event)"
        }
    }

    private func printIntro() {
        print("WebPageCLI")
        print("Type 'open https://example.com', then 'actions'. Type 'help' for commands.")
    }

    private func printHelp() {
        print("""

        Commands:
          open <url>              Load a page
          state                   Show title, URL, and loading state
          actions                 List visible links, buttons, inputs, selects, forms
          click <n>               Click an action from the last actions list
          fill <n> <text>         Fill an input/textarea/contenteditable action
          submit <n>              Submit the nearest form for an action
          text [selector]         Print visible text for the page or CSS selector
          html [selector]         Print HTML for the page or CSS selector
          eval <expression>       Evaluate a JavaScript expression
          js <function-body>      Run a WebPage.callJavaScript function body
          reload                  Reload the current page
          stop                    Stop loading
          wait                    Wait briefly for loading to settle
          quit                    Exit

        Examples:
          open https://example.com
          actions
          click 1
          fill 3 "hello from WebPage"
          eval document.title
          js return document.querySelectorAll("a").length;
        """)
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
    if (!el) return "not found; run actions again";
    if (el.disabled || el.getAttribute("aria-disabled") === "true") return "element is disabled";
    el.scrollIntoView({ block: "center", inline: "center" });
    el.focus({ preventScroll: true });
    el.click();
    return "clicked " + (el.innerText || el.value || el.href || el.tagName).toString().trim().slice(0, 120);
    """

    private static let fillScript = findElementScript + """

    const el = wkcliFind(id);
    if (!el) return "not found; run actions again";
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
    if (!el) return "not found; run actions again";

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
    if (!root) return "selector not found";
    const text = (root.innerText || root.textContent || "")
      .replace(/\\n{3,}/g, "\\n\\n")
      .trim();
    return text.slice(0, maxLength);
    """

    private static let htmlScript = """
    const root = selector ? document.querySelector(selector) : document.documentElement;
    if (!root) return "selector not found";
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

private struct BrowserAction: Decodable {
    let index: Int
    let id: String
    let kind: String
    let tag: String
    let type: String
    let text: String
    let href: String
    let disabled: Bool
    let selector: String?
}

private enum ShellError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message):
            return message
        }
    }
}

private func readPromptLine(_ prompt: String) async -> String? {
    write(prompt)
    return await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            continuation.resume(returning: readLine())
        }
    }
}

private func write(_ string: String) {
    FileHandle.standardOutput.write(Data(string.utf8))
}

private func makeURL(_ rawValue: String) -> URL? {
    if rawValue.contains("://") {
        return URL(string: rawValue)
    }
    return URL(string: "https://\(rawValue)")
}

private func commandIndex(_ parts: [String]) -> Int? {
    guard parts.count >= 2 else {
        return nil
    }
    return Int(parts[1])
}

private func tail(afterFirstTokenIn line: String) -> String {
    guard let space = line.firstIndex(where: { $0 == " " || $0 == "\t" }) else {
        return ""
    }
    return String(line[space...]).trimmingCharacters(in: .whitespaces)
}

private func splitCommand(_ line: String) -> [String] {
    var parts: [String] = []
    var current = ""
    var quote: Character?
    var isEscaping = false

    for character in line {
        if isEscaping {
            current.append(character)
            isEscaping = false
            continue
        }

        if character == "\\" {
            isEscaping = true
            continue
        }

        if let activeQuote = quote {
            if character == activeQuote {
                quote = nil
            } else {
                current.append(character)
            }
            continue
        }

        if character == "\"" || character == "'" {
            quote = character
            continue
        }

        if character == " " || character == "\t" {
            if !current.isEmpty {
                parts.append(current)
                current.removeAll()
            }
            continue
        }

        current.append(character)
    }

    if !current.isEmpty {
        parts.append(current)
    }

    return parts
}

private func printable(_ value: Any?) -> String {
    guard let value else {
        return "nil"
    }

    if value is NSNull {
        return "null"
    }

    if let string = value as? String {
        return string
    }

    if let number = value as? NSNumber {
        return number.stringValue
    }

    if JSONSerialization.isValidJSONObject(value),
       let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted]),
       let string = String(data: data, encoding: .utf8) {
        return string
    }

    return String(describing: value)
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    func clipped(to maxLength: Int) -> String {
        guard count > maxLength else {
            return self
        }
        return String(prefix(maxLength - 1)) + "..."
    }

    var singleLine: String {
        components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    func leftPadded(to width: Int) -> String {
        guard count < width else {
            return self
        }
        return String(repeating: " ", count: width - count) + self
    }

    func rightPadded(to width: Int) -> String {
        guard count < width else {
            return self
        }
        return self + String(repeating: " ", count: width - count)
    }
}

@main
private struct WebPageCLI {
    static func main() async {
        guard #available(macOS 26.0, *) else {
            print("WebPageCLI requires macOS 26.0 or newer.")
            return
        }

        let shell = await MainActor.run {
            BrowserShell()
        }
        await shell.run()
    }
}
