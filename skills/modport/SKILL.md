---
name: modport
description: Port a Minecraft Java mod (any version, jar or source) to the b1.7.3_rewrite mod loader as one .bmod that runs on client and server, extending the loader and SDK where the mod needs something new. Use when the user says /modport, /port, "port this mod", or hands over a mod jar to bring to beta 1.7.3. Also use to audit a finished port against its source.
---

# Port a mod to the b1.7.3_rewrite loader

Java mods cannot run. A port is a Rust rewrite (wasm guest, `b173_api` SDK, API 2.0, ABI 4) that uses the decompiled
mod as its spec. Deconstruct the mod into content, mechanics and data, then rewrite it as a native loader mod: one
file in both client and server `mods/`, everything through the loader's registries. The Java is a source of facts,
not a structure to copy.

This file is the whole map. Follow "The run" from step 1 to step 8 without stopping to ask, except where "When to
ask" says so.

## Operating rules

- **Tools first, files second.** Never read loader design or progress docs, guides or whole SDK files to orient.
  `T/api.sh find <word>` answers "is there an API for this" in one call. Open a file only at the line a tool printed.
- **Work from the ledger.** `PORT_STATUS.md` holds one row per piece of content, behavior and data. The run is: pick
  the first open row, build it, check it, tick it. Never work on something that has no row; add the row first.
- **Read the source once per row.** Open a Java class only for the rule or number its row needs, read that method,
  close it. Never read a class top to bottom "to understand the mod", never re-read one already mined.
- **Narrow checks.** After a change run the port build and the one console check that covers it. Run the full gates
  (step 7) once, at the end. Never re-run a check that passed on unchanged code.
- **Park bugs.** A bug that is not in the row being built goes in the "Bugs" list of `PORT_STATUS.md`. Fix the list
  in step 6, not when found.
- **Never stop early.** A turn ends only when every row is ticked, or the only open rows need a person's eyes (client
  visuals) or a "When to ask" decision. A loader gap is work to do (Extending the loader), not a reason to stop or to
  write the feature down as a difference.
- **Report truthfully.** Say what was checked and how (build, console test, log), and what was not. "Checked one to
  one" may only be said of rows that step 7's tools show as matched.

## When to ask

Ask the user only for these, and keep working on other rows while waiting:

- starting a test client (it opens a window on their desktop), or taking over a test server another session runs
- changing vanilla game logic beyond a generic hook line
- a beta substitute that changes what the player must gather or do (recharge items whose ingredients beta lacks,
  content moved to another dimension). Pick the closest beta-native choice, build it, and list it for confirmation
- any commit, push or `gh` write

Everything else has a default in this file: take it and note it once in `PORT_STATUS.md`.

## Porting rules

- **Complete content, native structure.** Every block, item, entity, dimension, structure, mechanic, GUI, HUD
  element, config option and piece of data ships. Gameplay values (drops, costs, timings, spawn rates, cooldowns,
  durability) keep the source's numbers. Code layout is not ported: write each feature on what the SDK offers, the
  way the exemplars do. Never cut or simplify a feature because the SDK route takes more work.
- **Registered is not ported.** An item or block with a texture and a name but without its use, hit, tick or
  interact behavior is a missing feature. Step 7's handler check exists because this is the commonest way a port
  ends up incomplete.
- **Names, tags and states, never ids.** Numeric ids and metadata are runtime handles, reassigned on every remap. A
  port never keeps an id cache (`ids.rs`) or compares against looked-up numbers:
  - identity by name: `world.is(pos, "rubber_wood")`, `blockIs(block, name)`, `ItemRef::is`; place with
    `world.place` or `world.setBlockState`. A bare name means the mod's own namespace.
  - groups by tag: `world.tagged(pos, "minecraft:logs")`, `blockTagged`, `ItemRef::tagged`. Never write a list of
    vanilla names. Use the seeded `minecraft:` and `c:` tags or add a `c:` tag, and put the mod's own content in the
    tags it belongs to, so other mods' content takes part.
  - variants by state: named properties on the block builder, read and written with `StateData`. No meta bit masks.
  - vanilla textures by sprite name: `minecraft:block/oak_leaves`, `minecraft:item/stick`, `minecraft:gui/icons`.
