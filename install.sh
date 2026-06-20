#!/usr/bin/env sh
set -eu

repo="${WB_REPO:-aduermael/wb}"
install_dir="${WB_INSTALL_DIR:-$HOME/.local/bin}"
version="${WB_VERSION:-latest}"

case "$(uname -s)" in
  Darwin)
    os="macos"
    ;;
  *)
    echo "wb prebuilt releases currently support macOS only." >&2
    exit 1
    ;;
esac

case "$(uname -m)" in
  arm64|aarch64)
    arch="arm64"
    ;;
  x86_64|amd64)
    arch="x86_64"
    ;;
  *)
    echo "Unsupported CPU architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

for cmd in curl tar; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    exit 1
  fi
done

asset="wb-$os-$arch.tar.gz"

if [ "$version" = "latest" ]; then
  url="https://github.com/$repo/releases/latest/download/$asset"
else
  case "$version" in
    v*) tag="$version" ;;
    *) tag="v$version" ;;
  esac
  url="https://github.com/$repo/releases/download/$tag/$asset"
fi

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/wb-install.XXXXXX")"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT INT HUP TERM

archive="$tmpdir/$asset"

echo "Downloading $asset from $repo..."
curl -fL "$url" -o "$archive"
tar -xzf "$archive" -C "$tmpdir"

if [ ! -f "$tmpdir/wb" ]; then
  echo "Release asset did not contain a wb binary." >&2
  exit 1
fi

mkdir -p "$install_dir"

if command -v install >/dev/null 2>&1; then
  install -m 0755 "$tmpdir/wb" "$install_dir/wb"
else
  cp "$tmpdir/wb" "$install_dir/wb"
  chmod 0755 "$install_dir/wb"
fi

echo "Installed wb to $install_dir/wb"

case ":$PATH:" in
  *":$install_dir:"*) ;;
  *) echo "Add $install_dir to PATH to run wb from any shell." ;;
esac
