#!/usr/bin/env bash
# ADR-0001: MoonShineCore imports none of the modules listed in `forbidden` (UI, scripting,
# store, calendar and YAML frameworks; Cocoa, Carbon and Quartz because they re-export AppKit).
# Exits 1 and lists the offending lines when one does; exits 2 when the folder cannot be
# searched. Usage: scripts/check-core-imports.sh [dir]
set -euo pipefail

dir="${1:-MoonShineCore}"
forbidden='AppKit|Cocoa|Carbon|Quartz|SwiftUI|SwiftUICore|OSAKit|GRDB|EventKit|Yams'
# An import at line start or after `;`; any mix of attributes, with or without arguments
# (`@testable`, `@_spi(X)`), and access modifiers (`public import`); an optional symbol kind
# (`import struct AppKit.NSColor`); block comments before the import and before the name; a
# name in backticks.
prefix='(@[A-Za-z_]+([[:space:]]*\([^)]*\))?|public|package|internal|fileprivate|private)'
comment='(/\*[^*]*\*/[[:space:]]*)*'
kind='((typealias|struct|class|enum|protocol|let|var|func)[[:space:]]+)?'
module='`?('"$forbidden"')`?'
pattern="(^|;)[[:space:]]*$comment($prefix[[:space:]]+)*import[[:space:]]+$comment$kind$comment$module([^A-Za-z0-9_]|$)"

if [ ! -d "$dir" ]; then
  echo "check-core-imports: $dir is not a folder" >&2
  exit 2
fi
status=0
matches=$(grep -rnE --include='*.swift' --exclude-dir=.build "$pattern" "$dir") || status=$?
case $status in
  0)
    echo "MoonShineCore must not import $forbidden (ADR-0001):"
    echo "$matches"
    exit 1
    ;;
  1) echo "Core imports: clean" ;;
  *)
    echo "check-core-imports: grep failed (exit $status)" >&2
    exit 2
    ;;
esac
