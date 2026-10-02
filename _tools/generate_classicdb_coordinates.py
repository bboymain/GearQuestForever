"""Fill Data.Coordinates.generated.lua for missing world-drop hunt items.

Sources:
  - cmangos classic-db (Vanilla 1.12 world DB): item -> creature loot entry
    -> creature_template.LootId/Name (drop source + chance).
  - QuestieDB Forever npcMeta spawns: npc id -> {areaId = {{x, y}, ...}}
    zone-local percentages, already Forever-corrected.
  - QuestieDB Zones files: areaId -> parent zone / uiMapId / display name.

Only items absent from GQ.Data.coordinates are added; existing rows are kept
verbatim. Rows are re-emitted sorted by item id.

Usage:
  python _tools/generate_classicdb_coordinates.py
  env GQ_CLASSICDB_SQL   override path to the decompressed classic-db dump
  env GQ_MISSING_JSON    override the missing-item id list (JSON array)
"""
import glob
import json
import os
import re
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
ADDONS = os.path.abspath(os.path.join(HERE, "..", ".."))
GQ_DIR = os.path.join(ADDONS, "GearQuestForever")
QDB_DIR = os.path.join(ADDONS, "QuestieDB")
OUT_LUA = os.path.join(GQ_DIR, "_generated", "Data.Coordinates.generated.lua")

DEFAULT_SQL = os.path.join(os.environ.get("TEMP", "."), "opencode", "classicdb.sql")
SQL_PATH = os.environ.get("GQ_CLASSICDB_SQL", DEFAULT_SQL)
DEFAULT_MISS = os.path.join(
    os.environ.get("TEMP", "."), "claude",
    "C--Program-Files--x86--World-of-Warcraft--classic-beta--Interface-AddOns-GearQuestForever",
    "172beaea-6d67-4ad7-86e0-4f27eed0a84b", "scratchpad", "missing_world.json")
MISS_PATH = os.environ.get("GQ_MISSING_JSON", DEFAULT_MISS)

MAX_TEMPLATES = 8
MAX_ZONES = 4
MAX_POINTS_PER_NPC = 60

sys.path.insert(0, HERE)
import generate_locations as g  # noqa: E402


def table_columns(text, table):
    m = re.search(r"CREATE TABLE `%s` \((.*?)\) ENGINE" % table, text, re.S)
    out = []
    for line in m.group(1).splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        upper = stripped.upper()
        if upper.startswith(("PRIMARY", "KEY", "UNIQUE", "CONSTRAINT",
                             "INDEX", "FULLTEXT", "FOREIGN")):
            continue
        col = re.match(r"`([A-Za-z_][A-Za-z0-9_]*)`", stripped)
        if col:
            out.append(col.group(1))
    return out


def iter_rows(text, table, cols):
    """Yield value-lists for every INSERT row of `table`."""
    needle = "INSERT INTO `%s` VALUES " % table
    pos = 0
    n = len(text)
    while True:
        start = text.find(needle, pos)
        if start < 0:
            return
        i = start + len(needle)
        while True:  # rows
            while i < n and text[i] in " \r\n\t,":
                i += 1
            if i >= n or text[i] != "(":
                break
            i += 1
            row = []
            while True:  # values
                if i >= n:
                    return
                c = text[i]
                if c == "'":
                    i += 1
                    buf = []
                    while i < n:
                        ch = text[i]
                        if ch == "\\":
                            buf.append(text[i + 1])
                            i += 2
                            continue
                        if ch == "'":
                            if i + 1 < n and text[i + 1] == "'":
                                buf.append("'")
                                i += 2
                                continue
                            i += 1
                            break
                        buf.append(ch)
                        i += 1
                    row.append("".join(buf))
                else:
                    j = i
                    while j < n and text[j] not in ",)":
                        j += 1
                    row.append(text[i:j].strip())
                    i = j
                if i < n and text[i] == ",":
                    i += 1
                    continue
                break
            yield row
            if i < n and text[i] == ")":
                i += 1
            if i < n and text[i] == ",":
                i += 1
                continue
            break
        pos = i


# --- Questie zone helpers -------------------------------------------------

