/// Defines JavaScript snippets used only while preparing viewport screenshots
/// for export.
import Foundation

@available(macOS 26.0, *)
extension BrowserInstance {
	static let screenshotPrepareLayoutScript = """
		const root = document.documentElement;
		const body = document.body;
		const shouldDispatchResize = typeof dispatchResize === "undefined" || dispatchResize !== false;
		if (root) { root.getBoundingClientRect(); void root.offsetHeight; }
		if (body) { body.getBoundingClientRect(); void body.offsetHeight; }
		if (shouldDispatchResize) window.dispatchEvent(new Event("resize"));
		if (shouldDispatchResize && window.visualViewport) {
		  window.visualViewport.dispatchEvent(new Event("resize"));
		}
		return "ok";
		"""

	static let screenshotWaitForFontsScript = """
		const limit = Math.max(0, Number(timeoutMs) || 0);
		if (!document.fonts || !document.fonts.ready) {
		  return "unavailable";
		}

		let timeoutHandle = null;
		const timeout = new Promise((resolve) => {
		  timeoutHandle = setTimeout(() => resolve("timeout"), limit);
		});
		const ready = document.fonts.ready.then(() => "ready").catch(() => "error");
		const result = await Promise.race([ready, timeout]);
		if (timeoutHandle !== null) clearTimeout(timeoutHandle);
		return result;
		"""

	static let screenshotWaitForAnimationFramesScript = """
		const requiredFrames = Math.max(1, Math.floor(Number(frameCount) || 1));
		const limit = Math.max(0, Number(timeoutMs) || 0);
		if (typeof requestAnimationFrame !== "function") {
		  return JSON.stringify({
		    completed: false,
		    frames: 0,
		    reason: "unavailable"
		  });
		}

		const startedAt = performance.now ? performance.now() : Date.now();
		let frames = 0;
		const result = await new Promise((resolve) => {
		  let completed = false;
		  let timeoutHandle = null;

		  function finish(didComplete, reason) {
		    if (completed) return;
		    completed = true;
		    if (timeoutHandle !== null) clearTimeout(timeoutHandle);
		    const finishedAt = performance.now ? performance.now() : Date.now();
		    resolve({
		      completed: didComplete,
		      frames,
		      reason,
		      elapsedMs: Math.max(0, finishedAt - startedAt)
		    });
		  }

		  timeoutHandle = setTimeout(() => finish(false, "timeout"), limit);
		  requestAnimationFrame(function tick() {
		    frames += 1;
		    if (frames >= requiredFrames) {
		      finish(true, "frames");
		      return;
		    }
		    requestAnimationFrame(tick);
		  });
		});
		return JSON.stringify(result);
		"""

	static let screenshotCompleteStuckAnimationsScript = """
		function intersectsViewport(rect) {
		  const width = window.innerWidth || document.documentElement?.clientWidth || 0;
		  const height = window.innerHeight || document.documentElement?.clientHeight || 0;
		  return rect.width > 0 && rect.height > 0 &&
		    rect.bottom > 0 && rect.right > 0 && rect.top < height && rect.left < width;
		}

		function canReveal(el) {
		  if (!el || el.nodeType !== 1) return false;
		  if (el.hidden || el.getAttribute("aria-hidden") === "true") return false;
		  const inlineStyle = String(el.getAttribute("style") || "");
		  if (!/(^|;)\\s*opacity\\s*:\\s*0(?:\\D|$)/i.test(inlineStyle)) return false;
		  const style = window.getComputedStyle(el);
		  if (!style || style.display === "none" || style.visibility === "hidden") return false;
		  if (Number(style.opacity) !== 0) return false;
		  return intersectsViewport(el.getBoundingClientRect());
		}

		let revealed = 0;
		for (const el of document.querySelectorAll("[style*='opacity']")) {
		  if (!canReveal(el)) continue;
		  el.style.opacity = "1";
		  if (/translate|matrix|scale/i.test(String(el.style.transform || ""))) {
		    el.style.transform = "none";
		  }
		  revealed += 1;
		  if (revealed >= 80) break;
		}
		return String(revealed);
		"""
}
