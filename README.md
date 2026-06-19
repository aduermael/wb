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
a3f19c0b

$ wp --browser a3f19c0b open https://example.com
{"actions":1,"browser":"a3f19c0b","htmlBytes":1256,"images":0,"jsonBytes":463,"progress":1.0,"title":"Example Domain","url":"https://example.com/"}

$ wp -b a3f19c0b page
{"actions":[{"href":"https://www.iana.org/domains/example","kind":"link","text":"More information..."}],"browser":"a3f19c0b","htmlBytes":1256,"images":0,"jsonBytes":463,"progress":1.0,"text":"Example Domain\n\nThis domain is for use in illustrative examples in documents. You may use this domain in literature without prior coordination or asking for permission.\n\n[More information...](https://www.iana.org/domains/example)","title":"Example Domain","url":"https://example.com/"}

$ wp -b a3f19c0b click 1
{"actions":1,"browser":"a3f19c0b","htmlBytes":1256,"images":0,"jsonBytes":463,"message":"clicked More information...","progress":1.0,"title":"Example Domain","url":"https://example.com/"}

$ wp -b a3f19c0b eval "document.title"
Example Domain
```

## Output

`wp` keeps structured CLI JSON compact by default. JSON is emitted on one line and omits fields that do not add information: `null`, `false`, empty strings, empty arrays, and empty objects. Raw `eval`, `text`, and `html` results are printed as returned strings.

Commands avoid returning a full page snapshot unless explicitly asked. Use `wp open <url>` for a short summary containing the browser ID, title, URL, loading/progress, action count, image count, full-document HTML byte count, and default page JSON byte count. Use `wp open --full <url>` or `wp -b <id> page` when you need visible text and the full action list. Full snapshots still use compact JSON pruning.

Browser IDs are random 8-character lowercase hex strings. Page snapshot text is markdown-like and includes inline links where possible. `images` is `document.images.length`; `htmlBytes` is the UTF-8 size of `document.documentElement.outerHTML`; `jsonBytes` is the UTF-8 size of the default full page JSON excluding the `jsonBytes` field itself. Page actions are compact by default and omit internal IDs, CSS selectors, tags, and explicit index fields. The action number for `click`, `fill`, and `submit` is still the 1-based position in the `actions` array. Use `wp -b <id> page --selectors` to include CSS selectors, or `wp -b <id> page --action-details` to include the internal action ID, index, tag, type, and selector.

Use `wp page --help` to see the documented full page JSON shape. Use `wp -b <id> page --fields title,url,images,htmlBytes,jsonBytes` to print only selected top-level fields. Available page fields are `actions`, `browser`, `htmlBytes`, `images`, `jsonBytes`, `loading`, `progress`, `text`, `title`, and `url`.

## Commands

- `wp browser create`: start the daemon if needed, create a browser, and print its ID.
- `wp browser list`: print active and dumped browser summaries as compact JSON.
- `wp browser close <id>`: close a daemon browser and delete any dumped session for that ID.
- `wp browser dump <id>`: write the browser session metadata to `./wp/sessions/<id>.json`.
- `wp browser resume <id>`: resume a dumped browser by reloading its saved URL.
- `wp open <url>`: create a browser, open the page, and print a compact summary.
- `wp open --full [--fields <list>] [--selectors|--action-details] <url>`: create a browser, open the page, and print the full page snapshot.
- `wp --browser <id> open <url>` / `wp -b <id> open <url>`: open a page in an existing browser.
- `wp -b <id> page [--fields <list>] [--selectors|--action-details]`: refresh and print page JSON, including visible actions.
- `wp -b <id> click <n>`: click an action from the latest page/action list and print a compact summary.
- `wp -b <id> fill <n> <text>`: set the value of an input, textarea, select, or contenteditable element and print a compact summary.
- `wp -b <id> submit <n>`: submit the nearest form for an action and print a compact summary.
- `wp -b <id> eval [--body] <javascript>`: evaluate a JavaScript expression, or run a raw `WebPage.callJavaScript` function body with `--body`, and print the result.
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
