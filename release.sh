#!/usr/bin/env sh
set -eu

usage() {
  echo "Usage: ./release.sh <version> [--build-only|--publish-only] [--repo owner/name] [arm64|x86_64 ...]" >&2
  echo "Examples:" >&2
  echo "  ./release.sh 0.1.0" >&2
  echo "  ./release.sh 0.1.0 --build-only" >&2
  echo "  ./release.sh 0.1.0 --publish-only" >&2
  echo "  ./release.sh 0.1.0 --build-only arm64" >&2
}

die() {
  echo "$1" >&2
  exit 1
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    die "Missing required command: $1"
  fi
}

set_mode() {
  if [ "$mode" != "all" ] && [ "$mode" != "$1" ]; then
    die "Choose only one of --build-only or --publish-only."
  fi
  mode="$1"
}

mode="all"
repo="${WB_REPO:-aduermael/wb}"
input_version=""
archs=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --build-only)
      set_mode "build"
      ;;
    --publish-only)
      set_mode "publish"
      ;;
    --repo)
      shift
      if [ "$#" -eq 0 ]; then
        die "--repo requires owner/name."
      fi
      repo="$1"
      ;;
    --repo=*)
      repo="${1#--repo=}"
      ;;
    arm64|x86_64)
      archs="${archs}${archs:+ }$1"
      ;;
    --*)
      die "Unknown flag: $1"
      ;;
    *)
      if [ -n "$input_version" ]; then
        die "Unexpected argument: $1"
      fi
      input_version="$1"
      ;;
  esac
  shift
done

if [ -z "$input_version" ]; then
  usage
  exit 1
fi

case "$input_version" in
  v*) tag="$input_version" ;;
  *) tag="v$input_version" ;;
esac

if [ "$tag" = "v" ]; then
  usage
  exit 1
fi

if [ -z "$archs" ]; then
  archs="arm64 x86_64"
fi

dist="dist/$tag"

require_release_git_state() {
  need_cmd git

  if [ -n "$(git status --porcelain --untracked-files=normal)" ]; then
    echo "Worktree must be clean before releasing." >&2
    git status --short
    exit 1
  fi

  branch="$(git rev-parse --abbrev-ref HEAD)"
  if [ "$branch" = "HEAD" ]; then
    die "Cannot release from a detached HEAD."
  fi
  if [ "$branch" != "main" ]; then
    die "Releases must be cut from main. Current branch: $branch"
  fi
}

validate_archs() {
  for arch in $archs; do
    case "$arch" in
      arm64|x86_64) ;;
      *) die "Unsupported release architecture: $arch" ;;
    esac
  done
}

build_release() {
  if [ "$(uname -s)" != "Darwin" ]; then
    die "The build phase must be run on macOS."
  fi

  need_cmd swift
  need_cmd tar
  need_cmd shasum
  validate_archs

  rm -rf "$dist"
  mkdir -p "$dist"

  for arch in $archs; do
    echo "Building wb for macOS $arch..."
    swift build -c release --arch "$arch"

    bin_dir="$(swift build -c release --arch "$arch" --show-bin-path)"
    bin="$bin_dir/wb"
    if [ ! -x "$bin" ]; then
      die "Build did not produce an executable wb at $bin"
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

  echo "Built release assets in $dist"
}

ensure_tag() {
  head_sha="$(git rev-parse HEAD)"

  if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    tag_sha="$(git rev-list -n 1 "$tag")"
    if [ "$tag_sha" != "$head_sha" ]; then
      die "Tag $tag already exists and does not point at HEAD."
    fi
    return
  fi

  if git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null 2>&1; then
    git fetch origin "refs/tags/$tag:refs/tags/$tag"
    tag_sha="$(git rev-list -n 1 "$tag")"
    if [ "$tag_sha" != "$head_sha" ]; then
      die "Remote tag $tag already exists and does not point at HEAD."
    fi
    return
  fi

  git tag -a "$tag" -m "$tag"
}

publish_release() {
  need_cmd gh
  validate_archs

  release_files=""
  for arch in $archs; do
    asset="$dist/wb-macos-$arch.tar.gz"
    checksum="$asset.sha256"
    if [ ! -f "$asset" ]; then
      die "Missing release asset: $asset"
    fi
    if [ ! -f "$checksum" ]; then
      die "Missing release checksum: $checksum"
    fi
    release_files="$release_files $asset $checksum"
  done

  git push origin main
  ensure_tag
  git push origin "refs/tags/$tag"

  if gh release view "$tag" --repo "$repo" >/dev/null 2>&1; then
    gh release upload "$tag" $release_files --repo "$repo" --clobber
  else
    gh release create "$tag" $release_files --repo "$repo" --title "$tag" --notes "macOS binaries for wb $tag" --verify-tag
  fi

  echo "Released $repo $tag"
}

require_release_git_state

case "$mode" in
  all)
    need_cmd gh
    build_release
    publish_release
    ;;
  build)
    build_release
    ;;
  publish)
    publish_release
    ;;
esac
