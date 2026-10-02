local _, GQ = ...

GQ.Pins = GQ.Pins or {}

local ICONS = {
    q = "Interface\\GossipFrame\\AvailableQuestIcon",
    b = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",
    p = "Interface\\QuestFrame\\UI-QuestLog-BookIcon",
    v = "Interface\\GossipFrame\\VendorIcon",
    w = "Interface\\Icons\\INV_Misc_Map_01",
}
local AREA_TEXTURE = "Interface\\Minimap\\UI-Minimap-Ping-Center"
local AREA_COLOR = { 0.3, 0.55, 1, 0.35 }
local UPDATE_INTERVAL = 0.05
local WORLD_PIN_SIZE = 24
local MINI_PIN_SIZE = 18
local EDGE_LIMIT_SQ = 0.92 * 0.92

local pins = {}
local selectedEntryId
local driver
local worldPool = {}
local miniPool = {}
local worldArea
local miniArea
local spanCache = {}
local elapsedAcc = 0
local poolsActive = true

local function SelectedPinOnMap(mapId)
    if not selectedEntryId or not mapId then
        return nil
    end
    for _, pin in ipairs(pins) do
        if pin.entry and pin.entry.id == selectedEntryId and pin.mapId == mapId then
            return pin
        end
    end
    return nil
end

-- Yards per 0-100 map percent, cached per map. Sign-agnostic: callers
-- re-derive east/north from the map's own axis directions.
local function MapSpans(mapId)
    local cached = spanCache[mapId]
    if cached then
        return cached[1], cached[2]
    end
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then
        return 0, 0
    end
    local _, topLeft = C_Map.GetWorldPosFromMapPos(mapId, CreateVector2D(0, 0))
    local _, bottomRight = C_Map.GetWorldPosFromMapPos(mapId, CreateVector2D(1, 1))
    if not (topLeft and bottomRight) then
        return 0, 0
    end
    local spanX = math.abs(bottomRight.x - topLeft.x)
    local spanY = math.abs(bottomRight.y - topLeft.y)
    spanCache[mapId] = { spanX, spanY }
    return spanX, spanY
end

local function ShowPinTooltip(frame)
    local pin = frame.pinData
    if not pin or not pin.entry then
        return
    end
    local entry = pin.entry

    GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")

    local name = GQ.Data and GQ.Data.GetEntryDisplayName and GQ.Data:GetEntryDisplayName(entry)
    GameTooltip:AddLine(name or ("Item " .. tostring(entry.itemId)), 1, 0.82, 0)

    local instructions = entry.instructions
    if GQ.Data and GQ.Data.GetProfessionInstructions then
        instructions = GQ.Data:GetProfessionInstructions(entry)
    end
    if GQ.Data and GQ.Data.SanitizeText then
        instructions = GQ.Data:SanitizeText(instructions) or instructions
    end
    if instructions and instructions ~= "" then
        GameTooltip:AddLine(instructions, 0.9, 0.9, 0.9, true)
    end

    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(pin.mapId)
    local zone = (info and info.name) or entry.zone or ""
    if pin.zoneOnly then
        if zone ~= "" then
            GameTooltip:AddLine(zone, 0.6, 0.8, 1)
        end
    elseif zone ~= "" then
        GameTooltip:AddLine(string.format("%s (%.1f, %.1f)", zone, pin.x, pin.y), 0.6, 0.8, 1)
    end

    if pin.entrance then
        GameTooltip:AddLine("Dungeon entrance", 0.8, 0.8, 0.8)
    end

    if pin.fac == "A" then
        GameTooltip:AddLine("Alliance", 0.3, 0.5, 1)
    elseif pin.fac == "H" then
        GameTooltip:AddLine("Horde", 1, 0.25, 0.25)
    end

    GameTooltip:Show()
end

local function ToggleArea(frame)
    local pin = frame.pinData
    if not pin or not pin.entry then
        return
    end
    if selectedEntryId == pin.entry.id then
        selectedEntryId = nil
    else
        selectedEntryId = pin.entry.id
    end
end

local function WirePin(frame)
    frame:SetScript("OnEnter", ShowPinTooltip)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame:SetScript("OnClick", function(self)
        ToggleArea(self)
    end)
    return frame
end

-- World map pins ----------------------------------------------------------------

local function EnsureWorldPin(index)
    local frame = worldPool[index]
    if frame then
        return frame
    end
    local canvas = WorldMapFrame and WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()
    if not canvas then
        return nil
    end
    frame = CreateFrame("Button", nil, canvas)
    frame:SetSize(WORLD_PIN_SIZE, WORLD_PIN_SIZE)
    frame:SetFrameStrata(canvas:GetFrameStrata() or "HIGH")
    frame:SetFrameLevel((canvas:GetFrameLevel() or 1) + 5)
    frame.icon = frame:CreateTexture(nil, "OVERLAY")
    frame.icon:SetAllPoints()
    WirePin(frame)
    frame:Hide()
    worldPool[index] = frame
    return frame
