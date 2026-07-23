#!/usr/bin/env bash
# Build the standalone Crush Windows x64 setup.exe (no Tauri/NSIS required).
# Requires: zig on PATH (https://ziglang.org/ or npm i -g @oven/zig)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="${CRUSH_RELEASE_VERSION:-${CRUSH_VERSION:-}}"
if [[ -z "$VERSION" ]]; then
  VERSION="$(python3 - <<'PY'
import json
print(json.load(open("src-tauri/tauri.conf.json"))["version"])
PY
)"
fi

OUT_DIR="${OUT_DIR:-$ROOT/dist}"
OUT_NAME="${OUT_NAME:-crush_${VERSION}_x64-setup.exe}"
mkdir -p "$OUT_DIR" installer/assets

cp -f src-tauri/icons/icon.ico installer/assets/icon.ico
cp -f src-tauri/open_game.bat installer/assets/open_game.bat
cp -f src-tauri/libraries/vcruntime140.dll installer/assets/vcruntime140.dll
cp -f src-tauri/libraries/vcruntime140_1.dll installer/assets/vcruntime140_1.dll

if ! command -v zig >/dev/null 2>&1; then
  echo "error: zig not found on PATH" >&2
  echo "Install Zig, or: npm install -g @oven/zig @oven/zig-linux-x64" >&2
  exit 1
fi

echo "Building Windows installer $OUT_NAME with $(zig version)..."
zig build-exe installer/main.zig \
  -target x86_64-windows-gnu \
  -OReleaseSmall \
  -femit-bin="$OUT_DIR/$OUT_NAME" \
  --subsystem windows

rm -f "$OUT_DIR/${OUT_NAME}.obj" installer/main.obj 2>/dev/null || true

echo "Built: $OUT_DIR/$OUT_NAME ($(wc -c <"$OUT_DIR/$OUT_NAME") bytes)"
sha256sum "$OUT_DIR/$OUT_NAME" | tee "$OUT_DIR/${OUT_NAME}.sha256"
