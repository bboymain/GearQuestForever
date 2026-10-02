"""Build _generated/Locations.generated.lua for GearQuest Forever.

Reads QuestieDB's baked TOC metadata (base64 + CBOR), QuestieDB's Forever zone
tables, and GearQuest's own hunt tables. Emits a coordinate index keyed by
itemId so GearQuest pins need no other addon at runtime.

Usage:  python _tools/generate_locations.py
"""

import base64
import glob
import os
import re
import sys
import zlib

import cbor2

HERE = os.path.dirname(os.path.abspath(__file__))
ADDONS = os.path.abspath(os.path.join(HERE, "..", ".."))
GQ_DIR = os.path.join(ADDONS, "GearQuestForever")
QDB_DIR = os.path.join(ADDONS, "QuestieDB")
QDB_TOC = os.path.join(QDB_DIR, "QuestieDB_Forever.toc")
AREA_MAP_LUA = os.path.join(QDB_DIR, "support", "Forever", "Zones", "areaIdToUiMapId.lua")
DUNGEONS_LUA = os.path.join(QDB_DIR, "support", "Forever", "Zones", "dungeons.lua")
OUT_LUA = os.path.join(GQ_DIR, "_generated", "Locations.generated.lua")

GQ_DIRS = ["GearQuestForever"] + [
    "GearQuestForever_" + c for c in
    ("PALADIN", "WARRIOR", "HUNTER", "DRUID", "SHAMAN", "ROGUE", "PRIEST", "WARLOCK", "MAGE")
]

MAX_GROUP = 6
MAX_WORLD_ZONES = 4
MAX_WORLD_POINTS = 12
MAX_WORLD_SAMPLES = 4  # collect 4x, then stride-sample evenly when writing
MAX_TRAINERS = 30
CHAIN_HOPS = 4

PROFESSIONS = (
    "alchemy", "blacksmithing", "enchanting", "engineering", "herbalism",
    "leatherworking", "mining", "skinning", "tailoring", "cooking", "fishing",
    "first aid", "lockpicking", "jewelcrafting", "archaeology",
)

# subName stems, e.g. "Journeyman Blacksmith", "Alchemy Trainer", "Master Cook".
PROF_STEMS = {
    "alchemy": ("alchemy", "alchemist"),
    "blacksmithing": ("blacksmith", "armorsmith", "weaponsmith"),
    "enchanting": ("enchant",),
    "engineering": ("engineer",),
    "herbalism": ("herbalis", "herbaliz", "herb gather"),
    "leatherworking": ("leatherwork", "leathercraft"),
    "mining": ("mining", "miner"),
    "skinning": ("skinning", "skinner"),
    "tailoring": ("tailor",),
    "cooking": ("cook",),
    "fishing": ("fish",),
    "first aid": ("first aid",),
    "lockpicking": ("lockpick",),
    "jewelcrafting": ("jewelcraft",),
    "archaeology": ("archaeolog",),
}

# Trainers only: drop suppliers/vendors/goods sellers from the same profession.
PROF_SUB_EXCLUDE = ("suppl", "vendor", "goods", "merchant", "trade", "for sale", "trade goods")

# --- QuestieDB TOC metadata ------------------------------------------------

def read_toc_meta(path):
    meta = {}
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            if not line.startswith("## "):
                continue
            body = line[3:].rstrip("\n")
            if ":" not in body:
                continue
            key, value = body.split(":", 1)
            meta[key.strip()] = value.strip()
    return meta


