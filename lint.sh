#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)

swift run --quiet --package-path "$script_dir" wblint "$script_dir"
