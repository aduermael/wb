#!/usr/bin/env sh
set -eu

swift build
cp .build/debug/wb wb
