# wb Documentation

## Operational Notes

Browsers persist between commands and are autosaved after creation, navigation, interactions, and JavaScript evaluation. Use `wb list` to find browser IDs, `wb page <id>` to inspect the current page, and `wb close <id>` when you are done.

Environment state is resolved in this order: `WB_DIR`, then `.wb` in the nearest parent git root, then `.wb` under the current directory. The `.wb/environment.json` file stores a stable environment UUID and the public sessions directory name. WebKit cookies, local storage, cache, and related website data are isolated per environment through that UUID with `WKWebsiteDataStore(forIdentifier:)`.

Treat `.wb/environment.json` as a local trust boundary. Copying or committing it intentionally reuses the same WebKit website data profile for that macOS user, so do not accept a tracked `.wb` directory from repositories you do not trust.

Migration note: older sessions created in a cwd-local `wb/` directory or a non-root `.wb` directory are not moved automatically. Set `WB_DIR` to that old directory when you need those sessions, or manually migrate the old contents into the new git-root `.wb`.

The `page` command refreshes the action list for the current document. If the page navigates or rerenders, run `wb page <id>` again before using action numbers from older output.

Use `wb type <id> <action> <text>` for text entry in inputs, textareas, and contenteditable elements. It focuses the element, clears existing content, enters characters with key/input/change events, and uses short randomized delays between keys so form validation and JavaScript listeners can react. Use `wb fill` when direct value assignment is intentional, such as selecting a `<select>` value or bypassing typing for a simple control.

URL opens return when the page HTML is ready by default. Use `--wait-resources` to wait for scripts, styles, images, and fetches. `--resource-timeout <seconds>` adjusts that wait, implies `--wait-resources`, and is capped at 100 seconds.

`wb page` resource entries are capped at 250 items to keep JSON output bounded. `resourceCount` reports the total discovered resources, which may be larger than the returned `resources` array.

Coordinate commands use top-left origin coordinates in the current web content viewport and do not open a window. `screenshot` waits for resources by default, pauses 0.3 seconds for visual settling, then captures that same viewport, so agents can inspect the image and use matching coordinates for `click`, `press`, `drag`, `release`, and `scroll`. Use `--capture-delay <seconds>` to adjust that final pause, or 0 to disable it. If the browser is already visible through `wb show`, the same page updates are visible there.

Browser dumps in `.wb/sessions` store resumable browser metadata, not full page text, resource lists, or action details. Use `wb page <id>` for live page inspection when needed.

The `show` command attaches a native 800x600 window to the same browser used by headless commands. Use `wb resize <id> <width> <height>` to resize it, or `wb resize <id>` to reset it to 800x600. While a browser window is visible, the daemon does not idle-exit. Use `wb hide <id>` or close the window to allow normal idle shutdown again.

Daemon logs are appended to `/tmp/wb-webpage-<uid>.log` by default. Use `wb daemon log` to print the exact path, or set `WB_LOG` to override it.
