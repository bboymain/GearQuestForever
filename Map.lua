local _, GQ = ...

GQ.Map = GQ.Map or {}

local PREFIX = "|cff66ccffGearQuest|r: "
local zoneCache = {}

-- ponytail: linear scan of map IDs by name, cached per zone. Fallback when the
-- locations index has no pin for the entry.
local function FindMapId(zoneName)
    if zoneCache[zoneName] ~= nil then
        return zoneCache[zoneName] or nil
    end
    local found = false
    if C_Map and C_Map.GetMapInfo then
        for id = 1, 3000 do
            local info = C_Map.GetMapInfo(id)
            if info and info.name == zoneName then
                found = id
                break
            end
        end
    end
    zoneCache[zoneName] = found
    return found or nil
end

-- Zone or subzone name -> UiMapId. Subzones ("Kharanos") resolve through the
-- shipped areaId table plus C_Map.GetAreaInfo.
local subzoneCache = {}
local function ZoneMap(zoneName)
    if not zoneName then
        return nil
    end
    local mapId = FindMapId(zoneName)
    if mapId then
        return mapId
    end
    if subzoneCache[zoneName] == nil then
        subzoneCache[zoneName] = false
        if GQ.AreaMapIndex and C_Map.GetAreaInfo then
            for areaId, uiMapId in pairs(GQ.AreaMapIndex) do
                if uiMapId > 0 and C_Map.GetAreaInfo(areaId) == zoneName then
                    subzoneCache[zoneName] = uiMapId
                    break
                end
            end
        end
    end
    return subzoneCache[zoneName] or nil
end

function GQ.Map:ZoneMap(zoneName)
    return ZoneMap(zoneName)
end

-- The NPC / object named by the entry or its instructions text.
local function SourceName(entry)
    local text = entry.instructions or ""
    return entry.npc
        or text:match("Starts with (.-) in %u")
        or text:match("Bought from (.-)[%.,]")
        or text:match("[Dd]rops from (.-)[%.,]")
end

-- Returns mapId, x, y (0-100), who — or mapId only (zone fallback) — or nil.
local function Locate(entry)
    if not entry then
        return nil
    end
    local pins = GQ.Locations and GQ.Locations.Resolve and GQ.Locations:Resolve(entry)
    local pin = pins and pins[1]
    if pin then
        return pin.mapId, pin.x, pin.y, SourceName(entry)
    end
    return ZoneMap(entry.zone), nil, nil, SourceName(entry)
end

local function WorldPos(mapId, x, y)
    if not (mapId and C_Map.GetWorldPosFromMapPos and CreateVector2D) then
        return nil
    end
    local continent, pos = C_Map.GetWorldPosFromMapPos(mapId, CreateVector2D(x, y))
    if continent and pos then
        return continent, pos:GetXY()
    end
end

local locCache = {}

-- World distance (yards) from the player to the entry's source; math.huge if unknown.
-- Other continents count as 1e6 + distance so they sort after everything nearby.
function GQ.Map:DistanceTo(entry)
    local playerMap = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local playerPos = playerMap and C_Map.GetPlayerMapPosition(playerMap, "player")
    if not playerPos then
        return math.huge
    end
    local pc, px, py = WorldPos(playerMap, playerPos:GetXY())

    local loc = locCache[entry.id]
    if not loc then
        local mapId, x, y = Locate(entry)
        -- Zone-only fallback: aim at the middle of the zone.
        loc = { mapId = mapId, x = (x or 50) / 100, y = (y or 50) / 100 }
        locCache[entry.id] = loc
    end
    local ec, ex, ey = WorldPos(loc.mapId, loc.x, loc.y)
    if not (pc and ec) then
        return math.huge
    end
    local d = math.sqrt((ex - px) ^ 2 + (ey - py) ^ 2)
    return ec == pc and d or 1e6 + d
end

-- Always clickable once something is selected; Show() falls back to the plain world map.
function GQ.Map:CanShow(entry)
    return entry ~= nil
end

local function SetPin(mapId, x, y, label)
    x, y = x / 100, y / 100
    if TomTom and TomTom.AddWaypoint then
        TomTom:AddWaypoint(mapId, x, y, { title = "GearQuest: " .. label })
        return true
    end
    if C_Map.SetUserWaypoint and UiMapPoint and C_Map.CanSetUserWaypointOnMap and C_Map.CanSetUserWaypointOnMap(mapId) then
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapId, x, y))
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            C_SuperTrack.SetSuperTrackedUserWaypoint(true)
        end
        return true
    end
    return false
end

function GQ.Map:Show(entry)
    if not entry then
        return
    end
    local mapId, x, y, who = Locate(entry)
    if not mapId then
        -- Nothing known (random world drop, crafted, ...): still open the map, and say how to get it.
        mapId = 947
        print(PREFIX .. "No exact spot for this item. " .. (entry.instructions or ""))
    end

    local label = who or entry.questName or entry.zone or "?"
    local pinned = x and SetPin(mapId, x, y, label)

    -- The map snaps to the player's zone on show; set ours after, and again next frame to win that race.
    if WorldMapFrame then
        if not WorldMapFrame:IsShown() then
            ShowUIPanel(WorldMapFrame)
        end
        WorldMapFrame:SetMapID(mapId)
        C_Timer.After(0, function()
            if WorldMapFrame:IsShown() then
                WorldMapFrame:SetMapID(mapId)
            end
        end)
    elseif OpenWorldMap then
        OpenWorldMap(mapId)
    end

    local info = C_Map.GetMapInfo and C_Map.GetMapInfo(mapId)
    local where = (info and info.name) or entry.zone or "?"
    if x then
        where = string.format("%s (%.1f, %.1f)", where, x, y)
    end
    print(PREFIX .. label .. " — " .. where .. (pinned and " — pin placed" or ""))
end
