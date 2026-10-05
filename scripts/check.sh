#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$repo_root"
if [[ -x bin/inspect-earbud ]]; then
  tool=("$repo_root/bin/inspect-earbud")
else
  tool=(/usr/bin/swift "$repo_root/tools/inspect-earbud.swift")
fi
"${tool[@]}" --help >/dev/null
"${tool[@]}" --self-test
/usr/bin/python3 tools/inspect_nvdm.py --self-test
/usr/bin/python3 tools/wrap_thumb.py --self-test

# Invalid writes must be rejected by argument validation, before Bluetooth starts.
for mode in --set-nvkey --peer-set-nvkey; do
  for args in '0xFB01 0 1' '0xFB03 255 0' '0xFC04 1 2'; do
    read -r key before after <<< "$args"
    if "${tool[@]}" SELF_TEST_NOT_A_DEVICE "$mode" "$key" "$before" "$after" >/dev/null 2>&1; then
      printf 'FAIL: an unreviewed write was accepted.\n' >&2
      exit 1
    else
      result=$?
      [[ "$result" -eq 2 ]] || { printf 'FAIL: expected usage rejection, got %s.\n' "$result" >&2; exit 1; }
    fi
  done
done
printf 'Offline checks passed, including six forbidden-write invocations. No device was contacted.\n'
