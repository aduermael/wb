# WebPageCLI

A small interactive command-line prototype for experimenting with Apple's `WebKit.WebPage`.

`WebPage` is available starting with macOS 26/iOS 26 SDKs. This prototype is a macOS CLI because iOS does not provide a normal user-facing shell for interactive command-line programs. The same `WebPage` approach can be moved into an iOS app UI.

## Requirements

- macOS 26.0 or newer
- Xcode 26 or newer, with Swift 6.2 SDKs

The current container does not include Swift or Apple's WebKit framework, so this project is meant to be built on a Mac.

## Run

```bash
swift run webpage-cli
```

## Basic Session

```text
webpage> open https://example.com
webpage> state
webpage> actions
webpage> click 1
webpage> text
webpage> eval document.title
webpage> js return document.querySelectorAll("a").length;
webpage> quit
```

## Commands

- `open <url>`: load a page.
- `state`: print title, URL, and load progress.
- `actions`: list visible links, buttons, inputs, selects, forms, labels, and clickable-ish elements.
- `click <n>`: click an action from the latest `actions` list.
- `fill <n> <text>`: set the value of an input, textarea, or contenteditable element.
- `submit <n>`: submit the nearest form for an action.
- `text [selector]`: print visible text for the page, or for a CSS selector.
- `html [selector]`: print HTML for the page, or for a CSS selector.
- `eval <expression>`: evaluate a JavaScript expression.
- `js <function-body>`: run a raw `WebPage.callJavaScript` function body. Use `return` if you want output.
- `reload`, `stop`, `wait`, `quit`.

## Notes

This is intentionally basic. The `actions` command injects `data-wkcli-id` attributes into the current document so later commands can find the same elements. If the page navigates or rerenders, run `actions` again.
