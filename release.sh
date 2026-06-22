#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
. "$script_dir/scripts/codesign-wb.sh"

usage() {
  echo "Usage: ./release.sh <version> [--build-only|--publish-only|--tap-only|--npm-only] [--repo owner/name] [--tap-repo owner/name|--no-tap] [--no-npm] [--force-tag] [arm64|x86_64 ...]" >&2
  echo "Examples:" >&2
  echo "  ./release.sh 0.1.0" >&2
  echo "  ./release.sh 0.1.0 --build-only" >&2
  echo "  ./release.sh 0.1.0 --publish-only" >&2
  echo "  ./release.sh 0.1.0 --tap-only" >&2
  echo "  ./release.sh 0.1.0 --npm-only" >&2
  echo "  ./release.sh 0.1.0 --publish-only --force-tag" >&2
  echo "  ./release.sh 0.1.0 --build-only arm64" >&2
  echo "  ./release.sh 0.1.0 --publish-only --no-tap --no-npm" >&2
  echo "" >&2
  echo "Signing environment:" >&2
  echo "  WB_CODESIGN_IDENTITY  Signing identity. Defaults to '-' for ad-hoc signing." >&2
  echo "  WB_CODESIGN=off       Skip binary signing." >&2
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
    die "Choose only one of --build-only, --publish-only, --tap-only, or --npm-only."
  fi
  mode="$1"
}

mode="all"
repo="${WB_REPO:-aduermael/wb}"
tap_repo="${WB_TAP_REPO:-aduermael/homebrew-tap}"
publish_npm=1
force_tag=0
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
    --tap-only)
      set_mode "tap"
      ;;
    --npm-only)
      set_mode "npm"
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
    --no-npm)
      publish_npm=0
      ;;
    --force-tag)
      force_tag=1
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

if [ "$mode" = "npm" ] && [ "$publish_npm" = "0" ]; then
  die "Cannot combine --npm-only with --no-npm."
fi

case "$mode:$force_tag" in
  build:1|tap:1|npm:1)
    die "--force-tag can only be used when publishing the GitHub release."
    ;;
esac

dist="dist/$tag"
version_file="$script_dir/Sources/WebPageCLI/Version.swift"
version_backup=""

restore_release_version() {
  if [ -n "$version_backup" ] && [ -f "$version_backup" ]; then
    cp "$version_backup" "$version_file"
    rm -f "$version_backup"
    version_backup=""
  fi
}

stamp_release_version() {
  version="$1"
  version_backup="$(mktemp "${TMPDIR:-/tmp}/wb-version.XXXXXX")"
  cp "$version_file" "$version_backup"
  trap restore_release_version EXIT INT HUP TERM
  escaped_version="$(printf '%s\n' "$version" | sed 's/[\/&]/\\&/g')"
  tmp_file="$version_file.tmp"
  sed "s/static let current = \"[^\"]*\"/static let current = \"$escaped_version\"/" "$version_file" > "$tmp_file"
  mv "$tmp_file" "$version_file"
}

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
  stamp_release_version "${tag#v}"

  for arch in $archs; do
    echo "Building wb for macOS $arch..."
    swift build -c release --product wb --arch "$arch" -Xswiftc -warnings-as-errors

    bin_dir="$(swift build -c release --product wb --arch "$arch" --show-bin-path)"
    bin="$bin_dir/wb"
    if [ ! -x "$bin" ]; then
      die "Build did not produce an executable wb at $bin"
    fi

    asset_dir="$dist/$arch"
    mkdir -p "$asset_dir"
    cp "$bin" "$asset_dir/wb"
    strip "$asset_dir/wb" 2>/dev/null || true
    wb_sign_binary "$asset_dir/wb"

    archive_name="wb-macos-$arch.tar.gz"
    archive="$dist/$archive_name"
    tar -C "$asset_dir" -czf "$archive" wb
    (cd "$dist" && shasum -a 256 "$archive_name" > "$archive_name.sha256")
    rm -rf "$asset_dir"
  done

  restore_release_version
  echo "Built release assets in $dist"
}

