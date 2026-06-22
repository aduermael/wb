#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)

swift format lint \
	--configuration "$script_dir/.swift-format" \
	--parallel \
	--recursive \
	--strict \
	"$script_dir/Package.swift" \
	"$script_dir/Sources" \
	"$script_dir/Tests" \
	"$script_dir/Tools"

swift run --quiet --package-path "$script_dir" -Xswiftc -warnings-as-errors wblint "$script_dir"
