-- Skin.lua: faction theme (Alliance / Horde) for the GearQuest Forever Log window.
-- Load AFTER Log.lua in the .toc. It only restyles; it never changes behavior.
local ADDON_NAME, GQ = ...
GQ.Skin = GQ.Skin or {}
local Skin = GQ.Skin

-- Built-in WoW fonts only (no license issues). MORPHEUS is the fantasy face used by in-game books.
local TITLE_FONT = "Fonts\\MORPHEUS.TTF"
local BODY_FONT = "Fonts\\FRIZQT__.TTF"

local THEMES = {
    Alliance = {
        accent = { 0.93, 0.78, 0.35 }, bg = { 0.04, 0.07, 0.16, 0.98 }, panel = { 0.06, 0.11, 0.24, 1 },
        border = { 0.20, 0.30, 0.55 }, letter = "A",
    },
    Horde = {
        accent = { 0.86, 0.27, 0.20 }, bg = { 0.10, 0.04, 0.04, 0.98 }, panel = { 0.18, 0.07, 0.07, 1 },
        border = { 0.45, 0.14, 0.12 }, letter = "H",
    },
}

Skin.override = nil -- "Alliance" | "Horde" (Simulator sets this); nil = player's faction

function Skin:GetFaction()
    if self.override then return self.override end
    local f = UnitFactionGroup and UnitFactionGroup("player")
    return THEMES[f] and f or "Alliance"
end

local function setEdge(frame, c)
    if frame.SetBackdropBorderColor then pcall(frame.SetBackdropBorderColor, frame, c[1], c[2], c[3], 1) end
end

local function setBg(frame, c)
    if frame.SetBackdropColor then pcall(frame.SetBackdropColor, frame, c[1], c[2], c[3], c[4] or 1) end
end

local function ensureDecor(frame)
    if frame.gqSkin then return frame.gqSkin end
    local d = {}
    d.bar = frame:CreateTexture(nil, "ARTWORK")
    d.bar:SetTexture("Interface\\Buttons\\WHITE8X8")
    d.bar:SetHeight(2)
    d.bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -26)
    d.bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -26)
    d.mark = frame:CreateFontString(nil, "BACKGROUND")
    d.mark:SetFont(TITLE_FONT, 260, "")
    d.mark:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 30)
    d.corners = {}
    for i, p in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
        local t = frame:CreateTexture(nil, "OVERLAY")
        t:SetTexture("Interface\\Buttons\\WHITE8X8")
        t:SetSize(7, 7)
        t:SetRotation(math.rad(45))
        t:SetPoint(p, frame, p, p:find("LEFT") and 2 or -2, p:find("TOP") and -2 or 2)
        d.corners[i] = t
    end
    frame.gqSkin = d
    return d
end

local function walk(frame, fn, depth)
    depth = depth or 0
    if depth > 6 then return end
    fn(frame)
    for _, child in ipairs({ frame:GetChildren() }) do walk(child, fn, depth + 1) end
end

function Skin:Apply()
    local frame = _G.GearQuestLogFrame
    if not frame then return end
    local th = THEMES[self:GetFaction()]
    local a = th.accent

    setBg(frame, th.bg)
    setEdge(frame, th.border)

    local d = ensureDecor(frame)
    d.bar:SetColorTexture(a[1], a[2], a[3], 0.9)
    d.mark:SetText(th.letter)
    d.mark:SetTextColor(a[1], a[2], a[3], 0.12)
    for _, t in ipairs(d.corners) do t:SetColorTexture(a[1], a[2], a[3], 1) end

    -- Title in the fantasy face.
    local title = frame.TitleText or (frame.TitleContainer and frame.TitleContainer.TitleText) or frame.title
    if title and title.SetFont then
        title:SetFont(TITLE_FONT, 18, "")
        title:SetTextColor(a[1], a[2], a[3])
    end

    -- Recolor flat panels and buttons that already use backdrops.
    walk(frame, function(f)
        local name = f.GetName and f:GetName() or ""
        local isBtn = f.GetObjectType and f:GetObjectType() == "Button"
        if f ~= frame and f.GetBackdropColor and f.SetBackdropColor and not isBtn then
            local ok, r, g, b = pcall(f.GetBackdropColor, f)
            if ok and r and (r + g + b) < 0.9 then
                setBg(f, th.panel)
                setEdge(f, th.border)
            end
        end
        if f.SetBackdropBorderColor and name:find("^GearQuest") then
            setEdge(f, th.border)
        end
        if f.GetObjectType and f:GetObjectType() == "Button" and name:find("^GearQuest") then
            local fs = f.GetFontString and f:GetFontString()
            if fs then fs:SetFont(BODY_FONT, 12, "") end
            if f.SetBackdropColor then setBg(f, th.panel) end
            if f.SetBackdropBorderColor then setEdge(f, th.border) end
        end
    end)
end

-- Re-apply whenever the Log opens or the Simulator picks a faction.
local function hook()
    if not (GQ.Log and GQ.Log.Show) or Skin.hooked then return end
    Skin.hooked = true
    hooksecurefunc(GQ.Log, "Show", function() Skin:Apply() end)
    for _, key in ipairs({ "Alliance", "Horde" }) do
        local b = _G["GearQuestSimFaction" .. key]
        if b then b:HookScript("OnClick", function() Skin.override = key; Skin:Apply() end) end
    end
    local reset = _G.GearQuestSimResetButton
    if reset then reset:HookScript("OnClick", function() Skin.override = nil; Skin:Apply() end) end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function() hook(); Skin:Apply() end)
