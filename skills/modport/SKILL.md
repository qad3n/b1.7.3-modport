---
name: modport
description: Port a Minecraft Java mod (any version, jar or source) to the b1.7.3-rewrite mod loader as one .b173mod that runs on client and server, extending the loader and SDK where the mod needs something new. Use when the user says /modport, /port, "port this mod", or hands over a mod jar to bring to beta 1.7.3.
---

# Port a mod to the b1.7.3-rewrite loader

Java mods cannot run. A port is a Rust rewrite (wasm guest, `b173_api` SDK) that uses the decompiled mod as its spec.
Goal: same look, feel and gameplay inside b1.7.3, from one file in both client and server `mods/`. Fix source bugs and
optimize freely when look and gameplay stay the same. Never replace a vanilla screen: extra UI is a toggleable overlay.

This file is the whole map. Do not read `modloader-design.md`, `modloader-progress.md`, the full guide or whole SDK
files to orient. Use the tools below, then open only the one exemplar file the step needs.

## Tools (all paths from the project root)

Source repo `b1.7.3-modport/` (skill and tools), linked into the workspace by its `install.sh`. Fix or extend the
tools there, never in a port.

| Tool | Use it when | Output |
|---|---|---|
| `tools/modport/new_port.sh <modid> <jar> [name]` | Starting a port. Writes manifests, git init, decompiles into `reference/src`, runs the inventory | `ports/<modid>/` |
| `tools/modport/inventory.sh <src>` | Listing what a mod registers (blocks, items, entities with classes, tiles, models, renderers, GUIs, worldgen, events) | ~15 KB for a large mod, saved as `reference/inventory.txt` |
| `tools/modport/api.sh` | Before writing code against the SDK. `api.sh sdk <file>` (world, register, screen, behavior, events, terrain, config, services), `spec <Struct>`, `enum <Name>` (HostCall, EntityField, ModelOp), `templates`, `events`, `console`, `hooks` | one line per signature, with line numbers into the SDK |
| `python3 -I ../../tools/modport/extract_assets.py <jar> <modid>` | Once, from the port folder. Copies textures, sounds, lang into `assets/<modid>`, maps lang keys to `tile.<modid>.x.name`, `item.<modid>.x.name`, `<modid>.<key>` | never committed |
| `python3 -I ../../tools/modport/convert_models.py --out src/models/generated.rs <Model.java>... [--arg Model.scale=0.5]` | Models. Converts ModelBase constructors (SRG or MCP names) into parts and boxes. Wrap it in `tools/convert_models.sh` | generated Rust, never hand edit |
| `tools/modport/test.sh deploy ports/<modid> [--game]` | Every test cycle. Builds the mod, stops the test server, installs the mod alone, starts the server. `--game` first rebuilds the game binaries and cargo-b173 (after any loader or SDK change). Refuses when a test server is already running: another session may own it, ask before `--force` | server console tail |
| `tools/modport/test.sh errors [n]` | First thing after any failure | panic, trap and error lines of both logs |
| `tools/rewrite/modtest.sh cmd <console line>` / `log server 80` | Driving and checking the server | reply lines only |
| `tools/rewrite/modtest.sh client` / `shot <png>` | Visual checks only. Ask the user before starting a client: it opens a window on their desktop | game-window PNG |

Console (`modtest.sh cmd loader ...`, full syntax from `api.sh console`): `gen`, `map` (top-down PNG), `slice` (vertical
cut PNG), `column` (block stack, check before `tp`, a player teleported into terrain suffocates), `fill`, `tp`, `use`,
`interact`, `close`, `entities`, `summon`, `slot`, `tile`. Read PNGs with the Read tool. Write small per-port scripts in
`ports/<modid>/tools/` for repeated checks (as `ports/aether/tools/test_mobs.sh`) instead of retyping command chains.

## Workflow

1. **Set up.** Pick the source version closest to beta (1.7.10 over 1.12 over 1.21): its models, textures and data
   shapes map almost 1:1. 1.7.10 jars use SRG names (`func_`, `field_`): read meaning from use, do not hunt mappings.
   Run `new_port.sh`, then `extract_assets.py`. Copy `ports/aether/src/models/mod.rs` (`part`, `cuboid`, `Program`)
   when the first entity arrives. Copy vanilla model classes a mod model extends into `reference/vanilla/`.
2. **Plan.** Turn `reference/inventory.txt` into PORT_STATUS.md todo rows in dependency order: blocks and items,
   recipes, worldgen and dimension, entities, machines and GUIs, structures, bosses, player systems, extra slots, item
   behaviors, sounds and particles, config. Milestones end with a deploy and a console check.
3. **Port module by module.** Read the mod's class, check the SDK with `api.sh`, copy the pattern from the exemplar
   below. Cite the source class in PORT_STATUS.md, not in code comments.
4. **Extend the loader** only when `api.sh` shows no way (checklist below).
5. **Test** after each module with `deploy`, `cmd`, `errors`. Keep a bug list in PORT_STATUS.md instead of looping on
   one issue; fix the list at the end.
