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
		const performanceEntries = performance.getEntriesByType
		  ? performance.getEntriesByType("resource")
		  : [];
		const imageAltByURL = new Map(
		  Array.from(document.images || [])
		    .map((img) => [
		      String(img.currentSrc || img.src || img.getAttribute("src") || "").trim(),
		      String(img.getAttribute("alt") || "").trim()
		    ])
		    .filter(([url]) => url)
		);

		function typeFor(url, initiatorType) {
		  const initiator = String(initiatorType || "").toLowerCase();
		  const pathname = (() => {
		    try {
		      return new URL(url, document.baseURI).pathname.toLowerCase();
		    } catch {
		      return String(url || "").toLowerCase();
		    }
		  })();

		  if (initiator === "img" || initiator === "image" || /\\.(avif|gif|jpe?g|png|svg|webp)$/.test(pathname)) {
		    return "image";
		  }
		  if (initiator === "script" || /\\.(cjs|js|mjs)$/.test(pathname)) return "script";
		  if (initiator === "css" || initiator === "style" || /\\.css$/.test(pathname)) return "style";
		  if (initiator === "font" || /\\.(otf|ttf|woff2?)$/.test(pathname)) return "font";
		  if (initiator === "audio" || initiator === "video" || /\\.(m4a|m4v|mp3|mp4|ogg|webm)$/.test(pathname)) {
		    return "media";
		  }
		  if (/\\.json$/.test(pathname)) return "json";
		  if (initiator === "xmlhttprequest") return "xhr";
		  if (initiator === "fetch") return "fetch";
		  if (initiator === "iframe" || initiator === "frame") return "document";
		  if (initiator === "link") return "link";
		  return initiator || "other";
		}

		const seen = new Set();
		const resources = performanceEntries
		  .map((entry) => {
		    const url = String(entry.name || "").trim();
		    if (!url || seen.has(url)) return null;
		    seen.add(url);
		    const type = typeFor(url, entry.initiatorType);
		    return {
		      index: seen.size,
		      type,
		      url,
		      alt: type === "image" ? (imageAltByURL.get(url) || "") : ""
		    };
		  })
		  .filter(Boolean);

		for (const img of Array.from(document.images || [])) {
		  const url = String(img.currentSrc || img.src || img.getAttribute("src") || "").trim();
		  if (!url || seen.has(url) || !img.complete) continue;
		  seen.add(url);
		  resources.push({
		    index: seen.size,
		    type: "image",
		    url,
		    alt: String(img.getAttribute("alt") || "").trim()
		  });
		}

		const tracker = window.__wbResourceTracker || {};
		const trackedTotalResourceCount = Number(tracker.totalResourceCount || 0);
		const trackedCurrentResourceCount = Number(tracker.resourceCount || 0);
		const resourceCount = Math.max(
		  resources.length,
		  Number.isFinite(trackedTotalResourceCount) ? trackedTotalResourceCount : 0,
		  Number.isFinite(trackedCurrentResourceCount) ? trackedCurrentResourceCount : 0
		);

		return JSON.stringify({
		  resourceCount,
		  resources: resources.slice(0, 250),
		  htmlBytes
		});
		"""

	static let resourceTrackerScript = """
		(() => {
		  try {
		    performance.setResourceTimingBufferSize?.(5000);
		  } catch {}

		  const now = performance.now ? performance.now() : Date.now();
		  const initialResourceEntries = performance.getEntriesByType
		    ? performance.getEntriesByType("resource")
		    : [];
		  const currentResourceCount = initialResourceEntries.length;
		  const currentReadyState = document.readyState || "";
		  let tracker = window.__wbResourceTracker;

		  if (!tracker) {
		    tracker = {
		      pendingRequests: 0,
		      pendingResources: 0,
		      lastActivityAt: now - 1000,
		      resourceCount: currentResourceCount,
		      totalResourceCount: 0,
		      resourceEntryKeys: new Set(),
		      readyState: currentReadyState,
		      cssImageURLs: new Set(),
		      cssImageProbes: new Map(),
		      elements: new WeakMap(),
		      installed: false,
		      waitingForObserver: false
		    };
		    window.__wbResourceTracker = tracker;
		  }
		  if (!tracker.elements) {
		    tracker.elements = new WeakMap();
		  }
		  if (!tracker.resourceEntryKeys || typeof tracker.resourceEntryKeys.has !== "function") {
		    tracker.resourceEntryKeys = new Set();
		  }
		  if (!tracker.cssImageURLs || typeof tracker.cssImageURLs.has !== "function") {
		    tracker.cssImageURLs = new Set();
		  }
		  if (!tracker.cssImageProbes || typeof tracker.cssImageProbes.set !== "function") {
		    tracker.cssImageProbes = new Map();
		  }
		  if (!Number.isFinite(Number(tracker.totalResourceCount))) {
		    tracker.totalResourceCount = 0;
		  }
		  if (typeof tracker.readyState !== "string") {
		    tracker.readyState = "";
		  }
		  tracker.resourceCount = currentResourceCount;

		  const cssImageScanLimit = 160;
		  const cssImageMutationScanLimit = 80;
		  const cssImageProbeLimit = 32;
		  const cssImageURLLimit = 1000;
		  const dynamicResourceFallbackMS = 30000;

		  function currentTime() {
		    return performance.now ? performance.now() : Date.now();
		  }

		  function markActivity() {
		    tracker.lastActivityAt = currentTime();
		  }

		  function resourceEntryKey(entry) {
		    return [
		      String(entry.name || ""),
		      String(entry.initiatorType || ""),
		      Number(entry.startTime || 0).toFixed(3),
		      Number(entry.duration || 0).toFixed(3)
		    ].join("|");
		  }

		  function recordPerformanceResources(entries) {
		    let added = false;
		    for (const entry of Array.from(entries || [])) {
		      if (!entry || !String(entry.name || "").trim()) continue;
		      const key = resourceEntryKey(entry);
		      if (tracker.resourceEntryKeys.has(key)) continue;
		      tracker.resourceEntryKeys.add(key);
		      tracker.totalResourceCount = Math.max(0, Number(tracker.totalResourceCount) || 0) + 1;
		      added = true;
		    }
		    if (added) markActivity();
		    return added;
		  }

		  function noteReadyStateTransition() {
		    const readyState = document.readyState || "";
		    if (!readyState || readyState === tracker.readyState) return false;
		    tracker.readyState = readyState;
		    markActivity();
		    return true;
		  }

		  function visibleElement(el) {
		    if (!el || el.nodeType !== 1) return false;
		    try {
		      if (!document.documentElement || !document.documentElement.contains(el)) return false;
		      const style = window.getComputedStyle(el);
		      const rect = el.getBoundingClientRect();
		      if (!style || style.display === "none" || style.visibility === "hidden" || style.opacity === "0") {
		        return false;
		      }
		      return rect.width > 0 && rect.height > 0;
		    } catch {
		      return false;
		    }
		  }

		  function intersectsViewport(el) {
		    if (!visibleElement(el)) return false;
		    try {
		      const rect = el.getBoundingClientRect();
		      return rect.bottom >= 0 && rect.right >= 0 &&
		        rect.top <= (window.innerHeight || document.documentElement?.clientHeight || 0) &&
		        rect.left <= (window.innerWidth || document.documentElement?.clientWidth || 0);
		    } catch { return false; }
		  }

		  function nodeTouchesVisibleDOM(node) {
		    if (!node) return false;
		    if (node.nodeType === Node.TEXT_NODE) {
		      return String(node.textContent || "").trim().length > 0 && visibleElement(node.parentElement);
		    }
		    if (node.nodeType !== Node.ELEMENT_NODE) return false;
		    return visibleElement(node) || visibleElement(node.parentElement);
		  }

		  function mutationTouchesVisibleDOM(mutation) {
		    if (mutation.type === "characterData") {
		      return nodeTouchesVisibleDOM(mutation.target);
		    }
		    if (nodeTouchesVisibleDOM(mutation.target)) return true;
		    for (const node of Array.from(mutation.addedNodes || [])) {
		      if (nodeTouchesVisibleDOM(node)) return true;
		    }
		    return false;
		  }

		  function resourceURL(el) {
		    const tag = (el.tagName || "").toLowerCase();
		    if (tag === "img") return el.currentSrc || el.src || el.getAttribute("src") || el.srcset || "";
		    if (tag === "script" || tag === "iframe") return el.src || el.getAttribute("src") || "";
		    if (tag === "audio" || tag === "video") return el.src || el.getAttribute("src") || el.poster || "";
		    if (tag === "link") return el.href || el.getAttribute("href") || "";
		    return "";
		  }

		  function finishRequest() {
		    tracker.pendingRequests = Math.max(0, tracker.pendingRequests - 1);
		    markActivity();
		  }

		  function beginResource(el, url, fallbackAfterMS = 0) {
		    const prior = tracker.elements.get(el);
		    if (prior && prior.pending && prior.url === url) return;
		    if (prior && prior.pending) {
		      prior.url = url;
		      return;
		    }

		    const state = { pending: true, url, fallbackTimer: null };
		    tracker.elements.set(el, state);
		    tracker.pendingResources += 1;
		    markActivity();

		    const done = () => {
		      const current = tracker.elements.get(el);
		      if (!current || !current.pending) return;
		      current.pending = false;
		      if (current.fallbackTimer) {
		        clearTimeout(current.fallbackTimer);
		        current.fallbackTimer = null;
		      }
		      tracker.pendingResources = Math.max(0, tracker.pendingResources - 1);
		      markActivity();
		    };

		    el.addEventListener("load", done, { once: true });
		    el.addEventListener("error", done, { once: true });
		    if (fallbackAfterMS > 0) {
		      state.fallbackTimer = setTimeout(done, fallbackAfterMS);
		    }
		    if ((el.tagName || "").toLowerCase() === "img" && el.complete) {
		      done();
		    }
		  }

		  function normalizedURL(rawURL) {
		    const raw = String(rawURL || "").trim().replace(/^["']|["']$/g, "");
		    if (!raw || raw === "none") return "";
		    try {
		      const url = new URL(raw, document.baseURI);
		      if (["about:", "data:", "javascript:"].includes(url.protocol)) return "";
		      return url.href;
		    } catch {
		      return raw;
		    }
		  }

		  function cssImageURLs(style) {
		    const urls = [];
		    const properties = [
		      "background-image",
		      "border-image-source",
		      "list-style-image",
		      "cursor",
		      "mask-image",
		      "-webkit-mask-image"
		    ];
		    for (const property of properties) {
		      const value = String(style.getPropertyValue?.(property) || "");
		      const matcher = /url\\((?:"([^"]*)"|'([^']*)'|([^)]*))\\)/g;
		      let match = null;
		      while ((match = matcher.exec(value)) && urls.length < 12) {
		        const url = normalizedURL(match[1] || match[2] || match[3] || "");
		        if (url) urls.push(url);
		      }
		    }
		    return urls;
		  }

		  function beginCSSImage(url) {
		    if (!url || tracker.cssImageURLs.has(url)) return false;
		    if (tracker.cssImageProbes.size >= cssImageProbeLimit) return false;
		    if (tracker.cssImageURLs.size >= cssImageURLLimit) return false;
		    tracker.cssImageURLs.add(url);
		    tracker.pendingResources += 1;
		    markActivity();

		    const probe = new Image();
		    let finished = false;
		    const done = () => {
		      if (finished) return;
		      finished = true;
		      tracker.cssImageProbes.delete(url);
		      tracker.pendingResources = Math.max(0, tracker.pendingResources - 1);
		      markActivity();
		    };

		    tracker.cssImageProbes.set(url, probe);
		    probe.onload = done;
		    probe.onerror = done;
		    probe.src = url;
		    if (probe.complete) done();
		    return true;
		  }

		  function scanCSSImages(root, limit = cssImageScanLimit) {
		    if (!root || root.nodeType !== 1 || !document.documentElement) return false;
		    let found = false;
		    let inspected = 0;
		    const inspect = (el) => {
		      if (!el || inspected >= limit) return false;
		      inspected += 1;
		      if (!visibleElement(el)) return inspected < limit;
		      let style = null;
		      try {
		        style = window.getComputedStyle(el);
		      } catch {
		        return inspected < limit;
		      }
		      for (const url of cssImageURLs(style)) {
		        found = beginCSSImage(url) || found;
		      }
		      return inspected < limit;
		    };

		    if (!inspect(root)) return found;
		    const walker = document.createTreeWalker(root, NodeFilter.SHOW_ELEMENT);
		    while (inspected < limit) {
		      const el = walker.nextNode();
		      if (!el) break;
		      inspect(el);
		    }
		    return found;
		  }

		  function trackElement(el, dynamic) {
		    if (!el || el.nodeType !== 1) return false;
		    const tag = (el.tagName || "").toLowerCase();
		    const url = String(resourceURL(el) || "").trim();
		    if (!url) return false;
		    if (tag === "img") {
		      if (String(el.loading || "").toLowerCase() === "lazy" && !intersectsViewport(el)) return false;
		      if (!el.complete) beginResource(el, url);
		      return true;
		    }
		    if (!dynamic) return false;
		    if (tag === "link") {
		      const rel = String(el.rel || el.getAttribute("rel") || "").toLowerCase();
		      if (!rel.split(/\\s+/).includes("stylesheet")) return false;
		    }
		    if (["script", "iframe", "audio", "video", "link"].includes(tag)) {
		      beginResource(el, url, dynamicResourceFallbackMS);
		      return true;
		    }
		    return false;
		  }

		  function scanResources(root, dynamic) {
		    if (!root || root.nodeType !== 1) return false;
		    let found = trackElement(root, dynamic);
		    root.querySelectorAll?.("img,script[src],iframe[src],audio[src],video[src],video[poster],link[href]")
		      ?.forEach((el) => {
		        found = trackElement(el, dynamic) || found;
		      });
		    return found;
		  }

		  recordPerformanceResources(initialResourceEntries);
		  noteReadyStateTransition();
		  window.__wbRecordPerformanceResources = recordPerformanceResources;
		  window.__wbNoteReadyStateTransition = noteReadyStateTransition;

		  const canObservePerformance =
		    !tracker.performanceObserver &&
		    !tracker.performanceObserverUnavailable &&
		    typeof PerformanceObserver === "function";
		  if (canObservePerformance) {
		    const performanceObserver = new PerformanceObserver((list) => {
		      recordPerformanceResources(list.getEntries ? list.getEntries() : []);
		    });
		    try {
		      performanceObserver.observe({ type: "resource", buffered: true });
		      tracker.performanceObserver = performanceObserver;
		    } catch {
		      try {
		        performanceObserver.observe({ entryTypes: ["resource"] });
		        tracker.performanceObserver = performanceObserver;
		      } catch {
		        tracker.performanceObserverUnavailable = true;
		      }
		    }
		  }

		  if (!tracker.installed) {
		    tracker.installed = true;

		    if (typeof window.fetch === "function") {
		      const originalFetch = window.fetch;
		      window.fetch = function(...args) {
		        tracker.pendingRequests += 1;
		        markActivity();
		        try {
		          return Promise.resolve(originalFetch.apply(this, args)).finally(finishRequest);
		        } catch (error) {
		          finishRequest();
		          throw error;
		        }
		      };
		    }

		    if (window.XMLHttpRequest && XMLHttpRequest.prototype) {
		      const originalOpen = XMLHttpRequest.prototype.open;
		      const originalSend = XMLHttpRequest.prototype.send;
		      XMLHttpRequest.prototype.open = function(...args) {
		        this.__wbResourceTracked = false;
		        return originalOpen.apply(this, args);
		      };
		      XMLHttpRequest.prototype.send = function(...args) {
		        let done = null;
		        if (!this.__wbResourceTracked) {
		          this.__wbResourceTracked = true;
		          tracker.pendingRequests += 1;
		          markActivity();
		          done = () => {
		            if (!this.__wbResourceTracked) return;
		            this.__wbResourceTracked = false;
		            finishRequest();
		          };
		          this.addEventListener("loadend", done, { once: true });
		          this.addEventListener("error", done, { once: true });
		          this.addEventListener("abort", done, { once: true });
		        }
		        try {
		          return originalSend.apply(this, args);
		        } catch (error) {
		          if (done) done();
		          throw error;
		        }
		      };
		    }

		    document.addEventListener("load", (event) => {
		      if (event.target && trackElement(event.target, true)) markActivity();
		    }, true);
		    document.addEventListener("error", (event) => {
		      if (event.target && trackElement(event.target, true)) markActivity();
		    }, true);
		    document.addEventListener("readystatechange", noteReadyStateTransition);
		  }

		  function installObserver() {
		    const root = document.documentElement;
		    if (!root) return false;
		    if (tracker.observer && tracker.observedRoot === root) {
		      scanCSSImages(root);
		      return true;
		    }
		    if (tracker.observer) {
		      try {
		        tracker.observer.disconnect();
		      } catch {}
		      tracker.observer = null;
		    }

		    Array.from(document.images || []).forEach((img) => trackElement(img, false));
		    scanCSSImages(root);
		    tracker.observer = new MutationObserver((mutations) => {
		      let foundResourceMutation = false;
		      let foundVisibleMutation = false;
		      for (const mutation of mutations) {
		        if (mutation.type === "childList") {
		          mutation.addedNodes.forEach((node) => {
		            foundResourceMutation = scanResources(node, true) || foundResourceMutation;
		            foundResourceMutation =
		              scanCSSImages(node, cssImageMutationScanLimit) || foundResourceMutation;
		          });
		        } else if (mutation.target) {
		          foundResourceMutation = trackElement(mutation.target, true) || foundResourceMutation;
		          foundResourceMutation =
		            scanCSSImages(mutation.target, cssImageMutationScanLimit) || foundResourceMutation;
		        }
		        foundVisibleMutation = mutationTouchesVisibleDOM(mutation) || foundVisibleMutation;
		      }
		      if (foundResourceMutation || foundVisibleMutation) markActivity();
		    });
		    tracker.observedRoot = root;
		    tracker.observer.observe(root, {
		      subtree: true,
		      childList: true,
		      characterData: true,
		      attributes: true,
		      attributeFilter: [
		        "aria-hidden",
		        "class",
		        "hidden",
		        "href",
		        "poster",
		        "rel",
		        "src",
		        "srcset",
		        "style"
		      ]
		    });
		    return true;
		  }

		  window.__wbInstallResourceObserver = installObserver;
		  if (!installObserver() && !tracker.waitingForObserver) {
		    tracker.waitingForObserver = true;
		    const retry = () => {
		      if (!installObserver()) return;
		      tracker.waitingForObserver = false;
		      document.removeEventListener("readystatechange", retry);
		    };
		    document.addEventListener("readystatechange", retry);
		    document.addEventListener("DOMContentLoaded", retry, { once: true });
		  }
		})();
		"""

	static let loadStatusScript =
		resourceTrackerScript + """

			if (typeof window.__wbInstallResourceObserver === "function") {
			  window.__wbInstallResourceObserver();
			}

			const statusNow = performance.now ? performance.now() : Date.now();
			const currentResourceEntries = performance.getEntriesByType
			  ? performance.getEntriesByType("resource")
			  : [];
			const currentResourceCount = currentResourceEntries.length;
			const tracker = window.__wbResourceTracker || {
			  pendingRequests: 0,
			  pendingResources: 0,
			  lastActivityAt: statusNow - 1000,
			  resourceCount: currentResourceCount,
			  totalResourceCount: currentResourceCount
			};
			window.__wbResourceTracker = tracker;

			if (typeof window.__wbRecordPerformanceResources === "function") {
			  window.__wbRecordPerformanceResources(currentResourceEntries);
			} else if (currentResourceCount !== tracker.resourceCount) {
			  tracker.resourceCount = currentResourceCount;
			  tracker.totalResourceCount = Math.max(
			    currentResourceCount,
			    Number(tracker.totalResourceCount || 0)
			  );
			  tracker.lastActivityAt = statusNow;
			}
			if (typeof window.__wbNoteReadyStateTransition === "function") {
			  window.__wbNoteReadyStateTransition();
			}

			return JSON.stringify({
			  readyState: document.readyState || "",
			  pendingRequests: Math.max(0, tracker.pendingRequests | 0),
			  pendingResources: Math.max(0, tracker.pendingResources | 0),
			  quietFor: Math.max(0, (statusNow - tracker.lastActivityAt) / 1000)
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
		if (typeof value === "object") { try { return JSON.stringify(value, null, 2); } catch (error) {} }
		return String(value);
		"""
}
