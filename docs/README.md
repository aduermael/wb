# wb Documentation

## Operational Notes

Browsers persist between commands and are autosaved after creation, navigation, interactions, and JavaScript evaluation. Use `wb list` to find browser IDs, `wb page <id>` to inspect the current page, and `wb close <id>` when you are done.

Environment state is resolved in this order: `WB_DIR`, then `.wb` in the nearest parent git root, then `.wb` under the current directory. The `.wb/environment.json` file stores a stable environment UUID and the public sessions directory name. WebKit cookies, local storage, cache, and related website data are isolated per environment through that UUID with `WKWebsiteDataStore(forIdentifier:)`.

Treat `.wb/environment.json` as a local trust boundary. Copying or committing it intentionally reuses the same WebKit website data profile for that macOS user, so do not accept a tracked `.wb` directory from repositories you do not trust.

Migration note: older sessions created in a cwd-local `wb/` directory or a non-root `.wb` directory are not moved automatically. Set `WB_DIR` to that old directory when you need those sessions, or manually migrate the old contents into the new git-root `.wb`.

The `page` command refreshes the action list for the current document. If the page navigates or rerenders, run `wb page <id>` again before using action numbers from older output.

Coordinate commands use top-left origin coordinates in the current web content viewport and do not open a window. `screenshot` captures that same viewport, so agents can inspect the image and use matching coordinates for `click`, `press`, `drag`, `release`, and `scroll`. If the browser is already visible through `wb show`, the same page updates are visible there.

Browser dumps in `.wb/sessions` store resumable browser metadata, not full page text, image lists, or action details. Use `wb page <id>` for live page inspection when needed.

The `show` command attaches a native window to the same browser used by headless commands. While a browser window is visible, the daemon does not idle-exit. Use `wb hide <id>` or close the window to allow normal idle shutdown again.

Daemon logs are appended to `/tmp/wb-webpage-<uid>.log` by default. Use `wb daemon log` to print the exact path, or set `WB_LOG` to override it.
