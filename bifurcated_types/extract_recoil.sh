OUT_DIR=/Users/danielharvey/code/bar-design-docs/bifurcated_types/recoil
node /Users/danielharvey/code/lua-doc-extractor/dist/src/cli.js \
  --src "/Users/danielharvey/code/spring/rts/{Lua,Rml/SolLua}/**/*.cpp" \
  --dest "$OUT_DIR" \
  --repo "https://github.com/beyond-all-reason/RecoilEngine/blob/master" 2>&1 | tail -20 && echo "" && echo "=== Output files ===" && ls "$OUT_DIR" && echo "OUT_DIR=$OUT_DIR"