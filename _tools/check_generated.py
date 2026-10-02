import re
from collections import Counter

from lupa import LuaRuntime

PATH = r"C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\GearQuestForever\_generated\Locations.generated.lua"

lua = LuaRuntime()
lua.execute("local f, err = loadfile([[%s]]); assert(f, err)" % PATH)
print("generated file compiles OK")

text = open(PATH, encoding="utf-8").read()
groups = Counter(re.findall(r"[,{]([qbpvwz])=\{", text))
print("group tuple counts:", dict(groups))
print("zone-only items:", len(re.findall(r"[,{]z=\{", text)))

maps = Counter(int(m) for m in re.findall(r"\{(\d{4}),-?[\d.]+,-?[\d.]+,\"[ABH]\"", text))
print("distinct mapIds:", len(maps), "range", min(maps), max(maps))
print("odd map ids:", sorted(m for m in maps if m < 900 or m > 1600))

trainers = re.findall(r'^\["([a-z ]+)"\]=\{', text, re.M)
print("trainer professions:", trainers)

factions = Counter(re.findall(r'\"([ABH])\"\}', text))
print("factions:", dict(factions))