- **Everything goes through a registry.** Recipes, machine jobs, fuels, loot, worldgen, structures, dimensions,
  biomes, fluids, energy, effects, attributes, particles, achievements, stats, game rules, damage types, config,
  lang, entities, spawns and accessory slots are registered. Machines look up registered jobs instead of private
  tables. Items, fluids and energy move through capabilities, never by checking for the mod's own blocks.
- **The game stays vanilla.** Never change vanilla logic or content in `b1.7.3_rewrite` (`crates/game`,
  `crates/server`, vanilla files in `crates/client`). The mod reaches the game only through the loader API. Never
  replace a vanilla screen: extra UI is an overlay behind a toggle on the vanilla screen.
- **The mod adapts to beta.** Where beta lacks a system (enchanting, potions brewing, hunger, experience, creative
  mode, written books, leads, later blocks and mobs) use the closest beta behavior or leave the feature out, and
  note it once in `PORT_STATUS.md` under "Beta differences". Never import later-version content into the game.
- **Source bugs.** Fix a plain bug (a flag never set, a counter that leaks, a loop that cannot end) and list it
  under "Source bugs fixed". Keep quirks players rely on (an unkeyed recipe letter that leaves a slot empty).
- **Loader changes are universal.** A new loader feature is general, named and documented without the mod, and keeps
  every other mod working. Never hardcode a mod's names or rules in the loader.

## Workspace, modes, tools

Paths are relative to the workspace root, the folder holding `b1.7.3_rewrite/`, `ports/` and the kit
`b1.7.3_modport/`. `T/` is `tools/modport/` (from a port folder `../../tools/modport/`). Fix or extend tools in
`b1.7.3_modport/tools/`, never inside a port. When a tool fails on a missing dependency run `T/doctor.sh`. Call
Python tools through `T/py.sh`.

Check once per session: `test -f .modport-maintainer`. With the marker (maintainer mode) the loader, SDK and kit
repos are the user's own; commit there when asked. Without it (user mode) loader and SDK changes stay in the working
tree, are logged in `ports/<modid>/LOADER_CHANGES.md`, and are never committed, pushed or sent upstream by any `gh`
write. Never create the marker.

| Tool | Use it for | Output |
|---|---|---|
| `T/new_port.sh <modid> <jar> [name] [more archives]` | Step 1. Manifests, `assets.toml`, decompile, inventory | `ports/<modid>/` |
| `T/decompile.sh <port> <jar>...` | Re-running the decompile. Merges archives; remaps a ModLoader era mod from obfuscated beta names to MCP names when the workspace has the mappings (`doctor.sh` says) | `reference/src`, `reference/inventory.txt` |
| `T/inventory.sh <src>` | What the source registers, all Forge, Fabric and ModLoader idioms | grouped lists |
| `T/api.sh find <word>` | First stop for any API question: SDK signatures and protocol variants naming the word | lines with file:line |
| `T/api.sh sdk <file>` / `spec <Struct>` / `enum <Name>` / `templates` / `events` / `console` / `hooks` | One SDK file's signatures (`world`, `register`, `screen`, `behavior`, `events`, `terrain`, `attachment`), a spec's fields, an enum's variants (`EntityField`, `ModelOp`, `WorldRequest` and the other request groups), template names, event names, dev console syntax, hook names | one line per item |
| `T/coverage.sh registry <modid> [kind]` | What the loader registered for the port, from the last deploy's log | names per kind, or full rows of one kind |
| `T/coverage.sh names <port>` / `recipes <port>` / `handlers <port>` / `all <port>` | Step 7 gates: source display names with no port row, recipe counts side by side, source gameplay methods and event handlers beside the port's behaviors and listeners | "source only" lists |
| `T/audit.sh <port>` | Code that bypasses names, tags, states and registries | hits per rule, `clean` when none |
| `T/py.sh recipe.py <jar> <modid> [--sheet <png> <names.txt> <to>]... [--url <page>]` | Regenerating `assets.toml`. `--sheet` cuts an old 16x16 grid sheet, names.txt lines are `<slot> <name> [span]` | `assets.toml` |
| `T/py.sh convert_models.py --out src/models/generated.rs <Model.java>...` | ModelBase constructors to parts and boxes | generated Rust, never hand edited |
| `T/test.sh deploy <port> [--game]` | Every test cycle: build, install alone, start the test server. `--game` after any loader or SDK change. Refuses while a server runs | console tail |
| `T/test.sh errors [n]` | After every deploy: panics, traps, errors and loader warnings. A loader warning names content the loader dropped (an unknown item in loot, an empty recipe slot) | lines of both logs |
| `T/modtest.sh cmd <console line>` / `log server 80` | Driving and reading the server | reply lines |
| `T/modtest.sh client` / `shot <png>` | Visual checks. Ask first | PNG, read with the Read tool |

