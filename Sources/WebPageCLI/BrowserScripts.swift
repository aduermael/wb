/// Stores the JavaScript snippets injected into WebKit pages for action
/// discovery, interaction, DOM stats, viewport measurement, text extraction,
/// and evaluation.

@available(macOS 26.0, *)
extension BrowserInstance {
	static let listActionsScript = """
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
		  const fallbackEscape = (value) => String(value).replace(/[^a-zA-Z0-9_-]/g, "\\\\$&");
		  const cssEscape = window.CSS && CSS.escape ? CSS.escape : fallbackEscape;
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

	static let findElementScript = """
		function wkcliFind(id) {
		  return Array.from(document.querySelectorAll("[data-wkcli-id]"))
		    .find((el) => el.getAttribute("data-wkcli-id") === id);
		}
		"""

	static let clickScript =
		findElementScript + """

			const el = wkcliFind(id);
			if (!el) return "not found; run page again";
			if (el.disabled || el.getAttribute("aria-disabled") === "true") return "element is disabled";
			el.scrollIntoView({ block: "center", inline: "center" });
			el.focus({ preventScroll: true });
			el.click();
			return "clicked " + (el.innerText || el.value || el.href || el.tagName).toString().trim().slice(0, 120);
			"""

	static let fillScript =
		findElementScript + """

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

	static let submitScript =
		findElementScript + """

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

	static let pageStatsScript = """
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

	static let viewportSizeScript = """
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

	static let coordinateActionScript = """
		const actionName = String(action || "");
		const clientX = Number(x);
		const clientY = Number(y);
		const scrollDeltaX = Number(deltaX || 0);
		const scrollDeltaY = Number(deltaY || 0);

		if (!Number.isFinite(clientX) || !Number.isFinite(clientY)) {
		  return "coordinates must be finite numbers";
		}
		if (clientX < 0 || clientY < 0 || clientX >= window.innerWidth || clientY >= window.innerHeight) {
		  return `coordinate x=${clientX},y=${clientY} is outside viewport ` +
		    `width=${window.innerWidth} height=${window.innerHeight}`;
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

	static let markdownTextScript = """
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

	static let evalScript = """
		const value = eval(source);
		if (typeof value === "undefined") return "undefined";
		if (value === null) return "null";
		if (typeof value === "object") {
		  try { return JSON.stringify(value, null, 2); } catch (error) {}
		}
		return String(value);
		"""
}
