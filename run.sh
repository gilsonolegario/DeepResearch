#!/bin/bash
# Build + compilar strings + run (substitui swift run direto)
# O SPM não compila .xcstrings → .strings; sem isso Bundle.module dá fatalError.
set -euo pipefail
cd "$(dirname "$0")"

swift build --skip-update -c release 2>&1 | tail -3

BUNDLE=".build/arm64-apple-macosx/release/DeepResearch_DeepResearch.bundle"
xcrun xcstringstool compile \
  Sources/DeepResearch/Resources/Localizable.xcstrings \
  --output-directory "$BUNDLE" \
  --format stringsAndStringsdict 2>/dev/null

exec swift run --skip-build -c release DeepResearch
