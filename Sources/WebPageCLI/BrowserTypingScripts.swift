/// Stores the JavaScript snippet used for human-like text entry, kept separate
/// from the general browser scripts to keep source files small.
@available(macOS 26.0, *)
extension BrowserInstance {
	static let typeScript =
		findElementScript + """

			function wkcliTypingTarget(id) {
			  const el = wkcliFind(id);
			  if (!el) return "not found; run page again";
			  if (el.disabled || el.readOnly || el.getAttribute("aria-disabled") === "true") return "element is disabled";

			  const tag = el.tagName.toLowerCase();
			  const inputType = (el.getAttribute("type") || "text").toLowerCase();
			  const nonTextInputTypes = [
			    "hidden",
			    "checkbox",
			    "radio",
			    "button",
			    "submit",
			    "reset",
			    "file",
			    "image",
			    "range",
			    "color"
			  ];
			  const canType =
			    el.isContentEditable ||
			    tag === "textarea" ||
			    (tag === "input" && !nonTextInputTypes.includes(inputType));
			  return canType ? el : "element cannot be typed into";
			}

			function wkcliCurrentText(el) {
			  if (el.isContentEditable) return el.textContent || "";
			  if ("value" in el) return el.value || "";
			  return "";
			}

			function wkcliSetText(el, text) {
			  if (el.isContentEditable) {
			    el.textContent = text;
			    wkcliPlaceCaretAtEnd(el);
			    return;
			  }

			  if (!("value" in el)) return;
			  const tag = el.tagName.toLowerCase();
			  const prototype = tag === "textarea" ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
			  const descriptor = Object.getOwnPropertyDescriptor(prototype, "value");
			  if (descriptor && descriptor.set) {
			    descriptor.set.call(el, text);
			  } else {
			    el.value = text;
			  }
			}

			function wkcliSelectionRange(el) {
			  const length = wkcliCurrentText(el).length;
			  try {
			    if (typeof el.selectionStart === "number" && typeof el.selectionEnd === "number") {
			      return [el.selectionStart, el.selectionEnd];
			    }
			  } catch {}
			  return [length, length];
			}

			function wkcliPlaceCaretAtEnd(el) {
			  if (el.isContentEditable) {
			    const selection = window.getSelection();
			    if (!selection) return;
			    const range = document.createRange();
			    range.selectNodeContents(el);
			    range.collapse(false);
			    selection.removeAllRanges();
			    selection.addRange(range);
			    return;
			  }

			  const length = wkcliCurrentText(el).length;
			  try {
			    if (typeof el.setSelectionRange === "function") {
			      el.setSelectionRange(length, length);
			    }
			  } catch {}
			}

			function wkcliSelectAll(el) {
			  if (el.isContentEditable) {
			    const selection = window.getSelection();
			    if (!selection) return;
			    const range = document.createRange();
			    range.selectNodeContents(el);
			    selection.removeAllRanges();
			    selection.addRange(range);
			    return;
			  }

			  try {
			    if (typeof el.select === "function") {
			      el.select();
			    } else if (typeof el.setSelectionRange === "function") {
			      el.setSelectionRange(0, wkcliCurrentText(el).length);
			    }
			  } catch {}
			}

			function wkcliInsertText(el, text) {
			  if (el.isContentEditable) {
			    const selection = window.getSelection();
			    if (!selection) {
			      el.appendChild(document.createTextNode(text));
			      return;
			    }
			    let range = selection.rangeCount > 0 ? selection.getRangeAt(0) : undefined;
			    if (!range || !el.contains(range.commonAncestorContainer)) {
			      range = document.createRange();
			      range.selectNodeContents(el);
			      range.collapse(false);
			      selection.removeAllRanges();
			      selection.addRange(range);
			    }
			    range.deleteContents();
			    const node = document.createTextNode(text);
			    range.insertNode(node);
			    range.setStartAfter(node);
			    range.setEndAfter(node);
			    selection.removeAllRanges();
			    selection.addRange(range);
			    return;
			  }

			  const current = wkcliCurrentText(el);
			  const [start, end] = wkcliSelectionRange(el);
			  const next = current.slice(0, start) + text + current.slice(end);
			  const cursor = start + text.length;
			  wkcliSetText(el, next);
			  try {
			    if (typeof el.setSelectionRange === "function") {
			      el.setSelectionRange(cursor, cursor);
			    }
			  } catch {}
			}

			function wkcliKeyboardEvent(type, key) {
			  const keyCodes = { Backspace: 8, Enter: 13 };
			  const code = keyCodes[key] || (key.length === 1 ? key.codePointAt(0) : 0);
			  try {
			    return new KeyboardEvent(type, {
			      key,
			      code: key.length === 1 ? "" : key,
			      keyCode: code,
			      which: code,
			      charCode: type === "keypress" ? code : 0,
			      bubbles: true,
			      cancelable: true
			    });
			  } catch {
			    return new Event(type, { bubbles: true, cancelable: true });
			  }
			}

			function wkcliInputEvent(type, data, inputType) {
			  const cancelable = type === "beforeinput";
			  try {
			    return new InputEvent(type, {
			      data,
			      inputType,
			      bubbles: true,
			      cancelable
			    });
			  } catch {
			    const event = new Event(type, { bubbles: true, cancelable });
			    try { Object.defineProperty(event, "data", { value: data }); } catch {}
			    try { Object.defineProperty(event, "inputType", { value: inputType }); } catch {}
			    return event;
			  }
			}

			function wkcliDispatchInput(el, data, inputType) {
			  el.dispatchEvent(wkcliInputEvent("input", data, inputType));
			}

			function wkcliDelay(milliseconds) {
			  return new Promise((resolve) => setTimeout(resolve, milliseconds));
			}

			function wkcliNextDelay() {
			  const min = Math.max(0, Number(delayMin || 0));
			  const max = Math.max(min, Number(delayMax || min));
			  return (min + Math.random() * (max - min)) * 1000;
			}

			function wkcliClear(el) {
			  wkcliSelectAll(el);
			  if (wkcliCurrentText(el).length === 0) return "typed";

			  const key = "Backspace";
			  if (!el.dispatchEvent(wkcliKeyboardEvent("keydown", key))) {
			    el.dispatchEvent(wkcliKeyboardEvent("keyup", key));
			    return "typing canceled";
			  }
			  if (!el.dispatchEvent(wkcliInputEvent("beforeinput", null, "deleteContentBackward"))) {
			    el.dispatchEvent(wkcliKeyboardEvent("keyup", key));
			    return "typing canceled";
			  }
			  wkcliSetText(el, "");
			  wkcliDispatchInput(el, null, "deleteContentBackward");
			  el.dispatchEvent(wkcliKeyboardEvent("keyup", key));
			  return "typed";
			}

			function wkcliTypeCharacter(el, textValue) {
			  const key = textValue === "\\n" ? "Enter" : textValue;
			  if (!el.dispatchEvent(wkcliKeyboardEvent("keydown", key))) {
			    el.dispatchEvent(wkcliKeyboardEvent("keyup", key));
			    return "typing canceled";
			  }
			  if (!el.dispatchEvent(wkcliKeyboardEvent("keypress", key))) {
			    el.dispatchEvent(wkcliKeyboardEvent("keyup", key));
			    return "typing canceled";
			  }
			  if (!el.dispatchEvent(wkcliInputEvent("beforeinput", textValue, "insertText"))) {
			    el.dispatchEvent(wkcliKeyboardEvent("keyup", key));
			    return "typing canceled";
			  }

			  wkcliInsertText(el, textValue);
			  wkcliDispatchInput(el, textValue, "insertText");
			  el.dispatchEvent(wkcliKeyboardEvent("keyup", key));
			  return "typed";
			}

			async function wkcliTypeText() {
			  const target = wkcliTypingTarget(id);
			  if (typeof target === "string") return target;
			  const el = target;
			  el.scrollIntoView({ block: "center", inline: "center" });
			  el.focus({ preventScroll: true });

			  const clearResult = wkcliClear(el);
			  if (clearResult !== "typed") return clearResult;

			  const characters = Array.from(String(value ?? ""));
			  for (const character of characters) {
			    await wkcliDelay(wkcliNextDelay());
			    const result = wkcliTypeCharacter(el, character);
			    if (result !== "typed") return result;
			  }

			  el.dispatchEvent(new Event("change", { bubbles: true }));
			  const count = characters.length;
			  return `typed ${count} character${count === 1 ? "" : "s"}`;
			}

			return await wkcliTypeText();
			"""
}