ensure_tag() {
  head_sha="$(git rev-parse HEAD)"

  if [ "$force_tag" = "1" ]; then
    git tag -f -a "$tag" -m "$tag" "$head_sha"
    return
  fi

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

push_release_tag() {
  if [ "$force_tag" = "1" ]; then
    git push --force origin "refs/tags/$tag"
  else
    git push origin "refs/tags/$tag"
  fi
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
  push_release_tag

  if gh release view "$tag" --repo "$repo" >/dev/null 2>&1; then
    gh release upload "$tag" $release_files --repo "$repo" --clobber
  else
    gh release create "$tag" $release_files --repo "$repo" --title "$tag" --notes "macOS binaries for wb $tag" --verify-tag
  fi

  echo "Released $repo $tag"
}

checksum_for_arch() {
  checksum_file="$dist/wb-macos-$1.tar.gz.sha256"
  if [ -f "$checksum_file" ]; then
    awk '{print $1}' "$checksum_file"
    return
  fi

  release_checksum_for_arch "$1"
}

release_checksum_for_arch() {
  arch="$1"
  asset_name="wb-macos-$arch.tar.gz"
  checksum_name="$asset_name.sha256"

  asset_present="$(gh release view "$tag" --repo "$repo" --json assets --jq ".assets[] | select(.name == \"$asset_name\") | .name" 2>/dev/null || true)"
  if [ -z "$asset_present" ]; then
    die "Missing release asset in $repo $tag: $asset_name"
  fi

  digest="$(gh release view "$tag" --repo "$repo" --json assets --jq ".assets[] | select(.name == \"$asset_name\") | .digest" 2>/dev/null || true)"
  case "$digest" in
    sha256:*)
      printf '%s\n' "${digest#sha256:}"
      return
      ;;
    ""|null)
      ;;
    *)
      die "Unexpected digest for $asset_name in $repo $tag: $digest"
      ;;
  esac

  tmp_checksum_dir="$(mktemp -d "${TMPDIR:-/tmp}/wb-release-checksum.XXXXXX")"
  (
    trap 'rm -rf "$tmp_checksum_dir"' EXIT INT HUP TERM
    gh release download "$tag" --repo "$repo" --pattern "$checksum_name" --dir "$tmp_checksum_dir" >/dev/null
    if [ ! -f "$tmp_checksum_dir/$checksum_name" ]; then
      die "Missing checksum asset in $repo $tag: $checksum_name"
    fi
    awk '{print $1}' "$tmp_checksum_dir/$checksum_name"
  )
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

publish_npm_package() {
  if [ "$publish_npm" = "0" ]; then
    return
  fi

  need_cmd awk
  need_cmd gh
  need_cmd node
  need_cmd npm

  release_checksum_for_arch arm64 >/dev/null
  release_checksum_for_arch x86_64 >/dev/null

  "$script_dir/scripts/prepare-npm-package.sh" "${tag#v}"

  npm_stage="$script_dir/$dist/npm"
  package_name="$(node -e "process.stdout.write(require(process.argv[1]).name)" "$npm_stage/package.json")"
  package_version="${tag#v}"

  npm pack --dry-run "$npm_stage" >/dev/null

  published_version="$(npm view "$package_name@$package_version" version 2>/dev/null || true)"
  if [ "$published_version" = "$package_version" ]; then
    echo "npm package $package_name@$package_version is already published"
    return
  fi

  npm publish "$npm_stage" --access public
  echo "Published npm package $package_name@$package_version"
}

case "$mode" in
  all)
    require_release_git_state
    need_cmd gh
    build_release
    publish_release
    update_homebrew_tap
    publish_npm_package
    ;;
  build)
    require_release_git_state
    build_release
    ;;
  publish)
    require_release_git_state
    publish_release
    update_homebrew_tap
    publish_npm_package
    ;;
  tap)
    require_release_git_state
    update_homebrew_tap
    ;;
  npm)
    publish_npm_package
    ;;
esac
