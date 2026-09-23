#!/usr/bin/env bash
#
# sync-from-beta.sh — refresh alpha's add-on source from ha-addons-beta.
#
# Beta is the source of truth for the add-on. This copies beta's librecoach/
# over alpha's, keeping alpha's config.yaml and alpha-only tooling, then
# re-registers that tooling. Review the result with git before committing.
#
# Usage: alpha-notes/sync-from-beta.sh [path-to-ha-addons-beta]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALPHA="$(cd "$SCRIPT_DIR/.." && pwd)"
BETA="${1:-$(cd "$ALPHA/.." && pwd)/ha-addons-beta}"

SRC="$BETA/librecoach/"
DST="$ALPHA/librecoach/"

# Alpha-owned paths, relative to librecoach/. rsync neither overwrites nor
# deletes them.
ALPHA_ONLY=(
  config.yaml
  librecoach_ble/devices/hughes_probe.py
  librecoach_ble/tests/test_hughes_probe.py
)

[[ -d "$SRC" ]] || { echo "ERROR: beta source missing: $SRC" >&2; exit 1; }
[[ -d "$DST" ]] || { echo "ERROR: alpha add-on missing: $DST" >&2; exit 1; }

RSYNC_OPTS=(
  -a --checksum --delete --itemize-changes
  --exclude='__pycache__/'
  --exclude='.pytest_cache/'
  --exclude='*.pyc'
)
for path in "${ALPHA_ONLY[@]}"; do
  RSYNC_OPTS+=(--exclude="/$path")
done

echo "Syncing $SRC [$(git -C "$BETA" rev-parse --abbrev-ref HEAD) $(git -C "$BETA" rev-parse --short HEAD)]"
echo "     -> $DST"
rsync "${RSYNC_OPTS[@]}" "$SRC" "$DST"

# Beta's devices/__init__.py does not know about the probe; re-register it.
echo
echo "probe registration ..."
python3 - "$DST/librecoach_ble/devices/__init__.py" <<'PYEOF'
import sys
path = sys.argv[1]
text = open(path).read()
anchor = "from .hughes import HughesHandler\n"
hook = '''
# Alpha builds replace the Hughes handler with its protocol probe, which lives
# only in ha-addons-alpha.
try:
    from .hughes_probe import HughesProbeHandler as HughesHandler
except ModuleNotFoundError as exc:
    if exc.name != f"{__name__}.hughes_probe":
        raise
'''
if "hughes_probe" in text:
    print("  ✓ already registered")
elif anchor not in text:
    print("  ⚠️  could not find the HughesHandler import — register the probe by hand")
else:
    open(path, "w").write(text.replace(anchor, anchor + hook, 1))
    print("  ✓ registered")
PYEOF

echo
echo "config.yaml check (alpha may differ only on 'version:' and 'image:') ..."
python3 - "$SRC/config.yaml" "$DST/config.yaml" <<'PYEOF'
import difflib, sys
beta = open(sys.argv[1]).read().splitlines()
alpha = open(sys.argv[2]).read().splitlines()
offenders = [
    line for line in difflib.unified_diff(alpha, beta, lineterm="")
    if line[:1] in "+-" and line[:2] not in ("++", "--")
    and line[1:].split(":", 1)[0].strip() not in ("version", "image")
]
if offenders:
    print("  ⚠️  port these beta config.yaml changes to alpha by hand:")
    for line in offenders:
        print("     ", line)
else:
    print("  ✓ only version/image differ")
PYEOF

newest="$(grep -oP '^### \K[0-9]+\.[0-9]+\.[0-9]+' "$DST/CHANGELOG.md" | head -1)"
echo
echo "alpha config.yaml version: $(grep -oP '^version: "\K[^"]+' "$DST/config.yaml")"
echo "newest CHANGELOG entry:    $newest  (use $newest-alpha.<n>, raising <n> each build)"
