I am done with the BAR type-error cleanup. These PRs are ready to go, barring any concerns -- I'll maintain them furiously for at least another week and have rebased my own branches on top to feel the rough edges before you do.

**The BAR-Devtools PR needs to land before the release cut.**

**[Tracking Issue](https://github.com/beyond-all-reason/Beyond-All-Reason/issues/7408)** -- full details, commit breakdown, pipeline docs
[Final BAR Transform Output PR](https://github.com/beyond-all-reason/Beyond-All-Reason/pull/7407) | [Script/Tooling PR](https://github.com/beyond-all-reason/BAR-Devtools/pull/17) | [Recoil PR](https://github.com/beyond-all-reason/RecoilEngine/pull/2799)

**What changed:**
* automated deterministic transforms + LLM pass driving type errors to zero
* [lua-doc-extractor](https://github.com/rhys-vdw/lua-doc-extractor/pull/77): `SpringSynced`/`SpringUnsynced`/`SpringShared` as mutually exclusive engine API wrappers
* updated [Recoil](https://github.com/beyond-all-reason/RecoilEngine/pull/2799) with new extractor + missing type decorators @bodasu @rhys_vdw
* replaced bespoke i18n with [kikito-i18n](https://github.com/kikito/i18n.lua) via `lx` -- first forced dependency, `just setup::distrobox` hides it @watchthefort
* new PR gate: "Type Check" (`just bar::check`)
* ripped out LuaLS/Sumneko for [EmmyLua](https://marketplace.visualstudio.com/items?itemName=tangzx.emmylua) (~100x faster). NEVER use the Sumneko plugin!!!

**New developer commands:**
`just bar::check` -> check types
`just bar::lint` -> check style
`just setup::editor` -> editor tooling + copy-pasteable vscode settings
`just bar::fmt-mig` -> apply deterministic transforms to your branch