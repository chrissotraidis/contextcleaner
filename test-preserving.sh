#!/bin/bash
set -euo pipefail
source_dir="$(cd "$(dirname "$0")" && pwd)"
output="${1:?Supply a NEW test output directory; fixtures will be retained}"
if [ -e "$output" ]; then echo "Refusing existing destination: $output" >&2; exit 1; fi
mkdir -p "$output"
cd "$source_dir"
common=(Sources/Planner.swift Sources/Contents.swift Sources/Domain.swift Sources/Classifier.swift Sources/Store.swift Sources/Inventory.swift Sources/Activity.swift Sources/Coverage.swift Sources/Design.swift Sources/OverviewData.swift Sources/Model.swift)
for suite in Core Detail ScanLimit Planner Discovery Overview; do
  inputs=("${common[@]}")
  if [ "$suite" = Overview ]; then inputs=(Sources/Domain.swift Sources/Contents.swift Sources/Classifier.swift Sources/Inventory.swift Sources/OverviewData.swift Sources/Coverage.swift); fi
  swiftc -swift-version 5 -O -target arm64-apple-macos14.0 -parse-as-library "${inputs[@]}" "Tests/${suite}Tests.swift" -framework SwiftUI -framework AppKit -framework Charts -o "$output/$suite" > "$output/$suite-build.log" 2>&1
  "$output/$suite" "$output/$suite-fixtures" > "$output/$suite.log" 2>&1
  tail -n 1 "$output/$suite.log"
done
