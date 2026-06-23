#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd "$(dirname "$0")/.." && pwd)

usage() {
  echo "Usage: scripts/prepare-npm-package.sh <version>" >&2
  echo "Example: scripts/prepare-npm-package.sh 0.1.2" >&2
}

die() {
  echo "$1" >&2
  exit 1
}

if [ "$#" -ne 1 ]; then
  usage
  exit 1
fi

case "$1" in
  v*) version="${1#v}" ;;
  *) version="$1" ;;
esac

case "$version" in
  *[!0-9A-Za-z.+-]*|"")
    die "Invalid npm version: $version"
    ;;
esac

if ! command -v node >/dev/null 2>&1; then
  die "Missing required command: node"
fi

node - "$version" <<'NODE'
const version = process.argv[2];
const semverPattern = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/;
if (!semverPattern.test(version)) {
  console.error(`Invalid npm semver version: ${version}`);
  process.exit(1);
}
NODE

tag="v$version"
stage="$script_dir/dist/$tag/npm"

rm -rf "$stage"
mkdir -p "$stage/npm/bin" "$stage/npm/scripts" "$stage/skill"

cp "$script_dir/package.json" "$stage/package.json"
cp "$script_dir/README.md" "$stage/README.md"
cp "$script_dir/LICENSE" "$stage/LICENSE"
cp "$script_dir/install-skill.sh" "$stage/install-skill.sh"
cp "$script_dir/npm/bin/wb.js" "$stage/npm/bin/wb.js"
cp "$script_dir/npm/scripts/install.js" "$stage/npm/scripts/install.js"
cp "$script_dir/skill/SKILL.md" "$stage/skill/SKILL.md"
cp "$script_dir/skill/install.sh" "$stage/skill/install.sh"
chmod 0755 "$stage/install-skill.sh" "$stage/npm/bin/wb.js" "$stage/npm/scripts/install.js"
chmod 0755 "$stage/skill/install.sh"

node - "$version" "$stage/package.json" <<'NODE'
const fs = require("node:fs");
const version = process.argv[2];
const packagePath = process.argv[3];
const packageJson = JSON.parse(fs.readFileSync(packagePath, "utf8"));
packageJson.version = version;
fs.writeFileSync(`${packagePath}.tmp`, `${JSON.stringify(packageJson, null, 2)}\n`);
fs.renameSync(`${packagePath}.tmp`, packagePath);
NODE

echo "Prepared npm package at $stage"
echo "Inspect it with: npm pack --dry-run $stage"
echo "Publish it through release.sh with: ./release.sh $version --npm-only"
echo "Publish it with: npm publish $stage --access public"
