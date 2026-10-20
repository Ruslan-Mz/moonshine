#!/usr/bin/env bash
# The generated `MoonShine.xcodeproj` is not committed, so its `Package.resolved` would not be
# either, and the app would build with whatever GRDB and Yams are newest. The app's package
# graph is the Adapters package's graph, so its committed `Package.resolved` pins the app too.
# Run after `xcodegen generate`; build with `-onlyUsePackageVersionsFromResolvedFile`.
set -euo pipefail

cd "$(dirname "$0")/.."
if [ ! -d MoonShine.xcodeproj ]; then
  echo "pin-app-packages: run xcodegen generate first" >&2
  exit 2
fi
target=MoonShine.xcodeproj/project.xcworkspace/xcshareddata/swiftpm
mkdir -p "$target"
cp Adapters/Package.resolved "$target/Package.resolved"
