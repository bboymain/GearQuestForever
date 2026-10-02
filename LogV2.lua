-- LogV2.lua: redesigned Log window (faction-themed). Load AFTER Log.lua and Commands.lua.
-- It reads the same data and progress as the classic Log, and replaces the window the player sees.
-- /gq classic opens the original window. /gq new returns to this one.
local ADDON_NAME, GQ = ...
GQ.LogV2 = GQ.LogV2 or {}
local V2 = GQ.LogV2

local W, H = 920, 600
local HEADER_H, BANNER_H = 60, 24
local LEFT_W, RIGHT_W = 190, 320
-- Put HyliaSerif.ttf in Interface\\AddOns\\<addon>\\Fonts\\ . Falls back to built-in fonts if it is missing or fails to load.
local TITLE_FONT = "Fonts\\MORPHEUS.TTF"
local BODY_FONT = "Fonts\\FRIZQT__.TTF"
do
    local custom = "Interface\\AddOns\\" .. tostring(ADDON_NAME) .. "\\Fonts\\HyliaSerif.ttf"
    local probe = UIParent:CreateFontString(nil, "OVERLAY")
    local ok, res = pcall(probe.SetFont, probe, custom, 14, "")
    if ok and res ~= false then TITLE_FONT = custom; BODY_FONT = custom end
end
local WHITE = "Interface\\Buttons\\WHITE8X8"

local THEMES = {
    Alliance = {
        letter = "A", accent = { 0.93, 0.78, 0.35 }, bg = { 0.04, 0.07, 0.15, 0.98 }, panel = { 0.06, 0.10, 0.21, 1 },
        card = { 0.08, 0.13, 0.26, 1 }, sel = { 0.12, 0.19, 0.38, 1 }, border = { 0.20, 0.30, 0.55 },
        parch = { 0.89, 0.85, 0.72 }, parchInk = { 0.10, 0.07, 0.03 }, muted = { 0.62, 0.68, 0.80 },
    },
    Horde = {
        letter = "H", accent = { 0.86, 0.27, 0.20 }, bg = { 0.09, 0.04, 0.04, 0.98 }, panel = { 0.15, 0.07, 0.07, 1 },
        card = { 0.20, 0.09, 0.09, 1 }, sel = { 0.32, 0.12, 0.10, 1 }, border = { 0.45, 0.14, 0.12 },
        parch = { 0.84, 0.76, 0.64 }, parchInk = { 0.12, 0.06, 0.03 }, muted = { 0.80, 0.64, 0.60 },
    },
}

local QUALITY = {
    [0] = { 0.62, 0.62, 0.62, "Poor" }, [1] = { 1, 1, 1, "Common" }, [2] = { 0.12, 1, 0, "Uncommon" },
    [3] = { 0, 0.44, 0.87, "Rare" }, [4] = { 0.64, 0.21, 0.93, "Epic" }, [5] = { 1, 0.5, 0, "Legendary" },
}

local ART = "Interface\\AddOns\\" .. tostring(ADDON_NAME) .. "\\Art\\"
local FILL, RING, PAPER = ART .. "V2-fill", ART .. "V2-ring", ART .. "V2-paper"

