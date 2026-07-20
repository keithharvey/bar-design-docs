# Editor Architecture: the MVP of the Real Thing

The mission editor track, separated from the hello_pawns demo so the demo can't inherit its scope. Companion to mission_authoring_dsl.md (the public design) — this is the build plan. The architecture is parser-first: the UI model is extracted from a real, lossless parse of the file, and every read and write goes through that model. The one economy: we don't hand-author the lexer/parser layer — the DSL is syntactically plain Lua, so we take Lua's grammar as implemented by tree-sitter-lua (lossless CST, comments as nodes) and author the layer above it: a subset recognizer that classifies CST nodes into DSL structure. The recognizer IS our grammar in the meaningful sense — the single definition of what's form-editable — it's just defined over a mature parse instead of a bespoke one.

## Principles

- **One source of truth: the .lua file.** Every consumer — runtime, type checker, editor, CI — derives its view from the file. No editor-side model that can drift from source.
- **The model is a lossless syntax tree.** Comments and whitespace are tree nodes, so fidelity is a property inherited from the parser, not a feature we implement. Never regenerate a file from semantic state; apply edits as tree transformations and print the tree.
- **Parse-by-execution is the runtime's loading path only.** It is how the game consumes missions (injected env, builders register descriptors). It is never a writer, and no tooling treats registered descriptors as the document model.

## The stack

1. **tree-sitter-lua** — lossless CST, incremental, battle-tested, and natively consumed by Zed (and by VS Code via extensions). One parse serves highlighting, the recognizer, and transformations.
2. **Subset recognizer** (the artifact the DSL doc calls "the grammar, defined once, two consumers"): a tree walk that classifies CST nodes into DSL structure — trigger chains, verb calls, literal arguments, named refs — and everything else as opaque spans. A few hundred lines of tree-walking, not a parser. Its classification is the single definition of "form-editable"; the same walk in check-mode is CI's mission validator (no execution of untrusted files needed).
3. **Transformations**: form edits become CST edits (replace a literal node, add a chain call), then print. Comment-safe by construction because comments are nodes we never touch.
4. **emmylua** stays the type layer: diagnostics in-editor via LSP (VS Code and Zed both), and batch checks in CI. The annotations that drive diagnostics are the same ones the form schema derives from — the "basically free" claim, now with the machinery named.
5. **UI as a projection over the source.** No separate form document: an editor extension renders widgets ONTO the code — decorations, CodeLens, inlay hints anchored to recognizer-identified CST nodes (a slider over the count in `Has(UnitDef("armpw"), 3)`, a run-this-trigger lens above each chain — the CSS-color-swatch pattern, generalized). Every widget interaction is a text edit at a known node, so hand-typing and widget-dragging are the same operation and the two-way problem dissolves: there is no second surface to sync. Presentation hints live in comments as a LuaCATS-style vocabulary (`---@ui slider(1, 10)`, `---@ui label("Pawns to win")`) that the recognizer picks up (comments are CST nodes) and emmylua ignores. Two rules keep it honest: comments hint presentation ONLY — stripping every comment may change rendering, never behavior; and `---@ui` is an optional refinement over what type annotations already imply (an `integer` param gets a number field with no hint; the hint upgrades it to a bounded slider) so verbs never sprout mandatory ceremony. The in-game RML editor later consumes the same hints for form rendering — the vocabulary is written once.

Before building the recognizer: check what the type-migration transform toolchain (Devtools) already parses Lua with. It is deterministic-AST machinery of the same species; reusing its parse layer beats introducing a second one, and if it is emmylua-based there may be a comments-preserved AST already available. tree-sitter is the default answer, not the foregone one.

## Milestones

Each milestone gets its own plan doc when it starts (milestone 1's already lives in hello_pawns_plan.md); this file stays the index and the principles — update the list here with links as the docs appear.

1. **VS Code + hot reload** (lives in hello_pawns_plan.md as the demo stretch): emmylua diagnostics + save-triggered `/luarules mission reload`. No parser work. Both directions exist and meet at the file. This is demoable first and buys time for the real track.
2. **Recognizer + validator**: tree-sitter parse, subset classification, CI check mode ("this mission is well-formed") wired into the repo's checks. Deliverable is a CLI: point it at a missions/ dir, get structure or errors. This is the first artifact that proves "one grammar, two consumers" concretely.
3. **Write-back**: CST transformations for the editable node kinds (literal args first — counts, names, times), print, emmylua gate, save. Hand-written prose anywhere in the file survives untouched. Test: round-trip a heavily commented mission file with zero byte churn outside the edited node.
4. **The form**: schema from annotations, rendered from recognizer output, writing through milestone 3. Host: in-game RML widget, or a VS Code webview panel, or both — decide when we get here; the model/transform layer is host-agnostic by construction, which is the point.
5. **Later**: verb palette, trigger creation, region painting (needs map integration), difficulty-variant views.

## What this obsoletes in the public doc

mission_authoring_dsl.md presents "the subset parser" abstractly. Once milestone 2 exists, revise that section to name the mechanism (tree-sitter CST + recognizer) and drop any implication that a bespoke grammar/lexer gets written. The claim gets stronger: the parser the editor trusts is the same parser the contributor's own editor uses for highlighting.
