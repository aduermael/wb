#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)

swift format format \
	--configuration "$script_dir/.swift-format" \
	--in-place \
	--parallel \
	--recursive \
	"$script_dir/Package.swift" \
	"$script_dir/Sources" \
	"$script_dir/Tests" \
	"$script_dir/Tools"
