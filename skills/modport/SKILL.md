---
name: modport
description: Port a Minecraft Java mod (any version, jar or source) to the b1.7.3_rewrite mod loader as one .bmod that runs on client and server, extending the loader and SDK where the mod needs something new. Use when the user says /modport, /port, "port this mod", or hands over a mod jar to bring to beta 1.7.3.
---

# Port a mod to the b1.7.3_rewrite loader

Java mods cannot run. A port is a Rust rewrite (wasm guest, `b173_api` SDK) that uses the decompiled mod as its spec.
Goal: deconstruct the mod into its content, mechanics and data, then rewrite it as a native loader mod, one file in
both client and server `mods/`. Every piece of content ships, and everything goes through the loader's registries so
the mod loads cleanly and works with other mods without setup. The Java is a source of facts, not a structure to
copy. Fix source bugs and optimize freely. Never replace a vanilla screen: extra UI is a toggleable overlay.

This file is the whole map. Do not read loader design or progress docs, guides or whole SDK files to orient. Use the
tools, then open only the one exemplar file the step needs.

## Porting rules

- **Complete content, native structure.** All of the mod is there: every block, item, entity, dimension, structure,
  mechanic, GUI and piece of data. Gameplay values (drops, costs, timings, spawn rates) keep the source's numbers
  unless beta forces a change. How the code is organized is not ported: write each feature the way a mod built for
  this loader would, on what the SDK offers (registries, builders, specs, components, behaviors, events, screens,
  services, `Draw` widgets), the way the exemplars do. Do not walk the Java class by class or mirror its classes,
  inheritance or helper layout; read a class only to pull out a rule or a number. Hand-roll logic only when `api.sh` shows nothing that fits, and then prefer extending the SDK with a
  general feature (below) over a private workaround inside the port. Never reimplement in a port what the SDK already
  provides, and never cut or simplify a feature because the SDK route takes more work.
- **Names, tags and states, never ids.** Numeric ids and metadata are the engine's runtime handles, reassigned on
  every remap. A port never keeps its own id cache (`ids.rs`) or compares against looked-up numbers:
  - identity by name: `world.is(pos, "rubber_wood")`, `ctx.is(...)`, `blockIs(block, name)`, `ItemRef::is`, place
    with `world.place` or `world.setBlockState`. A bare name means the mod's own namespace.
  - groups by tag: `world.tagged(pos, "minecraft:logs")`, `blockTagged`, `ItemRef::tagged`. Never write a list of
    vanilla names (soil, logs, leaves, stone, wool, ores, tools). Use the vanilla tags the loader seeds
    (`minecraft:dirt`, `minecraft:base_stone_overworld`, `c:ores/iron`, `minecraft:pickaxes` and the rest in the
    author guide) or add a `c:` tag, and put the mod's own blocks and items in the tags they belong to (rubber wood in
    `minecraft:logs`), so other mods' content takes part without either knowing the other.
  - variants by state: blocks with variants, facings or flags register named properties (`ctx.blocks().states`) and
    read and write them with `StateData` (`of`, `with`, `get`, `flag`). No meta bit masks.
  - vanilla textures by sprite name: `minecraft:block/oak_leaves`, `minecraft:item/stick`, not sheet slots.
  - shared helpers belong in the SDK once. A port never copies a helper another port already has.
- **Everything goes through a registry.** The loader must know everything a mod does so it can organize loading and
  mods work together with no manual setup. Recipes, machine recipes, fuels, loot, worldgen, structures, dimensions,
  biomes, fluids, energy, effects, attributes, particles, achievements, stats, game rules, config, lang, entities and
  spawns are registered, and machines look up their registered recipes instead of keeping private tables. Items, fluids and
  energy move through capabilities and services, never by checking for the mod's own blocks. Inputs take tags so
  other mods' content feeds in. A missing registry becomes a general SDK builder.
- **The game stays vanilla.** Never change, add or remove vanilla game logic or content in `b1.7.3_rewrite` (`crates/game`,
  `crates/server`, vanilla files in `crates/client`) unless the user says to. Do not refactor a vanilla function to reuse
  part of it: call it as it is from the loader. The mod changes the game only through the loader API.
