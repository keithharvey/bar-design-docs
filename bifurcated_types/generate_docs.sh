#!/usr/bin/env bash
set -e

SPRING_DIR=/Users/danielharvey/code/spring
SITE_DIR="$SPRING_DIR/doc/site"
LUA_LIBRARY_DIR="$SPRING_DIR/rts/Lua/library"
OUT_DIR=/Users/danielharvey/code/bar-design-docs/bifurcated_types/doc_output
EMMYLUA_VERSION=0.8.2

mkdir -p "$OUT_DIR"

echo "=== Step 1: extract Lua docs ==="
node /Users/danielharvey/code/lua-doc-extractor/dist/src/cli.js \
  --src "$SPRING_DIR/rts/{Lua,Rml/SolLua}/**/*.cpp" \
  --dest "$LUA_LIBRARY_DIR/generated" \
  --repo "https://github.com/beyond-all-reason/RecoilEngine/blob/master" 2>&1 | tail -20

echo ""
echo "=== Generated Lua files ==="
ls "$LUA_LIBRARY_DIR/generated"

echo ""
echo "=== Step 2: install emmylua_doc_cli (if needed) ==="
if ! command -v emmylua_doc_cli &>/dev/null; then
  cargo install emmylua_doc_cli --version "$EMMYLUA_VERSION"
fi

echo ""
echo "=== Step 3: emit JSON ==="
emmylua_doc_cli -f json -i "$LUA_LIBRARY_DIR" -o "$OUT_DIR"
echo "JSON written to $OUT_DIR"

echo ""
echo "=== Step 4: generate Markdown ==="
ruby "$SITE_DIR/docgen/generator.rb" \
  --doc="$OUT_DIR/doc.json" \
  --out="$OUT_DIR/lua-api.md"

echo ""
echo "=== Step 5: copy into Hugo site ==="
cp "$OUT_DIR/lua-api.md" "$SITE_DIR/content/docs/lua-api/_index.md"
cp "$OUT_DIR/doc.json" "$SITE_DIR/data/doc.json"
echo "Copied to $SITE_DIR"

echo ""
echo "=== Output files ==="
ls "$OUT_DIR"
echo ""
echo "Preview (first 80 lines of lua-api.md):"
head -80 "$OUT_DIR/lua-api.md"