6. **Finish.** Update PORT_STATUS.md, the guide section "Porting content from later versions" and memory. Run
   `cargo +nightly fmt` in the port and `cargo clippy` in the rewrite. Commit only when asked: the port repo holds Rust
   source, tools and manifests, never assets, `reference/` or AI files.

## Exemplars (ports/aether/src, line counts)

| Need | File | Notes |
|---|---|---|
| Block table, templates, behaviors | `blocks.rs` (680) | one const row array per kind |
| Items, tools, armor, food | `items.rs` (359), `tools.rs` (97), `gear.rs` (264) | armor sheets tinted |
| Recipes | `recipes.rs` (209) | |
| Config options | `config.rs` (56) | port every spawn rate roll, missing ones flood the world |
| Entity registration, shared helpers | `entities/mod.rs` (122) | `creature`, `drop`, spawn specs |
| Passive mob, mount | `entities/phyg.rs` (84), `entities/mount.rs` (159) | steering, saddles |
| Hostile mob, ranged | `entities/cockatrice.rs` (122), `entities/projectile.rs` (423) | |
| Flyer | `entities/zephyr.rs` (238) | ghast template |
| Synced client state | `entities/swet.rs`, `entities/moa.rs` | `setSynced`/`synced` |
| Boss, boss bar HUD, dialogue screen | `entities/bosses/mod.rs` (151), `valkyrie_queen.rs` | `transparent()` screen plus serverbound channel |
| Machine with GUI and tile data | `machines.rs` (625) | `ScreenBuilder`, `#[tile_behavior]` |
| Extra equipment slots, render layers | `accessories.rs` (609) | `screens().overlay("GuiInventory", ..)`, `playerLayer` |
| Local player movement (glide, jumps, step) | `player.rs` (216) | client side in `TickPost`, server state in `thread_local` maps by entity id |
| Dimension, biome, terrain, decoration | `world/mod.rs` (61), `world/terrain.rs`, `world/decorate.rs` | `terrain::Random` and noise ports keep seeds identical |
| Structures | `world/dungeons/mod.rs` (414), `writer.rs` (260) | `terrain::structure::candidates`, clip to `StructureBox::populated`, compress 256-high heights into 128 |
| Portal and travel | `portal.rs` (550) | |

Port shapes that always apply: renderer GL calls become `Program` ops (push, translate, rotate, scale, texture, blend,
lighting) in the entity's `pose`; `onLivingUpdate`/`updateEntityActionState` go to `onAi` (replaces template AI) or
`onTick`; check `isAuthority()` before changing the world (single player loops packets back, same code both sides);
validate every serverbound payload; chat through `translate("<modid>.gui.…")`; sounds as `<modid>.<path.with.dots>`;
textures as `<modid>:<path>`.

## Extending the loader

General features only, never a one-mod hack. Touch points, in order:

1. Protocol: append variants at the end of `HostCall`, `GuestCall`, `GuestReply` or `EntityField` in
   `b1.7.3-rewrite/vendor/b1.7.3-modding-sdk/mod_protocol/src/abi.rs`; new spec fields in `spec.rs` as
   `Option` or `Default` types (spec structs are `#[serde(default)]`, so old mods still load). Released contracts never change: a changed one gets a new version.
2. Host: match arm in `crates/modloader/src/host/world.rs` (runtime calls) or `host/register.rs` (register phase);
   larger systems in their own `crates/modloader/src/<system>.rs` or `extensions.rs`. New templates are rows in
   `crates/modloader/src/entities.rs` (`ENTITY_TEMPLATES`) or `content/templates.rs` (`BLOCK_TEMPLATES`).
3. SDK wrapper next to its siblings in `b173_api/src/{world,register,screen}.rs`, exported through the prelude if
   mods use it everywhere.
4. Client side in `crates/client/src/modded/`. Vanilla code calls new behavior through a one-line hook with a
   `// rewrite:` comment, listed with a version in `crates/modloader/hooks.toml`.
5. Dev console tools in `crates/modloader/src/devtools.rs` (add to `USAGE`).
6. `cargo build` and `cargo clippy` in `b1.7.3-rewrite`, then `test.sh deploy ports/<modid> --game`. One line per
   addition in `tools/rewrite/modloader-progress.md` and the guide. SDK changes are committed in the submodule repo,
   then bumped in the rewrite, only when the user asks.

Example chain, `World::lightning`: `HostCall::Lightning` (abi.rs) to the arm in `host/world.rs` to the wrapper in
`b173_api/src/world.rs`.

## Known traps

- `modtest.sh` runs one shared test server and client (`b1.7.3-rewrite/run/modtest-*`). Never stop, reset or
  take over one another session started without asking the user.
- `cargo b173 build` already runs the wasm build; there is no separate `cargo build` step.
- Loader or SDK change without `deploy --game`: the server still runs the old binary without the new host calls.
- The test client's window loses focus and opens the pause menu; it is the harness, not the port.
- Death screen keep-alive timeout (vanilla 30 seconds): loader fix in place, not verified.
