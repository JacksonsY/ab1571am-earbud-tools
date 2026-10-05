#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$repo_root"
mkdir -p bin
# Keep assertions active so the distributed executable can run its real self-test.
# Prefix maps prevent the builder's local source path from leaking into the executable.
/usr/bin/swiftc -Onone -assert-config Debug -module-name EarbudInterop \
  -file-prefix-map "$repo_root=." -debug-prefix-map "$repo_root=." \
  tools/inspect-earbud.swift -o bin/inspect-earbud
bin/inspect-earbud --self-test
printf 'Built bin/inspect-earbud for this Mac. No Bluetooth operation was performed.\n'
