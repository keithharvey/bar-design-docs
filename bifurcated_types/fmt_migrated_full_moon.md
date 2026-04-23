# bar-lua-codemod: AST-Based Lua Transformation Tool

A [full-moon](https://crates.io/crates/full_moon) (v2.1.1) based codemod tool for BAR's Lua codebase. full-moon is the Lua parser that [StyLua](https://github.com/JohnnyMorganz/StyLua) is built on -- lossless, trivia-preserving, zero false positives.

This is the recommended approach for the bracket-to-dot transform and any future AST-level migrations. See [fmt_migrated.md](fmt_migrated.md) for the broader migration context.

## First transform: bracket-to-dot

Addresses efrec's [PR comment](https://github.com/beyond-all-reason/Beyond-All-Reason/pull/7199#discussion_r2983337191). ~8,240 instances repo-wide.

### full-moon's AST maps directly to the transform

**Index access: `x["y"]` -> `x.y`**

```rust
enum Index {
    Brackets {
        brackets: ContainedSpan,  // the [ and ]
        expression: Expression,   // the "y" string literal
    },
    Dot {
        dot: TokenReference,      // the .
        name: TokenReference,     // y
    },
}
```

**Table constructor: `["y"] = val` -> `y = val`**

```rust
enum Field {
    ExpressionKey {
        brackets: ContainedSpan,  // the [ and ]
        key: Expression,          // the "y" string literal
        equal: TokenReference,    // the =
        value: Expression,        // val
    },
    NameKey {
        key: TokenReference,      // y (bare identifier)
        equal: TokenReference,    // the =
        value: Expression,        // val
    },
    NoKey(Expression),            // positional value
}
```

### Token construction (from StyLua source)

The fiddly part is constructing replacement `TokenReference` values. StyLua (`/home/daniel/code/StyLua/src/formatters/`) shows the pattern:

```rust
// Creating a token with trivia (from StyLua's general.rs)
TokenReference::new(leading_trivia_vec, token, trailing_trivia_vec)

// Creating a simple token
Token::new(TokenType::Symbol { symbol: Symbol::Dot })
Token::new(TokenType::Identifier { identifier: name.into() })
Token::new(TokenType::spaces(1))
```

For our transform, when converting `Index::Brackets` -> `Index::Dot`:
1. Take leading trivia from the opening `[` bracket
2. Create a `.` token: `Token::new(TokenType::Symbol { symbol: Symbol::Dot })`
3. Create the identifier token: `Token::new(TokenType::Identifier { identifier: name.into() })`
4. Take trailing trivia from the closing `]` bracket
5. Assemble: `Index::Dot { dot: TokenReference::new(leading, dot_token, vec![]), name: TokenReference::new(vec![], name_token, trailing) }`

StyLua reference files for token construction patterns:
- `src/formatters/general.rs` (line ~391): `format_token_reference` -- canonical `TokenReference::new` pattern
- `src/formatters/expression.rs` (line ~386): `format_index` -- handles `Index::Brackets` and `Index::Dot`
- `src/formatters/table.rs` (line ~168): `format_field` -- handles `Field::ExpressionKey` and `Field::NameKey`
- `src/formatters/trivia_util.rs`: trivia extraction from Index and Field nodes

### Implementation

```rust
use full_moon::{ast::*, parse, print, tokenizer::*, visitors::VisitorMut};
use std::{env, fs, path::PathBuf};

const LUA_RESERVED: &[&str] = &[
    "and", "break", "do", "else", "elseif", "end", "false", "for",
    "function", "if", "in", "local", "nil", "not", "or", "repeat",
    "return", "then", "true", "until", "while",
];

fn is_convertible_identifier(s: &str) -> bool {
    let mut chars = s.chars();
    match chars.next() {
        Some(c) if c.is_ascii_alphabetic() || c == '_' => {}
        _ => return false,
    }
    chars.all(|c| c.is_ascii_alphanumeric() || c == '_')
        && !LUA_RESERVED.contains(&s)
}

fn string_content(expr: &Expression) -> Option<String> {
    if let Expression::String(token_ref) = expr {
        let s = token_ref.token().to_string();
        if s.starts_with('"') && s.ends_with('"') {
            return Some(s[1..s.len() - 1].to_string());
        }
        if s.starts_with('\'') && s.ends_with('\'') {
            return Some(s[1..s.len() - 1].to_string());
        }
    }
    None
}

fn make_dot(leading: Vec<Token>, trailing: Vec<Token>) -> TokenReference {
    TokenReference::new(
        leading,
        Token::new(TokenType::Symbol { symbol: Symbol::Dot }),
        vec![],
    )
}

fn make_identifier(name: &str, trailing: Vec<Token>) -> TokenReference {
    TokenReference::new(
        vec![],
        Token::new(TokenType::Identifier {
            identifier: name.into(),
        }),
        trailing,
    )
}

struct BracketToDot {
    index_conversions: usize,
    field_conversions: usize,
}

impl VisitorMut for BracketToDot {
    fn visit_index(&mut self, index: Index) -> Index {
        if let Index::Brackets { ref brackets, ref expression } = index {
            if let Some(name) = string_content(expression) {
                if is_convertible_identifier(&name) {
                    self.index_conversions += 1;
                    let (open, close) = brackets.tokens();
                    let leading: Vec<Token> = open.leading_trivia().cloned().collect();
                    let trailing: Vec<Token> = close.trailing_trivia().cloned().collect();
                    return Index::Dot {
                        dot: make_dot(leading, vec![]),
                        name: make_identifier(&name, trailing),
                    };
                }
            }
        }
        index
    }

    fn visit_field(&mut self, field: Field) -> Field {
        if let Field::ExpressionKey {
            ref brackets,
            ref key,
            ref equal,
            ref value,
            ..
        } = field
        {
            if let Some(name) = string_content(key) {
                if is_convertible_identifier(&name) {
                    self.field_conversions += 1;
                    let (open, _close) = brackets.tokens();
                    let leading: Vec<Token> = open.leading_trivia().cloned().collect();
                    return Field::NameKey {
                        key: TokenReference::new(
                            leading,
                            Token::new(TokenType::Identifier {
                                identifier: name.into(),
                            }),
                            vec![],
                        ),
                        equal: equal.clone(),
                        value: value.clone(),
                    };
                }
            }
        }
        field
    }
}

struct Stats {
    files_changed: usize,
    total_index: usize,
    total_field: usize,
    per_file: Vec<(PathBuf, usize, usize)>,
}

fn process_file(path: &PathBuf) -> Option<(usize, usize)> {
    let code = fs::read_to_string(path).ok()?;
    let ast = parse(&code).ok()?;
    let mut visitor = BracketToDot {
        index_conversions: 0,
        field_conversions: 0,
    };
    let ast = visitor.visit_ast(ast);
    if visitor.index_conversions > 0 || visitor.field_conversions > 0 {
        fs::write(path, print(&ast)).ok()?;
        Some((visitor.index_conversions, visitor.field_conversions))
    } else {
        None
    }
}
```

### CLI and PR description output

The tool should support `--dry-run` (report what would change without writing) and output a summary suitable for `bar::fmt-mig-author` to include in a PR description:

```
bar-lua-codemod bracket-to-dot results:
  Files scanned:  1,847
  Files changed:    423
  Index conversions (x["y"] -> x.y):     3,891
  Field conversions (["y"] = -> y =):     4,349
  Total conversions:                      8,240
  Skipped (reserved words):                  12
  Errors (parse failures):                    0

Top files by conversion count:
  effects/atmospherics.lua                    49
  luaui/configs/buildmenu_sorting.lua        412
  ...
```

`bar::fmt-mig-author` captures this output and drafts a PR description summarizing the transform, the stats, and the verification steps.

## Build and distribution

Lives in `BAR-Devtools/bar-lua-codemod/`, alongside the existing tooling:

```
BAR-Devtools/
  bar-lua-codemod/
    Cargo.toml
    src/
      main.rs
      bracket_to_dot.rs
      spring_split.rs
  just/
    bar.just              ← recipes build and call the binary
  scripts/
  lua-doc-extractor/      ← existing TS tool, same pattern
```

```toml
# BAR-Devtools/bar-lua-codemod/Cargo.toml
[package]
name = "bar-lua-codemod"
version = "0.1.0"
edition = "2024"

[dependencies]
full_moon = "2.1"
glob = "0.3"
clap = { version = "4", features = ["derive"] }
```

Lua 5.1 parsing is always included in full-moon (it's the default). No feature flags needed -- we're parsing 5.1 code and transforming it within the same version.

```bash
# Build in distrobox (one-time, same pattern as lua-doc-extractor)
cd BAR-Devtools/bar-lua-codemod && cargo build --release
# Binary at target/release/bar-lua-codemod (~2-4 MB)

# Usage
bar-lua-codemod bracket-to-dot --path . --exclude common/luaUtilities --dry-run
bar-lua-codemod bracket-to-dot --path . --exclude common/luaUtilities
```

The `bar::fmt-mig` recipe builds it automatically before use, same way `just lua::library` runs `npm ci && npm run build` on lua-doc-extractor. The compiled binary has no runtime dependencies -- contributors who don't have Rust can use a pre-built binary from a GitHub release asset.

## Why not fork StyLua?

StyLua is a **formatter** -- it takes Lua and outputs formatted Lua. What we need is a **codemod tool** -- it takes Lua, applies structural transforms, and outputs Lua. Different use case, different architecture. StyLua's formatting engine (shape tracking, line width calculations, indent management) is irrelevant to us.

What we DO take from StyLua:
- Token construction patterns (`TokenReference::new`, `Token::new`, trivia handling)
- Reference for how full-moon's AST types are structured
- Confidence that full-moon is production-grade (StyLua has been formatting Lua codebases at scale for years)

## Second transform: `Spring.*` -> `SpringSynced` / `SpringUnsynced` / `SpringShared`

The recoil-lua-library defines three API surfaces:

- **`SpringShared`** -- methods available in both synced and unsynced contexts
- **`SpringSynced : SpringShared`** -- synced-only methods
- **`SpringUnsynced : SpringShared`** -- unsynced-only methods
- **`Spring : SpringSynced, SpringUnsynced`** -- the merged type (current usage everywhere)

Today, all game code calls `Spring.GetUnitDefID(...)`, `Spring.Echo(...)`, etc. regardless of context. This makes the type system useless for catching synced/unsynced API misuse -- LuaLS sees the merged `Spring` type and allows everything.

### The transform

Replace every `Spring.Method` call with the most specific type that defines it:

1. **Build a lookup table** from recoil-lua-library's generated stubs. Parse `library/generated/shared.lua`, `synced.lua`, `unsynced.lua` to determine which methods belong to which class.
2. **Determine file context** from directory/filename conventions:
   - `luarules/gadgets/*` -- has both synced and unsynced sections (split at `Spring.IsSyncedCode()` or the gadget's synced/unsynced block structure)
   - `luaui/Widgets/*` -- always unsynced
   - `common/` -- shared (use `SpringShared`)
3. **Rewrite**: `Spring.GetUnitDefID` -> `SpringShared.GetUnitDefID` (if defined on SharedShared), or `SpringSynced.GetUnitHealth` -> stays `SpringSynced` (synced-only), etc.

### Why this matters

Once `Spring.*` calls are split, LuaLS can catch real bugs: calling a synced-only API from a widget, or an unsynced-only API from synced gadget code. This is the primary type safety payoff of the entire migration.

### full-moon implementation

Same visitor pattern. Walk `FunctionCall` nodes, match calls where the prefix is `Spring`, look up the method name in the mapping table, rewrite to the correct prefix:

```rust
fn visit_function_call(&mut self, call: FunctionCall) -> FunctionCall {
    // If call is Spring.MethodName(...)
    // Look up MethodName in the generated mapping
    // Rewrite prefix to SpringShared/SpringSynced/SpringUnsynced
    // based on the mapping + file context
}
```

The mapping table can be generated at build time by parsing the recoil-lua-library stubs (which are themselves Lua files that full-moon can parse).

## Integration with `bar::fmt-mig`

The `just` recipes in `BAR-Devtools/just/bar.just`:

```
bar::fmt-mig          -- contributors run this after rebasing
  1. bar-lua-codemod bracket-to-dot --path $BAR_DIR --exclude common/luaUtilities
  2. bar-lua-codemod spring-split --path $BAR_DIR --library recoil-lua-library/library/generated
  3. stylua .

bar::fmt-mig-author   -- maintainer runs this when building/rebasing the migration commit
  1. bar::fmt-mig (above)
  2. trailing comment candidate scan (rg heuristic)
  3. capture bar-lua-codemod output for PR description
  4. verification checks (reserved word false conversions, remaining bracket patterns)
```

## What you get over regex

- **Zero false positives.** The parser knows syntactic context. String literals inside comments, long strings `[[ ]]`, or other expressions are never matched.
- **Trivia preservation.** Comments attached to brackets transfer to the dot/identifier. No formatting drift.
- **Extensibility.** Adding a new transform means adding a visitor method, not writing a new regex. The reserved word check is a function call, not a 20-keyword negative lookahead.
- **Testability.** Rust unit tests on the visitor. Parse input, apply visitor, assert output. No shell pipeline to debug.

## Future transforms

This tool is designed to grow. Each new transform is a subcommand:

```bash
bar-lua-codemod bracket-to-dot ...
bar-lua-codemod spring-split --library recoil-lua-library/library/generated ...
bar-lua-codemod rename-global --from "unpack" --to "table.unpack" ...
bar-lua-codemod <future-transform> ...
```

For Lua 5.1 -> 5.4 migration considerations, see [lua54_migration/full_moon_initial_opus_46_thoughts.md](../lua54_migration/full_moon_initial_opus_46_thoughts.md).