class EntityStore:
    """Baked-mode reads: base64 -> (zlib for IDS) -> CBOR."""

    def __init__(self, meta, prefix, field_of_name):
        self.meta = meta
        self.prefix = prefix
        self.field_of_name = field_of_name
        self._ids = None
        self._scalar = {}

    def stored(self, key):
        value = self.meta.get(key)
        if value is None:
            return None
        match = re.match(r"^~(\d+)~$", value)
        if match:
            count = int(match.group(1))
            parts = []
            for i in range(1, count + 1):
                part = self.meta.get("%s-%d" % (key, i))
                if part is None:
                    return None
                parts.append(part)
            return "".join(parts)
        return value

    def ids(self):
        if self._ids is None:
            raw = base64.b64decode(self.stored(self.prefix + "IDS"))
            data = None
            last = None
            for wbits in (15, -15, 47):
                try:
                    data = cbor2.loads(zlib.decompress(raw, wbits))
                    break
                except Exception as exc:  # noqa: BLE001 - try the next framing
                    last = exc
            if data is None:
                raise last
            self._ids = data
        return self._ids

    def scalar(self, entity_id):
        if entity_id in self._scalar:
            return self._scalar[entity_id]
        stored = self.stored("%s%d-S" % (self.prefix, entity_id))
        row = cbor2.loads(base64.b64decode(stored)) if stored else None
        if isinstance(row, list):
            # Sparse Lua rows serialize as arrays; restore 1-based field indices.
            row = {index + 1: value for index, value in enumerate(row)}
        self._scalar[entity_id] = row
        return row

    def field(self, entity_id, name):
        index = self.field_of_name.get(name)
        if index is None:
            return None
        row = self.scalar(entity_id)
        if row is None:
            return None
        stored = self.stored("%s%d-%d" % (self.prefix, entity_id, index))
        if stored is not None:
            return cbor2.loads(base64.b64decode(stored))
        value = row.get(index)
        return value if isinstance(value, list) else None

    def scalar_field(self, entity_id, name):
        index = self.field_of_name.get(name)
        if index is None:
            return None
        row = self.scalar(entity_id)
        if row is None:
            return None
        value = row.get(index)
        if isinstance(value, bytes):
            return value.decode("utf-8", "replace")
        return value


def as_list(value):
    """CBOR maps stand in for sparse Lua arrays; normalize to a list."""
    if isinstance(value, list):
        return value
    if isinstance(value, dict) and value:
        if not all(isinstance(key, int) for key in value):
            return []
        base = 0 if (0 in value and 1 not in value) else 1
        top = max(value)
        return [value.get(i) for i in range(base, top + 1)]
    return []


def as_ints(value):
    return [int(item) for item in as_list(value) if isinstance(item, int)]


def fields_from_meta(source, entity):
    text = open(source, "r", encoding="utf-8", errors="replace").read()
    text = re.sub(r"--[^\n]*", "", text)
    block = text.split("keys = {", 1)[1].split("},", 1)[0]
    keys = {}
    for name, index in re.findall(r"\['([A-Za-z0-9_]+)'\]\s*=\s*(\d+)", block):
        keys[name] = int(index)
    prefix = re.search(r"metaPrefix\s*=\s*'([^']+)'", text).group(1)
    return "X-" + prefix, keys


# --- plain Lua support tables ---------------------------------------------

def read_return_table(path):
    """Parse `Something = [[return { [k] = v, ... }]]` blocks (last wins)."""
    text = open(path, "r", encoding="utf-8", errors="replace").read()
    table = {}
    for block in re.findall(r"\[\[return\s*\{(.*?)\}\]\]", text, re.S):
        for key, value in re.findall(r"\[(\d+)\]\s*=\s*(\d+)", block):
            table[int(key)] = int(value)
    return table


def read_dungeons(path):
    """areaId (including interior aliases) -> (parentAreaId, x, y)."""
    text = open(path, "r", encoding="utf-8", errors="replace").read()
    lookup = {}
    pattern = re.compile(
        r"\[(\d+)\]\s*=\s*\{"
        r'"[^"]*"\s*,\s*'
        r'(?:\{([^}]*)\}|nil)\s*,\s*'
        r"(\d+)\s*,\s*"
        # {{areaId, x, y}} or {{areaId, x, y},{areaId, x, y},...}: first wins.
        r"\{\{(\d+),\s*([\d.]+),\s*([\d.]+)\}",
    )
    for key, alts, parent, loc_area, x, y in pattern.findall(text):
        areas = [int(key)]
        if alts.strip():
            areas.extend(int(a) for a in alts.split(","))
        for area in areas:
            lookup[area] = (int(loc_area), int(parent), float(x), float(y))
    return lookup


