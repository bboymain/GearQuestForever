-- Smoke tests for the generated index + Locations.lua + Pins.lua wiring.
-- Run through lupa via _tools/test_runtime.py.

local ROOT = [[C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\GearQuestForever]]

local function loadAddonFile(rel, GQ)
    local chunk, err = loadfile(ROOT .. "\\" .. rel)
    assert(chunk, err)
    chunk(nil, GQ)
end

-- Minimal WoW API stubs ------------------------------------------------------

local faction = "Alliance"

function _G.UnitFactionGroup()
    return faction
end

function _G.GetCVar(name)
    if name == "rotateMinimap" then
        return "0"
    end
    return ""
end

function _G.CreateFrame()
    return {
        SetScript = function() end,
        Hide = function() end,
        Show = function() end,
    }
end

_G.C_Map = {
    GetMapInfo = function(id)
        if id == 1436 then
            return { name = "Westfall" }
        end
        if id == 1453 then
            return { name = "Stormwind" }
        end
        if id == 1454 then
            return { name = "Orgrimmar" }
        end
        return { name = "Map" .. tostring(id) }
    end,
    GetAreaInfo = function()
        return nil
    end,
    GetBestMapForUnit = function()
        return nil
    end,
    GetPlayerMapPosition = function()
        return nil
    end,
    GetWorldPosFromMapPos = function()
        return nil
    end,
}

-- Addon tables --------------------------------------------------------------

local GQ = {}
_G.GearQuest = GQ
_G.GearQuestForeverDB = { hunts = {} }

loadAddonFile([[_generated\Locations.generated.lua]], GQ)
loadAddonFile([[Locations.lua]], GQ)
loadAddonFile([[Map.lua]], GQ)
loadAddonFile([[Pins.lua]], GQ)

assert(type(GQ.LocationsIndex) == "table", "LocationsIndex missing")
assert(type(GQ.TrainerIndex) == "table", "TrainerIndex missing")
assert(type(GQ.AreaMapIndex) == "table", "AreaMapIndex missing")

function GQ:GetEffectiveFaction()
    return faction
end

-- Locations:Resolve ---------------------------------------------------------

