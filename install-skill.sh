#!/usr/bin/env sh
set -eu

repo="${WB_REPO:-aduermael/wb}"
ref="${WB_REF:-main}"
skill_name="${WB_SKILL_NAME:-wb}"
targets="${WB_SKILL_TARGETS:-codex claude grok}"
base_url="https://raw.githubusercontent.com/$repo/$ref/skill"

err() {
  printf '%s\n' "$*" >&2
}

have() {
  command -v "$1" >/dev/null 2>&1
}

target_path() {
  case "$1" in
    codex|agents|openai)
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

if [ -z "$targets" ]; then
  err "WB_SKILL_TARGETS is empty; provide at least one target such as codex, claude, or grok."
  exit 1
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
first_path=

for target in $targets; do
  dest=$(target_path "$target")
  parent=$(dirname "$dest")

  mkdir -p "$parent"

  if [ -L "$dest" ] && [ ! -d "$dest" ]; then
    rm "$dest"
  fi

  if [ -e "$dest" ] && [ ! -d "$dest" ]; then
    err "Cannot install skill at $dest because a non-directory file already exists there."
    exit 1
  fi

  mkdir -p "$dest"
  cp "$tmpdir/SKILL.md" "$dest/SKILL.md"
  cp "$tmpdir/install.sh" "$dest/install.sh"
  chmod 0755 "$dest/install.sh"

  [ -n "$first_path" ] || first_path="$dest"
  installed_paths="${installed_paths}
  $dest"
done

printf 'Installed wb skill:%s\n' "$installed_paths"

if [ "${WB_INSTALL_CLI:-0}" = "1" ] && [ -n "$first_path" ]; then
  sh "$first_path/install.sh"
else
  printf 'The skill will use %s/install.sh if the wb command is not available.\n' "$first_path"
fi
