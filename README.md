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
{"actions":1,"browser":"1000","progress":1,"title":"Example Domain","url":"https://example.com/"}

$ wp -b 1000 page
{"actions":[...],"browser":"1000","progress":1,"text":"...","title":"Example Domain","url":"https://example.com/"}

$ wp -b 1000 click 1
{"actions":1,"browser":"1000","message":"clicked More information...","progress":1,"title":"Example Domain","url":"https://example.com/"}

$ wp -b 1000 eval "document.title"
Example Domain
```

## Output

`wp` keeps structured CLI JSON compact by default. JSON is emitted on one line and omits fields that do not add information: `null`, `false`, empty strings, empty arrays, and empty objects. Raw `eval`, `js`, `text`, and `html` results are printed as returned strings.

Commands avoid returning a full page snapshot unless explicitly asked. Use `wp open <url>` for a short summary containing the browser ID, title, URL, loading/progress, and action count. Use `wp open --full <url>` or `wp -b <id> page` when you need visible text and the full action list. Full snapshots still use compact JSON pruning.

## Commands

- `wp browser create`: start the daemon if needed, create a browser, and print its ID.
- `wp browser list`: print active and dumped browser summaries as compact JSON.
- `wp browser close <id>`: close a daemon browser and delete any dumped session for that ID.
- `wp browser dump <id>`: write the browser session metadata to `./wp/sessions/<id>.json`.
- `wp browser resume <id>`: resume a dumped browser by reloading its saved URL.
- `wp open <url>`: create a browser, open the page, and print a compact summary.
- `wp open --full <url>`: create a browser, open the page, and print the full page snapshot.
- `wp --browser <id> open <url>` / `wp -b <id> open <url>`: open a page in an existing browser.
- `wp -b <id> page`: refresh and print page JSON, including visible actions.
- `wp -b <id> click <n>`: click an action from the latest page/action list and print a compact summary.
- `wp -b <id> fill <n> <text>`: set the value of an input, textarea, select, or contenteditable element and print a compact summary.
- `wp -b <id> submit <n>`: submit the nearest form for an action and print a compact summary.
- `wp -b <id> eval <expression>`: evaluate a JavaScript expression and print the result.
- `wp -b <id> js <function-body>`: run a raw `WebPage.callJavaScript` function body.
- `wp -b <id> text [selector]`: print visible text for the page or CSS selector.
- `wp -b <id> html [selector]`: print HTML for the page or CSS selector.
- `wp daemon start [--idle-timeout <seconds|off>]`: start the daemon and optionally set its idle shutdown timeout.
- `wp daemon status`: print whether the daemon is running.
- `wp daemon stop`: dump active browsers and stop the daemon.

Dumped browser IDs can be used with normal `-b <id>` commands. If the browser is not active but has a dump file, the daemon resumes it first.

## Notes

This is intentionally basic. The `page` command injects `data-wkcli-id` attributes into the current document so later commands can find numbered elements. If the page navigates or rerenders, run `wp -b <id> page` again.

The daemon auto-dumps active browsers and exits after 180 seconds with no completed requests. Configure this with `WP_IDLE_SECONDS`, or start the daemon explicitly with `wp daemon start --idle-timeout <seconds|off>`. Use `0` or `off` to disable idle shutdown. A running daemon keeps the timeout it started with; stop and restart it to apply a new value.

Session files default to `./wp/sessions`. Set `WP_DIR` to use a different state directory. The default daemon socket is scoped to that state directory and lives under `/tmp`; set `WP_SOCKET` to override it.

Session resume is best-effort. The dump stores URL, title, timestamps, a last snapshot, and action metadata, then resumes by creating a new `WebPage` and reloading the saved URL. It does not serialize the JavaScript heap, in-flight network state, form edits, auth state, storage, or other process-local browser internals.
