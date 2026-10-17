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
  Sources/ChatGPTUsage/*.swift .build/direct/UsageCore.o -o .build/direct/ChatGPTUsage
if [[ "${1:-}" == "--test" ]]; then
  swiftc "${flags[@]}" -I .build/direct Tests/UsageVerifier/main.swift \
    .build/direct/UsageCore.o -o .build/direct/UsageVerifier
  .build/direct/UsageVerifier
  for verifier in ProviderVerifier ClaudeVerifier; do
    if [[ -f "Tests/$verifier/main.swift" ]]; then
      swiftc "${flags[@]}" -I .build/direct "Tests/$verifier/main.swift" .build/direct/UsageCore.o -o ".build/direct/$verifier"
      ".build/direct/$verifier"
    fi
  done
  swiftc "${flags[@]}" Sources/ChatGPTUsage/UsageBridge.swift Tests/BridgeVerifier/main.swift -o .build/direct/BridgeVerifier
  .build/direct/BridgeVerifier
  if [[ -d browser-extension/tests ]]; then
    command -v node >/dev/null || { echo "Node.js is required for browser extension tests." >&2; exit 1; }
    node --test browser-extension/tests/*.test.*
  fi
  swiftc "${flags[@]}" -D LAYOUT_TEST -parse-as-library -I .build/direct \
    Sources/ChatGPTUsage/*.swift Tests/PopupVerifier/PopupVerifier.swift \
    .build/direct/UsageCore.o -o .build/direct/PopupVerifier
  .build/direct/PopupVerifier
fi
printf 'Built .build/direct/ChatGPTUsage (%s)\n' "$arch"
