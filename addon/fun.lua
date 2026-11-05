-- The Fun menu (/fun): toggles for the silly stuff and buttons to test it on demand.

local _, ns = ...
local T = ns.theme
local C = T.C
local fun = {}
ns.fun = fun

local WIDTH = 300
local CLIP = "subway surfers gameplay"
local menu, toggles = nil, {}

local FAKE_CHAT = {
    { "xX_GankLord_Xx", "W streamer" }, { "moonglade_mommy", "chat is this real" },
    { "feral_frank", "LMAO the pet" }, { "auberdine_andy", "first" },
    { "tauren_tim", "drop the gold route" }, { "gnomer_gwen", "no way he pulled that" },
}

local function section(parent, text, y)
    local label = T.label(parent, "display", 10, C.goldDim)
    label:SetPoint("TOPLEFT", 16, y)
    label:SetText(text)
    local line = T.fadedLine(parent, C.goldDim)
    line:SetPoint("LEFT", label, "RIGHT", 10, 0)
    line:SetPoint("RIGHT", parent, "RIGHT", -16, 0)
    return y - 22
end

local function build()
    menu = CreateFrame("Frame", "WaiFunMenu", UIParent)
    menu:SetWidth(WIDTH)
    menu:SetFrameStrata("DIALOG")
    menu:SetToplevel(true)
    menu:SetClampedToScreen(true)
    menu:SetMovable(true)
    menu:EnableMouse(true)
    menu:RegisterForDrag("LeftButton")
    menu:SetScript("OnDragStart", menu.StartMoving)
    menu:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        WaiDB.funPos = { x = self:GetLeft(), y = self:GetTop() }
    end)
    tinsert(UISpecialFrames, "WaiFunMenu")
    T.panel(menu, 10)

    local avatar = T.portrait(menu, 30, T.waiIcon)
    avatar:SetPoint("TOPLEFT", 14, -14)
    local title = T.label(menu, "display", 15, C.gold)
    title:SetPoint("TOPLEFT", avatar, "TOPRIGHT", 10, -1)
    title:SetText("Fun")
    local sub = T.label(menu, "regular", 11, C.muted)
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    sub:SetText("Toggles and test buttons")
    local close = T.button(menu, "ghost", nil, { width = 24, height = 24, radius = 12, onClick = function() menu:Hide() end })
    close:SetPoint("TOPRIGHT", -10, -12)
    close.label = T.label(close, "regular", 16, C.goldSoft)
    close.label:SetPoint("CENTER", 0, 1)
    close.label:SetText("×")
    close.Paint(false)

    local y = section(menu, "TOGGLES", -62)
    local defs = {
        {
            label = "TikTok mode", hint = "Looping clip, captions and stream chat",
            get = function() return WaiCharDB.tiktok end,
            set = function(on)
                ns.video.setTikTok(on)
                if on then ns.video.request("clip", CLIP) end
            end,
        },
        {
            label = "Killstreaks", hint = "Chopper Gunner at 11, Nuke at 25",
            get = function() return not WaiCharDB.killstreaksOff end,
            set = function(on) WaiCharDB.killstreaksOff = (not on) or nil end,
        },
    }
    for _, def in ipairs(defs) do
        local row = T.toggle(menu, def)
        row:SetPoint("TOPLEFT", 16, y)
        row:SetPoint("TOPRIGHT", -16, y)
        toggles[#toggles + 1] = row
        y = y - row:GetHeight() - 10
    end

    y = section(menu, "TEST", y - 6)
    local tests = {
        { "Chopper Gunner", function() ns.streak.test("chopper") end },
        { "Nuke", function() ns.streak.test("nuke") end },
        { "+1 kill", function() ns.streak.addKill() end },
        { "Reset streak", function() ns.streak.reset() end },
        { "Play a video", function() ns.video.request("video", CLIP) end },
        { "Stream chat", function()
            for _, line in ipairs(FAKE_CHAT) do ns.video.stream(line[1], line[2]) end
        end },
    }
    local colW = (WIDTH - 32 - 8) / 2
    for i, t in ipairs(tests) do
        local b = T.button(menu, "outline", t[1], { width = colW, height = 30, radius = 8, size = 12, onClick = t[2] })
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        b:SetPoint("TOPLEFT", 16 + col * (colW + 8), y - row * 38)
    end
    y = y - math.ceil(#tests / 2) * 38 - 8
    menu:SetHeight(-y + 6)

    local pos = WaiDB.funPos
    if pos then
        menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
    elseif WaiFrame and WaiFrame:IsShown() then
        menu:SetPoint("TOPRIGHT", WaiFrame, "TOPLEFT", -12, 0)
    else
        menu:SetPoint("CENTER", -240, 0)
    end
    menu:Hide()
end

function fun.toggle()
    if not menu then build() end
    if menu:IsShown() then return menu:Hide() end
    for _, row in ipairs(toggles) do row:Refresh() end
    menu:Show()
    T.fadeIn(menu, 0.12)
end
