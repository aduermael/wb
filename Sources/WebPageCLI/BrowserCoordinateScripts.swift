/// JavaScript snippets for coordinate-based browser interactions such as
/// pointer clicks, drags, releases, and scroll gestures.
@available(macOS 26.0, *)
extension BrowserInstance {
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
}