Console (`T/modtest.sh cmd loader ...`, syntax from `T/api.sh console`): `gen`, `map`, `slice`, `column` (check
before `tp`), `fill`, `tp`, `use`, `interact`, `close`, `entities`, `summon`, `slot`, `tile`, `container`,
`spawns`, `structures`, `locate`, `features`,
`texturepack export`. Put a repeated check chain in a script under `ports/<modid>/tools/`.

## The run

1. **Set up.** Pick the source version closest to beta (a beta ModLoader build over 1.7.10 over 1.12). Run
   `new_port.sh`; pass every archive of a mod shipped in parts. A 1.7.10 jar keeps SRG names (`func_`, `field_`):
   read meaning from use. Third-party art never enters the port or its `.bmod`: `assets.toml` (format in
   `tools/rewrite/modloader-guide.md`, "Assets players supply") builds the modern pack layout from the player's
   own download in `mods/<modid>_assets/`. Steps the generator cannot write go in the port's `tools/recipe.py`.
   Text the port writes itself is its own `assets/<modid>/lang/en_US.lang`. For testing, drop the download in the
   test game's `mods/<modid>_assets/` once.
2. **Build the ledger.** Fill `PORT_STATUS.md` before writing any code. Sources, in this order, one pass each:
   - `reference/inventory.txt`: one row per block, item (each metadata or NBT variant is its own row), entity, tile
     entity, GUI, dimension, biome, structure, world generator, particle, sound set.
   - `T/coverage.sh handlers <port>` (the source half): one row per class and method listed, and one per event
     handler and ModLoader hook. These rows are the mod's behavior; they are what gets forgotten.
   - The mod's registry classes: every recipe call, smelting, fuel, machine recipe table, loot table, spawn entry,
     achievement, with counts.
   - The config class: every option with its default, each a row.
   - The client overlay and HUD classes, key bindings, packets (each packet is a client to server or server to
     client flow to rebuild on channels or synced state).
   Each row names the loader system it goes through (Registry map), the tags its content joins and, where beta
   lacks it, the beta decision. Rows with no loader fit are marked "loader" and built in step 4. Order the rows:
   blocks and items, recipes and data, worldgen and dimension, entities, machines and GUIs, structures, bosses,
   player systems and events, HUD, sounds and particles, config.
3. **Build row by row.** For each row: `T/api.sh find`, copy the pattern from an exemplar, read the one source
   method, write it, build. Every Java `blockID ==`, `instanceof`, metadata mask, private recipe map or hardcoded
   list becomes a name, tag, state or registry entry. Cite the source class in `PORT_STATUS.md`, not in code. Deploy
   and run a console check at the end of each ledger group, not each row.
4. **Extend the loader** for rows marked "loader" (checklist below), then return to the ledger.
5. **Test each group** with `deploy`, `errors`, `cmd`. A check must prove a result: place the block and read it
   back, run the machine and read its output slot, summon the mob and read `entities`. Write down in the row what
   was proven.
6. **Fix the bug list.**
7. **Gates.** All four must pass before the port is called done. Deploy first so the registry report is fresh.
   - `T/test.sh errors`: no panic, trap, error or loader warning.
   - `T/coverage.sh names <port>`: every "source only" name is ported or listed under "Beta differences".
   - `T/coverage.sh recipes <port>`: registered counts explain the source counts. When the source registers
     recipes in one list, compare the lists in order by pattern, result, count and damage, and map every source
     ingredient to exactly one port item (a script over both tables, not a read-through).
   - `T/coverage.sh handlers <port>`: every source class and method row has a port behavior or listener that does
     what the method does, checked by opening both. Every config option of the source exists or is listed as left
     out with the reason.
   - `T/audit.sh <port>` prints `clean`, or each hit is listed in `PORT_STATUS.md` with why it stays.
