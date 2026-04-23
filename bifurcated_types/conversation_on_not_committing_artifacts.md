Stormlight [BAR], Role icon, Tournaments — 10:43 AM
Hey just want to bump this so some people can test it and make sure it’s ready for PR ⁠New transport AI to make using…
atteanRole icon, Contributors — 11:36 AM
How would we feel about NOT committing the CI artifacts of
docs/ over in Recoil,
and recoil-lua-library as a submodule over in BAR
And instead start having our local build scripts generate them on demand? That allows us to preview and interact with changes to those libraries without getting git spammed and having to reset constantly.

I just added a just reset because I am working in there right now and doing this constantly before I commit so the artifacts don't bloat my PRs, and didn't really want to have this conversation. But I could just fix this TODO now since our local scripting layer already generates the artifacts locally, we'd just stop tracking them. People without a local Recoil checkout would still get the library automatically through Lux package installs. 
Stormlight [BAR], Role icon, Tournaments — 11:56 AM
is this for me?
atteanRole icon, Contributors — 11:56 AM
Nah, it is for anyone who has authority to make decisions in this regard or has an opinion 🙂 I can do the work, just curious what other people's thoughts are cuz otherwise I'm going to do other things on my todo list 
I've cleared the way a bit with Lux existing
and we do want to move that way with recoil and interpolate in BAR eventually, which would force our hand in introducing lx install in order to develop BAR (or "Use our scripting layer in BAR-Devtools"), so it's really a question of timing 
deleting recoil-lua-library as a submodule in BAR would make me incredibly happy, I will admit to that 🙂
[BONELESS] [BAR], Role icon, Contributors — 12:02 PM
I don't think we have submodules only because we do not have packages. But that assessment is still not too far off.
idc as long as the result works, and for me the current system does work
I had to un-commit a submodule change last week but it took me a minute or so. A minute once a week isn't going to take me out
atteanRole icon, Contributors — 12:04 PM
yeah, every rebase it crops up but I have the commands memorized and nbd 
when I'm working in docs or on recoil-lua-library itself that is of course an edge case
still, friction. I'm probably rushing things by pushing this now, which is why I threw it out there rather than making another dangling PR for myself. Soon, hopefully, but it's the sort of tooling problem I will never ever come back to once I am no longer in there 😄 
 [BAR], 
FlameinkRole icon, Contributors — 12:17 PM
Did you fix ⁠💡｜suggestions-and-feedback⁠New transport AI to make using… ?
Watch The Fort (Quality Lead)Role icon, Team Leaders — 1:02 PM
Why? These are pretty much static files, the documentation does not update that often.
And what is this resetting you're talking about? A git pull updates the submodules, the only inconvenience is having to set a config flag in your local git settings to automatically pull submodules.
atteanRole icon, Contributors — 1:08 PM
The issue isn't pulling submodules, it's that the generated files are tracked in git. When you're actively working on the Lua library or docs pipeline, every time you run the build (just lua::library, just docs::generate), the output lands in your working tree as modified/untracked files in RecoilEngine and BAR. You have to git checkout/git clean those paths before committing or they end up in your PR as noise.

You're right that it doesn't update often from a consumer perspective. But when you're the one changing the generator or its inputs, you're regenerating constantly, and the tracked output is what creates the friction. Right now the tradeoff favors consumers who don't use a scripting layer, at the cost of contributors working across these layers, which is a tradeoff that taken too far can decrease our ability to emulate our CI during local development or automate for our consumers. In this case, I'm trying to automate the docs/library/lint/test workflow for contributors coming behind me and I have this kludgey reset step in the middle of it.

For most people it's a non-issue outside rebasing, which is why just reset is fine as a band-aid for now.