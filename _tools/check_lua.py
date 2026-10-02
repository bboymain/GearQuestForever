import os
import sys

from lupa import LuaRuntime

ROOT = r"C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\GearQuestForever"

FILES = [
    r"_generated\Locations.generated.lua",
    r"Locations.lua",
    r"Pins.lua",
    r"Map.lua",
    r"Tracker.lua",
    r"Core.lua",
    r"Log.lua",
    r"Data.lua",
]

lua = LuaRuntime()
failed = False
for rel in FILES:
    path = os.path.join(ROOT, rel)
    script = (
        "local f, err = loadfile([[%s]]); "
        "if not f then error(err, 0) end; return 'ok'" % path
    )
    try:
        lua.execute(script)
        print("OK   %s" % rel)
    except Exception as exc:
        failed = True
        print("FAIL %s: %s" % (rel, exc))

sys.exit(1 if failed else 0)
