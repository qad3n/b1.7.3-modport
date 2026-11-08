---
name: modport
description: Port a Minecraft Java mod (any version, jar or source) to the b1.7.3-rewrite mod loader as one .b173mod that runs on client and server, extending the loader and SDK where the mod needs something new. Use when the user says /modport, /port, "port this mod", or hands over a mod jar to bring to beta 1.7.3.
---

# Port a mod to the b1.7.3-rewrite loader

Java mods cannot run. A port is a Rust rewrite (wasm guest, `b173_api` SDK) that uses the decompiled mod as its spec.
Goal: same look, feel and gameplay inside b1.7.3, from one file in both client and server `mods/`. Fix source bugs and
optimize freely when look and gameplay stay the same. Never replace a vanilla screen: extra UI is a toggleable overlay.

This file is the whole map. Do not read loader design or progress docs, guides or whole SDK files to orient. Use the
tools, then open only the one exemplar file the step needs.

## Workspace

Paths are relative to the workspace root, the folder that holds `b1.7.3-rewrite/`, `ports/` and the kit repo
`b1.7.3-modport/`. The kit's `install.sh` links its tools to `tools/modport/` (written `T/` below) and this skill to
`.claude/skills/modport`; from a port folder `T/` is `../../tools/modport/`. Fix or extend tools in `b1.7.3-modport/`, never inside a port. On a new machine, or when a
tool fails on a missing dependency, run `T/doctor.sh`: it prints the command that fixes each gap. All tools are
bash: on Windows they run in Git Bash (the Bash tool of Claude Code on Windows) and handle `.exe`, `py` and paths
themselves. Call Python tools through `T/py.sh`, never `python3` directly.

## Modes

Check once per session: `test -f .modport-maintainer` in the workspace root.

- **Maintainer mode** (the marker exists): the loader, SDK and kit repos are this user's own. Commit and push to them
  only when the user asks, as the steps below say.
- **User mode** (no marker, the default): the loader, SDK and kit repos belong to their upstream author.
  - Loader and SDK extensions stay in the local working tree. Never commit them to those repos, never push to their
    remotes, never run `gh pr create`, `gh issue create` or any other `gh` write against them, even when asked to
    "share" or "upstream" a change. Tell the user to do that themselves.
  - Log each loader or SDK change in `ports/<modid>/LOADER_CHANGES.md`: what it adds, why, which files.
  - Tell the user that a port needing a local loader change runs only on their patched loader, not on a stock one.
  - The port folder is the user's own repo: commit there when asked, push only to a remote the user set up.
  - Never create the marker file.

## Tools

| Tool | Use it when | Output |
|---|---|---|
| `T/new_port.sh <modid> <jar> [name]` | Starting a port. Writes manifests, git init, decompiles into `reference/src` (Vineflower, downloaded and verified on first use), runs the inventory | `ports/<modid>/` |
| `T/inventory.sh <src>` | Listing what a mod registers: blocks, items and entities with classes, tiles, models, renderers, GUIs, worldgen, events | ~15 KB for a large mod, kept in `reference/inventory.txt` |
| `T/api.sh` | Before writing code against the SDK. `sdk <file>` (world, register, screen, behavior, events, terrain, config, services), `spec <Struct>`, `enum <Name>` (HostCall, EntityField, ModelOp), `templates`, `events`, `console`, `hooks` | one line per signature with SDK line numbers |
| `T/py.sh extract_assets.py <jar> <modid>` | Once, from the port folder. Textures, sounds and lang into `assets/<modid>`, lang keys mapped to `tile.<modid>.x.name`, `item.<modid>.x.name`, `<modid>.<key>` | never committed |
| `T/py.sh convert_models.py --out src/models/generated.rs <Model.java>... [--arg Model.scale=0.5]` | Models. ModelBase constructors (SRG or MCP names) to parts and boxes. Wrap the call in the port's `tools/convert_models.sh` | generated Rust, never hand edit |
| `T/test.sh deploy ports/<modid> [--game]` | Every test cycle. Builds, stops the test server, installs the mod alone, starts the server. `--game` first rebuilds the game and cargo-b173 (after loader or SDK changes). Refuses while a test server runs: another session may own it, ask before `--force` | server console tail |
| `T/test.sh errors [n]` | First thing after any failure | panic, trap and error lines of both logs |
| `T/modtest.sh cmd <console line>` / `log server 80` | Driving and checking the server | reply lines only |
| `T/modtest.sh client` / `shot <png>` | Visual checks only. Ask the user before starting a client: it opens a window on their desktop | game-window PNG |

Console (`T/modtest.sh cmd loader ...`, syntax from `T/api.sh console`): `gen`, `map` (top-down PNG), `slice` (vertical
cut PNG), `column` (check before `tp`: a player teleported into terrain suffocates), `fill`, `tp`, `use`, `interact`,
`close`, `entities`, `summon`, `slot`, `tile`. Read PNGs with the Read tool. Put repeated check chains in small scripts
in `ports/<modid>/tools/` instead of retyping them.

## Workflow

1. **Set up.** Pick the source version closest to beta (1.7.10 over 1.12 over 1.21): its models, textures and data
   shapes map almost 1:1. 1.7.10 jars use SRG names (`func_`, `field_`): read meaning from use, do not hunt mappings.
   Run `new_port.sh`, then `extract_assets.py`. Copy vanilla model classes a mod model extends into
   `reference/vanilla/` for the converter. Port specific asset extras (sprites from 3D renderers) go in the port's own
   `tools/` script.
2. **Plan.** Turn `reference/inventory.txt` into PORT_STATUS.md todo rows in dependency order: blocks and items,
   recipes, worldgen and dimension, entities, machines and GUIs, structures, bosses, player systems, extra slots, item
   behaviors, sounds and particles, config. Milestones end with a deploy and a console check.