def read_gearquest_item_ids():
    ids = set()
    for addon in GQ_DIRS:
        for path in glob.glob(os.path.join(ADDONS, addon, "**", "*.lua"), recursive=True):
            text = open(path, "r", encoding="utf-8", errors="replace").read()
            ids.update(int(m) for m in re.findall(r"itemId\s*=\s*(\d+)", text))
            ids.update(int(m) for m in re.findall(r"\[(\d{2,6})\]\s*=\s*\{[^{}]*?sourceType", text))
            ids.update(int(m) for m in re.findall(r'\{\s*(\d{2,6})\s*,\s*"[A-Za-z]+"\s*,\s*\d+', text))
    return ids


# --- resolution helpers ----------------------------------------------------

def faction_code(raw):
    if isinstance(raw, bytes):
        raw = raw.decode("utf-8", "replace")
    if raw in ("A", "H"):
        return raw
    return "B"


def merge_faction(a, b):
    if a is None:
        return b
    if b is None:
        return a
    if a == b:
        return a
    return "B"


def dedupe_push(group, seen, item, cap):
    if len(group) >= cap:
        return
    key = (item[0], round(item[1], 1), round(item[2], 1))
    if key in seen:
        return
    seen.add(key)
    group.append(item)


def sample_pairs(flat, limit):
    """Evenly stride a flat [x,y,...] list down to `limit` coordinate pairs."""
    pairs = len(flat) // 2
    if pairs <= limit:
        return flat
    step = pairs / float(limit)
    out = []
    for index in range(limit):
        pick = int(index * step)
        out.extend((flat[pick * 2], flat[pick * 2 + 1]))
    return out


def entrance_flag(entry):
    """True for index tuples stamped by the dungeon-entrance fallback."""
    return len(entry) >= 6 and entry[5] is True


def drop_entrance_where_real(entries):
    """A map that has real spawns keeps them; entrance tuples there are dropped."""
    real_maps = {entry[0] for entry in entries if not entrance_flag(entry)}
    return [entry for entry in entries if not entrance_flag(entry) or entry[0] not in real_maps]


