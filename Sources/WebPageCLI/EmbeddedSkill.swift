/// Stores the agent skill files carried inside the wb binary for local skill
/// installation without requiring network access or a checkout.
import Foundation

enum EmbeddedSkill {
	static let skillText = #"""
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
		- Default typing speed is `--speed 2.0`; use `--speed 1.0` for the base delay speed.
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
		"""#

	static let installScriptText = #"""
		#!/usr/bin/env sh
		set -eu

		repo="${WB_REPO:-aduermael/wb}"
		formula="${WB_BREW_FORMULA:-aduermael/tap/wb}"
		npm_package="${WB_NPM_PACKAGE:-@aduermael_/wb}"
		install_url="https://raw.githubusercontent.com/$repo/main/install.sh"

		say() {
		  printf '%s\n' "$*"
		}

		err() {
		  printf '%s\n' "$*" >&2
		}

		have() {
		  command -v "$1" >/dev/null 2>&1
		}

		refresh_command_cache() {
		  hash -r 2>/dev/null || true
		}

		first_writable_path_dir() {
		  old_ifs=$IFS
		  IFS=:
		  for dir in ${PATH:-}; do
		    [ -n "$dir" ] || continue
		    if [ -d "$dir" ] && [ -w "$dir" ] && [ -x "$dir" ]; then
		      IFS=$old_ifs
		      printf '%s\n' "$dir"
		      return 0
		    fi
		  done
		  IFS=$old_ifs
		  return 1
		}

		choose_standalone_dir() {
		  if [ -n "${WB_INSTALL_DIR:-}" ]; then
		    printf '%s\n' "$WB_INSTALL_DIR"
		    return 0
		  fi

		  for dir in /usr/local/bin /opt/homebrew/bin; do
		    case ":${PATH:-}:" in
		      *":$dir:"*)
		        printf '%s\n' "$dir"
		        return 0
		        ;;
		    esac
		  done

		  if [ -n "${HOME:-}" ]; then
		    dir="$HOME/.local/bin"
		    case ":${PATH:-}:" in
		      *":$dir:"*)
		        printf '%s\n' "$dir"
		        return 0
		        ;;
		    esac
		  fi

		  printf '%s\n' "/usr/local/bin"
		}

		find_installed_wb() {
		  if have wb; then
		    command -v wb
		    return 0
		  fi

		  if have brew; then
		    brew_prefix="$(brew --prefix 2>/dev/null || true)"
		    if [ -n "$brew_prefix" ] && [ -x "$brew_prefix/bin/wb" ]; then
		      printf '%s\n' "$brew_prefix/bin/wb"
		      return 0
		    fi
		  fi

		  for candidate in /opt/homebrew/bin/wb /usr/local/bin/wb; do
		    if [ -x "$candidate" ]; then
		      printf '%s\n' "$candidate"
		      return 0
		    fi
		  done

		  if [ -n "${HOME:-}" ] && [ -x "$HOME/.local/bin/wb" ]; then
		    printf '%s\n' "$HOME/.local/bin/wb"
		    return 0
		  fi

		  if have npm; then
		    npm_prefix="$(npm prefix -g 2>/dev/null || true)"
		    if [ -n "$npm_prefix" ]; then
		      for candidate in \
		        "$npm_prefix/bin/wb" \
		        "$npm_prefix/lib/node_modules/$npm_package/npm/bin/wb"
		      do
		        if [ -x "$candidate" ]; then
		          printf '%s\n' "$candidate"
		          return 0
		        fi
		      done
		    fi
		  fi

		  return 1
		}

		print_path_instructions() {
		  installed="$1"
		  installed_dir=$(dirname "$installed")

		  err "wb is installed at $installed, but that directory is not on PATH."
		  err
		  err "For the current shell, run:"
		  err "  export PATH=\"$installed_dir:\$PATH\""
		  err
		  err "For future shells, add the same line to your shell profile."
		}

		ensure_wb_on_path() {
		  refresh_command_cache

		  if have wb; then
		    say "wb is available at $(command -v wb)"
		    return 0
		  fi

		  if ! installed="$(find_installed_wb)"; then
		    err "wb was not found after installation."
		    return 1
		  fi

		  if path_dir="$(first_writable_path_dir 2>/dev/null)" && [ ! -e "$path_dir/wb" ]; then
		    if ln -s "$installed" "$path_dir/wb" 2>/dev/null; then
		      refresh_command_cache
		      if have wb; then
		        say "Linked wb into $path_dir and found it at $(command -v wb)"
		        return 0
		      fi
		    fi
		  fi

		  print_path_instructions "$installed"
		  return 1
		}

		install_standalone() {
		  if ! have curl; then
		    err "Missing required command: curl"
		    err "Install Homebrew or curl, then rerun this support script."
		    exit 1
		  fi

		  install_dir="$(choose_standalone_dir)"
		  say "Installing wb with the standalone installer into $install_dir..."
		  curl -fsSL "$install_url" | env WB_REPO="$repo" WB_VERSION="${WB_VERSION:-}" WB_INSTALL_DIR="$install_dir" sh
		}

		install_npm() {
		  if ! have npm; then
		    return 1
		  fi

		  package_spec="$npm_package"
		  if [ -n "${WB_VERSION:-}" ] && [ "$WB_VERSION" != "latest" ]; then
		    case "$WB_VERSION" in
		      v*) version="${WB_VERSION#v}" ;;
		      *) version="$WB_VERSION" ;;
		    esac
		    package_spec="$npm_package@$version"
		  fi

		  say "Installing wb with npm..."
		  npm install -g "$package_spec"
		}

		if have wb; then
		  say "wb is already available at $(command -v wb)"
		  exit 0
		fi

		case "$(uname -s)" in
		  Darwin) ;;
		  *)
		    err "wb currently supports macOS only."
		    exit 1
		    ;;
		esac

		if have brew; then
		  say "Installing wb with Homebrew..."
		  if ! brew install "$formula"; then
		    err "Homebrew install failed; trying npm."
		    if ! install_npm; then
		      err "npm install unavailable or failed; trying the standalone installer."
		      install_standalone
		    fi
		  fi
		else
		  if ! install_npm; then
		    install_standalone
		  fi
		fi

		ensure_wb_on_path
		"""#

	static var skillData: Data {
		Data((skillText + "\n").utf8)
	}

	static var installScriptData: Data {
		Data((installScriptText + "\n").utf8)
	}
}
