#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/direct
arch="$(uname -m)"
flags=(-O -swift-version 5 -target "${arch}-apple-macosx14.0")
swiftc "${flags[@]}" -parse-as-library -whole-module-optimization \
  -emit-module -emit-object -module-name UsageCore Sources/UsageCore/*.swift \
  -o .build/direct/UsageCore.o -emit-module-path .build/direct/UsageCore.swiftmodule
swiftc "${flags[@]}" -parse-as-library -I .build/direct \
  Sources/ChatGPTUsage/App.swift .build/direct/UsageCore.o -o .build/direct/ChatGPTUsage
if [[ "${1:-}" == "--test" ]]; then
  swiftc "${flags[@]}" -I .build/direct Tests/UsageVerifier/main.swift \
    .build/direct/UsageCore.o -o .build/direct/UsageVerifier
  .build/direct/UsageVerifier
fi
printf 'Built .build/direct/ChatGPTUsage (%s)\n' "$arch"
