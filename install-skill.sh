#!/usr/bin/env sh
set -eu

repo="${WB_REPO:-aduermael/wb}"
ref="${WB_REF:-main}"
skill_name="${WB_SKILL_NAME:-wb}"
targets="${WB_SKILL_TARGETS:-}"
mode=install
install_cli="${WB_INSTALL_CLI:-0}"
base_url="https://raw.githubusercontent.com/$repo/$ref/skill"

err() {
  printf '%s\n' "$*" >&2
}

have() {
  command -v "$1" >/dev/null 2>&1
}

usage() {
  cat <<'USAGE'
Usage:
  install-skill.sh [--codex] [--claude] [--grok] [--all]
  install-skill.sh --auto-update-existing

Options:
  --codex                       Install .agents/skills/wb.
  --claude                      Install .claude/skills/wb.
  --grok                        Install .grok/skills/wb.
  --all                         Install all default agent targets.
  --target <name|path>          Install one named target or custom skill directory.
  --name <name>                 Use a skill folder name other than wb.
  --auto-update-existing        Update only existing wb skill folders; create nothing.
  --install-cli                 Run the bundled install.sh after installing the skill.
USAGE
}

add_target() {
  targets="${targets:+$targets }$1"
}

target_path() {
  case "$1" in
    codex)
      printf '.agents/skills/%s\n' "$skill_name"
      ;;
    claude)
      printf '.claude/skills/%s\n' "$skill_name"
      ;;
    grok)
      printf '.grok/skills/%s\n' "$skill_name"
      ;;
    *)
      printf '%s\n' "$1"
      ;;
  esac
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --codex)
      add_target codex
      ;;
    --claude)
      add_target claude
      ;;
    --grok)
      add_target grok
      ;;
    --all)
      targets="codex claude grok"
      ;;
    --target)
      shift
      if [ "$#" -eq 0 ]; then
        err "missing value after --target"
        exit 1
      fi
      add_target "$1"
      ;;
    --target=*)
      add_target "${1#*=}"
      ;;
    --name)
      shift
      if [ "$#" -eq 0 ]; then
        err "missing value after --name"
        exit 1
      fi
      skill_name="$1"
      ;;
    --name=*)
      skill_name="${1#*=}"
      ;;
    --auto-update-existing)
      mode=update-existing
      ;;
    --install-cli)
      install_cli=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      err "unknown option $1"
      usage >&2
      exit 1
      ;;
  esac
  shift
done

if [ -z "$targets" ]; then
  targets="codex claude grok"
fi

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/wb-skill-install.XXXXXX")"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT INT HUP TERM

script_dir=
case "$0" in
  */*) script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd) ;;
esac

if [ -n "$script_dir" ] && [ -f "$script_dir/skill/SKILL.md" ] && [ -f "$script_dir/skill/install.sh" ]; then
  cp "$script_dir/skill/SKILL.md" "$tmpdir/SKILL.md"
  cp "$script_dir/skill/install.sh" "$tmpdir/install.sh"
else
  if ! have curl; then
    err "Missing required command: curl"
    exit 1
  fi

  curl -fsSL "$base_url/SKILL.md" -o "$tmpdir/SKILL.md"
  curl -fsSL "$base_url/install.sh" -o "$tmpdir/install.sh"
fi

installed_paths=
updated_paths=
unchanged_paths=
first_path=

for target in $targets; do
  dest=$(target_path "$target")

  if [ "$mode" = update-existing ] && [ ! -f "$dest/SKILL.md" ]; then
    continue
  fi

  parent=$(dirname "$dest")
  mkdir -p "$parent"

  if [ -L "$dest" ] && [ ! -d "$dest" ]; then
    rm "$dest"
  fi

  if [ -e "$dest" ] && [ ! -d "$dest" ]; then
    err "Cannot install skill at $dest because a non-directory file already exists there."
    exit 1
  fi

  had_skill=0
  if [ -f "$dest/SKILL.md" ]; then
    had_skill=1
  fi

  mkdir -p "$dest"

  changed=0
  installer_changed=0
  if ! cmp -s "$tmpdir/SKILL.md" "$dest/SKILL.md" 2>/dev/null; then
    cp "$tmpdir/SKILL.md" "$dest/SKILL.md"
    changed=1
  fi
  if ! cmp -s "$tmpdir/install.sh" "$dest/install.sh" 2>/dev/null; then
    cp "$tmpdir/install.sh" "$dest/install.sh"
    installer_changed=1
    changed=1
  fi
  if [ "$installer_changed" -eq 1 ] || [ ! -x "$dest/install.sh" ]; then
    chmod 0755 "$dest/install.sh"
    changed=1
  fi

  [ -n "$first_path" ] || first_path="$dest"

  if [ "$changed" -eq 0 ]; then
    unchanged_paths="${unchanged_paths}
  $dest"
  elif [ "$had_skill" -eq 1 ]; then
    updated_paths="${updated_paths}
  $dest"
  else
    installed_paths="${installed_paths}
  $dest"
  fi
done

if [ -n "$installed_paths" ]; then
  printf 'Installed wb skill:%s\n' "$installed_paths"
fi
if [ -n "$updated_paths" ]; then
  printf 'Updated wb skill:%s\n' "$updated_paths"
fi
if [ -n "$unchanged_paths" ]; then
  printf 'wb skill already up to date:%s\n' "$unchanged_paths"
fi

if [ "$mode" = update-existing ] && [ -z "$first_path" ]; then
  printf 'No existing wb skill folders found; nothing installed.\n'
fi

if [ "$install_cli" = "1" ] && [ -n "$first_path" ]; then
  sh "$first_path/install.sh"
elif [ -n "$first_path" ]; then
  printf 'The skill will use %s/install.sh if the wb command is not available.\n' "$first_path"
fi