def load_zone_maps():
    amap, aname = {}, {}
    path = os.path.join(QDB_DIR, "support", "Forever", "Zones", "areaIdToUiMapId.lua")
    for line in open(path, encoding="utf-8", errors="replace"):
        m = re.search(r"\[(\d+)\]\s*=\s*(\d+)\s*,\s*--\s*(.+)$", line.rstrip())
        if m:
            aid, uid, cmt = int(m.group(1)), int(m.group(2)), m.group(3).strip()
            amap[aid] = uid
            aname[aid] = cmt.split(" -> ")[0]
    parent = {}
    path = os.path.join(QDB_DIR, "support", "Forever", "Zones", "subZoneToParentZone.lua")
    text = open(path, encoding="utf-8", errors="replace").read()
    for block in re.findall(r"\[\[return\s*\{(.*?)\}\]\]", text, re.S):
        for a, b in re.findall(r"\[(\d+)\]\s*=\s*(\d+)", block):
            parent[int(a)] = int(b)
    path = os.path.join(QDB_DIR, "support", "Forever", "Zones", "dungeons.lua")
    text = open(path, encoding="utf-8", errors="replace").read()
    for m in re.finditer(r"\[(\d+)\]\s*=\s*\{\"[^\"]*\"(?:,\{[^}]*\})?,(\d+),", text):
        parent.setdefault(int(m.group(1)), int(m.group(2)))
    return amap, aname, parent


def norm_zone(aid, parent):
    seen = set()
    while aid in parent and aid not in seen:
        seen.add(aid)
        aid = parent[aid]
    return aid


# --- classic-db drop extraction ------------------------------------------

def load_classicdb():
    text = open(SQL_PATH, encoding="utf-8", errors="replace").read()
    loot = {}
    for t in ("creature_loot_template", "reference_loot_template"):
        c = {n: i for i, n in enumerate(table_columns(text, t))}
        loot[t] = defaultdict(list)
        for row in iter_rows(text, t, None):
            if len(row) >= len(c):
                loot[t][int(row[c["entry"]])].append(
                    (int(row[c["item"]]), int(row[c["mincountOrRef"]]),
                     float(row[c["ChanceOrQuestChance"]])))

    def expand(table, entry, depth=0, seen=None):
        """(item, chance, direct) for a loot entry; direct=False via reference."""
        seen = seen or set()
        if entry in seen or depth > 6:
            return
        seen.add(entry)
        for item, ref, chance in loot[table].get(entry, ()):
            if ref < 0:
                for src in ("reference_loot_template", table):
                    if src == table and table == "reference_loot_template":
                        continue
                    for it, ch, _ in expand(src, -ref, depth + 1, seen):
                        yield it, ch, False
            elif item > 0:
                yield item, chance, True

    # loot entry -> concrete item count (specificity)
    entry_size = {}
    for entry in loot["creature_loot_template"]:
        items = {it for it, _, _ in expand("creature_loot_template", entry)}
        entry_size[entry] = len(items)

    # item -> [(loot entry, chance, direct)]
    item_entries = defaultdict(list)
    for entry in loot["creature_loot_template"]:
        for item, chance, direct in expand("creature_loot_template", entry):
            item_entries[item].append((entry, chance, direct))

    # LootId -> {template entry: name}
    ct = {n: i for i, n in enumerate(table_columns(text, "creature_template"))}
    lid_map = defaultdict(dict)
    for row in iter_rows(text, "creature_template", None):
        if len(row) >= len(ct):
            lid = row[ct["LootId"]]
            if lid and lid != "0":
                lid_map[int(lid)][int(row[ct["Entry"]])] = row[ct["Name"]]
    return item_entries, entry_size, lid_map


# --- main fill ------------------------------------------------------------

def fmt_num(v):
    v = round(v, 1)
    return "%d" % v if v == int(v) else ("%.1f" % v)


