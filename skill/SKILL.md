---
name: wb-browser
description: Use the installed wb CLI to browse web pages, inspect compact page JSON, click/fill/submit actions, use viewport coordinates, scroll, take screenshots, and extract structured data efficiently without returning full page snapshots.
---

# wb Browser Automation

## Operating Model

- Use the installed `wb` command directly.
- Browsers persist between commands. Reuse the returned browser ID until the task is done, then close it when appropriate.
- Start with compact commands. `wb <url>` and interaction commands return summaries with `browser`, `title`, `url`, `progress`, `actions`, `resources`, `htmlBytes`, and `jsonBytes`.
- Use `wb page <id>` only when you need visible text, action details, or loaded resource URLs.
- After any navigation, click, fill, submit, scroll, or rerender, refresh with `wb page <id>` before reusing action numbers.

## Basic Workflow

```bash
id=$(wb https://example.com | jq -r '.browser')
wb page "$id" --fields title,url,actions
wb click "$id" 1
wb page "$id" --fields title,url,text,actions
wb close "$id"
```

If a browser is already available:

```bash
wb list
wb "$id" https://example.com
```

## Live Preview And Credential Handoff

Use `wb show "$id"` when the user asks to watch progress, when visual confirmation helps, or when credentials, MFA, CAPTCHA, passkeys, or SSO block automation. The user can complete the step in the native browser window; do not ask them to paste secrets into chat.

After the user completes the handoff, continue with the same browser ID and refresh state with `wb page "$id"` before acting again. Use `wb hide "$id"` when the visible window is no longer useful; hiding does not close the browser or clear session state.

## Commands

- `wb create`: create an empty browser and print its ID.
- `wb env`: print public metadata for the current `.wb` environment.
- `wb <url> [--wait-resources] [--resource-timeout <seconds>]`: create a browser, load the page, and print a compact summary. `--resource-timeout` implies `--wait-resources`; max 100 seconds.
- `wb <id> <url> [--wait-resources] [--resource-timeout <seconds>]`: load a page in an existing browser. `--resource-timeout` implies `--wait-resources`; max 100 seconds.
- `wb list`: list active and saved browsers as compact JSON.
- `wb close <id>`: close the browser and delete any saved session for that ID.
- `wb show <id>` / `wb hide <id>`: show or hide a lightweight browser window.
- `wb resize <id> [<width> <height>]`: resize the browser window, or reset it to 800x600 when no size is provided.
- `wb screenshot <id> <path.png|path.jpg> [--resource-timeout <seconds>] [--capture-delay <seconds>]`: wait for resources, pause briefly for visual settling, then capture the current viewport. `--resource-timeout` is capped at 100 seconds; `--capture-delay` defaults to 0.3 seconds and accepts 0 to disable.
- `wb page <id> [--fields <list>] [--selectors|--action-details]`: print page JSON.
- `wb click <id> <action>`: click a page action by 1-based index or action ID.
- `wb click <id> <x> <y>`: click viewport coordinates.
- `wb press|drag|release <id> <x> <y>`: perform pointer gestures with top-left origin viewport coordinates.
- `wb scroll <id> <x> <y> <deltaX> <deltaY>`: scroll the nearest scrollable element at a viewport coordinate. Positive `deltaY` scrolls down.
- `wb fill <id> <action> <text>`: set input, textarea, select, or contenteditable content.
- `wb submit <id> <action>`: submit the nearest form or click the action if no form exists.
- `wb eval <id> [--body] <javascript>`: evaluate JavaScript and print the returned value.
- `wb daemon <start|status|log|stop>`: inspect or control the browser daemon.

Run `wb <command> --help` when command syntax is uncertain.

URL opens return when the page HTML is ready. Add `--wait-resources` when the task depends on loaded images, scripts, styles, JSON, or fetch results. `--resource-timeout` implies that wait for opens and is capped at 100 seconds. Screenshots wait for resources by default, then use a 0.3 second capture delay for visual settling.

## Page JSON

`wb` emits compact one-line JSON. Fields with default values are omitted; treat omitted fields as defaults when filtering.

Top-level `wb page` fields are:

```text
actions,browser,htmlBytes,jsonBytes,loading,progress,resourceCount,resources,resourcesLoading,text,title,url
```

The returned `resources` array is capped at 250 entries. Use `resourceCount` for the total discovered resource count.