end

local function EnsureWorldArea(canvas)
    if worldArea and worldArea:GetParent() == canvas then
        return worldArea
    end
    worldArea = CreateFrame("Frame", nil, canvas)
    worldArea:SetSize(WORLD_PIN_SIZE, WORLD_PIN_SIZE)
    worldArea:SetFrameStrata(canvas:GetFrameStrata() or "HIGH")
    worldArea:SetFrameLevel((canvas:GetFrameLevel() or 1) + 2)
    worldArea.tex = worldArea:CreateTexture(nil, "ARTWORK")
    worldArea.tex:SetTexture(AREA_TEXTURE)
    worldArea.tex:SetAllPoints()
    worldArea.tex:SetVertexColor(AREA_COLOR[1], AREA_COLOR[2], AREA_COLOR[3], AREA_COLOR[4])
    worldArea:Hide()
    return worldArea
end

local function HideWorldPins()
    for _, frame in ipairs(worldPool) do
        frame:Hide()
    end
    if worldArea then
        worldArea:Hide()
    end
end

local function UpdateWorldMap()
    local mapId = WorldMapFrame and WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
    local canvas = WorldMapFrame and WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()
    if not (WorldMapFrame and WorldMapFrame:IsShown() and mapId and canvas) then
        HideWorldPins()
        return
    end
    local width, height = canvas:GetWidth(), canvas:GetHeight()
    if width <= 0 or height <= 0 then
        HideWorldPins()
        return
    end

    local used = 0
    for _, pin in ipairs(pins) do
        if pin.mapId == mapId then
            used = used + 1
            local frame = EnsureWorldPin(used)
            if not frame then
                break
            end
            local nx, ny = pin.x / 100, pin.y / 100
            if frame.lastNX ~= nx or frame.lastNY ~= ny
                or frame.lastW ~= width or frame.lastH ~= height then
                frame.lastNX, frame.lastNY = nx, ny
                frame.lastW, frame.lastH = width, height
                frame:ClearAllPoints()
                frame:SetPoint("CENTER", canvas, "TOPLEFT", nx * width, -ny * height)
            end
            local texture = ICONS[pin.kind] or ICONS.w
            if frame.lastTexture ~= texture then
                frame.lastTexture = texture
                frame.icon:SetTexture(texture)
            end
            frame.pinData = pin
            frame:Show()
        end
    end
    for index = used + 1, #worldPool do
        worldPool[index]:Hide()
    end

    local area = EnsureWorldArea(canvas)
    local pin = SelectedPinOnMap(mapId)
    if not pin then
        area:Hide()
        return
    end
    local cx, cy, rx, ry = GQ.Locations:AreaBounds(pin)
    local padX = (rx > 0 and rx * 0.3 or 0) + 1
    local padY = (ry > 0 and ry * 0.3 or 0) + 1
    local areaW = math.max((rx + padX) * 2 * width / 100, width * 0.10)
    local areaH = math.max((ry + padY) * 2 * height / 100, height * 0.10)
    local key = string.format("%d:%d:%d", mapId, math.floor(cx * 10), math.floor(cy * 10))
    if area.lastKey ~= key or area.lastW ~= width or area.lastH ~= height then
        area.lastKey, area.lastW, area.lastH = key, width, height
        area:ClearAllPoints()
        area:SetPoint("CENTER", canvas, "TOPLEFT", cx / 100 * width, -cy / 100 * height)
        area:SetSize(areaW, areaH)
    end
    area:Show()
end

-- Minimap pins ------------------------------------------------------------------

local function EnsureMiniPin(index)
    local frame = miniPool[index]
    if frame then
        return frame
    end
    frame = CreateFrame("Button", nil, Minimap)
    frame:SetSize(MINI_PIN_SIZE, MINI_PIN_SIZE)
    frame:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 5)
    frame.icon = frame:CreateTexture(nil, "OVERLAY")
    frame.icon:SetAllPoints()
    WirePin(frame)
    frame:Hide()
    miniPool[index] = frame
    return frame
end

local function EnsureMiniArea()
    if miniArea then
        return miniArea
    end
    miniArea = CreateFrame("Frame", nil, Minimap)
    miniArea:SetSize(MINI_PIN_SIZE, MINI_PIN_SIZE)
    miniArea:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 2)
    miniArea.tex = miniArea:CreateTexture(nil, "ARTWORK")
    miniArea.tex:SetTexture(AREA_TEXTURE)
    miniArea.tex:SetAllPoints()
    miniArea.tex:SetVertexColor(AREA_COLOR[1], AREA_COLOR[2], AREA_COLOR[3], AREA_COLOR[4])
    miniArea:Hide()
    return miniArea
end

local function HideMiniPins()
    for _, frame in ipairs(miniPool) do
        frame:Hide()
    end
    if miniArea then
        miniArea:Hide()
    end
