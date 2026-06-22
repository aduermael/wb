# wb

[![Lint](https://github.com/aduermael/wb/actions/workflows/lint.yml/badge.svg)](https://github.com/aduermael/wb/actions/workflows/lint.yml)

`wb` is a macOS 26+ web browser for agents, exposed as a lightweight command-line tool.

It gives scripts and coding agents a real persistent browser session without a bundled Chromium, driver server, or heavyweight app wrapper. The release binary is less than 2 MB, starts from a normal shell command, speaks compact JSON, and can still show a live native preview window when you need to see what the agent sees.

`wb` is built on macOS system browser technology and is macOS-only. It does not run on Linux, Windows, or older macOS releases.

## Why wb

- **Small enough to vendor into agent workflows.** A single lightweight macOS binary, not a browser distribution.
- **Made for command loops.** Create a browser once, then navigate, inspect, click, fill, scroll, screenshot, and evaluate JavaScript across separate CLI calls.
- **Structured output by default.** Commands return compact JSON summaries and stable action indexes that are easy for agents to consume.
- **Headless until you need eyes.** Use `wb show <id>` to attach a live preview window to the same browser session, then `wb hide <id>` to go back to CLI-only control.
- **Coordinates and screenshots line up.** The screenshot viewport is the same coordinate space used by `click`, `press`, `drag`, `release`, and `scroll`.

## Install

For agent workflows, install the skill folder in the current project:

```bash
curl -fsSL https://raw.githubusercontent.com/aduermael/wb/main/install-skill.sh | sh
```

The project installer copies the `wb` skill into `.agents/skills/wb`, `.claude/skills/wb`, and `.grok/skills/wb` by default. The skill includes a bundled `install.sh` support script that makes the `wb` command available if an agent tries to use the skill before the CLI is installed.

To install only one agent target:

```bash
curl -fsSL https://raw.githubusercontent.com/aduermael/wb/main/install-skill.sh | env WB_SKILL_TARGETS=codex sh
```

To install the CLI immediately while installing the skill:

```bash
curl -fsSL https://raw.githubusercontent.com/aduermael/wb/main/install-skill.sh | env WB_INSTALL_CLI=1 sh
```

To install only the CLI, use Homebrew:

```bash
brew install aduermael/tap/wb
```

Or use the standalone installer:

Prebuilt releases are macOS 26+ binaries. Installing them does not require Xcode or a Swift toolchain.

```bash
curl -fsSL https://raw.githubusercontent.com/aduermael/wb/main/install.sh | sh
```

By default this installs to `/usr/local/bin/wb`, which is on `PATH` for most macOS shells. If that location requires admin permissions, the script offers to use `sudo`.

To choose another location:

```bash
curl -fsSL https://raw.githubusercontent.com/aduermael/wb/main/install.sh | env WB_INSTALL_DIR="$HOME/.local/bin" sh
```

To install a specific release:

```bash
curl -fsSL https://raw.githubusercontent.com/aduermael/wb/main/install.sh | env WB_VERSION=0.1.0 sh
```

## Quick Start

```bash
wb https://example.com
```

That creates a browser, loads the page, and prints a compact JSON summary. For a longer-lived session:

```text
$ wb create
a3f19c0b

$ wb a3f19c0b https://example.com
{"actions":1,"browser":"a3f19c0b","htmlBytes":1256,"images":0,"jsonBytes":463,"progress":1.0,"title":"Example Domain","url":"https://example.com/"}

$ wb page a3f19c0b
{"actions":[{"href":"https://www.iana.org/domains/example","index":1,"kind":"link","text":"More information..."}],"browser":"a3f19c0b","htmlBytes":1256,"imageCount":0,"jsonBytes":479,"progress":1.0,"text":"Example Domain\n\nThis domain is for use in illustrative examples in documents. You may use this domain in literature without prior coordination or asking for permission.\n\n[More information...](https://www.iana.org/domains/example)","title":"Example Domain","url":"https://example.com/"}

$ wb click a3f19c0b 1
{"actions":1,"browser":"a3f19c0b","htmlBytes":1256,"images":0,"jsonBytes":463,"message":"clicked More information...","progress":1.0,"title":"Example Domain","url":"https://example.com/"}

$ wb screenshot a3f19c0b /tmp/example.png
saved /tmp/example.png

$ wb show a3f19c0b
$ wb hide a3f19c0b
```

## Requirements

The install path is intentionally light: prebuilt binaries do not require Xcode or a Swift toolchain.

To run a prebuilt release:

- macOS 26.0 or newer
- No Xcode required
- No Swift toolchain required

To build from source:

- A Mac with macOS 26.0 or newer
- Xcode 26 or newer, with Swift 6.2 SDKs

## Build From Source

```bash
swift build
.build/debug/wb create
```

For a local debug binary at `./wb`:

```bash
./build.sh
./wb create
```

`build.sh` signs the final `./wb` binary by default using ad-hoc codesigning, so no Apple Developer ID is required. To use a specific local signing identity:

```bash
WB_CODESIGN_IDENTITY="wb local code signing" ./build.sh
```

Set `WB_CODESIGN=off` to skip signing for local debugging.

## Lint

```bash
./lint.sh
```

The linter is a Swift executable target and runs on both macOS and Linux.

## Agent Skill

This repo includes a standalone agent skill folder at [skill](skill). It contains the skill instructions plus an `install.sh` support script that installs `wb` through Homebrew when available, or through the standalone installer otherwise.

In this checkout, `.agents/skills/wb`, `.claude/skills/wb`, and `.grok/skills/wb` are symlinks to `skill/`, so each agent sees both files. In another project, use `install-skill.sh` from the install section to copy the folder into the local agent skill directories.

## Output

`wb` keeps structured CLI JSON compact by default. JSON is emitted on one line and omits fields that do not add information: `null`, most `false` values, empty strings, empty arrays, and empty objects. Error responses preserve `ok:false`. Raw `eval` results are printed as returned strings.

Commands avoid returning a full page snapshot unless explicitly asked. Use `wb <url>` or `wb <id> <url>` for a compact summary containing the browser ID, title, URL, loading/progress, action count, image count, full-document HTML byte count, and default page JSON byte count. Use `wb page <id>` when you need visible text, the full action list, and image URLs.

Browser IDs are random 8-character lowercase hex strings. Page snapshot text is markdown-like and includes inline links where possible. Page actions are compact by default and include a 1-based `index` for `click`, `fill`, and `submit`; internal IDs, CSS selectors, and tags are omitted unless requested. Image entries include a 1-based `index` and resolved URL. Use `wb page <id> --action-details` to include internal action IDs, or `wb page <id> --selectors` to include CSS selectors.

Navigation errors are emitted as JSON responses with `ok:false` and a nonzero exit status. When a browser exists, the error JSON includes its browser ID so it can still be shown, reused, or closed.

Use `wb page --help` to see filterable fields. Use `wb page <id> --fields title,url,imageCount,images,htmlBytes,jsonBytes` to print selected top-level fields.

## Commands

- `wb create`: create an empty browser and print its ID.
- `wb env`: print public metadata for the current `.wb` environment.
- `wb <url>`: create a browser, load the page, and print a compact summary.
- `wb <id> <url>`: load a page in an existing browser.
- `wb list`: print active and saved browser summaries as compact JSON.
- `wb close <id>`: close an active browser and delete any saved session for that ID.
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
- `wb eval <id> [--body] <javascript>`: evaluate a JavaScript expression, or run a raw JavaScript function body with `--body`, and print the result.
- `wb daemon <start|status|log|stop>`: advanced browser session controls.

Each command has its own help, for example `wb click --help` or `wb daemon --help`.

Browser IDs can be used across commands. If a saved browser is not currently active, `wb` resumes it automatically.

## Notes

Browsers persist between commands and are autosaved after creation, navigation, interactions, and JavaScript evaluation. Use `wb list` to find browser IDs, `wb page <id>` to inspect the current page, and `wb close <id>` when you are done.

Environment state is resolved in this order: `WB_DIR`, then `.wb` in the nearest parent git root, then `.wb` under the current directory. The `.wb/environment.json` file stores a stable environment UUID and the public sessions directory name. WebKit cookies, local storage, cache, and related website data are isolated per environment through that UUID with `WKWebsiteDataStore(forIdentifier:)`.

Treat `.wb/environment.json` as a local trust boundary. Copying or committing it intentionally reuses the same WebKit website data profile for that macOS user, so do not accept a tracked `.wb` directory from repositories you do not trust.

Migration note: older sessions created in a cwd-local `wb/` directory or a non-root `.wb` directory are not moved automatically. Set `WB_DIR` to that old directory when you need those sessions, or manually migrate the old contents into the new git-root `.wb`.

The `page` command refreshes the action list for the current document. If the page navigates or rerenders, run `wb page <id>` again before using action numbers from older output.

Coordinate commands use top-left origin coordinates in the current web content viewport and do not open a window. `screenshot` captures that same viewport, so agents can inspect the image and use matching coordinates for `click`, `press`, `drag`, `release`, and `scroll`. If the browser is already visible through `wb show`, the same page updates are visible there.

Browser dumps in `.wb/sessions` store resumable browser metadata, not full page text, image lists, or action details. Use `wb page <id>` for live page inspection when needed.

The `show` command attaches a native window to the same browser used by headless commands. While a browser window is visible, the daemon does not idle-exit. Use `wb hide <id>` or close the window to allow normal idle shutdown again.

Daemon logs are appended to `/tmp/wb-webpage-<uid>.log` by default. Use `wb daemon log` to print the exact path, or set `WB_LOG` to override it.