3. **Port module by module.** Read the mod's class, check the SDK with `api.sh`, copy the pattern from an exemplar.
   Cite the source class in PORT_STATUS.md, not in code comments.
4. **Extend the loader** only when `api.sh` shows no way (checklist below).
5. **Test** after each module with `deploy`, `cmd`, `errors`. Keep a bug list in PORT_STATUS.md instead of looping on
   one issue; fix the list at the end.
6. **Finish.** Update PORT_STATUS.md. Run `cargo +nightly fmt` in the port and `cargo clippy` in `b1.7.3-rewrite`.
   Commit only when asked: a port holds Rust source, tools and manifests, never assets, `reference/` or AI files.
   `ports/` is either one git repo per port or a monorepo with one folder per mod; `new_port.sh` detects which.
   In user mode, list the local loader changes the port needs from `LOADER_CHANGES.md` in the final report.

## Exemplars

SDK examples, always present: `b1.7.3-rewrite/vendor/b1.7.3-modding-sdk/examples/` with `testmod` (every API module in
one file), `ruby` (data only content), `energy`, `energy_api`, `machines` (services between mods).

A finished port, when the workspace has one, is the faster map. The Aether port (`ports/aether/src`):

| Need | File |
|---|---|
| Block table, templates, behaviors | `blocks.rs` (one const row array per kind) |
| Items, tools, armor, food, recipes | `items.rs`, `tools.rs`, `gear.rs`, `recipes.rs` |
| Config options | `config.rs` (port every spawn rate roll, missing ones flood the world) |
| Entity registration and helpers | `entities/mod.rs` |
| Passive mob and mount, hostile, flyer, projectile | `entities/phyg.rs` + `mount.rs`, `cockatrice.rs`, `zephyr.rs`, `projectile.rs` |
| Client-visible entity state | `entities/swet.rs`, `entities/moa.rs` (`setSynced`/`synced`) |
| Models and animation | `models/mod.rs` (`part`, `cuboid`, `Program`; copy it into a new port) |
| Boss, boss bar HUD, dialogue screen | `entities/bosses/mod.rs`, `valkyrie_queen.rs` (`transparent()` screen plus serverbound channel) |
| Machine with GUI and tile data | `machines.rs` (`ScreenBuilder`, `#[tile_behavior]`) |
| Extra equipment slots, render layers | `accessories.rs` (`screens().overlay("GuiInventory", ..)`, `playerLayer`) |
| Local player movement | `player.rs` (client side in `TickPost`, server state in `thread_local` maps by entity id) |
| Dimension, terrain, decoration | `world/mod.rs`, `world/terrain.rs`, `world/decorate.rs` |
| Structures | `world/dungeons/mod.rs`, `writer.rs` (`terrain::structure::candidates`, clip to `StructureBox::populated`, compress 256-high heights into 128) |
| Portal and travel | `portal.rs` |

Shapes that always apply: renderer GL calls become `Program` ops (push, translate, rotate, scale, texture, blend,
lighting) in the entity's `pose`; `onLivingUpdate`/`updateEntityActionState` go to `onAi` (replaces template AI) or
`onTick`; `terrain::Random` and the noise ports keep seeds identical; check `isAuthority()` before changing the world
(single player loops packets back, same code both sides); validate every serverbound payload; chat through
`translate("<modid>.gui.…")`; sounds as `<modid>.<path.with.dots>`; textures as `<modid>:<path>`.

## Extending the loader

General features only, never a one-mod hack. Paths below are inside `b1.7.3-rewrite/`. Touch points, in order:

1. Protocol: append variants at the end of `HostCall`, `GuestCall`, `GuestReply` or `EntityField` in
   `vendor/b1.7.3-modding-sdk/mod_protocol/src/abi.rs`; new spec fields in `spec.rs` as `Option` or `Default` types
   (spec structs are `#[serde(default)]`, so old mods still load). Released contracts never change: a changed one
   gets a new version.
2. Host: match arm in `crates/modloader/src/host/world.rs` (runtime calls) or `host/register.rs` (register phase);
   larger systems in their own `crates/modloader/src/<system>.rs` or `extensions.rs`. New templates are rows in
   `crates/modloader/src/entities.rs` (`ENTITY_TEMPLATES`) or `content/templates.rs` (`BLOCK_TEMPLATES`).
3. SDK wrapper next to its siblings in `b173_api/src/{world,register,screen}.rs`, in the prelude if mods use it
   everywhere.
4. Client side in `crates/client/src/modded/`. Vanilla code calls new behavior through a one-line hook with a
   `// rewrite:` comment, listed with a version in `crates/modloader/hooks.toml`.
5. Dev console tools in `crates/modloader/src/devtools.rs` (add to `USAGE`).
6. `cargo build` and `cargo clippy`, then `T/test.sh deploy ports/<modid> --game`. Note the addition where the
   workspace keeps loader notes. Maintainer mode: SDK changes are committed in the SDK submodule, then bumped in the
   rewrite, only when the user asks. User mode: nothing is committed there, the change goes in `LOADER_CHANGES.md`.

Example chain, `World::lightning`: `HostCall::Lightning` (abi.rs) to its arm in `host/world.rs` to the wrapper in
`b173_api/src/world.rs`.

## Known traps

- `T/modtest.sh` drives one shared test server and client (`b1.7.3-rewrite/run/modtest-*`). Never stop, reset or take
  over one another session started without asking the user.
- `cargo b173 build` already runs the wasm build; there is no separate `cargo build` step.
- Loader or SDK change without `deploy --game`: the server still runs the old binary without the new host calls.
- The test client's window loses focus and opens the pause menu; it is the harness, not the port.