8. **Finish.** `cargo +nightly fmt` in the port, `cargo clippy` in `b1.7.3_rewrite` if the loader changed. Update
   `PORT_STATUS.md`: done rows, "Beta differences", "Source bugs fixed", "Not checked" (client visuals,
   multiplayer). Commit only when asked, one commit per feature or fix: a port holds Rust source, tools, manifests,
   `assets.toml` and its own lang file, never third-party art, `reference/` or AI files. In user mode list the
   loader changes from `LOADER_CHANGES.md` in the final report.

Auditing an existing port is steps 7 and 8 alone: deploy, run the gates, add a ledger row for each gap, build the
rows, run the gates again.

## Source to loader

Registries (`T/api.sh sdk register` lists the builders):

| Source | Loader |
|---|---|
| `Block`/`Item` classes | `ctx.blocks()`/`ctx.items()` rows from one const array per kind; a block's item behavior with `BlockSpecBuilder::itemBehavior` |
| Metadata, `BlockState` | properties and variants on the block builder, `StateData::of/with/get/flag`, `stateModel`, `textureFor` |
| `OreDictionary`, hardcoded lists | seeded `minecraft:` and `c:` tags, `ctx.tags()`, `.tag()` on the mod's rows |
| `CraftingManager`, `addRecipe`, `addSmelting` | `ctx.recipes()`, `keyTag` and `shapelessTagged` for tag or any-damage ingredients |
| Machine recipe maps | `ctx.machines().job`, the machine runs `matchJob`; `inputAny` for "anything but" inputs |
| Fuel handlers | `ctx.recipes().fuel`, `ctx.machines().fuel`, read with `fuelTicks`/`machineFuel` |
| Chest loot, mob drops | `ctx.loot()` pools, state dependent drops through loot conditions, never rolled in `onDeath` |
| `IWorldGenerator`, ores, trees | named features: `ctx.worldgen().add` or `custom`; a mod dimension's decoration steps are named features placed in the source's order on the chunk random |
| Dimensions, biomes, structures | `ctx.dimensions()`, biome tags, `ctx.structures()` with a finder |
| Liquids, buckets, cells | `ctx.fluids()` and containers |
| Power | `ctx.energy()`, tile `energy`/`tank` buffers the loader keeps and syncs |
| `IInventory`, pipes, tanks | capabilities: `insertItem`, `extractItem`, `fillFluid`, `drainFluid`, `sendEnergy`; `ctx.services()` for mod APIs |
| Extra equipment slots | `ctx.accessories()` slots taking a `c:accessories/<kind>` tag, an overlay on `GuiInventory` |
| Potions, attributes, particles, achievements, stats, game rules, config, lang | `ctx.effects()`, `attributes()`, `particles()`, `achievements()`, `stats()`, `gameRules()`, `config()`, `lang()` |
| `EntityList`, spawn lists | `ctx.entities()` with `SpawnSpec`, `modifySpawns` |

Behavior hooks:

| Source | Loader |
|---|---|
| `onItemUse`, `onItemRightClick`, `hitEntity`, `onBlockDestroyed`, use duration and release | `ItemBehavior`: `onUseOnBlock`, `onRightClick`, `onHitEntity`, `onBlockDestroyed`, `useDuration`/`onUsingTick`/`onStoppedUsing`/`onUseFinish`, `name` for per-stack names |
| Item used on a mob | the mod entity's `EntityBehavior::onInteract(entity, player)`; for vanilla mobs `ItemBehavior::onInteractEntity`, which names no player (find the nearest player holding the item) |
| Block methods | `BlockBehavior` (`T/api.sh sdk behavior`) |
| Entity AI, update, interact, hurt, death | `EntityBehavior`: `onAi` (replaces template AI), `onTick`, `onInteract`, `onHurt`, `onDeath`, `canSpawn`, `pose` |
| `PlayerInteractEvent` right click on a block | `ItemUseOnBlock` (any held item, blocks included, cancel stops the use) and `BlockActivate` (the block clicked) |
| `FillBucketEvent` | `ItemUseOnBlock` with the bucket stack, the target is the block next to the clicked face |
| `LivingAttackEvent`, `LivingHurtEvent`, `LivingFallEvent` | `LivingAttack` (cancel) and `LivingHurt` (amount is mutable); the hit's type from `damageType()`, a fall is `minecraft:fall` |
| `LivingDeathEvent`, `LivingDropsEvent` | `LivingDeath`, `LivingDrops` (`addDrop`; the event runs before the loot falls and does not list it) |
| `EntityStruckByLightningEvent` | `LightningStrike` (cancel spares the entity) |
| `BreakEvent`, `HarvestDropsEvent`, `BreakSpeed` | `BlockBreak`, `BlockHarvestDrops` (drops are mutable), `PlayerBreakSpeed` |
| `ItemCraftedEvent`, pickup, toss | `ItemCrafted`, `ItemPickup`, `ItemToss` |
| Login, respawn, dimension change, sleep | `PlayerLogin`, `PlayerRespawn`, `PlayerChangeDimension`, `PlayerSleep` |
| `LivingUpdateEvent`, player tick, `OnTickInGame` | `TickPost` over `allPlayers()`, client-only work behind `isClient()` and `localPlayer()` |
| `RenderGameOverlayEvent`, HUD classes | `ctx.screens().hud(draw)` with `Draw` (`texture` for 256 sheets, `region`, `tinted`, `centered`) |
| GUIs and containers | `ctx.screens().register` with `ScreenBuilder`, buttons as serverbound channel messages validated on the server |
| Packets | `ctx.channels()` for events and button presses; state the client must see is synced data, not a packet |
| Key bindings | `ctx.keybinds()` |

State:

| Source | Loader |
|---|---|
| Fields of a mod entity, extended entity properties | `EntityState<T>` statics (`.saved()` for NBT fields, `.kept()` to survive death), `entity.setSynced` for what clients draw |
| Player NBT of the mod | `player.setData(key, ..)`; client-visible parts in synced data |
| Tile entity fields | tile data with `Tile::new(..).synced()` |
| Data on blocks, chunks, the world that other code reads | `Attachment<T>` statics (`saved()`, `synced()`), declared with `ctx.attachments().declare`, clients hear changes through `watch` |
| Item NBT | data components (`stackComponent`/`setStackComponent`); one item per variant instead of damage subtypes |
| World saved data | `setWorldData`, shared across saves `setSharedData` |

Shapes that always apply: renderer GL calls become `Program` ops in the entity's `pose`; check `isAuthority()`
before changing the world (single player runs client and server code in one place, so the same handler sees both);
client-side motion on mobs and other players does nothing in multiplayer, port it to the server; validate every
serverbound payload; chat through `translate("<modid>.gui...")`; sounds as `<modid>.<path.with.dots>`; textures as
`<modid>:<path>`; config values are readable during registration once `config().options` ran.

## Exemplars

SDK examples, always present: `b1.7.3_rewrite/vendor/b1.7.3-modding-sdk/examples/` with `testmod` (every API module
in one file), `ruby` (data only), `energy`, `energy_api`, `machines` (services between mods).

A finished port, when the workspace has one, is the faster map (`ports/aether/src` unless noted):

| Need | File |
|---|---|
| Block and item tables, tools, armor, food | `blocks.rs`, `items.rs`, `tools.rs` |
| Item behaviors: use on block, eat, throw, cooldown, hit effects | `items.rs`, `weapons.rs`, `gear.rs` |
| Event handlers for world rules and player protections | `portal.rs` (`bucketUsed`), `abilities.rs` |
| HUD overlays | `hud.rs`, `portal_overlay.rs` |
| Config options | `config.rs` (port every spawn rate roll, missing ones flood the world) |
| Entities: passive mount, hostile, flyer, projectile, synced state | `entities/phyg.rs` + `mount.rs`, `cockatrice.rs`, `zephyr.rs`, `projectile.rs`, `moa.rs` |
| Models and animation | `models/mod.rs` |
| Boss, boss bar, dialogue screen | `entities/bosses/mod.rs`, `valkyrie_queen.rs` |
| Machine with GUI, jobs and tile data | `machines.rs` |
| Extra equipment slots, render layers | `accessories.rs` |
| Dimension, terrain, ordered decoration features | `world/mod.rs`, `world/terrain.rs`, `world/decorate.rs` |
| Structures | `world/dungeons/mod.rs`, `writer.rs` |
| Recipes as one ordered table | `ports/ic2/src/recipes.rs` |
| Energy net, cables, machines taking tags | `ports/ic2/src/energy/`, `ports/ic2/src/machines/processing.rs` |
| Pipes, capabilities, synced attachments with `watch` | `ports/buildcraft/src/transport/`, `ports/buildcraft/src/energy/engine.rs` |
| Tile data driving textures, channels for GUI buttons, a service other mods call | `ports/wirelessredstone/src/` |