def main():
    missing = json.load(open(MISS_PATH))
    existing_ids, header, rows, footer = read_existing()

    todo = [i for i in missing if i not in existing_ids]
    print("missing list: %d   already in file: %d   to fill: %d"
          % (len(missing), len(missing) - len(todo), len(todo)))

    amap, aname, parent = load_zone_maps()
    item_entries, entry_size, lid_map = load_classicdb()
    print("classic-db items with creature loot:", len(item_entries))

    meta = g.read_toc_meta(g.QDB_TOC)
    _, nkeys = g.fields_from_meta(os.path.join(QDB_DIR, "src", "meta", "npcMeta.lua"), "Npc")
    npcs = g.EntityStore(meta, "X-Npc-", nkeys)

    new_lines = []
    unfilled = []
    stats = defaultdict(int)
    for item_id in todo:
        entries = item_entries.get(item_id, [])
        if not entries:
            unfilled.append((item_id, "not in classic-db creature loot"))
            stats["no loot"] += 1
            continue

        # candidate templates, scored: direct + chance + narrow loot table
        cand = {}
        for entry, chance, direct in entries:
            size = entry_size.get(entry, 999)
            for tid, name in lid_map.get(entry, {}).items():
                score = (2 if direct else 0) + (2 if direct and chance > 0 else 0)
                score += 2 if size <= 10 else (1 if size <= 40 else 0)
                prev = cand.get(tid)
                if prev is None or score > prev[0]:
                    cand[tid] = (score, name, chance if direct else 0.0)
        if not cand:
            unfilled.append((item_id, "no creature_template on loot entry"))
            stats["no template"] += 1
            continue

        ranked = sorted(cand.items(), key=lambda kv: -kv[1][0])[:MAX_TEMPLATES]
        zones = defaultdict(list)
        used = 0
        for tid, (_score, _name, _chance) in ranked:
            sp = npcs.field(tid, "spawns")
            if not isinstance(sp, dict):
                continue
            for z, pts in sp.items():
                z = norm_zone(int(z), parent)
                for pt in pts:
                    if isinstance(pt, (list, tuple)) and len(pt) >= 2 and pt[0] >= 0 and pt[1] >= 0:
                        zones[z].append((float(pt[0]), float(pt[1])))
                        used += 1
                        if used >= MAX_POINTS_PER_NPC * MAX_TEMPLATES * 4:
                            break
        if not zones:
            unfilled.append((item_id, "droppers have no Questie spawns"))
            stats["no spawns"] += 1
            continue

        ranked_zones = sorted(zones.items(), key=lambda kv: -len(kv[1]))
        spots = []
        for z, pts in ranked_zones[:MAX_ZONES]:
            if z not in aname:
                continue
            mx = sum(p[0] for p in pts) / len(pts)
            my = sum(p[1] for p in pts) / len(pts)
            map_id = amap.get(z)
            spot = 'map="%s"' % aname[z]
            if map_id is not None:
                spot += ",mapId=%d" % map_id
            spot += ",x=%s,y=%s" % (fmt_num(mx), fmt_num(my))
            spots.append("{%s}" % spot)
        if not spots:
            unfilled.append((item_id, "zones not resolvable: %s"
                             % sorted(zones)[:6]))
            stats["no zone name"] += 1
            continue

        top_name = ranked[0][1][1]
        top_chance = ranked[0][1][2]
        note = "drops from %s" % top_name
        if top_chance > 0:
            note += " (%g%%)" % top_chance
        more = ",more=true" if len(ranked_zones) > MAX_ZONES else ""
        line = '    [%d]={note="%s"%s,spots={%s}},' % (
            item_id, note, more, ",".join(spots))
        new_lines.append(line)
        stats["filled"] += 1

    # preserve existing order verbatim; append new rows (prior sessions also
    # appended their additions at the end of the file)
    merged = [line for _iid, line in rows]
    merged += sorted(new_lines, key=lambda l: int(re.match(r"\s*\[(\d+)\]", l).group(1)))
    with open(OUT_LUA, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(header)
        for line in merged:
            fh.write(line + "\n")
        fh.write(footer)

    print("stats:", dict(stats))
    print("added rows:", len(new_lines), "->", OUT_LUA)
    if unfilled:
        print("unfilled %d, first 20:" % len(unfilled))
        for iid, why in unfilled[:20]:
            print("   %d  %s" % (iid, why))
    json.dump({"filled": sorted(int(re.match(r"\s*\[(\d+)\]", l).group(1))
                                for l in new_lines),
               "unfilled": [{"id": i, "why": w} for i, w in unfilled]},
              open(os.path.join(os.path.dirname(SQL_PATH),
                                "fill_report.json"), "w"), indent=1)


def read_existing():
    text = open(OUT_LUA, encoding="utf-8").read()
    lines = text.splitlines()
    head_end = None
    rows = []
    for idx, line in enumerate(lines):
        if line.startswith("GQ.Data.coordinates = {"):
            head_end = idx
            break
        assert head_end is None
    assert head_end is not None, "coordinates table not found"
    header = "\n".join(lines[:head_end + 1]) + "\n"
    ids = {}
    footer = None
    for line in lines[head_end + 1:]:
        m = re.match(r"\s*\[(\d+)\]=(.*),\s*$", line)
        if m:
            ids[int(m.group(1))] = None
            rows.append((int(m.group(1)), line))
        elif line.strip() == "}":
            footer = line + "\n"
        else:
            raise SystemExit("unexpected line in generated file: %r" % line)
    return ids, header, rows, footer


if __name__ == "__main__":
    main()
