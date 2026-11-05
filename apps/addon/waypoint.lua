-- wai's own waypoint arrow: a gold-ringed badge whose arrowhead points at the target,
-- with the place name and distance underneath. Drag to move, right-click to clear.

local _, ns = ...
local T = ns.theme
local C = T.C
local way = {}
ns.way = way

local ARRIVE_YARDS = 8

local frame, ring, arrow, unknown, title, dist
local current -- { map, x, y, title, zone, continent, wx, wy, arrivedAt }
local maps

local function usable(v) return ns.context.usable(v) end

-- Map names to IDs, preferring zone maps over same-named dungeons or micro maps.
local function mapIndex()
    if maps then return maps end
    maps = {}
    local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
    for id = 1, 3000 do
        local info = C_Map.GetMapInfo(id)
        if info and info.name and info.name ~= "" then
            local key = info.name:lower()
            local cur = maps[key]
            if not cur or (info.mapType == zoneType and cur.type ~= zoneType) then maps[key] = { id = id, type = info.mapType } end
        end
    end
    return maps
end

function way.findMap(name)
    local entry = mapIndex()[strtrim(name or ""):lower()]
    return entry and entry.id
end

local function worldPos(mapID, x, y)
    local ok, continent, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
    if ok and pos then return continent, pos.x, pos.y end
end

local function playerPos()
    local mapID = C_Map.GetBestMapForUnit("player")
    local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return end
    local x, y = pos:GetXY()
    if not (usable(x) and usable(y)) then return end
    return worldPos(mapID, x, y)
end

local function tint(color)
    ring:SetVertexColor(color[1], color[2], color[3])
    arrow:SetVertexColor(color[1], color[2], color[3])
end

local elapsedSince = 0
local function update(_, elapsed)
    elapsedSince = elapsedSince + elapsed
    if elapsedSince < 0.03 or not current then return end
    elapsedSince = 0
    if current.arrivedAt then return end

    local continent, px, py = playerPos()
    if not px or continent ~= current.continent then
        arrow:Hide()
        unknown:Show()
        dist:SetText(px and "On another continent" or "Location unavailable")
        return
    end
    local dx, dy = current.wx - px, current.wy - py
    local d = math.sqrt(dx * dx + dy * dy)
    if d <= ARRIVE_YARDS then
        current.arrivedAt = GetTime()
        tint(C.uncommon)
        arrow:Hide()
        unknown:Hide()
        dist:SetText("You have arrived")
        local arrived = current
        C_Timer.After(3, function() if current == arrived then way.clear() end end)
        return
    end
    -- World X points north and Y points west; facing is radians counter-clockwise from north.
    local facing = GetPlayerFacing()
    if usable(facing) then
        arrow:SetRotation(math.atan2(dy, dx) - facing)
        arrow:Show()
        unknown:Hide()
    else
        arrow:Hide()
        unknown:Show()
    end
    dist:SetText(("%d yards"):format(d))
end

local function build()
    frame = CreateFrame("Button", "WaiWaypoint", UIParent)
    frame:SetSize(170, 104)
    local pos = WaiDB.wayPos
    if pos then frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", pos.x, pos.y) else frame:SetPoint("TOP", 0, -140) end
    frame:SetFrameStrata("MEDIUM")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:RegisterForClicks("RightButtonUp")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = self:GetCenter()
        WaiDB.wayPos = { x = x, y = y }
    end)
    frame:SetScript("OnClick", function(_, button) if button == "RightButton" then way.clear() end end)
    frame:SetScript("OnEnter", function(self)
        if not current then return end
        T.tooltip(self, current.title, ("%s  %.1f, %.1f"):format(current.zone or "", current.x * 100, current.y * 100),
            "Drag to move. Right-click to clear.")
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local badge = CreateFrame("Frame", nil, frame)
    badge:SetSize(58, 58)
    badge:SetPoint("TOP")
    local halo = T.dot(badge, 96, T.alpha(C.goldSoft, 0.07), "BACKGROUND")
    halo:SetPoint("CENTER")
    local disc = T.dot(badge, 58, T.alpha(C.bg, 0.92), "BORDER")
    disc:SetPoint("CENTER")
    ring = badge:CreateTexture(nil, "OVERLAY")
    ring:SetTexture(T.RING)
    ring:SetAllPoints()
    arrow = badge:CreateTexture(nil, "ARTWORK")
    arrow:SetTexture(T.NAV)
    arrow:SetSize(30, 30)
    arrow:SetPoint("CENTER")
    unknown = T.label(badge, "display", 18, C.goldSoft)
    unknown:SetPoint("CENTER", 0, 1)
    unknown:SetText("?")
    unknown:Hide()

    title = T.label(frame, "display", 12, C.gold)
    title:SetPoint("TOP", badge, "BOTTOM", 0, -8)
    title:SetJustifyH("CENTER")
    title:SetWidth(170)
    title:SetWordWrap(false)
    dist = T.label(frame, "regular", 11, C.muted)
    dist:SetPoint("TOP", title, "BOTTOM", 0, -3)
    dist:SetJustifyH("CENTER")

    frame:Hide()
    frame:SetScript("OnUpdate", ns.core.guard(update))
end

-- x, y in 0..1 map coordinates.
function way.set(mapID, x, y, label)
    local continent, wx, wy = worldPos(mapID, x, y)
    if not wx then return false, "That spot isn't on a map I can track." end
    if not frame then build() end
    local info = C_Map.GetMapInfo(mapID)
    local zone = info and info.name
    current = { map = mapID, x = x, y = y, title = label or zone or "Waypoint", zone = zone, continent = continent, wx = wx, wy = wy }
    WaiCharDB.way = { map = mapID, x = x, y = y, title = current.title }
    tint(C.goldSoft)
    title:SetText(current.title)
    dist:SetText("")
    frame:Show()
    T.fadeIn(frame, 0.2)
    return true
end

-- x, y as map percentages (0..100); zone may be empty for your current map.
function way.setByZone(zone, x, y, label)
    local mapID = (zone and zone ~= "") and way.findMap(zone) or C_Map.GetBestMapForUnit("player")
    if not mapID then return false, ("I don't know a zone called %s."):format(zone) end
    return way.set(mapID, x / 100, y / 100, label)
end

function way.clear()
    current = nil
    WaiCharDB.way = nil
    if frame then frame:Hide() end
end

function way.restore()
    local saved = WaiCharDB.way
    if saved then way.set(saved.map, saved.x, saved.y, saved.title) end
end