-- boss_drop entry: Rockslicer drops in Deadmines, pinned on Westfall.
local bossPins = GQ.Locations:Resolve({ id = 1, itemId = 872, sourceType = "boss_drop" })
assert(#bossPins >= 1, "boss pins expected")
assert(bossPins[1].mapId == 1436, "boss pin should sit on Westfall, got " .. tostring(bossPins[1].mapId))
assert(bossPins[1].kind == "b", "boss pin kind")

-- Faction filtering on a synthetic vendor entry.
GQ.LocationsIndex[999001] = {
    v = { { 1453, 10, 10, "A" }, { 1454, 20, 20, "H" } },
}
local entry = { id = 2, itemId = 999001, sourceType = "vendor" }

faction = "Alliance"
local pins = GQ.Locations:Resolve(entry)
assert(#pins == 1 and pins[1].mapId == 1453, "alliance sees the alliance vendor")

faction = "Horde"
pins = GQ.Locations:Resolve(entry)
assert(#pins == 1 and pins[1].mapId == 1454, "horde sees the horde vendor")

faction = "Alliance"

-- Zone fallback when the item is unknown and no group applies.
GQ.Map.ZoneMap = function(_, zone)
    if zone == "Westfall" then
        return 1436
    end
    return nil
end
local zonePins = GQ.Locations:Resolve({ id = 3, itemId = 999002, sourceType = "world_drop", zone = "Westfall" })
assert(#zonePins == 1, "zone fallback pin expected")
assert(zonePins[1].zoneOnly and zonePins[1].mapId == 1436, "zone fallback shape")

-- Profession entries fall back to trainer coordinates.
local profPins = GQ.Locations:Resolve({
    id = 4,
    itemId = 999003,
    sourceType = "profession",
    profession = "Blacksmithing",
})
assert(#profPins >= 1, "trainer pins expected")
assert(profPins[1].trainer, "profession pins should come from the trainer index")
for _, pin in ipairs(profPins) do
    assert(pin.fac == "B" or pin.fac == "A", "alliance player must not see horde trainers")
end

-- Cross-group fallback: quest_reward with no q group uses another group.
GQ.LocationsIndex[999004] = { v = { { 1454, 30, 30, "H" } }, w = { { 1436, 40, 40, "B" } } }
pins = GQ.Locations:Resolve({ id = 5, itemId = 999004, sourceType = "quest_reward" })
assert(#pins == 1 and pins[1].kind == "w" and pins[1].mapId == 1436, "cross-group fallback")

-- Generated zone-only group: source data has the zone but no coordinates.
GQ.LocationsIndex[999005] = { z = { { 1412 }, { 1440 } } }
local zoneGroupPins = GQ.Locations:Resolve({ id = 9, itemId = 999005, sourceType = "world_drop" })
assert(#zoneGroupPins == 2, "zone group pins expected, got " .. tostring(#zoneGroupPins))
assert(zoneGroupPins[1].zoneOnly and zoneGroupPins[1].mapId == 1412, "zone group shape")
assert(zoneGroupPins[1].x == 50 and zoneGroupPins[1].y == 50, "zone group centers the pin")
local zoneGroupCoords = GQ.Locations:DescribeCoords({ id = 9, itemId = 999005, sourceType = "world_drop" })
assert(zoneGroupCoords and zoneGroupCoords:find("zone only", 1, true), "zone only coords line, got " .. tostring(zoneGroupCoords))

-- Dungeon-entrance fallback tuples are labeled; a false flat list is tolerated.
GQ.LocationsIndex[999006] = { b = { { 1436, 40, 60, "B", false, 1 } } }
local entrancePins = GQ.Locations:Resolve({ id = 10, itemId = 999006, sourceType = "boss_drop" })
assert(#entrancePins == 1 and entrancePins[1].entrance == true, "entrance flag")
assert(entrancePins[1].flat == nil, "false flat list normalised to nil")
assert(GQ.Locations:AreaContains(entrancePins[1], 40, 60), "entrance pin contains point")
local entranceCoords = GQ.Locations:DescribeCoords({ id = 10, itemId = 999006, sourceType = "boss_drop" })
assert(entranceCoords and entranceCoords:find("(entrance)", 1, true), "entrance coords label")
assert(not (pins[1] and pins[1].entrance), "real spawns are not labeled")

-- Area bounds / containment for world drops.
local dropPins = GQ.Locations:Resolve({ id = 6, itemId = 720, sourceType = "world_drop" })
assert(#dropPins >= 1, "world drop pins expected")
local flatPin
for _, pin in ipairs(dropPins) do
    if pin.flat and #pin.flat >= 4 then
        flatPin = pin
        break
    end
end
assert(flatPin, "expected a world drop pin with flat points")
local cx, cy, rx, ry = GQ.Locations:AreaBounds(flatPin)
assert(cx and cy and rx and ry, "bounds expected")
assert(GQ.Locations:AreaContains(flatPin, cx, cy), "center must be inside")
assert(not GQ.Locations:AreaContains(flatPin, cx + rx + 0.05, cy), "outside must fail")

-- DescribeCoords for the log.
local coords = GQ.Locations:DescribeCoords({ id = 7, itemId = 872, sourceType = "boss_drop" })
assert(type(coords) == "string" and coords:find("Coords:", 1, true), "coords line expected, got " .. tostring(coords))

local profCoords = GQ.Locations:DescribeCoords({
    id = 8,
    itemId = 999003,
    sourceType = "profession",
    profession = "Blacksmithing",
})
assert(type(profCoords) == "string" and profCoords:find("trainers", 1, true), "trainer hint expected")

-- Map.lua --------------------------------------------------------------------

assert(GQ.Map:ZoneMap("Westfall") == 1436, "ZoneMap by name")
assert(GQ.Map:ZoneMap("Nowhere") == nil, "ZoneMap miss")

-- Pins.lua wiring ------------------------------------------------------------

local tracked = {
    { id = 1, itemId = 872, sourceType = "boss_drop" },
    { id = 4, itemId = 999003, sourceType = "profession", profession = "Blacksmithing" },
}
GQ.Tracker = {
    GetTrackedEntries = function()
        return tracked
    end,
}

assert(GQ.Pins, "GQ.Pins missing")
GQ.Pins:Init()
GQ.Pins:Sync()

tracked = {}
GQ.Pins:Sync()

print("runtime smoke tests passed")