end

-- Rotating minimaps turn the map under a fixed-up orientation; GetPlayerFacing
-- is restricted on some clients, so fall back to facing north-up.
local function FacingRadians()
    if not (GetCVar and GetCVar("rotateMinimap") == "1") then
        return 0, false
    end
    local facing = GetPlayerFacing and GetPlayerFacing() or nil
    if not facing then
        return 0, false
    end
    return facing, true
end

local function UpdateMinimap()
    if not (Minimap and Minimap:IsShown()) then
        HideMiniPins()
        return
    end
    local playerMap = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local playerPos = playerMap and C_Map.GetPlayerMapPosition(playerMap, "player")
    if not (playerMap and playerPos) then
        HideMiniPins()
        return
    end
    local px, py = playerPos:GetXY()

    local radius = C_Minimap and C_Minimap.GetViewRadius and C_Minimap.GetViewRadius()
    if not radius or radius <= 0 then
        HideMiniPins()
        return
    end
    local halfW = Minimap:GetWidth() / 2
    local halfH = Minimap:GetHeight() / 2
    local facing, rotating = FacingRadians()
    local cos, sin = math.cos(facing), math.sin(facing)
    local spanX, spanY = MapSpans(playerMap)

    -- Map percent deltas -> east/north yards -> minimap fractions of view radius.
    local function project(x, y)
        local east = (x - px) * spanX
        local north = (py - y) * spanY
        local fx, fy = east / radius, north / radius
        if rotating then
            local rx = fx * cos - fy * sin
            local ry = fx * sin + fy * cos
            return rx, ry
        end
        return fx, fy
    end

    local used = 0
    for _, pin in ipairs(pins) do
        if pin.mapId == playerMap and GQ.Locations:AreaContains(pin, px, py) then
            local fx, fy = project(pin.x, pin.y)
            if fx * fx + fy * fy <= EDGE_LIMIT_SQ then
                used = used + 1
                local frame = EnsureMiniPin(used)
                if frame then
                    local ox, oy = fx * halfW, -fy * halfH
                    if frame.lastOX ~= ox or frame.lastOY ~= oy then
                        frame.lastOX, frame.lastOY = ox, oy
                        frame:ClearAllPoints()
                        frame:SetPoint("CENTER", Minimap, "CENTER", ox, oy)
                    end
                    local texture = ICONS[pin.kind] or ICONS.w
                    if frame.lastTexture ~= texture then
                        frame.lastTexture = texture
                        frame.icon:SetTexture(texture)
                    end
                    frame.pinData = pin
                    frame:Show()
                end
            end
        end
    end
    for index = used + 1, #miniPool do
        miniPool[index]:Hide()
    end

    local area = EnsureMiniArea()
    local pin = SelectedPinOnMap(playerMap)
    if not pin or not GQ.Locations:AreaContains(pin, px, py) then
        area:Hide()
        return
    end
    local cx, cy, rx, ry = GQ.Locations:AreaBounds(pin)
    local fx, fy = project(cx, cy)
    local eastRadius = rx * spanX
    local northRadius = ry * spanY
    local yardRadius = math.max(eastRadius, northRadius)
    local size = math.min(math.max(yardRadius / radius * halfW, halfW * 0.15), halfW * 0.9)
    local ox, oy = fx * halfW, -fy * halfH
    area:ClearAllPoints()
    area:SetPoint("CENTER", Minimap, "CENTER", ox, oy)
    area:SetSize(size * 2, size * 2)
    area:Show()
end

-- Driver -------------------------------------------------------------------------

local function UpdateAll()
    if #pins == 0 then
        if poolsActive then
            poolsActive = false
            HideWorldPins()
            HideMiniPins()
        end
        return
    end
    poolsActive = true
    UpdateWorldMap()
    UpdateMinimap()
end

function GQ.Pins:Sync(entries)
    if not driver then
        self:Init()
    end

    pins = {}
    if not entries and GQ.Tracker and GQ.Tracker.GetTrackedEntries then
        entries = GQ.Tracker:GetTrackedEntries()
    end
    if entries then
        for _, entry in ipairs(entries) do
            for _, pin in ipairs(GQ.Locations:Resolve(entry)) do
                pins[#pins + 1] = pin
            end
        end
    end

    if selectedEntryId then
        local found = false
        for _, pin in ipairs(pins) do
            if pin.entry and pin.entry.id == selectedEntryId then
                found = true
                break
            end
        end
        if not found then
            selectedEntryId = nil
        end
    end

    UpdateAll()
end

function GQ.Pins:Init()
    if driver then
        return
    end
    driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", function(_, elapsed)
        elapsedAcc = elapsedAcc + (elapsed or 0)
        if elapsedAcc < UPDATE_INTERVAL then
            return
        end
        elapsedAcc = 0
        UpdateAll()
    end)
    UpdateAll()
end
