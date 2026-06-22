#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)

swift run --package-path "$script_dir" -Xswiftc -enable-testing -Xswiftc -warnings-as-errors wblint-tests

if [ "$(uname -s)" = "Darwin" ]; then
	swift run --package-path "$script_dir" -Xswiftc -enable-testing -Xswiftc -warnings-as-errors wb-tests
fi
