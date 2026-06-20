---
name: wb-browser
description: Use the wb CLI to browse web pages, inspect compact page JSON, click/fill/submit actions, use viewport coordinates, scroll, take screenshots, and extract structured data efficiently without loading full pages.
---

# wb Browser Automation

Use this skill when a task requires browsing or interacting with web content through the local `wb` CLI.

## Operating Model

- Prefer `wb` when it is on `PATH`; use `./wb` only when the repo provides a local binary and `wb` is unavailable.
- Browsers persist between commands. Reuse the returned browser ID until the task is done, then close it when appropriate.
- Start with compact commands. `wb <url>` and interaction commands return summaries with `browser`, `title`, `url`, `progress`, `actions`, `images`, `htmlBytes`, and `jsonBytes`.
- Use `wb page <id>` only when you need visible text, action details, or image URLs.
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

## Commands

- `wb create`: create an empty browser and print its ID.
- `wb <url>`: create a browser, load the page, and print a compact summary.
- `wb <id> <url>`: load a page in an existing browser.
- `wb list`: list active and dumped browsers as compact JSON.
- `wb close <id>`: close the browser and delete any dumped session for that ID.
- `wb dump <id>`: save the browser so it can be resumed later.
- `wb show <id>` / `wb hide <id>`: show or hide a lightweight browser window.
- `wb screenshot <id> <path.png|path.jpg>`: capture the current viewport.
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

## Page JSON

`wb` emits compact one-line JSON. Empty strings, empty arrays, empty objects, `null`, and most `false` values are omitted. Treat omitted fields as their zero value when filtering.

Top-level `wb page` fields are:

```text
actions,browser,htmlBytes,imageCount,images,jsonBytes,loading,progress,text,title,url
```

Use `--fields` to request only what is needed:

```bash
wb page "$id" --fields title,url,jsonBytes
wb page "$id" --fields actions
wb page "$id" --fields title,url,images
```

Default actions include `index`, `kind`, `text`, optional `href`, and optional `disabled`. Use `--selectors` only when CSS selectors are needed. Use `--action-details` only when internal action IDs, tags, types, and selectors are needed.

## Efficient JSON Parsing

- Filter at the source with `--fields` before using `jq`.
- Avoid pretty-printing or storing full page JSON in shell variables. Pipe directly from `wb` to `jq`.
- Prefer compact row output with `jq -c` and raw scalar output with `jq -r`.
- Use known structure when filtering: actions are in `.actions[]`; images are in `.images[]`; visible text is in `.text`.
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

List compact links without loading page text or images:

```bash
wb page "$id" --fields actions |
  jq -c '.actions[]
    | select(.kind == "link")
    | {index, text: (.text // ""), href: (.href // "")}'
```

Extract image URLs only:

```bash
wb page "$id" --fields images |
  jq -r '.images[]?.url'
```

When output is still too large after `--fields`, use streaming filters that match path shape instead of materializing the whole document:

```bash
wb page "$id" --fields images |
  jq --stream -r 'select(.[0][0] == "images" and .[0][2] == "url") | .[1]'
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

Use screenshots when visual layout matters, when a canvas/custom control is not represented in `actions`, or when scrolling/clicking by coordinates is more reliable than DOM actions. Use `wb show "$id"` only when a visible native window helps observe behavior.

## Interaction Guidance

- Prefer action indexes from `wb page --fields actions` over coordinate clicks.
- Use `fill` for form controls, then `submit` on the same action or a nearby submit action.
- Use coordinate clicks for canvas, maps, drag handles, or controls missing from `.actions`.
- Use scroll before extracting more content from infinite-scroll pages; then refresh `wb page`.
- If a command returns JSON with `ok:false`, read `error`, `browser`, and any included page summary before retrying.
