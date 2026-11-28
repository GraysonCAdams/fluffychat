#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Checks whether a compiled Seam build carries the dev control server, by
# looking for strings only the server's code holds in the AOT snapshot.
#
#   tools/devctl/check_stripped.sh <app.so | libapp.so | .apk | .aab> [--expect-present]
#
# Without --expect-present it fails when the server is in the binary, which
# is the check for any build made without --dart-define=SEAM_DEV_CONTROL=true
# (Play, Store and release builds). With it, it fails when the server is
# missing, which proves the check can see it at all. Windows keeps the
# snapshot in build/windows/x64/runner/<Mode>/data/app.so; an APK or AAB is
# unpacked for lib/*/libapp.so.
set -euo pipefail

target=${1:?usage: check_stripped.sh <app.so|libapp.so|apk|aab> [--expect-present]}
expect_present=false
[[ ${2:-} == --expect-present ]] && expect_present=true

# Literals from lib/utils/dev_control/dev_control.dart.
markers=('Dev control listening on' 'Requests from web pages are refused')

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

snapshots=()
case $target in
  *.apk | *.aab)
    unzip -q -o "$target" '*libapp.so' -d "$work"
    mapfile -t snapshots < <(find "$work" -name libapp.so)
    ;;
  *) snapshots=("$target") ;;
esac
[[ ${#snapshots[@]} -gt 0 ]] || { echo "no libapp.so in $target" >&2; exit 2; }

status=0
for snapshot in "${snapshots[@]}"; do
  found=0
  for marker in "${markers[@]}"; do
    if strings -n 6 "$snapshot" | grep -qF "$marker"; then
      found=$((found + 1))
    fi
  done
  if $expect_present; then
    if [[ $found -eq ${#markers[@]} ]]; then
      echo "present: $snapshot"
    else
      echo "MISSING ($found/${#markers[@]} markers): $snapshot" >&2
      status=1
    fi
  else
    if [[ $found -eq 0 ]]; then
      echo "stripped: $snapshot"
    else
      echo "DEV CONTROL PRESENT ($found/${#markers[@]} markers): $snapshot" >&2
      status=1
    fi
  fi
done
exit $status
