-- Minimap button: wai's portrait on the minimap ring. Left-click toggles the chat, right-click
-- opens Settings, shift-right-click the Fun menu; drag it around the ring. A small dot shows when
-- wai is working (pulsing blue) or a reply is waiting (gold). Hidden from Settings.

local _, ns = ...
local T = ns.theme
local C = T.C
local minimap = {}
ns.minimap = minimap

local SIZE = 32
local DEFAULT_ANGLE = 215 -- degrees, counter-clockwise from the right; lower left of the ring

local button

local function place()
    local angle = math.rad(WaiDB.minimapAngle or DEFAULT_ANGLE)
    local radius = Minimap:GetWidth() / 2 + 6
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

-- Follows the cursor around the minimap's centre while dragging.
local function drag()
    local mx, my = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    WaiDB.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
    place()
end

local function status()
    local busy, unread = false, false
    for _, tab in ipairs(ns.core.tabs()) do
        busy = busy or tab.busy
        unread = unread or tab.unread
    end
    return busy, unread
end

local function build()
    button = CreateFrame("Button", "WaiMinimapButton", Minimap)
    button:SetSize(SIZE, SIZE)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    local halo = T.dot(button, SIZE + 14, T.alpha(C.goldSoft, 0), "BACKGROUND")
    halo:SetPoint("CENTER")
    local portrait = T.portrait(button, SIZE, T.waiIcon)
    portrait:SetPoint("CENTER")
    portrait:EnableMouse(false)
    local badge = T.dot(portrait, 9, C.rare, "OVERLAY")
    badge:SetPoint("TOPRIGHT", 1, 1)
    badge:Hide()

    button:SetScript("OnClick", ns.core.guard(function(_, mouse)
        if mouse == "RightButton" and IsShiftKeyDown() then return ns.fun.toggle() end
        if mouse == "RightButton" then return ns.settings.toggle() end
        ns.ui.toggle()
    end))
    button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", drag) end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", self.tick) end)
    button:SetScript("OnEnter", function(self)
        halo:SetVertexColor(C.goldSoft[1], C.goldSoft[2], C.goldSoft[3], 0.18)
        portrait.ring:SetVertexColor(C.gold[1], C.gold[2], C.gold[3])
        T.tooltip(self, "wai", "Click to open the chat.", "Right-click for settings, shift-right-click for fun.", "Drag to move around the minimap.")
    end)
    button:SetScript("OnLeave", function()
        halo:SetVertexColor(C.goldSoft[1], C.goldSoft[2], C.goldSoft[3], 0)
        portrait.ring:SetVertexColor(C.goldSoft[1], C.goldSoft[2], C.goldSoft[3])
        GameTooltip:Hide()
    end)

    -- The status dot, refreshed a few times a second.
    local t, since = 0, 0
    button.tick = ns.core.guard(function(_, elapsed)
        t = t + elapsed
        since = since + elapsed
        if since > 0.25 then
            since = 0
            local busy, unread = status()
            badge:SetShown(busy or unread)
            local c = busy and C.rare or C.gold
            badge:SetVertexColor(c[1], c[2], c[3])
            badge.pulse = busy
        end
        badge:SetAlpha(badge.pulse and (0.45 + 0.55 * math.abs(math.sin(t * 2.5))) or 1)
    end)
    button:SetScript("OnUpdate", button.tick)
end

function minimap.refresh()
    if not button then
        if not ns.settings.get("minimap") then return end
        build()
    end
    place()
    button:SetShown(ns.settings.get("minimap") and true or false)
end

-- Settings: a switch in General, on by default.
ns.settings.DEFAULTS.minimap = true
table.insert(ns.settings.SECTIONS[1].items, 1, {
    kind = "toggle", key = "minimap", label = "Minimap button", hint = "wai's portrait on the minimap ring",
    set = function(on)
        ns.settings.set("minimap", on)
        minimap.refresh()
    end,
})

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", ns.core.guard(function() minimap.refresh() end))
