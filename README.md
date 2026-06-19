# wp

A small non-interactive command-line prototype for experimenting with Apple's `WebKit.WebPage`.

`wp` is a short-lived CLI client plus a local daemon. The daemon owns long-lived `WebPage` instances, and each `wp` command talks to it over a Unix socket.

`WebPage` is available starting with macOS 26/iOS 26 SDKs. This prototype is a macOS CLI because iOS does not provide a normal user-facing shell for command-line programs. The same manager/client approach can be moved into an app or service host.

## Requirements

- macOS 26.0 or newer
- Xcode 26 or newer, with Swift 6.2 SDKs

The current container does not include Swift or Apple's WebKit framework, so this project is meant to be built on a Mac.

## Run

```bash
swift run wp browser create
```

For repeated use, build once and call the binary directly:

```bash
swift build
.build/debug/wp browser create
```

## Basic Flow

```text
$ wp browser create
1000

$ wp --browser 1000 open https://example.com
{ ... page JSON ... }

$ wp -b 1000 page
{ ... title, url, visible text, actions ... }

$ wp -b 1000 click 1
{ ... message and updated page JSON ... }

$ wp -b 1000 eval "document.title"
Example Domain
```

## Commands

- `wp browser create`: start the daemon if needed, create a browser, and print its ID.
- `wp browser list`: print daemon browser summaries as JSON.
- `wp browser close <id>`: close a daemon browser.
- `wp open <url>`: create a browser, open the page, and print page JSON.
- `wp --browser <id> open <url>` / `wp -b <id> open <url>`: open a page in an existing browser.
- `wp -b <id> page`: refresh and print page JSON, including visible actions.
- `wp -b <id> click <n>`: click an action from the latest page/action list.
- `wp -b <id> fill <n> <text>`: set the value of an input, textarea, select, or contenteditable element.
- `wp -b <id> submit <n>`: submit the nearest form for an action.
- `wp -b <id> eval <expression>`: evaluate a JavaScript expression and print the result.
- `wp -b <id> js <function-body>`: run a raw `WebPage.callJavaScript` function body.
- `wp -b <id> text [selector]`: print visible text for the page or CSS selector.
- `wp -b <id> html [selector]`: print HTML for the page or CSS selector.
- `wp daemon status`: print whether the daemon is running.
- `wp daemon stop`: stop the daemon.

## Notes

This is intentionally basic. The `page` command injects `data-wkcli-id` attributes into the current document so later commands can find numbered elements. If the page navigates or rerenders, run `wp -b <id> page` again.

The daemon socket defaults to `/tmp/wp-webpage-<uid>.sock`. Set `WP_SOCKET` to override it.
