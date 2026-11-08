#!/usr/bin/env bash
# lists what a decompiled mod registers, grouped by kind, covering 1.2 to 1.21 Forge, Fabric and ModLoader idioms
#   inventory.sh <decompiled source dir>
set -euo pipefail

src="${1:?decompiled source dir}"

section()
{
    local title="$1" pattern="$2"
    local hits
    hits=$(grep -rhoE "$pattern" --include='*.java' "$src" | sort -u || true)
    [[ -z "$hits" ]] && return
    printf '== %s (%s)\n%s\n' "$title" "$(wc -l <<< "$hits")" "$hits"
}

section "registry classes" "class [A-Z][A-Za-z]*(Blocks|Items|Entities|EntityTypes|TileEntities|BlockEntities|Registry|Registries|Sounds|Biomes|Dimensions|Recipes|Structures|Features)[A-Za-z]* "
named()
{
    local title="$1" pattern="$2" toRow="$3" keep="${4:-.}"
    local hits
    hits=$(grep -rhoE "$pattern" --include='*.java' "$src" | sed -E "$toRow" | grep -E "$keep" | sort -u || true)
    [[ -z "$hits" ]] && return
    printf '== %s (%s)\n%s\n' "$title" "$(wc -l <<< "$hits")" "$(column -c 120 <<< "$hits" | expand -t 8 | tr -s " ")"
}

# "name Class" rows from register helpers, as register("zanite", new ItemZanite()) or BLOCKS.register("x", () -> new Block
registered='register[A-Za-z]*\("[a-z0-9_]+", *(\(\) *-> *)?new [A-Z][A-Za-z0-9_]*'
toRow='s/^[^"]*"([^"]+)".*new ([A-Za-z0-9_]+)$/\1 \2/'
named "blocks" "$registered" "$toRow" ' Block'
named "items" "$registered" "$toRow" ' Item'
named "other registrations" "$registered" "$toRow" ' [^BI]|^[^ ]+ $' 
named "entities" '[A-Z][A-Za-z0-9_]*\.class, *"[a-z0-9_]+"' 's/^([A-Za-z0-9_]+)\.class, *"([^"]+)"/\2 \1/'
section "names without a register helper" '(setRegistryName|setUnlocalizedName|setBlockName|setItemName|setTranslationKey)\("[a-z0-9_.:]+"'
section "deferred and fabric registrations" '(BLOCKS|ITEMS|ENTITIES|ENTITY_TYPES|BLOCK_ENTITIES|TILE_ENTITIES|SOUNDS|SOUND_EVENTS|FEATURES|STRUCTURES)\.register\("[a-z0-9_]+"'
section "entity registration calls" '(registerModEntity|registerGlobalEntityID|EntityType\.Builder\.of|FabricEntityTypeBuilder)\([A-Za-z0-9_.]+'
section "tile entities" '(registerTileEntity|setTileEntityName)\([A-Za-z0-9_.]+, *"[A-Za-z0-9_:.]+"'
section "models" 'class [A-Za-z0-9_]+ extends (ModelBase|ModelBiped|ModelQuadruped|EntityModel|HierarchicalModel|AgeableListModel)'
section "renderers" 'class [A-Za-z0-9_]+ extends (Render[A-Za-z]*|[A-Za-z]*Renderer)( |<)'
section "guis and containers" 'class [A-Za-z0-9_]+ extends (Gui[A-Za-z]*|Container|AbstractContainerScreen|Screen|AbstractContainerMenu)( |<)'
section "world and dimension" 'class [A-Za-z0-9_]+ (extends|implements) (WorldProvider|ChunkProvider[A-Za-z]*|IChunkProvider|ChunkGenerator|BiomeGenBase|WorldGenerator|MapGenStructure|StructureStart|StructureComponent|Feature|Structure|Teleporter)( |<)'
section "event handlers" '@(SubscribeEvent|ForgeSubscribe|EventHandler)'
section "network packets" 'class [A-Za-z0-9_]+ (extends|implements) (IMessage|AbstractPacket|Packet|CustomPacketPayload)( |<)'
find "$src" -name '*.lang' -o -name 'en_us.json' -o -name 'en_US.lang' 2>/dev/null | sed 's/^/lang: /'
