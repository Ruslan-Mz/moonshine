#!/usr/bin/env bash
# ADR-0001: MoonShineCore imports no UI, scripting, store, calendar or YAML framework.
# Exits 1 and lists the offending lines when one does. Usage: scripts/check-core-imports.sh [dir]
set -euo pipefail

dir="${1:-MoonShineCore}"
forbidden='AppKit|SwiftUI|OSAKit|GRDB|EventKit|Yams'
# Plain, attributed (`@testable`, `@preconcurrency`) and kind-qualified (`import struct X.Y`) forms.
pattern="^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*import[[:space:]]+((typealias|struct|class|enum|protocol|let|var|func)[[:space:]]+)?($forbidden)([^A-Za-z0-9_]|$)"

if matches=$(grep -rnE --include='*.swift' --exclude-dir=.build "$pattern" "$dir"); then
  echo "MoonShineCore must not import $forbidden (ADR-0001):"
  echo "$matches"
  exit 1
fi
echo "Core imports: clean"
