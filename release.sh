#!/usr/bin/env sh
set -eu

usage() {
  echo "Usage: ./release.sh <version> [arm64|x86_64 ...]" >&2
  echo "Example: ./release.sh 0.1.0" >&2
}

if [ "$#" -lt 1 ]; then
  usage
  exit 1
fi

input_version="$1"
shift

case "$input_version" in
  v*) tag="$input_version" ;;
  *) tag="v$input_version" ;;
esac

if [ "$tag" = "v" ]; then
  usage
  exit 1
fi

if [ "$(uname -s)" != "Darwin" ]; then
  echo "release.sh must be run on macOS." >&2
  exit 1
fi

for cmd in swift gh git tar shasum; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    exit 1
  fi
done

if [ -n "$(git status --porcelain --untracked-files=normal)" ]; then
  echo "Worktree must be clean before releasing." >&2
  git status --short
  exit 1
fi

branch="$(git rev-parse --abbrev-ref HEAD)"
if [ "$branch" = "HEAD" ]; then
  echo "Cannot release from a detached HEAD." >&2
  exit 1
fi
if [ "$branch" != "main" ]; then
  echo "Releases must be cut from main. Current branch: $branch" >&2
  exit 1
fi

repo="${WB_REPO:-aduermael/wb}"
archs="$*"
if [ -z "$archs" ]; then
  archs="arm64 x86_64"
fi

dist="dist/$tag"
rm -rf "$dist"
mkdir -p "$dist"

for arch in $archs; do
  case "$arch" in
    arm64|x86_64) ;;
    *)
      echo "Unsupported release architecture: $arch" >&2
      exit 1
      ;;
  esac

  echo "Building wb for macOS $arch..."
  swift build -c release --arch "$arch"

  bin_dir="$(swift build -c release --arch "$arch" --show-bin-path)"
  bin="$bin_dir/wb"
  if [ ! -x "$bin" ]; then
    echo "Build did not produce an executable wb at $bin" >&2
    exit 1
  fi

  asset_dir="$dist/$arch"
  mkdir -p "$asset_dir"
  cp "$bin" "$asset_dir/wb"
  strip "$asset_dir/wb" 2>/dev/null || true

  archive_name="wb-macos-$arch.tar.gz"
  archive="$dist/$archive_name"
  tar -C "$asset_dir" -czf "$archive" wb
  (cd "$dist" && shasum -a 256 "$archive_name" > "$archive_name.sha256")
  rm -rf "$asset_dir"
done

git push origin "$branch"

head_sha="$(git rev-parse HEAD)"
if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
  tag_sha="$(git rev-list -n 1 "$tag")"
  if [ "$tag_sha" != "$head_sha" ]; then
    echo "Tag $tag already exists and does not point at HEAD." >&2
    exit 1
  fi
else
  git tag -a "$tag" -m "$tag"
fi

git push origin "$tag"

if gh release view "$tag" --repo "$repo" >/dev/null 2>&1; then
  gh release upload "$tag" "$dist"/*.tar.gz "$dist"/*.sha256 --repo "$repo" --clobber
else
  gh release create "$tag" "$dist"/*.tar.gz "$dist"/*.sha256 --repo "$repo" --title "$tag" --notes "macOS binaries for wb $tag" --verify-tag
fi

echo "Released $repo $tag"
