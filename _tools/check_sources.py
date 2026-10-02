import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import generate_locations as g

meta = g.read_toc_meta(g.QDB_TOC)
_, keys = g.fields_from_meta(os.path.join(g.QDB_DIR, "src", "meta", "itemMeta.lua"), "Item")
items = g.EntityStore(meta, "X-Item-", keys)

files = []
for addon in g.GQ_DIRS:
    files += glob.glob(os.path.join(g.ADDONS, addon, "**", "*.lua"), recursive=True)

hard, r2, r3 = set(), set(), set()
for path in files:
    text = open(path, encoding="utf-8", errors="replace").read()
    hard.update(int(x) for x in re.findall(r"itemId\s*=\s*(\d+)", text))
    r2.update(int(x) for x in re.findall(r"\[(\d{2,6})\]\s*=\s*\{[^{}]*?sourceType", text))
    r3.update(int(x) for x in re.findall(r'\{\s*(\d{2,6})\s*,\s*"[A-Za-z]+"\s*,\s*\d+', text))


def cov(ids):
    known = sum(1 for i in ids if items.scalar(i))
    return len(ids), known, len(ids) - known


print("hard total/known/missing:", cov(hard))
print("r2   total/known/missing:", cov(r2))
print("r3   total/known/missing:", cov(r3))
print("r3 only sample:", sorted(r3 - hard - r2)[:25])
print("r2 only sample:", sorted(r2 - hard)[:15])

union = hard | r2 | r3
print("union:", cov(union))
