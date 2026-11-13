#!/usr/bin/env bash
# compares what a port registers and handles with what its source mod does, the completeness gate of a port
#   coverage.sh registry <modid> [kind]   what the loader registered for the mod, from the newest log holding its report
#                                         (deploy the port first); kind is block, item, recipe, entity, ...
#   coverage.sh names <port folder>       display names of the source that no registered block, item or lang row carries
#   coverage.sh recipes <port folder>     recipe counts of the source beside the port's registered counts
#   coverage.sh handlers <port folder>    source classes with gameplay methods and event handlers, then the port's
#                                         behaviors and event listeners, to match row by row
#   coverage.sh all <port folder>         names, recipes and handlers
# a line under "source only" is content the port lacks, or beta lacks it and PORT_STATUS.md says so
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

home="${MODTEST_HOME:-$game/target/modtest}"

# newest log that holds the registry report of the mod
reportLog()
{
    local modid="$1" log
    while IFS= read -r log; do
        if grep -q "registry::report.*\[$modid\]" "$log" 2> /dev/null; then
            echo "$log"
            return
        fi
    done < <(ls -t "$home/server/console.txt" "$home/console.txt" "$home"/logs/*.log "$game"/target/*/logs/client.log \
        "$game"/target/*/server/console.txt 2> /dev/null)
    fail "no registry report of $modid in a test log: run T/test.sh deploy on the port first"
}

# report rows of one mod as "kind name rest", the last report in the log
reportRows()
{
    local modid="$1" log
    log="$(reportLog "$modid")"
    grep "registry::report" "$log" | sed -E 's/^.*registry::report:[0-9]+\] //' | grep -F "[$modid]   " \
        | sed -E "s/^\[$modid\] +//" | awk '!seen[$0]++'
}

registry()
{
    local modid="${1:?modid}" kind="${2:-}"
    if [[ -n "$kind" ]]; then
        reportRows "$modid" | awk -v kind="$kind" '$1 == kind' | cut -d' ' -f2- | cut -c1-200
        return
    fi
    echo "log: $(reportLog "$modid")"
    reportRows "$modid" | awk '{ count[$1]++; names[$1] = names[$1] " " $2 } END { for (kind in count) printf "== %s (%d)\n%s\n", kind, count[kind], names[kind] }' \
        | sed "s/ $modid:/ /g"
}

portOf()
{
    port="$(absPath "${1:?port folder}")"
    modid="$(basename "$port")"
    src="$port/reference/src"
    [[ -d "$src" ]] || fail "no reference/src in $port"
}

lower()
{
    tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/ /g; s/^ +| +$//g' | sort -u
}

# display names the source gives its blocks, items and entities
sourceNames()
{
    {
        find "$src" \( -name 'en_US.lang' -o -name 'en_us.lang' \) -print0 | { xargs -0 -r grep -hE '^(item|tile|block|entity)\.[^=]*=' || true; } | cut -d= -f2-
        find "$src" -name 'en_us.json' -print0 | { xargs -0 -r grep -hoE '"(item|block|entity)\.[^"]*": *"[^"]*"' || true; } | sed -E 's/^[^:]*: *"//; s/"$//'
        { grep -rhoE --include='*.java' '(AddName|addName|AddLocalization|addNameForObject)\([^;]*"[^"]+"\)' "$src" || true; } | sed -E 's/.*"([^"]+)"\)$/\1/'
    } | tr -d '\r' | lower
}

# every name the port shows: registered spec names, registry paths and its lang rows, built or converted
portNames()
{
    {
        reportRows "$modid" | { grep -E '^(block|item|entity) ' || true; } | { grep -oE ' name .*' || true; } \
            | sed -E 's/^ name //; s/ (template|stack|durability|tool|armor|food|block item|record|texture|light|tile entity|material|container|size|health)( .*)?$//'
        reportRows "$modid" | { grep -E '^(block|item|entity) ' || true; } | cut -d' ' -f2 | sed -E "s/^$modid://; s/_/ /g"
        find "$port/assets" "$game"/target/*/.cache/mods/assets/"$modid" -name 'en_US.lang' -print0 2> /dev/null \
            | { xargs -0 -r grep -hE '^(item|tile|entity)\.[^=]*=' || true; } | cut -d= -f2-
    } | tr -d '\r' | lower
}

names()
{
    portOf "$1"
    local source ported missing
    source="$(sourceNames)"
    ported="$(portNames)"
    missing="$(comm -23 <(echo "$source") <(echo "$ported"))"
    echo "== names: $(wc -l <<< "$source") in the source, $(grep -c . <<< "$missing" || true) source only"
    [[ -z "$missing" ]] || echo "$missing" | tr '\n' ';' | fold -s -w 160
    echo
}

count()
{
    { grep -rhoE --include='*.java' "$1" "$src" || true; } | wc -l
}

