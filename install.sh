#!/usr/bin/env sh
set -eu

repo="${WB_REPO:-aduermael/wb}"
install_url="https://raw.githubusercontent.com/$repo/main/install.sh"
install_dir="${WB_INSTALL_DIR:-/usr/local/bin}"
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

install_binary() {
  src="$1"
  dest="$2"

  if command -v install >/dev/null 2>&1; then
    install -m 0755 "$src" "$dest"
  else
    cp "$src" "$dest"
    chmod 0755 "$dest"
  fi
}

sudo_install_binary() {
  src="$1"
  dest="$2"

  if command -v install >/dev/null 2>&1; then
    sudo install -m 0755 "$src" "$dest"
  else
    sudo cp "$src" "$dest"
    sudo chmod 0755 "$dest"
  fi
}

print_permission_help() {
  echo "Could not write to $install_dir." >&2
  echo >&2
  if [ "$install_dir" = "/usr/local/bin" ]; then
    echo "To install to /usr/local/bin with admin permissions:" >&2
    echo "  curl -fsSL $install_url | sudo sh" >&2
    echo >&2
    echo "Or choose a user-writable install directory:" >&2
    echo "  curl -fsSL $install_url | env WB_INSTALL_DIR=\$HOME/.local/bin sh" >&2
  else
    echo "Choose a writable install directory with WB_INSTALL_DIR, for example:" >&2
    echo "  curl -fsSL $install_url | env WB_INSTALL_DIR=\$HOME/.local/bin sh" >&2
  fi
}

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

if ! mkdir -p "$install_dir" 2>/dev/null || ! install_binary "$tmpdir/wb" "$install_dir/wb" 2>/dev/null; then
  if [ "$install_dir" = "/usr/local/bin" ] && command -v sudo >/dev/null 2>&1 && [ -r /dev/tty ]; then
    printf "Installing to /usr/local/bin requires admin permissions. Use sudo? [y/N] " >/dev/tty
    IFS= read -r answer </dev/tty || answer=""
    case "$answer" in
      y|Y|yes|YES)
        sudo mkdir -p "$install_dir"
        sudo_install_binary "$tmpdir/wb" "$install_dir/wb"
        ;;
      *)
        print_permission_help
        exit 1
        ;;
    esac
  else
    print_permission_help
    exit 1
  fi
fi

echo "Installed wb to $install_dir/wb"

case ":$PATH:" in
  *":$install_dir:"*) ;;
  *) echo "Add $install_dir to PATH to run wb from any shell." ;;
esac
