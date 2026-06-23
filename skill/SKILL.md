---
name: wb-browser
description: Use the installed wb CLI for persistent browser automation with compact page JSON and screenshots.
---

# wb Browser Automation

## Principles

- Use the installed `wb` command directly.
- Browser IDs are persistent. Reuse the returned ID until the task is done, then close it when appropriate.
- Prefer fast commands. URL opens return after page HTML readiness while resources may keep loading.
- Add `--wait-resources` or a short `--resource-timeout <seconds>` only when loaded resources matter.
- After navigation, interaction, scroll, or rerender, refresh with `wb page <id>` before reusing actions.
- Run `wb --help` or `wb <command> --help` for exact syntax and advanced flags.

## Core Workflow

```bash
id=$(wb https://example.com | jq -r '.browser')
wb page "$id" --fields title,url,actions
wb click "$id" 1
wb page "$id" --fields title,url,text,actions
wb close "$id"
```

If a browser already exists, find or reuse it:

```bash
wb list
wb "$id" https://example.com
```

## Command Map

- Start/load: `wb <url>`, `wb <id> <url>`
- Inspect: `wb list`, `wb page <id> [--fields ...] [--selectors|--action-details]`
- Interact: `wb click`, `wb type`, `wb fill`, `wb submit`
- Coordinates: `wb click <id> <x> <y>`, `wb press`, `wb drag`, `wb release`, `wb scroll`
- View/capture: `wb show`, `wb hide`, `wb resize`, `wb screenshot`
- Script: `wb eval`
- Admin: `wb env`, `wb install-skill`, `wb update`, `wb version`, `wb daemon ...`, `wb close`

## Typing

- Always try `wb type` first for inputs, textareas, and contenteditable fields.
- Defaults are native backend plus natural rhythm. Do not add flags unless you need a fallback or comparison.
- Native/natural sends AppKit key events through the persistent browser with short word and punctuation pauses.
- Use `--backend js` only when native typing is unavailable.
- Use `--rhythm flat` only when deterministic timing matters.
- Use `fill` for deliberate direct assignment, simple controls such as selects, or fallback.

## Page JSON

- Use `--fields` to keep output small.
- Common fields: `title,url,actions,text,resources,resourceCount,htmlBytes,jsonBytes`.
- Loading fields: `progress,loading,resourcesLoading`.
- Actions use 1-based indexes. Request details only when IDs, tags, types, or selectors are needed.
- Omitted values mean defaults.

```bash
wb page "$id" --fields title,url,actions
wb page "$id" --fields title,url,resources
```

## Extraction

- Prefer `wb page --fields ...` before reaching for JavaScript.
- Use `wb eval <id> --body` for small, targeted JSON extraction from DOM structure.
- Return bounded arrays and strings from `eval`; avoid full `outerHTML` or full body text unless explicitly needed.

```bash
wb eval "$id" --body '
  const rows = [...document.querySelectorAll("table tr")]
    .slice(0, 50)
    .map(tr => [...tr.cells].map(td => td.innerText.trim()))
    .filter(row => row.length);
  return JSON.stringify(rows);
' | jq -c '.[]'
```

## Screenshots And Coordinates

- Screenshots, coordinate clicks, gestures, and scroll use the same viewport with top-left origin coordinates.
- Use screenshots for canvas/custom controls, visual state, or when actions are missing.
- Default screenshots wait briefly for resources and visual settling. Increase resource timeout only when needed.

```bash
wb screenshot "$id" /tmp/page.png
wb click "$id" 640 420
wb scroll "$id" 640 780 0 700
```

## Live Preview

- Use `wb show <id>` for user handoff, credentials, MFA, CAPTCHA, passkeys, SSO, or visual debugging.
- Continue with the same browser ID after handoff, then run `wb page <id>` before acting again.
- Use `wb hide <id>` when the visible window is no longer useful; it keeps session state.

## Error Handling

- If JSON returns `ok:false`, inspect `error`, `browser`, and any included page summary before retrying.
- If action indexes changed or appear stale, run `wb page <id>` again.
- If `wb` is unavailable, run the bundled `install.sh` next to this skill.