## Extending the loader

General features only. Paths are inside `b1.7.3_rewrite/`. A new host call:

1. Protocol: append the variant at the end of its group enum in
   `vendor/b1.7.3-modding-sdk/mod_protocol/src/abi/calls/<group>.rs` (`T/api.sh enum HostCall` lists the groups) and
   give it a row in the side table `mod_protocol/src/rules.rs`. Shared types live in `abi/shared.rs`, `abi/types.rs`
   and `spec.rs`. Spec structs travel as named data: a new field with a default is safe. Never reorder or remove
   enum variants.
2. Host: the match arm in `crates/modloader/src/host/world.rs` (runtime) or `host/register.rs` (register phase);
   larger systems in their own file. Templates are rows in `crates/modloader/src/entities.rs` or
   `content/templates.rs`.
3. SDK wrapper beside its siblings under `b173_api/src/`, exported in the prelude when mods use it everywhere.

A new event, when the game does something no event covers:

1. `EventKind` variant at the end, plus its `EVENT_NAMES` row and count, in `mod_protocol/src/abi/events.rs`; the
   marker in `event_types!` in `b173_api/src/events.rs`.
2. `GameEvent` variant in `crates/game/src/hooks/mod.rs`, fired by one line at the vanilla site
   (`crate::hooks::fire(..)` returns true when a mod canceled); behavior-neutral with zero mods.
3. Kind mapping and payload in `crates/modloader/src/gameevents.rs`; a row in `crates/modloader/hooks.toml`.

Example chain, `lightning_strike`: `EventKind::LightningStrike`, `GameEvent::LightningStrike` fired in
`entity_lightning_bolt.rs` before `onStruckByLightning`, posted as `EventData::Entity` in `gameevents.rs`.

Then `cargo check --workspace` in `b1.7.3_rewrite`, `T/test.sh deploy <port> --game`, and note the addition where
the workspace keeps loader notes (maintainer mode) or in `LOADER_CHANGES.md` (user mode).

## Known limits and traps

- A mod cannot read the wall clock or files. Date-driven features become config options; say so in
  `PORT_STATUS.md`.
- One guest call has a time budget. Never scan thousands of blocks in one call; spread the work over ticks.
- A server never learns a player's own motion. Derive speed from the position change between ticks.
- A numeric id from `world.block(pos)`, a callback or a stack changes on every remap, and mod ids sit above beta's
  256. Compare through `blockIs`/`blockTagged`. A block with more than 16 states has hidden page ids that only
  `world.is` and `nameOf` resolve.
- A vanilla texture string that names no sprite fails registration (names from `loader texturepack export`).
- A tag the port reads but nothing fills is empty, not an error. An item name in loot or a recipe that is not
  registered is dropped with a loader warning, not an error: `T/test.sh errors` shows it.
- A lang row beats a spec `name`. A name that depends on config or on the stack is an `ItemBehavior::name`.
- `LivingDrops` cannot see what falls. To change a mob's own loot use loot pools and conditions; to act on the fallen
  items, handle them at the end of the tick.
- Player data set on an entity does not survive death unless it is `player.setData` or a `.kept()` state. Worn
  extra-slot items do not drop on death by themselves: the port drops them in `LivingDeath`.
- `T/modtest.sh` drives one shared test server and client. `MODTEST_HOME` and `MODTEST_PORT` give a session its
  own. Never stop, reset or take over one another session started.
- `cargo b173 build` runs the wasm build. After a loader or SDK change, a deploy without `--game` runs the old
  binary.
- The registry report `coverage.sh` reads comes from the last deploy. Deploy before running the gates.
