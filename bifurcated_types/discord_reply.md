**A few closing thoughts:**
* I think this will let us actually use the formal type system to fuller effect (because people treat it as a real signal) and will greatly increase code quality over time.
* The more formal verification we wire in, the better our parsers and LLM agents get. I added `claude/rules/codemod.md` to BAR-Devtools as a driver for the subagents -- worth doing the same across our scripts and automation.
* This makes the argument in [Game Economy](https://github.com/beyond-all-reason/RecoilEngine/pull/2664) more compelling (and I confess that's what led me here). Lua can now express its own design patterns under type checking -- both where the engine has no stake and where it does, by wrapping the API in typed abstractions instead of leaking it everywhere. @sprunk
* Shout out to @rhys_vdw for the fantastic foundation in lua-doc-extractor and recoil-lua-library -- not a snowball's chance in hell I would've started this without that work.
* Super enabled by BAR-Devtools existing, shout out to @thule for getting that ball rolling. SHARED CROSS REPO SCRIPTING LAYER!!!!!
