# GearQuest Forever

WoW addon: picks, tracks and pins gear upgrades ("hunts") for Classic Forever.

## Install

Drop the `GearQuestForever` folder into `Interface/AddOns` and enable it.

## Location data

Coordinates are **not scraped at runtime**. `_tools/generate_locations.py` decodes
QuestieDB's baked database offline and writes a static index:

```bash
python _tools/generate_locations.py
python _tools/check_generated.py   # file compiles, tuple/faction sanity
python _tools/check_lua.py         # every shipped .lua parses
python _tools/test_runtime.py      # Locations/Pins/Map smoke tests
python _tools/check_coverage.py    # coordinate coverage per source type
```

Groups in `Locations.generated.lua`: `q` quest giver, `b` boss/dungeon,
`p` profession, `v` vendor, `w` world drop (with spawn footprint), `z` zone only.

## Credits

- Location and quest data: [QuestieDB](https://github.com/Questie/Questie) baked database + `support/Forever` zone tables.
- Item name/quality audit generated from Wowhead Forever item pages.
