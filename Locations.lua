local _, GQ = ...

GQ.Locations = GQ.Locations or {}

-- Generated groups (see _tools/generate_locations.py): q=quest giver, b=boss/dungeon,
-- p=profession, v=vendor, w=world drop, z=zone only (no coordinates in the source data).
-- Tuples: {mapId, x, y, faction[, flatPoints|false[, 1]]}; trailing 1 marks a dungeon-entrance
-- fallback; z tuples are {mapId}.
local SOURCE_GROUP = {
    quest_reward = "q",
    seasonal_quest = "q",
    boss_drop = "b",
    profession = "p",
    vendor = "v",
    world_drop = "w",
}

local FALLBACK_ORDER = { "q", "b", "v", "w", "p" }
local MAX_COORDS = 3

local function PlayerFactionCode()
    local faction = GQ.GetEffectiveFaction and GQ:GetEffectiveFaction() or nil
    if not faction then
        faction = (UnitFactionGroup and UnitFactionGroup("player")) or nil
    end
    if faction == "Horde" then
        return "H"
    end
    if faction == "Alliance" then
        return "A"
    end
    return nil
end

local function FactionAllows(code, want)
    if code == nil or code == "B" or not want then
        return true
    end
    return code == want
end

function GQ.Locations:GetGroups(itemId)
    if not itemId or not GQ.LocationsIndex then
        return nil
    end
    return GQ.LocationsIndex[itemId]
end

function GQ.Locations:Trainers(profession)
    if not profession or not GQ.TrainerIndex then
        return nil
    end
    return GQ.TrainerIndex[string.lower(profession)]
end

-- Resolved pins for an entry: {mapId, x, y, kind, fac, flat, trainer, zoneOnly, entry}.
-- Primary group by sourceType, then cross-group fallback, then zone-only at 50/50.
function GQ.Locations:Resolve(entry)
    local pins = {}
    if not entry then
        return pins
    end

    local want = PlayerFactionCode()
    local groups = self:GetGroups(entry.itemId)
    local kind = SOURCE_GROUP[entry.sourceType] or "w"

    local function push(groupKey, tuples, isTrainer)
        for _, t in ipairs(tuples) do
            if FactionAllows(t[4], want) then
                pins[#pins + 1] = {
                    mapId = t[1],
                    x = t[2],
                    y = t[3],
                    kind = groupKey,
                    fac = t[4],
                    flat = t[5] or nil,
                    entrance = (t[6] == 1) or nil,
                    trainer = isTrainer or nil,
                    entry = entry,
                }
            end
        end
    end

    if entry.sourceType == "profession" and entry.profession then
        local trainers = self:Trainers(entry.profession)
        if trainers then
            push("p", trainers, true)
        end
    end

    if #pins == 0 and groups and groups[kind] then
        push(kind, groups[kind])
    end

    if #pins == 0 and groups then
        for _, key in ipairs(FALLBACK_ORDER) do
            if key ~= kind and groups[key] then
                push(key, groups[key])
                if #pins > 0 then
                    break
                end
            end
        end
    end

    -- Generated zone-level fallback: the source data knows the zone, not the spot.
    if #pins == 0 and groups and groups.z then
        for _, t in ipairs(groups.z) do
            pins[#pins + 1] = {
                mapId = t[1],
                x = 50,
                y = 50,
                kind = kind,
                fac = "B",
                zoneOnly = true,
                entry = entry,
            }
        end
    end

    if #pins == 0 and entry.zone and GQ.Map and GQ.Map.ZoneMap then
        local mapId = GQ.Map:ZoneMap(entry.zone)
        if mapId then
            pins[1] = {
                mapId = mapId,
                x = 50,
                y = 50,
                kind = kind,
                fac = "B",
                zoneOnly = true,
                entry = entry,
            }
        end
    end

    return pins
end

function GQ.Locations:DescribeCoords(entry)
    local pins = self:Resolve(entry)
    if #pins == 0 then
        return nil
    end

    local parts, zones, seen = {}, {}, {}
    for _, pin in ipairs(pins) do
        if #parts >= MAX_COORDS then
            break
        end
        if not seen[pin.mapId] then
            local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(pin.mapId)
            local zone = (info and info.name) or ("map " .. tostring(pin.mapId))
            if pin.zoneOnly then
                seen[pin.mapId] = true
                zones[#zones + 1] = zone
            else
                seen[pin.mapId] = true
                parts[#parts + 1] = string.format("%s (%.1f, %.1f)%s", zone, pin.x, pin.y, pin.entrance and " (entrance)" or "")
            end
        end
    end

    if #parts == 0 then
        if #zones == 0 then
            return nil
        end
        return "Coords: " .. table.concat(zones, ", ") .. " (zone only)"
    end

    local line = "Coords: " .. table.concat(parts, ", ")
    if #pins > #parts then
        line = line .. " ..."
    end
    if entry and entry.sourceType == "profession" and entry.profession then
        line = line .. " (" .. string.lower(entry.profession) .. " trainers)"
    end
    return line
end

-- Bounding box of a pin's footprint in map percent: cx, cy, halfWidth, halfHeight.
function GQ.Locations:AreaBounds(pin)
    if not pin then
        return nil
    end
    local flat = pin.flat
    if not flat or #flat < 2 then
        return pin.x, pin.y, 0, 0
    end

    local minX, maxX = flat[1], flat[1]
    local minY, maxY = flat[2], flat[2]
    for i = 1, #flat - 1, 2 do
        local x, y = flat[i], flat[i + 1]
        if x < minX then minX = x end
        if x > maxX then maxX = x end
        if y < minY then minY = y end
        if y > maxY then maxY = y end
    end
    return (minX + maxX) / 2, (minY + maxY) / 2, (maxX - minX) / 2, (maxY - minY) / 2
end

-- World drop pins need the player inside the spawn footprint; point pins use the zone test.
function GQ.Locations:AreaContains(pin, x, y)
    if not pin or not x or not y then
        return false
    end
    if not pin.flat or #pin.flat < 2 then
        return true
    end
    local cx, cy, rx, ry = self:AreaBounds(pin)
    local pad = 0.03
    return math.abs(x - cx) <= rx + pad and math.abs(y - cy) <= ry + pad
end