local function Slice(frame, file, cs, layer, sub)
    local c, all = 0.25, {}
    local function tx(u1, u2, v1, v2)
        local x = frame:CreateTexture(nil, layer, nil, sub)
        x:SetTexture(file); x:SetTexCoord(u1, u2, v1, v2); all[#all + 1] = x
        return x
    end
    local tl = tx(0, c, 0, c); tl:SetSize(cs, cs); tl:SetPoint("TOPLEFT")
    local tr = tx(1 - c, 1, 0, c); tr:SetSize(cs, cs); tr:SetPoint("TOPRIGHT")
    local bl = tx(0, c, 1 - c, 1); bl:SetSize(cs, cs); bl:SetPoint("BOTTOMLEFT")
    local br = tx(1 - c, 1, 1 - c, 1); br:SetSize(cs, cs); br:SetPoint("BOTTOMRIGHT")
    local top = tx(c, 1 - c, 0, c); top:SetPoint("TOPLEFT", tl, "TOPRIGHT"); top:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
    local bot = tx(c, 1 - c, 1 - c, 1); bot:SetPoint("TOPLEFT", bl, "TOPRIGHT"); bot:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
    local lf = tx(0, c, c, 1 - c); lf:SetPoint("TOPLEFT", tl, "BOTTOMLEFT"); lf:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT")
    local rt = tx(1 - c, 1, c, 1 - c); rt:SetPoint("TOPLEFT", tr, "BOTTOMLEFT"); rt:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
    local ce = tx(c, 1 - c, c, 1 - c); ce:SetPoint("TOPLEFT", tl, "BOTTOMRIGHT"); ce:SetPoint("BOTTOMRIGHT", br, "TOPLEFT")
    return function(r, g, b, a) for _, x in ipairs(all) do x:SetVertexColor(r, g, b, a or 1) end end
end

-- Rounded fill + ring using the Art/V2-*.tga textures. Keeps the SetBackdropColor API.
local function Round(frame, cs)
    local setF = Slice(frame, FILL, cs, "BACKGROUND", -2)
    local setR = Slice(frame, RING, cs, "BORDER", 0)
    setR(1, 1, 1, 0)
    frame.SetBackdropColor = function(_, r, g, b, a) setF(r, g, b, a or 1) end
    frame.SetBackdropBorderColor = function(_, r, g, b, a) setR(r, g, b, a or 1) end
end

local CLASS_FILES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local CLASS_NAMES = {
    WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
    SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid",
}

V2.tab = "log"
V2.slot = nil
V2.themed = { panels = {}, cards = {}, edges = {}, accents = {}, accentTex = {}, muted = {}, buttons = {} }

local function Theme()
    local f = V2.themeFaction or (GQ.GetEffectiveFaction and GQ:GetEffectiveFaction()) or (UnitFactionGroup and UnitFactionGroup("player"))
    return THEMES[f] or THEMES.Alliance, (THEMES[f] and f or "Alliance")
end

local function Box(parent, kind)
    local f = CreateFrame("Frame", nil, parent)
    Round(f, 8)
    V2.themed[kind or "panels"][#V2.themed[kind or "panels"] + 1] = f
    return f
end

local function Text(parent, size, font, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(font or BODY_FONT, size or 12, "")
    fs:SetJustifyH(justify or "LEFT")
    fs:SetTextColor(0.95, 0.95, 0.96)
    return fs
end

local function Button(parent, label, w, h, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    Round(b, 7)
    b.label = Text(b, 13, BODY_FONT, "CENTER")
    b.label:SetPoint("CENTER")
    b.label:SetText(label)
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(s) s.hover = true; V2:PaintButton(s) end)
    b:SetScript("OnLeave", function(s) s.hover = false; V2:PaintButton(s) end)
    V2.themed.buttons[#V2.themed.buttons + 1] = b
    return b
end

function V2:PaintButton(b)
    local th = Theme()
    local a = th.accent
    if b.primary then
        b:SetBackdropColor(a[1], a[2], a[3], b.hover and 1 or 0.9)
        b:SetBackdropBorderColor(a[1], a[2], a[3], 1)
        b.label:SetTextColor(0.1, 0.08, 0.04)
    elseif b.outline then
        local ink = th.parchInk
        b:SetBackdropColor(ink[1], ink[2], ink[3], b.hover and 0.10 or 0)
        b:SetBackdropBorderColor(ink[1], ink[2], ink[3], 1)
        b.label:SetTextColor(ink[1], ink[2], ink[3])
    elseif b.brown then
        local c = b.hover and 0.30 or 0.24
        b:SetBackdropColor(c, c * 0.62, c * 0.34, 1)
        b:SetBackdropBorderColor(c, c * 0.62, c * 0.34, 1)
        b.label:SetTextColor(0.96, 0.89, 0.72)
    elseif b.onParchment then
        local c = b.hover and th.sel or th.card
        b:SetBackdropColor(c[1], c[2], c[3], 1)
        b:SetBackdropBorderColor(a[1], a[2], a[3], 1)
        b.label:SetTextColor(a[1], a[2], a[3])
    else
        local c = b.hover and th.sel or th.card
        b:SetBackdropColor(c[1], c[2], c[3], 1)
        b:SetBackdropBorderColor(th.border[1], th.border[2], th.border[3], 1)
        b.label:SetTextColor(0.95, 0.95, 0.96)
    end
end

local function Scroller(parent)
    local sf = CreateFrame("ScrollFrame", nil, parent)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(10, 10)
    sf:SetScrollChild(child)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(s, d)
        local max = s:GetVerticalScrollRange() or 0
        s:SetVerticalScroll(math.max(0, math.min(max, s:GetVerticalScroll() - d * 42)))
    end)
    sf:SetScript("OnSizeChanged", function(_, w) child:SetWidth(w) end)
    return sf, child
end

local function Strip(s)
    s = tostring(s or "")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return s
end

local function IconFor(itemId)
    if not itemId then return "Interface\\Icons\\INV_Misc_QuestionMark" end
    if GQ.Equip and GQ.Equip.GetItemIconTexture then
        local t = GQ.Equip:GetItemIconTexture(itemId)
        if t then return t end
    end
    return (GetItemIcon and GetItemIcon(itemId)) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function QualityOf(entry)
    local q = entry.itemId and GQ.Data and GQ.Data.GetItemQualityForDisplay and GQ.Data:GetItemQualityForDisplay(entry.itemId)
    return QUALITY[q or 1] or QUALITY[1]
end

local function HuntState(entry)
    local log = GQ.Log
    if log:IsEntryObtained(entry.id) then return "Obtained" end
    local rec = log:CharProgress().hunts[entry.id]
    if rec and (rec.status == "tracked" or rec.status == "active") then return "Tracking" end
    if GQ.Data:IsEntryNewForPlayer(entry) then return "New" end
    return ""
end

-- ---------------------------------------------------------------- build
function V2:Build()
    if self.frame then return end
    local f = CreateFrame("Frame", "GearQuestV2Frame", UIParent)
    f:SetSize(W, H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    Round(f, 14)
    f:Hide()
    tinsert(UISpecialFrames, "GearQuestV2Frame")
    self.frame = f
    self.themed.panels[#self.themed.panels + 1] = f

    -- header
    local head = CreateFrame("Frame", nil, f)
    head:SetPoint("TOPLEFT"); head:SetPoint("TOPRIGHT"); head:SetHeight(HEADER_H)
    local crest = head:CreateTexture(nil, "ARTWORK"); crest:SetSize(36, 36); crest:SetPoint("LEFT", 16, 0)
    crest:SetTexture(WHITE); self.crest = crest
    self.themed.accentTex[#self.themed.accentTex + 1] = crest
    local letter = Text(head, 24, TITLE_FONT, "CENTER"); letter:SetPoint("CENTER", crest); letter:SetTextColor(0.1, 0.08, 0.04); self.letter = letter
    local title = Text(head, 24, TITLE_FONT); title:SetPoint("LEFT", crest, "RIGHT", 12, 0)
    title:SetText("GearQuest Forever"); self.title = title
    self.themed.accents[#self.themed.accents + 1] = title

    local flipBtn = CreateFrame("Button", nil, head)
    flipBtn:SetAllPoints(crest)
    flipBtn:SetScript("OnClick", function() V2:FlipFaction() end)
    flipBtn:SetScript("OnEnter", function(s) GameTooltip:SetOwner(s, "ANCHOR_BOTTOM"); GameTooltip:SetText("Switch Alliance / Horde theme"); GameTooltip:Show() end)
    flipBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local close = Button(head, "X", 28, 28, function() V2:Hide() end)
    close:SetPoint("RIGHT", -14, 0)

    self.tabButtons = {}
    local prev
    for _, t in ipairs({ { "log", "Log" }, { "sim", "Simulator" }, { "settings", "Settings" } }) do
        local b = CreateFrame("Button", nil, head)
        b:SetSize(84, HEADER_H)
        b.label = Text(b, 14, BODY_FONT, "CENTER"); b.label:SetPoint("CENTER")
        b.label:SetText(t[2])
        b.line = b:CreateTexture(nil, "ARTWORK"); b.line:SetTexture(WHITE); b.line:SetHeight(2)
        b.line:SetPoint("BOTTOMLEFT", 8, 0); b.line:SetPoint("BOTTOMRIGHT", -8, 0)
        b:SetScript("OnClick", function() V2:SetTab(t[1]) end)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 2, 0) else b:SetPoint("LEFT", title, "RIGHT", 20, 0) end
        prev = b
        self.tabButtons[t[1]] = b
    end

    self.pills = {}
    local right = close
    for i = 1, 2 do
        local p = Box(head, "cards")
        p:SetHeight(24)
        p.text = Text(p, 12); p.text:SetPoint("CENTER")
        p:SetPoint("RIGHT", right, "LEFT", -8, 0)
        right = p
        self.pills[i] = p
    end

    local rule = f:CreateTexture(nil, "ARTWORK"); rule:SetTexture(WHITE); rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", 0, -HEADER_H); rule:SetPoint("TOPRIGHT", 0, -HEADER_H)
    self.themed.accentTex[#self.themed.accentTex + 1] = rule; rule.alpha = 0.5

    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT", 10, -(HEADER_H + 4)); bar:SetPoint("TOPRIGHT", -10, -(HEADER_H + 4)); bar:SetHeight(20)
    Round(bar, 7); bar:SetBackdropColor(0.22, 0.17, 0.07, 1); bar:SetBackdropBorderColor(0.50, 0.38, 0.12, 1)
    local banner = Text(bar, 12, BODY_FONT, "CENTER"); banner:SetPoint("CENTER")
    banner:SetText("Beta data: some gear is incomplete or incorrect while WoW Forever is still being discovered. Talent changes can shift rankings.")
    banner:SetTextColor(0.95, 0.83, 0.52)

    local body = CreateFrame("Frame", nil, f)
    body:SetPoint("TOPLEFT", 0, -(HEADER_H + BANNER_H)); body:SetPoint("BOTTOMRIGHT")
    self.body = body

    self:BuildLog(body)
    self:BuildSim(body)
    self:BuildSettings(body)
    f:SetScript("OnShow", function() V2:Refresh() end)
end

function V2:BuildLog(body)
    local page = CreateFrame("Frame", nil, body)
    page:SetAllPoints()
    self.logPage = page

    -- slots
    local left = Box(page, "panels")
    left:SetPoint("TOPLEFT", 10, -4); left:SetPoint("BOTTOMLEFT", 10, 10); left:SetWidth(LEFT_W)
    local lh = Text(left, 11); lh:SetPoint("TOPLEFT", 12, -10); lh:SetText("SLOTS")
    self.themed.muted[#self.themed.muted + 1] = lh
    local sf, sc = Scroller(left)
    sf:SetPoint("TOPLEFT", 4, -28); sf:SetPoint("BOTTOMRIGHT", -4, 6)
    self.slotScroll, self.slotChild, self.slotRows = sf, sc, {}

    -- middle
    local mid = CreateFrame("Frame", nil, page)
    mid:SetPoint("TOPLEFT", left, "TOPRIGHT", 14, 0)
    mid:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -(RIGHT_W + 22), 10)
    self.mid = mid
    local slotTitle = Text(mid, 26, TITLE_FONT); slotTitle:SetPoint("TOPLEFT", 4, -2); self.slotTitle = slotTitle
    local sub = Text(mid, 13); sub:SetPoint("TOPLEFT", slotTitle, "BOTTOMLEFT", 0, -4); self.slotSub = sub
    self.themed.muted[#self.themed.muted + 1] = sub

    self.listTabs = {}
    local prevT
    for _, t in ipairs({ { "completed", "Completed" }, { "active", "Active" } }) do
        local b = Button(mid, t[2], 84, 24, function()
            if GQ.Log.SetListTab then GQ.Log:SetListTab(t[1]) end
            V2.selected = nil
            V2:Refresh()
        end)
        if prevT then b:SetPoint("RIGHT", prevT, "LEFT", -6, 0) else b:SetPoint("TOPRIGHT", 0, -4) end
        prevT = b
        self.listTabs[t[1]] = b
    end

    local hsf, hsc = Scroller(mid)
    hsf:SetPoint("TOPLEFT", 0, -64); hsf:SetPoint("BOTTOMRIGHT", 0, 0)
    self.huntScroll, self.huntChild, self.huntCards = hsf, hsc, {}
    local empty = Text(mid, 14); empty:SetPoint("TOPLEFT", 4, -80); empty:SetWidth(360); empty:SetJustifyH("LEFT")
    self.themed.muted[#self.themed.muted + 1] = empty
    self.emptyText = empty

    -- detail (parchment)
    local d = CreateFrame("Frame", nil, page)
    Round(d, 14)
    d.paper = d:CreateTexture(nil, "BACKGROUND", nil, -1)
    d.paper:SetTexture(PAPER); d.paper:SetPoint("TOPLEFT", 6, -6); d.paper:SetPoint("BOTTOMRIGHT", -6, 6)
    d.band = d:CreateTexture(nil, "ARTWORK"); d.band:SetTexture(WHITE); d.band:SetHeight(86)
    d.band:SetPoint("TOPLEFT", 6, -6); d.band:SetPoint("TOPRIGHT", -6, -6)
    d.veil = d:CreateTexture(nil, "ARTWORK", nil, -1); d.veil:SetPoint("TOPLEFT", 6, -6); d.veil:SetPoint("BOTTOMRIGHT", -6, 6)
    d.veil:SetColorTexture(0.82, 0.62, 0.36, 0.62)
    local function fade(tex, top)
        tex:SetTexture(WHITE)
        local lo, hi = { 0.90, 0.72, 0.46, 0 }, { 0.90, 0.72, 0.46, 0.92 }
        if not top then lo, hi = hi, lo end
        local ok = pcall(tex.SetGradient, tex, "VERTICAL", CreateColor(unpack(lo)), CreateColor(unpack(hi)))
        if not ok then ok = pcall(tex.SetGradientAlpha, tex, "VERTICAL", lo[1], lo[2], lo[3], lo[4], hi[1], hi[2], hi[3], hi[4]) end
        if not ok then tex:SetColorTexture(0.86, 0.78, 0.60, 0.45) end
    end
    d.fadeTop = d:CreateTexture(nil, "ARTWORK", nil, 0); d.fadeTop:SetHeight(170)
    d.fadeTop:SetPoint("TOPLEFT", 6, -6); d.fadeTop:SetPoint("TOPRIGHT", -6, -6); fade(d.fadeTop, true)
    d.fadeBot = d:CreateTexture(nil, "ARTWORK", nil, 0); d.fadeBot:SetHeight(130)
    d.fadeBot:SetPoint("BOTTOMLEFT", 6, 6); d.fadeBot:SetPoint("BOTTOMRIGHT", -6, 6); fade(d.fadeBot, false)
    d.gemBg = d:CreateTexture(nil, "OVERLAY", nil, 1); d.gemBg:SetTexture(WHITE); d.gemBg:SetSize(16, 16)
    d.gemBg:SetPoint("TOP", 0, 8); d.gemBg:SetRotation(math.rad(45)); d.gemBg:SetVertexColor(0.05, 0.04, 0.03, 1)
    d.gem = d:CreateTexture(nil, "OVERLAY", nil, 2); d.gem:SetTexture(WHITE); d.gem:SetSize(10, 10)
    d.gem:SetPoint("TOP", 0, 5); d.gem:SetRotation(math.rad(45))
    d:SetPoint("TOPRIGHT", -10, -4); d:SetPoint("BOTTOMRIGHT", -10, 10); d:SetWidth(RIGHT_W)
    self.detail = d
    local ic = CreateFrame("Frame", nil, d)
    ic:SetSize(56, 56); ic:SetPoint("TOPLEFT", 20, -20)
    Round(ic, 8); ic:SetBackdropColor(0, 0, 0, 1)
    ic.tex = ic:CreateTexture(nil, "ARTWORK"); ic.tex:SetPoint("TOPLEFT", 3, -3); ic.tex:SetPoint("BOTTOMRIGHT", -3, 3)
    ic.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    self.dIcon = ic
    local lbl = Text(d, 11); lbl:SetPoint("TOPLEFT", ic, "TOPRIGHT", 10, -4); self.dLabel = lbl
    local q = Text(d, 13); q:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -4); self.dQuality = q
    local name = Text(d, 20, TITLE_FONT); name:SetPoint("TOPLEFT", 22, -92); name:SetPoint("RIGHT", -22, 0)
    name:SetWordWrap(true); self.dName = name
    local div = d:CreateTexture(nil, "ARTWORK"); div:SetTexture(WHITE); div:SetHeight(1)
    div:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -10); div:SetPoint("RIGHT", -22, 0); self.dDiv = div
    d.divGap = d:CreateTexture(nil, "ARTWORK", nil, 3); d.divGap:SetTexture(WHITE); d.divGap:SetSize(22, 6)
    d.divGap:SetPoint("CENTER", div, "CENTER", 0, 0); d.divGap:SetVertexColor(0.86, 0.72, 0.50, 1)
    d.divGem = d:CreateTexture(nil, "ARTWORK", nil, 4); d.divGem:SetTexture(WHITE); d.divGem:SetSize(7, 7)
    d.divGem:SetPoint("CENTER", div, "CENTER", 0, 0); d.divGem:SetRotation(math.rad(45)); d.divGem:SetVertexColor(0.36, 0.24, 0.12, 1)
    local bsf, bsc = Scroller(d)
    bsf:SetPoint("TOPLEFT", div, "BOTTOMLEFT", 0, -10); bsf:SetPoint("RIGHT", -22, 0); bsf:SetPoint("BOTTOM", 0, 112)
    local body = Text(bsc, 13); body:SetPoint("TOPLEFT"); body:SetPoint("RIGHT"); body:SetWordWrap(true); body:SetSpacing(4)
    local meta = Text(bsc, 13); meta:SetPoint("TOPLEFT", body, "BOTTOMLEFT", 0, -14); meta:SetPoint("RIGHT"); meta:SetWordWrap(true); meta:SetSpacing(5)
    self.dMeta = meta
    self.dBodyScroll, self.dBody = bsf, body

    self.mapBtn = Button(d, "Show on Map", 276, 28, function() if V2.sel then GQ.Map:Show(V2.sel) end end)
    self.mapBtn.outline = true
    self.mapBtn:SetPoint("BOTTOM", 0, 68)
    self.trackBtn = Button(d, "Track this hunt", 276, 28, function()
        if not V2.sel then return end
        local id = V2.sel.id
        local rec = GQ.Log:CharProgress().hunts[id]
        if rec and (rec.status == "tracked" or rec.status == "active") then GQ.Log:RequestUntrackHunt(id) else GQ.Log:TrackHunt(id) end
        V2:Refresh()
    end)
    self.trackBtn.primary = true
    self.trackBtn:SetPoint("BOTTOM", 0, 28)
    local none = Text(d, 14); none:SetPoint("CENTER"); none:SetWidth(250); none:SetJustifyH("CENTER")
    none:SetText("Pick a hunt to see where to get it."); self.dNone = none
end

function V2:BuildSim(body)
    local page = CreateFrame("Frame", nil, body)
    page:SetAllPoints(); page:Hide()
    self.simPage = page
    local h = Text(page, 26, TITLE_FONT); h:SetPoint("TOPLEFT", 30, -24); h:SetText("Simulator")
    self.themed.accents[#self.themed.accents + 1] = h
    local sub = Text(page, 13); sub:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -6)
    sub:SetText("Browse another class, spec, faction or level. Your own character is unchanged.")
    self.themed.muted[#self.themed.muted + 1] = sub

    local function label(txt, y)
        local l = Text(page, 11); l:SetPoint("TOPLEFT", 30, y); l:SetText(txt); self.themed.muted[#self.themed.muted + 1] = l; return l
    end
    label("CLASS", -90)
    self.simClassBtns = {}
    for i, cf in ipairs(CLASS_FILES) do
        local b = Button(page, CLASS_NAMES[cf], 92, 28, function() V2:SimPickClass(cf) end)
        b:SetPoint("TOPLEFT", 30 + ((i - 1) % 5) * 98, -108 - math.floor((i - 1) / 5) * 34)
        self.simClassBtns[cf] = b
    end
    label("FACTION", -190)
    self.simFacBtns = {}
    for i, fac in ipairs({ "Alliance", "Horde" }) do
        local b = Button(page, fac, 120, 28, function() V2.simFaction = fac; V2.themeFaction = fac; V2:Refresh() end)
        b:SetPoint("TOPLEFT", 30 + (i - 1) * 126, -208)
        self.simFacBtns[fac] = b
    end
    label("SPECIALIZATION", -252)
    self.simSpecBtns = {}
    for i = 1, 3 do
        local b = Button(page, "", 150, 28, function(s) V2.simSpec = s.specId; V2:RefreshSim() end)
        b:SetPoint("TOPLEFT", 30 + (i - 1) * 156, -270)
        self.simSpecBtns[i] = b
    end
    label("LEVEL", -314)
    local eb = CreateFrame("EditBox", nil, page)
    eb:SetSize(64, 28); eb:SetPoint("TOPLEFT", 30, -332); eb:SetAutoFocus(false); eb:SetNumeric(true); eb:SetMaxLetters(2)
    eb:SetFont(BODY_FONT, 14, ""); eb:SetJustifyH("CENTER"); eb:SetTextColor(1, 1, 1)
    Round(eb, 7)
    eb:SetScript("OnEscapePressed", eb.ClearFocus); eb:SetScript("OnEnterPressed", eb.ClearFocus)
    eb:SetScript("OnTextChanged", function() V2:RefreshSim(true) end)
    self.themed.cards[#self.themed.cards + 1] = eb
    self.simLevel = eb

    local prev = Box(page, "panels")
    prev:SetPoint("TOPLEFT", 560, -90); prev:SetPoint("BOTTOMRIGHT", -24, 30)
    local pl = Text(prev, 11); pl:SetPoint("TOPLEFT", 20, -18); pl:SetText("PREVIEW"); self.themed.muted[#self.themed.muted + 1] = pl
    local pt = Text(prev, 24, TITLE_FONT); pt:SetPoint("TOPLEFT", pl, "BOTTOMLEFT", 0, -8); pt:SetPoint("RIGHT", -20, 0); pt:SetWordWrap(true)
    self.simPreviewTitle = pt
    self.themed.accents[#self.themed.accents + 1] = pt
    local pb = Text(prev, 13); pb:SetPoint("TOPLEFT", pt, "BOTTOMLEFT", 0, -12); pb:SetPoint("RIGHT", -20, 0); pb:SetWordWrap(true)
    pb:SetText("Simulate applies these settings to the Log. Reset returns to your own character.")
    self.themed.muted[#self.themed.muted + 1] = pb
    local go = Button(prev, "Simulate", 130, 30, function() V2:SimApply() end); go.primary = true
    go:SetPoint("BOTTOMLEFT", 20, 20)
    Button(prev, "Reset", 100, 30, function() V2:SimReset() end):SetPoint("LEFT", go, "RIGHT", 10, 0)
end

function V2:BuildSettings(body)
    local page = CreateFrame("Frame", nil, body)
    page:SetAllPoints(); page:Hide()
    self.setPage = page
    local h = Text(page, 26, TITLE_FONT); h:SetPoint("TOPLEFT", 30, -24); h:SetText("Settings")
    self.themed.accents[#self.themed.accents + 1] = h
    local row = Box(page, "panels")
    row:SetPoint("TOPLEFT", 30, -80); row:SetSize(560, 74)
    local t = Text(row, 16); t:SetPoint("TOPLEFT", 18, -14); t:SetText("Hide minimap icon")
    local d = Text(row, 13); d:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -6); d:SetText("You can still open GearQuest with /gq while the icon is hidden.")
    self.themed.muted[#self.themed.muted + 1] = d
    local tog = Button(row, "", 70, 28, function()
        if GQ.Minimap and GQ.Minimap.SetHidden then GQ.Minimap:SetHidden(not GQ.Minimap:IsHidden()) end
        V2:RefreshSettings()
    end)
    tog:SetPoint("RIGHT", -18, 0); self.minimapToggle = tog
    local rep = Text(page, 13); rep:SetPoint("TOPLEFT", row, "BOTTOMLEFT", 0, -20); rep:SetWidth(560)
    rep:SetText("Wrong rank or missing item? Report it with class, spec, level, faction and slot in the GearQuest Discord.")
    self.themed.muted[#self.themed.muted + 1] = rep
end

-- ---------------------------------------------------------------- theming
function V2:ApplyTheme()
    local th, fac = Theme()
    local a = th.accent
    self.frame:SetBackdropColor(th.bg[1], th.bg[2], th.bg[3], th.bg[4])
    self.frame:SetBackdropBorderColor(th.border[1], th.border[2], th.border[3], 1)
    for _, p in ipairs(self.themed.panels) do
        if p ~= self.frame and p.SetBackdropColor then
            p:SetBackdropColor(th.panel[1], th.panel[2], th.panel[3], 1); p:SetBackdropBorderColor(th.border[1], th.border[2], th.border[3], 1)
        end
    end
    for _, p in ipairs(self.themed.cards) do
        p:SetBackdropColor(th.card[1], th.card[2], th.card[3], 1); p:SetBackdropBorderColor(th.border[1], th.border[2], th.border[3], 1)
    end
    for _, fs in ipairs(self.themed.accents) do fs:SetTextColor(a[1], a[2], a[3]) end
    for _, fs in ipairs(self.themed.muted) do fs:SetTextColor(th.muted[1], th.muted[2], th.muted[3]) end
    for _, t in ipairs(self.themed.accentTex) do t:SetColorTexture(a[1], a[2], a[3], t.alpha or 1) end
    for _, b in ipairs(self.themed.buttons) do self:PaintButton(b) end
    self.letter:SetText(th.letter)
    self.detail:SetBackdropColor(th.parch[1], th.parch[2], th.parch[3], 1)
    self.detail:SetBackdropBorderColor(a[1], a[2], a[3], 1)
    self.detail.paper:SetVertexColor(fac == "Horde" and 1 or 0.97, fac == "Horde" and 0.9 or 0.96, fac == "Horde" and 0.86 or 1, 1)
    local ink = th.parchInk
    for _, fs in ipairs({ self.dName, self.dBody, self.dMeta, self.dLabel, self.dQuality, self.dNone }) do fs:SetShadowOffset(0, 0) end
    self.dName:SetTextColor(ink[1], ink[2], ink[3]); self.dBody:SetTextColor(ink[1], ink[2], ink[3]); self.dMeta:SetTextColor(ink[1], ink[2], ink[3])
    self.dLabel:SetTextColor(ink[1], ink[2], ink[3], 0.7); self.dNone:SetTextColor(ink[1], ink[2], ink[3])
    self.dDiv:SetColorTexture(ink[1], ink[2], ink[3], 0.45)
    for key, b in pairs(self.tabButtons) do
        local on = key == self.tab
        b.line:SetColorTexture(a[1], a[2], a[3], on and 1 or 0)
        if on then b.label:SetTextColor(a[1], a[2], a[3]) else b.label:SetTextColor(th.muted[1], th.muted[2], th.muted[3]) end
    end
    return th, fac
end

-- ---------------------------------------------------------------- refresh
function V2:FlipFaction()
    local _, cur = Theme()
    self.themeFaction = (cur == "Alliance") and "Horde" or "Alliance"
    self:Refresh()
end

function V2:SetTab(tab)
    tab = tostring(tab or "log"):lower()
    if tab:find("sim") then tab = "sim" elseif tab:find("set") then tab = "settings" else tab = "log" end
    self.tab = tab
    if self.frame then self:Refresh() end
end

function V2:Refresh()
    if not self.frame or not self.frame:IsShown() then return end
    local th = self:ApplyTheme()
    self.logPage:SetShown(self.tab == "log")
    self.simPage:SetShown(self.tab == "sim")
    self.setPage:SetShown(self.tab == "settings")

    local classFile = GQ:GetEffectiveClass()
    local className = CLASS_NAMES[classFile] or tostring(classFile)
    local spec = GQ.Spec and GQ.Spec.GetDisplaySpec and GQ.Spec:GetDisplaySpec()
    local specLabel
    if GQ.Spec and GQ.Spec.GetOptions then
        for _, o in ipairs(GQ.Spec:GetOptions(classFile) or {}) do if o.id == spec then specLabel = o.label end end
    end
    self.specLabel = specLabel
    local _, themeFac = Theme()
    local pillText = { themeFac, "Level " .. tostring(GQ:GetEffectiveLevel() or 1) }
    for i, p in ipairs(self.pills) do
        p.text:SetText(pillText[i]); p:SetWidth(p.text:GetStringWidth() + 24)
    end
    self.pills[1].text:SetTextColor(th.accent[1], th.accent[2], th.accent[3])
    self.pills[1]:EnableMouse(true)
    self.pills[1]:SetScript("OnMouseUp", function() V2:FlipFaction() end)

    if self.tab == "log" then self:RefreshLog()
    elseif self.tab == "sim" then self:InitSim(); self:RefreshSim()
    else self:RefreshSettings() end
end

function V2:RefreshLog()
    local th = Theme()
    local log = GQ.Log
    local classFile = GQ:GetEffectiveClass()
    local slots = GQ.Data:GetSlotsForClass(classFile) or {}
    if not self.slot then self.slot = slots[1] end
    local listTab = log.GetListTab and log:GetListTab() or "active"
    for key, b in pairs(self.listTabs) do b.primary = key == listTab; self:PaintButton(b) end

    -- slots
    local y = 0
    for i, s in ipairs(slots) do
        local row = self.slotRows[i]
        if not row then
            row = CreateFrame("Button", nil, self.slotChild)
            row:SetHeight(28); Round(row, 8)
            row.text = Text(row, 14); row.text:SetPoint("LEFT", 10, 0)
            row.dot = row:CreateTexture(nil, "OVERLAY"); row.dot:SetTexture(WHITE); row.dot:SetSize(7, 7)
            row.dot:SetPoint("RIGHT", -10, 0); row.dot:SetRotation(math.rad(45))
            row:SetScript("OnClick", function(self2) V2.slot = self2.slotName; V2.selected = nil; V2:Refresh() end)
            row:SetScript("OnEnter", function(self2) self2.hover = true; V2:Refresh() end)
            row:SetScript("OnLeave", function(self2) self2.hover = false; V2:Refresh() end)
            self.slotRows[i] = row
        end
        row.slotName = s
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -y); row:SetPoint("RIGHT", 0, 0)
        row.text:SetText((s:gsub("(%l)(%u)", "%1 %2")))
        local on = s == self.slot
        local c = on and th.sel or th.panel
        row:SetBackdropColor(c[1], c[2], c[3], (on or row.hover) and 1 or 0)
        if row.hover and not on then row:SetBackdropColor(th.card[1], th.card[2], th.card[3], 1) end
        if on then row.text:SetTextColor(th.accent[1], th.accent[2], th.accent[3]) else row.text:SetTextColor(0.9, 0.9, 0.92) end
        local tracked = false
        for _, e in ipairs(log:GetSlotListEntries(s) or {}) do
            local rec = log:CharProgress().hunts[e.id]
            if rec and (rec.status == "tracked" or rec.status == "active") then tracked = true break end
        end
        row.dot:SetColorTexture(th.accent[1], th.accent[2], th.accent[3], tracked and 1 or 0)
        row:Show()
        y = y + 28
    end
    for i = #slots + 1, #self.slotRows do self.slotRows[i]:Hide() end
    self.slotChild:SetHeight(math.max(y, 1))

    -- hunts
    local entries = self.slot and log:GetSlotListEntries(self.slot) or {}
    self.slotTitle:SetText(self.slot and (self.slot:gsub("(%l)(%u)", "%1 %2")) or "")
    self.slotTitle:SetTextColor(th.accent[1], th.accent[2], th.accent[3])
    self.slotSub:SetText(string.format("Best hunts for level %s %s%s", tostring(GQ:GetEffectiveLevel() or 1), CLASS_NAMES[classFile] or "", self.specLabel and (" · " .. self.specLabel) or ""))
    self.emptyText:SetText(#entries == 0 and (listTab == "completed" and "No completed hunts in this slot yet." or "No upgrades found for this slot.") or "")

    local selId = self.selected or (log.selectedEntry and log.selectedEntry.slot and GQ.Data:NormalizeSlotName(log.selectedEntry.slot) == self.slot and log.selectedHuntId)
    local found
    for _, e in ipairs(entries) do if e.id == selId then found = e end end
    if not found then found = entries[1] end
    self.sel = found
    self.selected = found and found.id or nil
    if found then log.selectedHuntId = found.id; log.selectedEntry = found end

    local cy = 0
    for i, e in ipairs(entries) do
        local card = self.huntCards[i]
        if not card then
            card = CreateFrame("Button", nil, self.huntChild)
            card:SetHeight(64); Round(card, 10)
            card.rank = Text(card, 22, TITLE_FONT, "CENTER"); card.rank:SetPoint("LEFT", 6, 0); card.rank:SetWidth(28)
            card.icon = CreateFrame("Frame", nil, card)
            card.icon:SetSize(46, 46); card.icon:SetPoint("LEFT", 38, 0)
            Round(card.icon, 7); card.icon:SetBackdropColor(0, 0, 0, 1)
            card.icon.tex = card.icon:CreateTexture(nil, "ARTWORK")
            card.icon.tex:SetPoint("TOPLEFT", 3, -3); card.icon.tex:SetPoint("BOTTOMRIGHT", -3, 3)
            card.icon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            card.name = Text(card, 15); card.name:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 12, -3); card.name:SetPoint("RIGHT", -12, 0)
            card.name:SetWordWrap(false)
            card.src = Text(card, 12); card.src:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -6); card.src:SetPoint("RIGHT", -86, 0); card.src:SetWordWrap(false)
            card.state = Text(card, 12, BODY_FONT, "RIGHT"); card.state:SetPoint("BOTTOMRIGHT", -12, 12)
            card:SetScript("OnClick", function(s2) V2.selected = s2.entry.id; V2:Refresh() end)
            card:SetScript("OnEnter", function(s2)
                s2.hover = true
                if s2.entry.itemId then GameTooltip:SetOwner(s2, "ANCHOR_LEFT"); GameTooltip:SetHyperlink("item:" .. s2.entry.itemId); GameTooltip:Show() end
                V2:Refresh()
            end)
            card:SetScript("OnLeave", function(s2) s2.hover = false; GameTooltip:Hide(); V2:Refresh() end)
            self.huntCards[i] = card
        end
        card.entry = e
        card:ClearAllPoints(); card:SetPoint("TOPLEFT", 0, -cy); card:SetPoint("RIGHT", -2, 0)
        local on = found and e.id == found.id
        local c = on and th.sel or (card.hover and th.sel or th.card)
        card:SetBackdropColor(c[1], c[2], c[3], 1)
        if on then card:SetBackdropBorderColor(th.accent[1], th.accent[2], th.accent[3], 1) else card:SetBackdropBorderColor(th.border[1], th.border[2], th.border[3], 1) end
        local q = QualityOf(e)
        local notable = GQ.Data:ShouldDisplayAsNotable(e, self.slot)
        card.rank:SetText(notable and "!" or tostring(i))
        card.rank:SetTextColor(th.accent[1], th.accent[2], th.accent[3])
        card.icon.tex:SetTexture(IconFor(e.itemId))
        card.icon:SetBackdropBorderColor(q[1], q[2], q[3], 1)
        card.name:SetText(Strip(GQ.Data:GetEntryDisplayName(e) or ("Item " .. tostring(e.itemId))))
        card.name:SetTextColor(q[1], q[2], q[3])
        local srcLabel = GQ.GetSourceLabel and GQ:GetSourceLabel(e.sourceType) or ""
        card.src:SetText(Strip(srcLabel .. (e.zone and (" · " .. e.zone) or "") .. (notable and " · Notable" or "")))
        card.src:SetTextColor(th.muted[1], th.muted[2], th.muted[3])
        local st = HuntState(e)
        card.state:SetText(st)
        card.state:SetTextColor(th.accent[1], th.accent[2], th.accent[3])
        card:Show()
        cy = cy + 72
    end
    for i = #entries + 1, #self.huntCards do self.huntCards[i]:Hide() end
    self.huntChild:SetHeight(math.max(cy, 1))
    self:RefreshDetail()
end

function V2:RefreshDetail()
    local th = Theme()
    local e = self.sel
    local show = e ~= nil
    for _, w in ipairs({ self.dIcon, self.dLabel, self.dQuality, self.dName, self.dDiv, self.dBodyScroll, self.mapBtn, self.trackBtn }) do w:SetShown(show) end
    self.dNone:SetShown(not show)
    if not show then return end
    local q = QualityOf(e)
    self.dIcon.tex:SetTexture(IconFor(e.itemId))
    self.dIcon:SetBackdropBorderColor(q[1], q[2], q[3], 1)
    self.dLabel:SetText("THE LOG")
    self.dQuality:SetText(q[4] .. " item")
    local qc = (q[4] == "Common" or q[4] == "Poor") and th.parchInk or { q[1] * 0.5, q[2] * 0.5, q[3] * 0.5 }
    self.dQuality:SetTextColor(qc[1], qc[2], qc[3])
    self.detail:SetBackdropBorderColor(th.border[1], th.border[2], th.border[3], 1)
    self.detail.band:SetColorTexture(0, 0, 0, 0)
    self.detail.gem:SetVertexColor(0, 0, 0, 0); self.detail.gemBg:SetVertexColor(0, 0, 0, 0)
    self.dName:SetText(Strip(GQ.Data:GetEntryDisplayName(e) or ("Item " .. tostring(e.itemId))))
    local ok, lines = pcall(GQ.Log.BuildDetailLines, GQ.Log, e)
    local text = ok and table.concat(lines, "\n") or "Details unavailable."
    if GQ.Data.SanitizeText then text = GQ.Data:SanitizeText(text) or text end
    local main, meta = {}, {}
    for line in Strip(text):gmatch("[^\n]+") do
        local k, v = line:match("^(%a+):%s*(.+)$")
        if k and (k == "Zone" or k == "Quest" or k == "NPC" or k == "Source" or k == "Completed") then
            meta[#meta + 1] = { k, v }
        elseif line:find("%d+%.?%d*, %d+%.?%d*") and line:find("%(") then
            meta[#meta + 1] = { "Coords", (line:gsub("^Coords:%s*", "")) }
        else
            main[#main + 1] = line
        end
    end
    local child = self.dBody:GetParent()
    local cw = math.max(self.dBodyScroll:GetWidth() or 0, 270)
    self.dBody:SetWidth(cw)
    self.dBody:SetText(table.concat(main, "\n\n"))
    self.dMeta:SetText("")
    local y = self.dBody:GetStringHeight() + 14
    self.metaRows = self.metaRows or {}
    local ink = th.parchInk
    for i, m in ipairs(meta) do
        local r = self.metaRows[i]
        if not r then
            r = {}
            r.line = child:CreateTexture(nil, "ARTWORK"); r.line:SetTexture(WHITE); r.line:SetHeight(1)
            r.k = Text(child, 13); r.v = Text(child, 13)
            r.k:SetShadowOffset(0, 0); r.v:SetShadowOffset(0, 0)
            self.metaRows[i] = r
        end
        r.line:ClearAllPoints(); r.line:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y); r.line:SetPoint("RIGHT", child, "RIGHT", 0, 0)
        r.line:SetColorTexture(ink[1], ink[2], ink[3], 0.35); r.line:Show()
        r.k:ClearAllPoints(); r.k:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(y + 9)); r.k:SetWidth(62); r.k:SetText(m[1])
        r.k:SetTextColor(0.40, 0.28, 0.14)
        r.v:ClearAllPoints(); r.v:SetPoint("TOPLEFT", child, "TOPLEFT", 68, -(y + 9)); r.v:SetWidth(cw - 68); r.v:SetWordWrap(true)
        r.v:SetText(m[2]); r.v:SetTextColor(ink[1], ink[2], ink[3])
        r.k:Show(); r.v:Show()
        y = y + 9 + math.max(r.v:GetStringHeight(), 14) + 9
    end
    for i = #meta + 1, #self.metaRows do local r = self.metaRows[i]; r.line:Hide(); r.k:Hide(); r.v:Hide() end
    self.dBodyScroll:SetVerticalScroll(0)
    child:SetHeight(y + 8)
    local rec = GQ.Log:CharProgress().hunts[e.id]
    local tracked = rec and (rec.status == "tracked" or rec.status == "active")
    local obtained = GQ.Log:IsEntryObtained(e.id)
    self.trackBtn.label:SetText(tracked and "Stop tracking" or "Track this hunt")
    self.trackBtn:SetShown(not obtained)
    self.trackBtn.primary = false
    self.trackBtn.brown = not tracked
    self.trackBtn.outline = tracked
    self:PaintButton(self.trackBtn)
end

-- ---------------------------------------------------------------- simulator
function V2:InitSim()
    if self.simReady and self.simOpened then return end
    self.simOpened = true
    self.simClass = GQ:GetEffectiveClass()
    self.simFaction = GQ:GetEffectiveFaction() or "Alliance"
    self.simSpec = GQ.Spec and (GQ.Spec.GetDisplaySpec and GQ.Spec:GetDisplaySpec() or GQ.Spec:GetEffectiveSpec())
    self.simLevel:SetText(tostring(GQ:GetEffectiveLevel() or 1))
    self.simReady = true
end

function V2:SimPickClass(cf)
    self.simClass = cf
    self.simSpec = GQ.Spec and (GQ.Spec:GetSavedSpec(cf) or GQ.Spec:GetDefaultSpec(cf))
    self:RefreshSim()
end

function V2:RefreshSim(fromText)
    if not self.simReady then return end
    local th = Theme()
    for cf, b in pairs(self.simClassBtns) do b.primary = cf == self.simClass; self:PaintButton(b) end
    for fac, b in pairs(self.simFacBtns) do b.primary = fac == self.simFaction; self:PaintButton(b) end
    local opts = {}
    if GQ.Spec and GQ.Spec.GetOptions then
        for _, o in ipairs(GQ.Spec:GetOptions(self.simClass) or {}) do
            if GQ.Spec:IsSpecSelectable(o.id, self.simClass) then opts[#opts + 1] = o end
        end
    end
    local valid = false
    for _, o in ipairs(opts) do if o.id == self.simSpec then valid = true end end
    if not valid and opts[1] then self.simSpec = opts[1].id end
    local specLabel = ""
    for i, b in ipairs(self.simSpecBtns) do
        local o = opts[i]
        if o then
            b:Show(); b.label:SetText(o.label); b.specId = o.id; b.primary = o.id == self.simSpec; self:PaintButton(b)
            if o.id == self.simSpec then specLabel = o.label end
        else b:Hide() end
    end
    self.simPreviewTitle:SetText(string.format("Level %s %s %s", self.simLevel:GetText() ~= "" and self.simLevel:GetText() or "?", self.simFaction or "", (CLASS_NAMES[self.simClass] or "") .. (specLabel ~= "" and (", " .. specLabel) or "")))
end

function V2:SimApply()
    local lv = self.simLevel:GetText()
    if lv == "" then print("|cff66ccffGearQuest|r: Enter a level between 1 and " .. (GQ.MAX_PLAYER_LEVEL or 60) .. "."); return end
    local ok, err = GQ.Preview:ApplySimulation(self.simClass, lv, self.simSpec, self.simFaction)
    if not ok then print("|cff66ccffGearQuest|r: " .. tostring(err or "Could not simulate.")); return end
    self.slot = nil; self.selected = nil
    self.themeFaction = nil
    self:SetTab("log")
end

function V2:SimReset()
    self.themeFaction = nil
    GQ.Preview:ApplyCurrentCharacter()
    GQ.Preview:SetEnabled(false)
    self.simOpened = false; self.simReady = false; self.slot = nil; self.selected = nil
    if GQ.RefreshUI then GQ:RefreshUI() end
    self:Refresh()
end

function V2:RefreshSettings()
    local hidden = GQ.Minimap and GQ.Minimap.IsHidden and GQ.Minimap:IsHidden()
    self.minimapToggle.label:SetText(hidden and "On" or "Off")
    self.minimapToggle.primary = hidden and true or false
    self:PaintButton(self.minimapToggle)
end

-- ---------------------------------------------------------------- show / hide / wiring
function V2:Show() self:Build(); self.frame:Show(); self.frame:Raise() end
function V2:Hide() if self.frame then self.frame:Hide() end end
function V2:Toggle() self:Build(); if self.frame:IsShown() then self:Hide() else self:Show() end end
function V2:SetClassic(on) self.classic = on and true or false; if on then self:Hide() end end

local function Wire()
    local Log = GQ.Log
    if not Log or V2.wired then return end
    V2.wired = true
    local oShow, oHide, oToggle, oTab = Log.Show, Log.Hide, Log.Toggle, Log.SetPageTab
    function Log:Show() if V2.classic then return oShow(self) end V2:Show(); V2:Refresh() end
    function Log:Hide() oHide(self); V2:Hide() end
    function Log:Toggle()
        if V2.classic then return oToggle(self) end
        V2:Toggle()
    end
    function Log:SetPageTab(tab, ...)
        if V2.classic then return oTab(self, tab, ...) end
        V2:SetTab(tab)
    end
    hooksecurefunc(Log, "Refresh", function() if not V2.classic then V2:Refresh() end end)

    local oSlash = SlashCmdList and SlashCmdList["GEARQUEST"]
    if oSlash then
        SlashCmdList["GEARQUEST"] = function(msg)
            local m = strtrim(msg or ""):lower()
            if m == "classic" then V2:SetClassic(true); Log:Show()
            elseif m == "new" then if Log.frame then Log.frame:Hide() end V2:SetClassic(false); V2:Show(); V2:Refresh()
            else oSlash(msg) end
        end
    end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function() Wire() end)