- **The mod adapts to beta, never the other way.** Port the mod's content into the beta world as it is:
  - Leave out systems beta does not have: dyeing, enchanting, potions brewing, creative-only blocks, written books,
    death messages, map copying and the like. Use the closest beta behavior, or leave the feature out, and note it once
    in PORT_STATUS.md.
  - Content tied to later versions (the End, newer mobs, blocks or materials) is reorganized and rebalanced so it makes
    sense in beta: move it to a beta place, swap materials for beta ones, retune drops and costs.
  - Never import later version content into the game to make a mod fit.
- **Loader changes are universal.** When the API cannot do something the mod needs, extend the loader with a general
  feature any mod could use, named and documented without the mod. Never hardcode a mod's ids, names or rules in the
  loader. A change to an existing loader function must keep every other mod working.
- **Vanilla files change only to grow the loader API, never for one mod.** First reach the game through hooks that
  already exist (`api.sh hooks`) and vanilla's own extension points: registries and lists vanilla keeps
  (`RenderEngine.registerTextureFX`, entity and block classes, vtable classes set on objects the loader creates),
  and vanilla functions called as they are. When none fits, a new hook site is allowed: one `// rewrite:` call into
  the loader, generic and named for what it lets any mod do, behavior-neutral with zero mods, listed in
  `crates/modloader/hooks.toml`. Never put a mod's ids, names, rules or content in vanilla code, and never refactor or
  change vanilla logic itself.
- **Done means verified.** Report what was checked (builds, console tests, server logs) and what was not (client
  visuals, multiplayer, player-driven features). Never call a port finished while PORT_STATUS.md lists open rows.

## Workspace

Paths are relative to the workspace root, the folder that holds `b1.7.3_rewrite/`, `ports/` and the kit repo
`b1.7.3_modport/`. The kit's `install.sh` links its tools to `tools/modport/` (written `T/` below) and this skill to
`.claude/skills/modport`; from a port folder `T/` is `../../tools/modport/`. Fix or extend tools in `b1.7.3_modport/`, never inside a port. On a new machine, or when a
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
| `T/new_port.sh <modid> <jar> [name]` | Starting a port. Writes manifests and `assets.toml`, git init, decompiles into `reference/src` (Vineflower, downloaded and verified on first use), runs the inventory | `ports/<modid>/` |
| `T/inventory.sh <src>` | Listing what a mod registers: blocks, items and entities with classes, tiles, models, renderers, GUIs, worldgen, events | ~15 KB for a large mod, kept in `reference/inventory.txt` |
| `T/api.sh` | Before writing code against the SDK. `sdk <file>` (world, register, screen, behavior, events, terrain, config, services), `spec <Struct>`, `enum <Name>` (HostCall, EntityField, ModelOp), `templates`, `events`, `console`, `hooks` | one line per signature with SDK line numbers |
| `T/py.sh recipe.py <jar> <modid> [--sheet <png in jar> <names.txt> <to>]... [--url <page>]` | Regenerating `assets.toml` from the port folder (`new_port.sh` writes the first one). Pins the download by name and sha256, copies textures and sounds (lower case targets), maps lang keys to `tile.<modid>.x.name`, `item.<modid>.x.name`, `<modid>.<key>`. `--sheet` cuts an old-style 16x16 grid sheet: names.txt lines are `<slot> <name> [span]`, `<to>` is `textures/block` or `textures/item` | `assets.toml`, committed |
| `T/py.sh convert_models.py --out src/models/generated.rs <Model.java>... [--arg Model.scale=0.5]` | Models. ModelBase constructors (SRG or MCP names) to parts and boxes. Wrap the call in the port's `tools/convert_models.sh` | generated Rust, never hand edit |
| `T/audit.sh ports/<modid>` | After each module and before calling a port done. Lists code that bypasses names, tags, states and registries: numeric id lookups and comparisons, meta bits, blocks placed by number, numeric items, vanilla sheet slot textures, lists of vanilla names, a private `ids.rs` | hits per rule with file:line, `clean` and exit 0 when none |
| `T/test.sh deploy ports/<modid> [--game]` | Every test cycle. Builds, stops the test server, installs the mod alone, starts the server. `--game` first rebuilds the game and cargo-b173 (after loader or SDK changes). Refuses while a test server runs: another session may own it, ask before `--force` | server console tail |
| `T/test.sh errors [n]` | First thing after any failure | panic, trap and error lines of both logs |
| `T/modtest.sh cmd <console line>` / `log server 80` | Driving and checking the server | reply lines only |
| `T/modtest.sh client` / `shot <png>` | Visual checks only. Ask the user before starting a client: it opens a window on their desktop | game-window PNG |

