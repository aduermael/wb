#!/usr/bin/env sh
set -eu

usage() {
  echo "Usage: ./release.sh <version> [--build-only|--publish-only] [--repo owner/name] [--tap-repo owner/name|--no-tap] [arm64|x86_64 ...]" >&2
  echo "Examples:" >&2
  echo "  ./release.sh 0.1.0" >&2
  echo "  ./release.sh 0.1.0 --build-only" >&2
  echo "  ./release.sh 0.1.0 --publish-only" >&2
  echo "  ./release.sh 0.1.0 --build-only arm64" >&2
  echo "  ./release.sh 0.1.0 --publish-only --no-tap" >&2
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
tap_repo="${WB_TAP_REPO:-aduermael/homebrew-tap}"
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
    --tap-repo)
      shift
      if [ "$#" -eq 0 ]; then
        die "--tap-repo requires owner/name."
      fi
      tap_repo="$1"
      ;;
    --tap-repo=*)
      tap_repo="${1#--tap-repo=}"
      ;;
    --no-tap)
      tap_repo=""
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

checksum_for_arch() {
  checksum_file="$dist/wb-macos-$1.tar.gz.sha256"
  awk '{print $1}' "$checksum_file"
}

write_homebrew_formula() {
  formula_path="$1"
  version="${tag#v}"
  arm_sha="$2"
  intel_sha="$3"

  cat > "$formula_path" <<EOF
class Wb < Formula
  desc "macOS web browser for agents"
  homepage "https://github.com/$repo"
  version "$version"

  depends_on :macos

  on_macos do
    depends_on macos: :tahoe
  end

  if Hardware::CPU.arm?
    url "https://github.com/$repo/releases/download/$tag/wb-macos-arm64.tar.gz"
    sha256 "$arm_sha"
  elsif Hardware::CPU.intel?
    url "https://github.com/$repo/releases/download/$tag/wb-macos-x86_64.tar.gz"
    sha256 "$intel_sha"
  end

  def install
    bin.install "wb"
  end

  test do
    assert_match "Usage:", shell_output("#{bin}/wb --help")
  end
end
EOF
}

update_homebrew_tap() {
  if [ -z "$tap_repo" ]; then
    return
  fi

  need_cmd awk
  need_cmd gh
  need_cmd git

  for required_arch in arm64 x86_64; do
    if [ ! -f "$dist/wb-macos-$required_arch.tar.gz.sha256" ]; then
      echo "Skipping Homebrew tap update; missing checksum for $required_arch." >&2
      return
    fi
  done

  arm_sha="$(checksum_for_arch arm64)"
  intel_sha="$(checksum_for_arch x86_64)"
  tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/wb-homebrew-tap.XXXXXX")"
  tap_dir="$tmpdir/homebrew-tap"

  (
    trap 'rm -rf "$tmpdir"' EXIT INT HUP TERM

    gh repo clone "$tap_repo" "$tap_dir"
    mkdir -p "$tap_dir/Formula"
    write_homebrew_formula "$tap_dir/Formula/wb.rb" "$arm_sha" "$intel_sha"

    if [ -z "$(git -C "$tap_dir" status --porcelain -- Formula/wb.rb)" ]; then
      echo "Homebrew tap $tap_repo already has wb $tag"
      exit 0
    fi

    git -C "$tap_dir" add Formula/wb.rb
    git -C "$tap_dir" commit -m "Update wb to $tag"
    git -C "$tap_dir" push origin HEAD
  )

  echo "Updated Homebrew tap $tap_repo for $tag"
}

require_release_git_state

case "$mode" in
  all)
    need_cmd gh
    build_release
    publish_release
    update_homebrew_tap
    ;;
  build)
    build_release
    ;;
  publish)
    publish_release
    update_homebrew_tap
    ;;
esac