def main():
    meta = read_toc_meta(QDB_TOC)
    npc_prefix, npc_keys = fields_from_meta(os.path.join(QDB_DIR, "src", "meta", "npcMeta.lua"), "Npc")
    item_prefix, item_keys = fields_from_meta(os.path.join(QDB_DIR, "src", "meta", "itemMeta.lua"), "Item")
    quest_prefix, quest_keys = fields_from_meta(os.path.join(QDB_DIR, "src", "meta", "questMeta.lua"), "Quest")
    obj_prefix, obj_keys = fields_from_meta(os.path.join(QDB_DIR, "src", "meta", "objectMeta.lua"), "Object")

    npcs = EntityStore(meta, npc_prefix, npc_keys)
    items = EntityStore(meta, item_prefix, item_keys)
    quests = EntityStore(meta, quest_prefix, quest_keys)
    objects = EntityStore(meta, obj_prefix, obj_keys)

    area_map = read_return_table(AREA_MAP_LUA)
    overrides = {}
    text = open(AREA_MAP_LUA, "r", encoding="utf-8", errors="replace").read()
    override_block = re.search(r"areaIdToUiMapIdOverride\s*=\s*\[\[return\s*\{(.*?)\}\]\]", text, re.S)
    if override_block:
        for key, value in re.findall(r"\[(\d+)\]\s*=\s*(\d+)", override_block.group(1)):
            overrides[int(key)] = int(value)
    area_map.update(overrides)

    dungeons = read_dungeons(DUNGEONS_LUA)
    gearquest_items = read_gearquest_item_ids()
    print("gearquest item ids: %d" % len(gearquest_items))

    def map_for_area(area_id):
        value = area_map.get(area_id)
        return value if value and value > 0 else None

    def npc_faction(npc_id):
        row = npcs.scalar(npc_id)
        if not row:
            return "B"
        return faction_code(row.get(npc_keys["friendlyToFaction"]))

    def npc_name(npc_id):
        row = npcs.scalar(npc_id)
        if not row:
            return None
        value = row.get(npc_keys["name"])
        if isinstance(value, bytes):
            return value.decode("utf-8", "replace")
        return value

    def spawn_tuples(spawn_table, prefer_dungeon=True):
        """spawnlist -> [(mapId, x, y, isEntrance)] for every area that resolves.

        isEntrance is True only when the mob's own coordinates were replaced by
        the dungeon entrance from dungeons.lua (the mob lives inside a dungeon,
        whose interior coordinates are not useful for a world pin).
        """
        if isinstance(spawn_table, list):
            # Contiguous 1..n area keys serialize as a CBOR array.
            spawn_table = {index + 1: points for index, points in enumerate(spawn_table)}
        out = []
        for area_id, points in (spawn_table or {}).items():
            points = as_list(points)
            if not points:
                continue
            dungeon = dungeons.get(area_id)
            if dungeon and prefer_dungeon and 0 <= dungeon[2] <= 100 and 0 <= dungeon[3] <= 100:
                parent_map = map_for_area(dungeon[0]) or map_for_area(dungeon[1])
                if parent_map:
                    out.append((parent_map, dungeon[2], dungeon[3], True))
                continue
            map_id = map_for_area(area_id)
            if not map_id:
                continue
            for point in points:
                if isinstance(point, (list, tuple)) and len(point) >= 2:
                    x, y = float(point[0]), float(point[1])
                    if 0 <= x <= 100 and 0 <= y <= 100:
                        out.append((map_id, x, y, False))
        return out

    def npc_spawn_tuples(npc_id, prefer_dungeon=True):
        return spawn_tuples(npcs.field(npc_id, "spawns"), prefer_dungeon)

    def obj_spawn_tuples(obj_id, prefer_dungeon=True):
        return spawn_tuples(objects.field(obj_id, "spawns"), prefer_dungeon)

    def area_to_map(area_id):
        dungeon = dungeons.get(area_id)
        if dungeon:
            mapped = map_for_area(dungeon[0]) or map_for_area(dungeon[1])
            if mapped:
                return mapped
        return map_for_area(area_id)

    def spawn_area_maps(spawn_table, out, seen):
        if isinstance(spawn_table, list):
            spawn_table = {index + 1: points for index, points in enumerate(spawn_table)}
        for area_id in (spawn_table or {}):
            if len(out) >= MAX_WORLD_ZONES:
                return
            map_id = area_to_map(area_id)
            if map_id and map_id not in seen:
                seen.add(map_id)
                out.append(map_id)

    def entity_zone_maps(store, entity_id, out, seen):
        """Zone-level mapIds: spawn area keys first, then zoneID (no coordinates)."""
        spawn_area_maps(store.field(entity_id, "spawns"), out, seen)
        if len(out) >= MAX_WORLD_ZONES:
            return
        zone_id = store.scalar_field(entity_id, "zoneID")
        if isinstance(zone_id, int) and zone_id:
            map_id = area_to_map(zone_id)
            if map_id and map_id not in seen:
                seen.add(map_id)
                out.append(map_id)

    def points_by_map(entity_ids, spawn_fn, faction_fn, prefer_dungeon=True):
        """{mapId: {"real": [...], "entrance": [...]}} plus running faction merge."""
        points = {}
        fac = {}
        for entity_id in entity_ids or []:
            for map_id, x, y, is_entrance in spawn_fn(entity_id, prefer_dungeon):
                bucket = points.setdefault(map_id, {"real": [], "entrance": []})
                key = "entrance" if is_entrance else "real"
                if len(bucket[key]) >= MAX_WORLD_POINTS * MAX_WORLD_SAMPLES * 16:
                    continue
                bucket[key].extend((round(x, 1), round(y, 1)))
                fac[map_id] = merge_faction(fac.get(map_id), faction_fn(entity_id))
        return points, fac

    def npc_points_by_map(npc_ids, prefer_dungeon=True):
        return points_by_map(npc_ids, npc_spawn_tuples, npc_faction, prefer_dungeon)

    def obj_points_by_map(obj_ids, prefer_dungeon=True):
        return points_by_map(obj_ids, obj_spawn_tuples, lambda _oid: "B", prefer_dungeon)

    def quest_givers(quest_id, depth=0, seen=None, out=None):
        """startedBy NPCs/objects, walking pre-quests; finishedBy as fallback."""
        if out is None:
            out, seen = [], set()
        if quest_id in seen or depth > CHAIN_HOPS or len(out) >= MAX_GROUP:
            return out
        seen.add(quest_id)

        started = as_list(quests.field(quest_id, "startedBy"))
        npcs_list = as_ints(started[0]) if len(started) > 0 else []
        objs_list = as_ints(started[1]) if len(started) > 1 else []
        items_list = as_ints(started[2]) if len(started) > 2 else []

        if not npcs_list and not objs_list:
            finished = as_list(quests.field(quest_id, "finishedBy"))
            if len(finished) > 0:
                npcs_list = as_ints(finished[0])
            if len(finished) > 1:
                objs_list = as_ints(finished[1])

        for npc_id in npcs_list:
            for map_id, x, y, _is_entrance in npc_spawn_tuples(npc_id, prefer_dungeon=False)[:2]:
                dedupe_push(out, seen, (map_id, round(x, 1), round(y, 1), npc_faction(npc_id)), MAX_GROUP)
        for obj_id in objs_list:
            for map_id, x, y, _is_entrance in obj_spawn_tuples(obj_id, prefer_dungeon=False)[:2]:
                dedupe_push(out, seen, (map_id, round(x, 1), round(y, 1), "B"), MAX_GROUP)

        for item_id in items_list:
            for map_id, x, y, _is_entrance in drop_points(item_id)[:2]:
                dedupe_push(out, seen, (map_id, round(x, 1), round(y, 1), "B"), MAX_GROUP)

        parents = []
        for key in ("preQuestSingle", "preQuestGroup"):
            parents.extend(as_ints(quests.field(quest_id, key)))
        parent = quests.scalar_field(quest_id, "parentQuest")
        if parent:
            parents.append(int(parent))
        for parent_id in parents[:1]:
            quest_givers(parent_id, depth + 1, seen, out)
        return out

    def drop_points(item_id):
        """npcDrops + objectDrops resolved to (mapId, x, y, isEntrance) points."""
        out = []
        for npc_id in as_ints(items.field(item_id, "npcDrops")):
            out.extend(npc_spawn_tuples(npc_id, prefer_dungeon=False))
        for obj_id in as_ints(items.field(item_id, "objectDrops")):
            out.extend(obj_spawn_tuples(obj_id, prefer_dungeon=False))
        return out

    index = {}
    stats = {"items": 0, "with_locations": 0, "tuples": 0}

    for item_id in sorted(gearquest_items):
        if not items.scalar(item_id):
            continue
        stats["items"] += 1
        groups = {}

        quest_ids = as_ints(items.field(item_id, "questRewards"))
        quest_group = []
        seen = set()
        for quest_id in quest_ids[:6]:
            quest_givers(int(quest_id), out=quest_group, seen=seen)
        start_quest = items.scalar_field(item_id, "startQuest")
        if start_quest:
            for map_id, x, y, _is_entrance in drop_points(item_id)[:4]:
                dedupe_push(quest_group, seen, (map_id, round(x, 1), round(y, 1), "B"), MAX_GROUP)
            source_item = quests.scalar_field(int(start_quest), "sourceItemId")
            if source_item:
                for map_id, x, y, _is_entrance in drop_points(int(source_item))[:3]:
                    dedupe_push(quest_group, seen, (map_id, round(x, 1), round(y, 1), "B"), MAX_GROUP)
        if quest_group:
            groups["q"] = quest_group

        # Boss / dungeon: pin the dungeon the drop lives in.
        # Entrance substitutions are flagged so the runtime can label them; a map
        # that also has real spawns keeps only those.
        boss_group, boss_seen = [], set()
        for npc_id in (as_ints(items.field(item_id, "npcDrops")))[:MAX_GROUP * 2]:
            for map_id, x, y, is_entrance in npc_spawn_tuples(npc_id, prefer_dungeon=True)[:2]:
                tuple_out = (map_id, round(x, 1), round(y, 1), npc_faction(npc_id))
                if is_entrance:
                    tuple_out = tuple_out + (False, True)
                dedupe_push(boss_group, boss_seen, tuple_out, MAX_GROUP)
        for obj_id in (as_ints(items.field(item_id, "objectDrops")))[:MAX_GROUP]:
            for map_id, x, y, is_entrance in obj_spawn_tuples(obj_id, prefer_dungeon=True)[:2]:
                tuple_out = (map_id, round(x, 1), round(y, 1), "B")
                if is_entrance:
                    tuple_out = tuple_out + (False, True)
                dedupe_push(boss_group, boss_seen, tuple_out, MAX_GROUP)
        boss_group = drop_entrance_where_real(boss_group)
        if boss_group:
            groups["b"] = boss_group

        vendor_group, vendor_seen = [], set()
        for npc_id in (as_ints(items.field(item_id, "vendors")))[:MAX_GROUP * 2]:
            tuples = npc_spawn_tuples(npc_id, prefer_dungeon=False)
            if tuples:
                map_id, x, y, _is_entrance = tuples[0]
                dedupe_push(vendor_group, vendor_seen, (map_id, round(x, 1), round(y, 1), npc_faction(npc_id)), MAX_GROUP)
        if vendor_group:
            groups["v"] = vendor_group

        # Recipes/patterns: the profession source is whoever sells or drops them.
        item_class = items.scalar_field(item_id, "class")
        if str(item_class) == "9":
            prof_group = list(vendor_group)
            prof_seen = {(t[0], round(t[1], 1), round(t[2], 1)) for t in prof_group}
            for map_id, x, y, _is_entrance in drop_points(item_id)[:MAX_GROUP * 2]:
                dedupe_push(prof_group, prof_seen, (map_id, round(x, 1), round(y, 1), "B"), MAX_GROUP)
            if prof_group:
                groups["p"] = prof_group[:MAX_GROUP]

        world_group = []
        drop_maps, drop_fac = npc_points_by_map(as_ints(items.field(item_id, "npcDrops")))
        obj_maps, obj_fac = obj_points_by_map(as_ints(items.field(item_id, "objectDrops")))
        for map_id, buckets in obj_maps.items():
            merged = drop_maps.setdefault(map_id, {"real": [], "entrance": []})
            for bucket_key in ("real", "entrance"):
                merged[bucket_key].extend(buckets[bucket_key])
        for map_id, fac in obj_fac.items():
            drop_fac[map_id] = merge_faction(drop_fac.get(map_id), fac)
        ranked = sorted(
            drop_maps.items(),
            key=lambda kv: -(len(kv[1]["real"]) + len(kv[1]["entrance"])) // 2,
        )
        for map_id, buckets in ranked[:MAX_WORLD_ZONES]:
            # Real spawns on this map win; entrance coordinates are the fallback.
            is_entrance = not buckets["real"]
            flat = buckets["entrance"] if is_entrance else buckets["real"]
            xs = flat[0::2]
            ys = flat[1::2]
            if not xs:
                continue
            cx = round(sum(xs) / len(xs), 1)
            cy = round(sum(ys) / len(ys), 1)
            tuple_out = (map_id, cx, cy, drop_fac.get(map_id, "B"), flat)
            if is_entrance:
                tuple_out = tuple_out + (True,)
            world_group.append(tuple_out)
        if world_group:
            groups["w"] = world_group

        # Zone-only fallback: drop data names the area but carries no coordinates.
        if not groups:
            zones, zone_seen = [], set()
            for npc_id in as_ints(items.field(item_id, "npcDrops")):
                entity_zone_maps(npcs, npc_id, zones, zone_seen)
            for obj_id in as_ints(items.field(item_id, "objectDrops")):
                entity_zone_maps(objects, obj_id, zones, zone_seen)
            if zones:
                groups["z"] = [(map_id,) for map_id in zones]

        if groups:
            stats["with_locations"] += 1
            for group in groups.values():
                stats["tuples"] += len(group)
        index[item_id] = groups

    # Trainers, keyed by profession (npc subName, e.g. "Journeyman Blacksmith").
    CAPITAL_MAPS = (1453, 1454, 1455, 1456, 1457, 1458)
    trainer_candidates = {}
    for npc_id in npcs.ids():
        row = npcs.scalar(npc_id)
        if not row:
            continue
        sub = row.get(npc_keys["subName"])
        if isinstance(sub, bytes):
            sub = sub.decode("utf-8", "replace")
        if not sub:
            continue
        lowered = sub.lower()
        if any(word in lowered for word in PROF_SUB_EXCLUDE):
            continue
        matched = None
        for profession, stems in PROF_STEMS.items():
            if any(stem in lowered for stem in stems):
                matched = profession
                break
        if not matched:
            continue
        tuples = npc_spawn_tuples(npc_id, prefer_dungeon=False)
        if not tuples:
            continue
        map_id, x, y, _is_entrance = tuples[0]
        trainer_candidates.setdefault(matched, []).append(
            (map_id, round(x, 1), round(y, 1), npc_faction(npc_id))
        )

    trainers = {}
    for profession, bucket in trainer_candidates.items():
        seen = set()
        ordered = sorted(bucket, key=lambda t: (0 if t[0] in CAPITAL_MAPS else 1, t[0]))
        kept = []
        for item in ordered:
            key = (item[0], round(item[1], 1), round(item[2], 1))
            if key in seen:
                continue
            seen.add(key)
            kept.append(item)
            if len(kept) >= MAX_TRAINERS:
                break
        trainers[profession] = kept

    with open(OUT_LUA, "w", encoding="utf-8", newline="\n") as out:
        out.write("local _, GQ = ...\n\n")
        out.write("-- GENERATED by _tools/generate_locations.py from QuestieDB's baked data.\n")
        out.write("-- Do not edit by hand: rerun the generator instead.\n")
        out.write("-- Groups: q=quest giver, b=boss/dungeon, p=profession, v=vendor, w=world drop,\n")
        out.write("--         z=zone only (drop data names the area, no coordinates).\n")
        out.write("-- Tuple: {mapId, x, y, faction}, world drop keeps {mapId, x, y, faction, flatPoints}.\n")
        out.write("-- Dungeon-entrance fallbacks append 1: {mapId, x, y, faction, flatPoints|false, 1}.\n\n")
        out.write("GQ.LocationsIndex = {\n")
        for item_id, groups in index.items():
            if not groups:
                continue
            parts = []
            for key, group in groups.items():
                tuples = []
                for entry in group:
                    if len(entry) == 1:
                        tuples.append("{%d}" % entry[0])
                        continue
                    if len(entry) > 4 and isinstance(entry[4], (list, tuple)):
                        pts = ",".join("%g" % p for p in sample_pairs(entry[4], MAX_WORLD_POINTS))
                        text = "{%d,%g,%g,\"%s\",{%s}}" % (entry[0], entry[1], entry[2], entry[3], pts)
                    elif len(entry) > 4:
                        text = "{%d,%g,%g,\"%s\",false}" % (entry[0], entry[1], entry[2], entry[3])
                    else:
                        text = "{%d,%g,%g,\"%s\"}" % (entry[0], entry[1], entry[2], entry[3])
                    if entrance_flag(entry):
                        text = text[:-1] + ",1}"
                    tuples.append(text)
                parts.append("%s={%s}" % (key, ",".join(tuples)))
            out.write("[%d]={%s},\n" % (item_id, ",".join(parts)))
        out.write("}\n\n")

        out.write("GQ.TrainerIndex = {\n")
        for profession, group in sorted(trainers.items()):
            tuples = ",".join("{%d,%g,%g,\"%s\"}" % (t[0], t[1], t[2], t[3]) for t in group)
            out.write('["%s"]={%s},\n' % (profession, tuples))
        out.write("}\n\n")

        out.write("GQ.AreaMapIndex = {\n")
        for area_id in sorted(area_map):
            out.write("[%d]=%d,\n" % (area_id, area_map[area_id]))
        out.write("}\n")

    size = os.path.getsize(OUT_LUA)
    print("wrote %s (%.1f KB)" % (OUT_LUA, size / 1024))
    print("items scanned: %(items)d, with locations: %(with_locations)d, tuples: %(tuples)d" % stats)
    print("trainer entries: %d professions" % len(trainers))


if __name__ == "__main__":
    sys.exit(main())
