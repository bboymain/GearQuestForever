"""Report coordinate coverage per source type for GearQuest hunt entries.

Usage:  python _tools/check_coverage.py
"""

import glob
import os
import re
import sys
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import generate_locations as g

SOURCE_GROUP = {
    "quest_reward": "q",
    "seasonal_quest": "q",
    "boss_drop": "b",
    "profession": "p",
    "vendor": "v",
    "world_drop": "w",
}
EXACT = set(SOURCE_GROUP.values())


def read_index(path):
    index, in_index = {}, False
    for line in open(path, encoding="utf-8"):
        if line.startswith("GQ.LocationsIndex"):
            in_index = True
            continue
        if line.startswith("GQ.") and in_index:
            break
        match = re.match(r"\[(\d+)\]=", line)
        if match:
            index[int(match.group(1))] = set(re.findall(r"(?:^|[,{])([qbpvwz])=\{", line))
    return index


def entries():
    """(itemId, sourceType) pairs from every GearQuest data file."""
    seen = set()
    for addon in g.GQ_DIRS:
        for path in glob.glob(os.path.join(g.ADDONS, addon, "**", "*.lua"), recursive=True):
            if "_generated" in path:
                continue
            text = open(path, encoding="utf-8", errors="replace").read()
            for match in re.finditer(r"itemId\s*=\s*(\d+)", text):
                item_id = int(match.group(1))
                window = text[max(0, match.start() - 400): match.end() + 900]
                kind = re.findall(r'sourceType\s*=\s*"(\w+)"', window)
                key = (item_id, kind[0] if kind else "?")
                if key not in seen:
                    seen.add(key)
                    yield key


def main():
    meta = g.read_toc_meta(g.QDB_TOC)
    _, item_keys = g.fields_from_meta(os.path.join(g.QDB_DIR, "src", "meta", "itemMeta.lua"), "Item")
    items = g.EntityStore(meta, "X-Item-", item_keys)
    index = read_index(os.path.join(g.GQ_DIR, "_generated", "Locations.generated.lua"))

    report = Counter()
    gaps = {}
    for item_id, source in entries():
        want = SOURCE_GROUP.get(source, "w")
        have = index.get(item_id, set())
        if not items.scalar(item_id):
            bucket = "unknown item"
        elif want in have and want in EXACT:
            bucket = "exact (matching source)"
        elif have & EXACT:
            bucket = "exact (other source)"
        elif "z" in have:
            bucket = "zone only"
        else:
            bucket = "missing"
        report[(source, bucket)] += 1
        if bucket in ("missing", "unknown item"):
            gaps.setdefault(bucket, []).append((item_id, source))

    sources = sorted({key[0] for key in report})
    buckets = ["exact (matching source)", "exact (other source)", "zone only", "missing", "unknown item"]
    width = max(len(s) for s in sources) + 2
    print("%-*s %s" % (width, "source", "  ".join("%-24s" % b for b in buckets[:3])))
    for source in sources:
        row = [report.get((source, b), 0) for b in buckets]
        print("%-*s %s  missing=%d unknown=%d" % (width, source, "  ".join("%-24d" % r for r in row[:3]), row[3], row[4]))

    totals = Counter()
    for (source, bucket), count in report.items():
        totals[bucket] += count
    print()
    print("totals:", dict(totals))
    for bucket, items_list in gaps.items():
        print("%s: %s" % (bucket, ", ".join("%d/%s" % pair for pair in items_list[:25])))


if __name__ == "__main__":
    sys.exit(main())