Console (`T/modtest.sh cmd loader ...`, syntax from `T/api.sh console`): `gen`, `map` (top-down PNG), `slice` (vertical
cut PNG), `column` (check before `tp`: a player teleported into terrain suffocates), `fill`, `tp`, `use`, `interact`,
`close`, `entities`, `summon`, `slot`, `tile`, `texturepack export [folder]` (the vanilla files as a modern pack, for
sprite names). Read PNGs with the Read tool. Put repeated check chains in small scripts
in `ports/<modid>/tools/` instead of retyping them.

## Workflow

1. **Set up.** Pick the source version closest to beta (1.7.10 over 1.12 over 1.21): its models, textures and data
   shapes map most directly. 1.7.10 jars use SRG names (`func_`, `field_`): read meaning from use, do not hunt mappings.
   Run `new_port.sh`. Third-party art never goes in the port's `assets/` or its `.bmod`: the `assets.toml` recipe
   (format in `tools/rewrite/modloader-guide.md`, "Assets players supply") tells the client how to build it from the
   player's own download in `mods/<modid>_assets/`, cached in `.cache/mods/assets/<modid>/`. The README names that
   download. The recipe writes the modern resource pack layout only, one file per sprite under `textures/`, sounds
   under `sounds/`, lang in `lang/en_US.lang`: the game loads each mod as a texture pack layer and player packs replace
   any of it. An old-style jar's grid sheets become `[[slice]]` steps via `recipe.py --sheet`, never sheets or root
   paths. Steps the generator cannot write (`[[compose]]` sprites from 3D renderers, extra downloads, renames) go in
   the port's own `tools/recipe.py`, which runs `T/py.sh recipe.py` and appends them. Text the port writes itself
   (names, messages, GUI labels) ships as the port's own `assets/<modid>/lang/en_US.lang`, the only file in its
   `assets/`. Copy vanilla model classes a mod model extends into `reference/vanilla/` for the converter. For testing,
   drop the download in the test game's `mods/<modid>_assets/` once.
2. **Deconstruct and plan.** From `reference/inventory.txt` and the source, write down what the mod is, not how its
   code is laid out: its content (blocks, items, entities, dimensions, structures), mechanics (what each thing does,
   with its rules and numbers), data (recipes, machine recipes, fuels, loot, worldgen, spawns, config) and UI flow.
   Each entry becomes a PORT_STATUS.md todo row naming the registry or system it goes through (Registry map below)
   and the tags its content joins, in dependency order: blocks and items, recipes, worldgen and dimension, entities,
   machines and GUIs, structures, bosses, player systems, extra slots, item behaviors, sounds and particles, config.
   Rows with no loader fit are loader extensions to build (Extending the loader). Milestones end with a deploy and a
   console check.
3. **Rewrite feature by feature** from the rows, not from the Java files. Find the SDK system with `api.sh` and copy
   the pattern from an exemplar. Open a source class only for a rule or number the row needs. Every Java `blockID ==`,
   `instanceof` on a mod block, metadata mask, private recipe map or hardcoded block list becomes a name, tag, state
   or registry entry, never copied. Run `T/audit.sh` when the feature builds.
   Cite the source class in PORT_STATUS.md, not in code comments. Decide per feature how it fits beta (Porting rules)
   before writing it.
4. **Extend the loader** only when `api.sh` shows no way (checklist below).
5. **Test** after each module with `deploy`, `cmd`, `errors`. Keep a bug list in PORT_STATUS.md instead of looping on
   one issue; fix the list at the end.
6. **Finish.** `T/audit.sh ports/<modid>` prints `clean`, or every remaining hit is listed in PORT_STATUS.md with
   why it stays (an air check, a tag list, a vanilla API that only takes numbers). Update PORT_STATUS.md. Run `cargo +nightly fmt` in the port and `cargo clippy` in `b1.7.3_rewrite`.
   Commit only when asked: a port holds Rust source, tools, manifests, `assets.toml` and its own lang file, never
   third-party art, `reference/` or AI files.
   `ports/` is either one git repo per port or a monorepo with one folder per mod; `new_port.sh` detects which.
   In user mode, list the local loader changes the port needs from `LOADER_CHANGES.md` in the final report.

