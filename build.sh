#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
. "$script_dir/scripts/codesign-wb.sh"

swift build
cp .build/debug/wb wb
wb_sign_binary wb
