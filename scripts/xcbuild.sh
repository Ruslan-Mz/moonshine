#!/bin/sh
# The one way to build or test the Mac app (H1c; CLAUDE.md → Commands): `build` or `test`, or
# `summary` for the newest test result, nothing else, from the repository root. XcodeGen and xcodebuild run outside the sandbox, so locally this
# runs as the copy the guard installer took from main (`~/.config/moonshine/bin/xcbuild`, which
# clears the environment first), with the project check beside it, never the checkout's copies;
# CI runs the checkout's. Stops at the first failure:
# 1. the check of project.yml, the signing settings and the build tree (scripts/check-project-scripts.mjs);
# 2. MoonShine.xcodeproj removed, so nothing planted in it survives, and generated again;
# 3. the package pin: the generated project is not committed, so its Package.resolved would not be
#    either; the app's package graph is the Adapters package's, whose committed file pins it too;
# 4. xcodebuild with the fixed flags.
# Tests: node --test scripts/xcbuild.test.mjs
set -eu

fail() {
  echo "xcbuild: $1" >&2
  exit 2
}

[ $# -eq 1 ] || fail "usage: xcbuild build|test|summary"
case $1 in
  build | test | summary) ;;
  *) fail "usage: xcbuild build|test|summary" ;;
esac
here=$(cd "$(dirname "$0")" && pwd -P)
root=$(pwd -P)
[ -f "$root/project.yml" ] && [ ! -L "$root/project.yml" ] || fail "run it from the repository root, where project.yml is a file."

for file in xcbuild.sh check-project-scripts.mjs; do
  cmp -s "$here/$file" "$root/scripts/$file" ||
    echo "xcbuild: warning: the installed $file differs from this checkout's scripts/$file. Reinstall the guard after the change is merged (CLAUDE.md → Commands → Guard); the installed copy runs." >&2
done

if [ "$1" = summary ]; then
  # The newest test result, with no link on its path or inside it: the summary runs outside the
  # sandbox and takes no path, so it reads nothing outside the repository (PR #47 round 1).
  for dir in DerivedData DerivedData/Logs DerivedData/Logs/Test; do
    [ ! -L "$root/$dir" ] || fail "$dir is a symbolic link; no summary."
  done
  newest=
  for bundle in "$root"/DerivedData/Logs/Test/*.xcresult; do
    [ -e "$bundle" ] || [ -L "$bundle" ] || continue
    if [ -z "$newest" ] || [ "$bundle" -nt "$newest" ]; then newest=$bundle; fi
  done
  [ -n "$newest" ] || fail "no test results in DerivedData/Logs/Test; run xcbuild test first."
  if [ -L "$newest" ] || [ -n "$(find "$newest" -type l -print -quit)" ]; then
    fail "the newest result bundle is or holds a symbolic link; no summary."
  fi
  exec xcrun xcresulttool get test-results summary --path "$newest" --compact
fi

command -v node > /dev/null 2>&1 ||
  fail "node is not on PATH (the installed xcbuild names node's folder as found at install time); reinstall the guard after node's folder changes (CLAUDE.md → Commands → Guard)."
node "$here/check-project-scripts.mjs" "$root/project.yml"
rm -rf "$root/MoonShine.xcodeproj"
xcodegen generate --spec "$root/project.yml"
target=$root/MoonShine.xcodeproj/project.xcworkspace/xcshareddata/swiftpm
mkdir -p "$target"
cp "$root/Adapters/Package.resolved" "$target/Package.resolved"
exec xcodebuild -project MoonShine.xcodeproj -scheme MoonShineMac -destination platform=macOS,arch=arm64 \
  -derivedDataPath DerivedData -onlyUsePackageVersionsFromResolvedFile "$1"