## Exemplars

SDK examples, always present: `b1.7.3_rewrite/vendor/b1.7.3-modding-sdk/examples/` with `testmod` (every API module in
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
`onTick`; worldgen uses `terrain::Random` and the noise ports (matching the source's exact terrain is not required); check `isAuthority()` before changing the world
(single player loops packets back, same code both sides); client side motion on mobs and other players does nothing in
multiplayer since the server drives their positions, so port such code to the server; validate every serverbound payload; chat through
`translate("<modid>.gui.…")`; sounds as `<modid>.<path.with.dots>`; textures as `<modid>:<path>`.

Registry map. Each source concept goes to one loader system (`T/api.sh sdk register` lists the builders):

| Source | Loader |
|---|---|
| `Block`/`Item` classes, `blockID`, `itemID` | `ctx.blocks()`/`ctx.items()` rows, identity by name (`world.is`, `blockIs`, `ItemRef::is`); world calls take a `BlockRef` name, `notifyAround` for neighbor updates; logs and leaves in `minecraft:logs`/`minecraft:leaves` decay through the loader, never by hand |
| Metadata, `BlockState` | `ctx.blocks().states`, `StateData::of/with/get/flag`; models by state with `ctx.blocks().stateModel`, textures with `BlockBehavior::textureFor` |
| `OreDictionary`, hardcoded block or item lists | tags: seeded `minecraft:` and `c:` tags, `ctx.tags()`, `.tag()` on the mod's own rows |
| `CraftingManager`, `FurnaceRecipes`, `GameRegistry.addRecipe` | `ctx.recipes()`, tag ingredients (`keyTag` in shaped) |
| Machine recipe maps (macerator, enchanter, assembly) | `ctx.machines()`, the machine reads its registered recipes when it runs |
| Fuel handlers, burn time tables | `ctx.recipes().fuel`, read back with `fuelTicks` |
| Loot in chests, dungeon rewards, mob drops | `ctx.loot()` tables and pools; drops that depend on mob state (sheared, saddled, type, clone) through `ctx.loot().condition/count` and `PoolBuilder::when/unless/countBy`, never rolled in `onDeath` |
| `IWorldGenerator`, ore gen, trees, structures | named features: `ctx.worldgen().add(FeatureBuilder::ore/tree)` or `custom`, saplings through `world.placeFeature`, never a `ChunkPopulate` handler or a generator on a vanilla dimension; `ctx.structures()` |
| Dimensions, biomes | `ctx.dimensions()`, biome tags (tag every mod biome), `World::biomeSpawns` instead of private creature tables |
| Liquids, `LiquidStack`, buckets, cells | `ctx.fluids()`, containers through `ctx.fluids().container`, `containedFluid`/`fill`/`drainItem`; picky extraction through `world.extractMatching` |
| Power (EU, MJ) | `ctx.energy()` |
| `IInventory` access, pipes, cables, tanks | capabilities: `insertItem`, `extractItem`, `fillFluid`, `drainFluid`, `sendEnergy`; `ctx.services()` for mod APIs |
| Potions, attributes, particles, achievements, stats, game rules, config, lang | `ctx.effects()`, `attributes()`, `particles()`, `achievements()`, `stats()`, `gameRules()`, `config()`, `lang()` |
| `EntityList`, spawn lists | `ctx.entities()`, spawn rules, `modifySpawns` |

Data shapes (loader API 1.1, ABI 3). Identity is always by name, never by numeric id:
- **Block variants and facing.** Source metadata or block states become named states: `ctx.blocks().states(name, BlockStatesSpec)` or `data/<modid>/states/<block>.toml`.
  - List each property's values in the source's metadata order, so `ctx.meta()` code keeps working.
  - A block with more than 16 states gets extra hidden ids from the loader. Read and write such a block only through `world.blockState`/`setBlockState` or `ctx.state()`/`setState()`.
  - Textures per state go in `variants`.
- **Per-stack data.** Item NBT and capabilities become data components: `stackComponent`/`setStackComponent` with a `StackRef`.
  - A mod writes only `<modid>:*` components.
  - Stacks with different components never merge.
  - Damage stays durability. Use one item per variant instead of damage subtypes.
- **Data on things the mod does not own.** Entity, player, tile, chunk and world NBT or capabilities become per-mod slots:
  - entity: `entity.setData` or `setSynced`
  - player: `player.setData(key, ..)`
  - tile entity: `world.setTileAttachment`
  - chunk: `world.setChunkAttachment`
  - world: `setWorldData`

  Every slot is keyed by the mod id, so two mods never clash.
- **Edits to vanilla or other mods' content.** Property edits (hardness, light, flammability, tool) become `ctx.blocks().modify(BlockModifySpec)` or `data/<modid>/modify/blocks/*.toml`. Spawn list edits become `modifySpawns` or `modify/spawns/*.toml`. Mining speed for a tool class comes from the `minecraft:mineable/<pickaxe|axe|shovel>` tags. Conflicting edits are reported in the Mod Loader screen. Never replace a whole vanilla block for a property change.
- **Worldgen and commands.**
  - Name each worldgen feature uniquely. The name seeds its random, so other mods never shift it.
  - Commands answer to `/<modid>:<name>`. The short `/<name>` goes to the first mod that registers it.

## Extending the loader

General features only, never a one-mod hack. Paths below are inside `b1.7.3_rewrite/`. Touch points, in order:

1. Protocol: append variants at the end of `HostCall`, `GuestCall`, `GuestReply` or `EntityField` in
   `vendor/b1.7.3-modding-sdk/mod_protocol/src/abi.rs`; new spec fields in `spec.rs` as `Option` or `Default` types
   (spec structs are `#[serde(default)]`, so old mods still load). Released contracts never change: a changed one
   gets a new version.
2. Host: match arm in `crates/modloader/src/host/world.rs` (runtime calls) or `host/register.rs` (register phase);
   larger systems in their own `crates/modloader/src/<system>.rs` or `extensions.rs`. New templates are rows in
   `crates/modloader/src/entities.rs` (`ENTITY_TEMPLATES`) or `content/templates.rs` (`BLOCK_TEMPLATES`).
3. SDK wrapper next to its siblings in `b173_api/src/{world,register,screen}.rs`, in the prelude if mods use it
   everywhere.
4. Client side in `crates/client/src/modded/`, reached from an existing hook or a vanilla extension point. Only
   when neither fits, a new generic hook line with a `// rewrite:` comment, listed with a version in
   `crates/modloader/hooks.toml` (see Porting rules).
5. Dev console tools in `crates/modloader/src/devtools.rs` (add to `USAGE`).
6. `cargo build` and `cargo clippy`, then `T/test.sh deploy ports/<modid> --game`. Note the addition where the
   workspace keeps loader notes. Maintainer mode: SDK changes are committed in the SDK submodule, then bumped in the
   rewrite, only when the user asks. User mode: nothing is committed there, the change goes in `LOADER_CHANGES.md`.

Example chain, `World::lightning`: `HostCall::Lightning` (abi.rs) to its arm in `host/world.rs` to the wrapper in
`b173_api/src/world.rs`.

## Known traps

- A numeric id from `world.block(pos)`, a callback or a stack is a runtime handle. It changes on every remap, and mod
  ids sit above beta's 256, so any table sized for beta ids overflows. Compare through `blockIs`/`blockTagged`, never
  against a looked-up number.
- A block with more than 16 states has hidden page ids. `nameOf` and `world.is` answer with the block's own name for
  every page; a raw number compare misses all but the first page.
- A vanilla texture string that names no sprite fails registration. Use `minecraft:block/<sprite>` (names from
  `loader texturepack export`).
- A tag the port reads but nothing fills is empty, not an error. Tag the mod's own content and check
  `tagMembers` in a console test.

- `HostCall`, `HostReply` and spec structs are postcard encoded. Never add a field to an existing struct: ABI 2 guests would stop decoding. New data needs a new variant or a new struct.

- `T/modtest.sh` drives one shared test server and client (`b1.7.3_rewrite/target/modtest`, server in its `server/`). Never stop, reset or take
  over one another session started without asking the user.
- `cargo b173 build` already runs the wasm build; there is no separate `cargo build` step.
- Loader or SDK change without `deploy --game`: the server still runs the old binary without the new host calls.
- The test client's window loses focus and opens the pause menu; it is the harness, not the port.