recipes()
{
    portOf "$1"
    echo "== recipes, source calls beside registered rows (helpers and loops make the source count a floor)"
    printf 'source: shaped %s, shapeless %s, smelting %s, other register calls %s\n' \
        "$(count '\b(AddRecipe|addRecipe|addShapedRecipe|addEnchantedRecipe)\(')" \
        "$(count '\b(AddShapelessRecipe|addShapelessRecipe|registerShapeless)\(')" \
        "$(count '\b(AddSmelting|addSmelting|func_151394_a|func_151396_a|func_151393_a)\(')" \
        "$(count '^\s*(register|addRecipe)\("[a-z_0-9]+", *new ItemStack')"
    printf 'port:   shaped %s, shapeless %s, smelting %s, machine jobs and pages %s\n' \
        "$(reportRows "$modid" | grep -cE '^recipe [^ ]+ #[0-9]+ shaped' || true)" \
        "$(reportRows "$modid" | grep -cE '^recipe [^ ]+ #[0-9]+ shapeless' || true)" \
        "$(reportRows "$modid" | grep -c '^smelting ' || true)" \
        "$({ grep -rhoE --include='*.rs' '\bjob\(|\.machines\(\)\.(recipe|job|page)' "$port/src" || true; } | wc -l)"
    echo "list the port's rows: coverage.sh registry $modid recipe"
}

# gameplay methods a block, item or entity class overrides, by MCP name and 1.7.10 SRG name
readonly METHODS='onItemUse(First)?|onItemRightClick|hitEntity|onBlockDestroyed|onPlayerStoppedUsing|onUsingTick|onEaten|onFoodEaten|saddleEntity|itemInteractionForEntity|onLeftClickEntity|onCreated|onBlockStartBreak|onArmorTick|onBlockActivated|blockActivated|updateTick|randomDisplayTick|onNeighborBlockChange|onEntityCollidedWithBlock|onEntityWalking|onBlockAdded|onBlockRemoval|breakBlock|onBlockPlacedBy|onBlockClicked|harvestBlock|onFallenUpon|interact|attackEntityFrom|onDeath|dropFewItems|onStruckByLightning|func_77648_a|func_77659_a|func_77644_a|func_77654_b|func_77663_a|func_111207_a|func_150894_a|func_77615_a|func_77622_d|func_149727_a|func_149674_a|func_149734_b|func_149695_a|func_149670_a|func_149724_b|func_149726_b|func_149749_a|func_149689_a|func_149699_a|func_149636_a|func_149746_a|func_70085_c|func_70097_a|func_70645_a|func_70628_a|func_70077_a'
readonly BASEMOD='OnTickInGame|OnTickInGUI|GenerateSurface|GenerateNether|AddFuel|TakenFromCrafting|TakenFromFurnace|OnItemPickup|KeyboardEvent|HandleGUI|HandlePacket|DispenseEntity|RegisterAnimation'

handlers()
{
    portOf "$1"
    echo "== source classes with gameplay methods"
    { grep -rnoE --include='*.java' "(public|protected) [][A-Za-z<>]+ ($METHODS)\(" "$src" || true; } \
        | sed -E "s|^$src/||; s|\.java:[0-9]+:.* ([A-Za-z0-9_]+)\($|\t\1|; s|^.*/||" \
        | awk -F'\t' '{ if (!seen[$0]++) methods[$1] = methods[$1] " " $2 } END { for (class in methods) print class ":" methods[class] }' | sort
    echo "== source event handlers and ModLoader hooks"
    { grep -rnE --include='*.java' -A1 '@(SubscribeEvent|ForgeSubscribe|EventHandler)' "$src" || true; } | { grep -E 'public [a-z]+ [A-Za-z0-9_]+\(' || true; } \
        | sed -E "s|^$src/||; s|\.java-[0-9]+-.* ([A-Za-z0-9_]+)\(([A-Za-z0-9_.]+) .*|: \1(\2)|; s|^.*/||" | sort -u || true
    { grep -rnoE --include='*.java' "public [a-zA-Z]+ ($BASEMOD)\(" "$src" || true; } \
        | sed -E "s|^$src/||; s|\.java:[0-9]+:.* ([A-Za-z]+)\($|: \1|; s|^.*/||" | sort -u || true
    echo "== port behaviors"
    { grep -rnE --include='*.rs' 'impl (Item|Block|Entity|Tile|Effect)Behavior for' "$port/src" || true; } \
        | sed -E "s|^$port/src/||; s|:[0-9]+:impl ([A-Za-z]+)Behavior for ([A-Za-z0-9_]+).*| \1 \2|" \
        | awk '{ rows[$2] = rows[$2] " " $3 "(" $1 ")" } END { for (kind in rows) print kind ":" rows[kind] }' | fold -s -w 160
    echo "== port event listeners"
    { grep -rnoE --include='*.rs' 'events\(\)\.on::<[A-Za-z]+>' "$port/src" || true; } \
        | sed -E "s|^$port/src/||; s|:[0-9]+:events\(\)\.on::<([A-Za-z]+)>| \1|" \
        | awk '{ rows[$2] = rows[$2] " " $1 } END { for (event in rows) print event ":" rows[event] }' | sort
}

case "${1:-}" in
    registry) registry "${2:-}" "${3:-}" ;;
    names) names "${2:-}" ;;
    recipes) recipes "${2:-}" ;;
    handlers) handlers "${2:-}" ;;
    all) names "${2:-}"; recipes "${2:-}"; handlers "${2:-}" ;;
    *) sed -n '2,11p' "$0"; exit 1 ;;
esac
