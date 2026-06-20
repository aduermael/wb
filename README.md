# wb

A small non-interactive command-line prototype for experimenting with Apple's `WebKit.WebPage`.

`wb` opens and controls persistent `WebPage` browser sessions from the command line.

`WebPage` is available starting with macOS 26/iOS 26 SDKs. This prototype is a macOS CLI because iOS does not provide a normal user-facing shell for command-line programs. The same manager/client approach can be moved into an app or service host.

## Requirements

- macOS 26.0 or newer
- Xcode 26 or newer, with Swift 6.2 SDKs

The current container does not include Swift or Apple's WebKit framework, so this project is meant to be built on a Mac.

## Run

```bash
swift run wb create
```

For repeated use, build once and call the binary directly:

```bash
swift build
.build/debug/wb create
```

## Basic Flow

```text
$ wb create
a3f19c0b

$ wb a3f19c0b https://example.com
{"actions":1,"browser":"a3f19c0b","htmlBytes":1256,"images":0,"jsonBytes":463,"progress":1.0,"title":"Example Domain","url":"https://example.com/"}

$ wb page a3f19c0b
{"actions":[{"href":"https://www.iana.org/domains/example","index":1,"kind":"link","text":"More information..."}],"browser":"a3f19c0b","htmlBytes":1256,"imageCount":0,"jsonBytes":479,"progress":1.0,"text":"Example Domain\n\nThis domain is for use in illustrative examples in documents. You may use this domain in literature without prior coordination or asking for permission.\n\n[More information...](https://www.iana.org/domains/example)","title":"Example Domain","url":"https://example.com/"}

$ wb click a3f19c0b 1
{"actions":1,"browser":"a3f19c0b","htmlBytes":1256,"images":0,"jsonBytes":463,"message":"clicked More information...","progress":1.0,"title":"Example Domain","url":"https://example.com/"}

$ wb eval a3f19c0b "document.title"
Example Domain

$ wb screenshot a3f19c0b /tmp/example.png
saved /tmp/example.png

$ wb show a3f19c0b
$ wb hide a3f19c0b
```

## Output

`wb` keeps structured CLI JSON compact by default. JSON is emitted on one line and omits fields that do not add information: `null`, most `false` values, empty strings, empty arrays, and empty objects. Error responses preserve `ok:false`. Raw `eval` results are printed as returned strings.

Commands avoid returning a full page snapshot unless explicitly asked. Use `wb <url>` or `wb <id> <url>` for a compact summary containing the browser ID, title, URL, loading/progress, action count, image count, full-document HTML byte count, and default page JSON byte count. Use `wb page <id>` when you need visible text, the full action list, and image URLs.

Browser IDs are random 8-character lowercase hex strings. Page snapshot text is markdown-like and includes inline links where possible. Page actions are compact by default and include a 1-based `index` for `click`, `fill`, and `submit`; internal IDs, CSS selectors, and tags are omitted unless requested. Image entries include a 1-based `index` and resolved URL. Use `wb page <id> --action-details` to include internal action IDs, or `wb page <id> --selectors` to include CSS selectors.

Navigation errors are emitted as JSON responses with `ok:false` and a nonzero exit status. When a browser exists, the error JSON includes its browser ID so it can still be shown, reused, or closed.

Use `wb page --help` to see filterable fields. Use `wb page <id> --fields title,url,imageCount,images,htmlBytes,jsonBytes` to print selected top-level fields.

## Commands

- `wb create`: create an empty browser and print its ID.
- `wb <url>`: create a browser, load the page, and print a compact summary.
- `wb <id> <url>`: load a page in an existing browser.
- `wb list`: print active and dumped browser summaries as compact JSON.
- `wb close <id>`: close an active browser and delete any dumped session for that ID.
- `wb dump <id>`: save the browser so it can be resumed later.
- `wb show <id>`: show a lightweight browser window for the browser.
- `wb hide <id>`: hide the browser window without closing the browser.
- `wb screenshot <id> <destination.png|destination.jpg>`: capture the current browser viewport as PNG or JPEG, selected by extension.
- `wb page <id> [--fields <list>] [--selectors|--action-details]`: refresh and print page JSON, including visible actions and image URLs.
- `wb click <id> <action>`: click an action from the latest page/action list and print a compact summary.
- `wb click <id> <x> <y>`: click the current viewport coordinate without opening a window.
- `wb press <id> <x> <y>`: send a page mouse-down event at a viewport coordinate.
- `wb drag <id> <x> <y>`: send a page mouse-drag event to a viewport coordinate after `press`.
- `wb release <id> <x> <y>`: send a page mouse-up event at a viewport coordinate.
- `wb scroll <id> <x> <y> <deltaX> <deltaY>`: scroll at a viewport coordinate without opening a window.
- `wb fill <id> <action> <text>`: set the value of an input, textarea, select, or contenteditable element and print a compact summary.
- `wb submit <id> <action>`: submit the nearest form for an action and print a compact summary.
- `wb eval <id> [--body] <javascript>`: evaluate a JavaScript expression, or run a raw `WebPage.callJavaScript` function body with `--body`, and print the result.
- `wb daemon <start|status|log|stop>`: advanced browser session controls.

Each command has its own help, for example `wb click --help` or `wb daemon --help`.

Browser IDs can be used across commands. If a saved browser is not currently active, `wb` resumes it automatically.

## Notes

Browsers persist between commands and are autosaved after creation, navigation, interactions, and JavaScript evaluation. Use `wb list` to find browser IDs, `wb page <id>` to inspect the current page, and `wb close <id>` when you are done.

The `page` command refreshes the action list for the current document. If the page navigates or rerenders, run `wb page <id>` again before using action numbers from older output.

Coordinate commands use top-left origin coordinates in the current web content viewport and do not open a window. `screenshot` captures that same viewport, so agents can inspect the image and use matching coordinates for `click`, `press`, `drag`, `release`, and `scroll`. If the browser is already visible through `wb show`, the same page updates are visible there.

By default, browser sessions are stored in `.wb/sessions` under the current directory. Existing `wb/sessions` directories are still used for compatibility. Set `WB_DIR` to override the state directory.

The `show` command attaches a native window to the same `WebPage` used by headless commands. While a browser window is visible, the daemon does not idle-exit. Use `wb hide <id>` or close the window to allow normal idle shutdown again.

Daemon logs are appended to `/tmp/wb-webpage-<uid>.log` by default. Use `wb daemon log` to print the exact path, or set `WB_LOG` to override it.