Use `--fields` to request only what is needed:

```bash
wb page "$id" --fields title,url,jsonBytes
wb page "$id" --fields actions
wb page "$id" --fields title,url,resources
```

Default actions include `index`, `kind`, `text`, optional `href`, and optional `disabled`. Use `--selectors` only when CSS selectors are needed. Use `--action-details` only when internal action IDs, tags, types, and selectors are needed.

## Efficient JSON Parsing

- Filter at the source with `--fields` before using `jq`.
- Avoid pretty-printing or storing full page JSON in shell variables. Pipe directly from `wb` to `jq`.
- Prefer compact row output with `jq -c` and raw scalar output with `jq -r`.
- Use known structure when filtering: actions are in `.actions[]`; resources are in `.resources[]`; visible text is in `.text`.
- Because omitted values are common, use defaults such as `(.disabled // false)`, `(.href // "")`, and `(.text // "")`.
- Use `jsonBytes` to decide whether a fuller snapshot is safe to request.

Find an enabled action by label:

```bash
idx=$(
  wb page "$id" --fields actions |
    jq -r '.actions[]
      | select(((.disabled // false) | not) and ((.text // "") | test("sign in|continue"; "i")))
      | .index' |
    head -n 1
)
```

List compact links without returning page text or resources:

```bash
wb page "$id" --fields actions |
  jq -c '.actions[]
    | select(.kind == "link")
    | {index, text: (.text // ""), href: (.href // "")}'
```

Extract image resource URLs only:

```bash
wb page "$id" --fields resources |
  jq -r '.resources[]? | select(.type == "image") | .url'
```

When output is still too large after `--fields`, use streaming filters that match path shape instead of materializing the whole document:

```bash
wb page "$id" --fields resources |
  jq --stream -r 'select(.[0][0] == "resources" and .[0][2] == "url") | .[1]'
```

## Targeted Extraction With JavaScript

Use `wb eval` for structured extraction when `wb page` would return too much data or when the needed data is hidden in DOM structure. Return small JSON strings and parse them with `jq`.

```bash
wb eval "$id" --body '
  const rows = [...document.querySelectorAll("table tr")]
    .slice(0, 50)
    .map(tr => [...tr.cells].map(td => td.innerText.trim()))
    .filter(row => row.length);
  return JSON.stringify(rows);
' | jq -c '.[]'
```

For action discovery that depends on DOM attributes:

```bash
wb eval "$id" --body '
  const items = [...document.querySelectorAll("a,button,input,textarea,select")]
    .map((el, i) => ({
      i,
      tag: el.tagName.toLowerCase(),
      text: (el.innerText || el.value || el.getAttribute("aria-label") || "").trim(),
      href: el.href || "",
      name: el.getAttribute("name") || ""
    }))
    .filter(item => item.text || item.href || item.name)
    .slice(0, 100);
  return JSON.stringify(items);
' | jq -c '.[]'
```

Avoid returning `document.documentElement.outerHTML`, full `document.body.innerText`, or large unbounded arrays unless the user explicitly needs a full dump.

## Screenshots And Coordinates

Screenshots, coordinate clicks, pointer gestures, and scroll all use the same current viewport with top-left origin coordinates.

```bash
wb screenshot "$id" /tmp/page.png
wb click "$id" 640 420
wb scroll "$id" 640 780 0 700
wb press "$id" 400 500
wb drag "$id" 700 500
wb release "$id" 700 500
```

Use screenshots when visual layout matters, when a canvas/custom control is not represented in `actions`, or when scrolling/clicking by coordinates is more reliable than DOM actions.

## Interaction Guidance

- Prefer action indexes from `wb page --fields actions` over coordinate clicks.
- Use `fill` for form controls, then `submit` on the same action or a nearby submit action.
- Use coordinate clicks for canvas, maps, drag handles, or controls missing from `.actions`.
- Use scroll before extracting more content from infinite-scroll pages; then refresh `wb page`.
- If a command returns JSON with `ok:false`, read `error`, `browser`, and any included page summary before retrying.

## Install Fallback

Assume `wb` is installed. If the command is unavailable, run the bundled `install.sh` support script next to this `SKILL.md`; it tries Homebrew first, then npm, then the standalone release installer. Continue after `wb` runs normally.
