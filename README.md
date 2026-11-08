# Beta 1.7.3 Mod Port Kit

A Claude Code skill and helper tools for porting Minecraft Java mods of any version to the b1.7.3-rewrite mod loader.
A port is a Rust rewrite compiled to one `.b173mod` that runs on both client and server. The decompiled original mod
is its spec.

The kit moves the slow parts of a port into scripts: scaffolding, decompiling, listing content, looking up the SDK,
extracting assets, converting models and the build, install and test cycle. That leaves the agent free for the
porting itself.

## Layout

```
skills/modport/SKILL.md   the /modport skill: workflow, tool table, exemplar map, loader extension checklist
tools/new_port.sh         scaffold ports/<modid>, decompile the jar with Vineflower, write the content inventory
tools/inventory.sh        list what a decompiled mod registers (blocks, items, entities, tiles, models, GUIs, worldgen)
tools/api.sh              one line per signature index of the b173_api SDK, protocol enums, templates and console
tools/extract_assets.py   copy textures, sounds and lang from the user's own jar, with port lang keys
tools/convert_models.py   turn ModelBase classes (SRG or MCP names) into Rust EntityModelSpec builders
tools/test.sh             deploy a port to the shared test server, then scan the logs for errors
install.sh                link the skill and tools into a workspace
```

## Workspace

The tools expect this repo next to the other projects in one workspace folder:

```
<workspace>/
  b1.7.3-modport/          this repo
  b1.7.3-rewrite/          the game, mod loader and vendored modding SDK
  b1.7.3_decomp/tools/bin/ vineflower-1.12.0.jar
  tools/rewrite/modtest.sh test server and client driver
  ports/<modid>/           one git repo per port
```

`B173_ROOT` points the tools at another workspace and `VINEFLOWER` at another Vineflower jar.

## Install

```bash
./install.sh
```

This links `skills/modport` to `<workspace>/.claude/skills/modport` and `tools` to `<workspace>/tools/modport`. Pass
a workspace path to install somewhere else. Then run `/modport` (or ask Claude Code to port a mod) in that workspace.

Requirements: bash, Python 3, a JDK for Vineflower, Rust with the `wasm32-unknown-unknown` target, and `cargo-b173`
built from the modding SDK.

## Assets

The kit never ships mod or Minecraft assets. `extract_assets.py` reads them from a jar the user owns into the port's
gitignored `assets/` folder.

## License

See [LICENSE](LICENSE).
