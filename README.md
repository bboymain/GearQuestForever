# GearQuest Forever

**"What should I be wearing in this slot right now — and where do I get it?"**

GearQuest Forever is a leveling companion for **World of Warcraft: Forever** (client 1.60.1, levels 1–60).
Right-click any gear slot and it shows the best upgrades for *your* class, *your* spec, *your* faction and
*your* level — with a plain-language source and a one-click track. When the item lands in your bags you get
a toast: hunt done.

No spreadsheet. No alt-tab to a website.

> **Credits** — GearQuest Forever was created by **[weber8210](https://www.curseforge.com/wow/addons/gearquest-forever)**
> and is published on CurseForge (project license: All Rights Reserved). This repository is where new
> features are added to the addon; all original design and code belong to weber8210.

## Getting started

1. Drop the `GearQuestForever` folder into `World of Warcraft\_classic_beta_\Interface\AddOns` and `/reload`.
2. Left-click the minimap button, or type `/gq`, to open **The Log**.
3. Right-click a character-panel slot to see the three best upgrades for that slot.
4. Press **Track** on the one you want. When it drops, the toast means you are done.

## What it does

- **Top 3 per slot** — for all nine classes and every spec, levels 1–60, Alliance and Horde.
- **The Log** — a parchment page per upgrade: how to get it (quest, boss, vendor, profession), what it
  replaces, and always a Source line. Faction-correct, so no Stormwind quest shows up on a Horde character.
- **Map pins with coordinates** — quest givers, bosses, vendors, profession trainers, world drops and
  dungeon entrances are pinned on the map. Hover a pin for the details; the log prints
  `Coords: <zone> (x, y)` so you know exactly where to stand. Pins that only know the zone say
  `(zone only)` instead of guessing.
- **Track a hunt** — pinned objectives and completion tracking in the tracker, plus a toast the moment
  the item is yours.
- **Simulator** — browse any class, spec, faction or level without logging it in (right-click the
  minimap button).
- **Paper-doll upgrades** — right-click a gear slot on your character sheet for the comparison.
- **Suffix names on the tooltip** — Forever's unsuffixed green items still show *of Agility* and the roll.
- **Random enchants ranked honestly** — if a suffix roll is the best item in the slot, it is listed first
  with its slim drop chance, not hidden.

## Commands

| Command | What it does |
| --- | --- |
| `/gq` or `/gearquest` | open/close The Log |
| `/gq log` | open/close The Log |
| `/gq track` / `/gq untrack` | track or stop tracking the selected upgrade |
| `/gq map` | show the map for the selected upgrade |
| `/gq help` | list commands |
| `/gq wipe data` | reset hunt progress for this character (keeps preview and UI settings) |

## Good to know

- GearQuest never equips or moves items — no bag automation, no libraries required.
- Forever data is still landing. The beta's gear, suffixes and talents change often, so some rankings
  can be incomplete or shift between updates. Reports with class, spec, level, faction and slot are what
  keep the weights honest.
- Feedback: the [official GearQuest Discord](https://discord.gg/jQ2GdDEeN), or the
  [CurseForge project page](https://www.curseforge.com/wow/addons/gearquest-forever).

## For developers

Coordinates are **not scraped at runtime**. `_tools/generate_locations.py` decodes QuestieDB's baked
database offline and writes a static index:

```bash
python _tools/generate_locations.py
python _tools/check_generated.py   # file compiles, tuple/faction sanity
python _tools/check_lua.py         # every shipped .lua parses
python _tools/test_runtime.py      # Locations/Pins/Map smoke tests
python _tools/check_coverage.py    # coordinate coverage per source type
```

Groups in `Locations.generated.lua`: `q` quest giver, `b` boss/dungeon, `p` profession, `v` vendor,
`w` world drop (with spawn footprint), `z` zone only. Tuple shape:
`{mapId, x, y, faction[, flatPoints|false[, 1]]}` — a trailing `1` marks a dungeon-entrance pin, which
is labeled "Dungeon entrance" in game instead of looking like an exact mob spot.

## Data sources

- The location index is generated from [QuestieDB](https://github.com/Questie/Questie).
- Questie/QuestieDB declares no license. This repo makes no license claim over the derived data.
- Item name/quality audit generated from Wowhead Forever item pages.

## Credits

- **Original author: [weber8210](https://www.curseforge.com/members/weber8210)** — GearQuest Forever on
  [CurseForge](https://www.curseforge.com/wow/addons/gearquest-forever). This repo adds features on top
  of their work.
- Location and quest data: [QuestieDB](https://github.com/Questie/Questie) baked database +
  `support/Forever` zone tables.
- Item name/quality audit generated from Wowhead Forever item pages.
