#!/usr/bin/env bash
# Checks the shared RonisHub.lua (one minimap button and options window for
# all Roni's addons). Run from the repository root:
#
#   bash .github/scripts/check-hub.sh [base-ref]
#
# 1. Every addon folder (Ronis*/ with a .toc) has RonisHub.lua.
# 2. All copies are byte-for-byte identical.
# 3. Every addon's .toc loads RonisHub.lua.
# 4. With a base ref: if RonisHub.lua changed since then, its VERSION went
#    up. Players with an older copy in another addon would otherwise keep
#    running the old code, because the newest VERSION wins.
set -u
fail=0
err() { echo "::error::$*"; fail=1; }

ref=""
for toc in Ronis*/Ronis*.toc; do
  dir=${toc%%/*}
  [ "$toc" = "$dir/$dir.toc" ] || continue
  hub="$dir/RonisHub.lua"
  if [ ! -f "$hub" ]; then
    err "$dir has no RonisHub.lua (copy it from another Roni's addon)"
    continue
  fi
  tr -d '\r' < "$toc" | grep -qxF 'RonisHub.lua' || err "$toc does not load RonisHub.lua"
  if [ -z "$ref" ]; then
    ref=$hub
  elif ! cmp -s "$ref" "$hub"; then
    err "$hub differs from $ref; all copies must be identical"
    diff -u "$ref" "$hub" | head -20
  fi
done
[ -n "$ref" ] || err "no Roni's addon found (run from the repository root)"

version() { sed -n 's/^local VERSION = \([0-9][0-9]*\).*/\1/p'; }

base=${1:-}
if [ -n "$base" ] && [ -n "$ref" ] && git cat-file -e "$base^{commit}" 2>/dev/null; then
  old=$(git show "$base:$ref" 2>/dev/null || true)
  if [ -n "$old" ] && [ "$old" != "$(cat "$ref")" ]; then
    ov=$(printf '%s\n' "$old" | version)
    nv=$(version < "$ref")
    if [ -z "$nv" ]; then
      err "$ref has no 'local VERSION = <number>' line"
    elif [ -n "$ov" ] && [ "$nv" -le "$ov" ]; then
      err "RonisHub.lua changed since $base but VERSION is still $nv; raise it"
    fi
  fi
fi

[ $fail -eq 0 ] && echo "RonisHub.lua: all copies identical and loaded${base:+, version checked against $base}"
exit $fail
