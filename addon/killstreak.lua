-- Killstreaks: chain kills without dying. 11 calls in the Chopper Gunner, 25 drops a Nuke.
-- Purely cosmetic overlays and sound; the combat log is closed to addons here, so kills come
-- from the game's own kill and XP messages.

local _, ns = ...
local T = ns.theme
local C = T.C
local streak = {}
ns.streak = streak

local CHOPPER, NUKE = 11, 25
local count, lastKill = 0, 0
local badge, overlay

local LINES = {
    [CHOPPER] = { "Chopper Gunner inbound. Eleven down, keep it rolling.", "Air support is yours. Eleven without dying, absolute menace." },
    [NUKE] = { "TACTICAL NUKE INCOMING. Twenty-five. Nobody does that.", "Twenty-five kill streak. The zone will remember this." },
}

local function sound(kit)
    if SOUNDKIT and SOUNDKIT[kit] then pcall(PlaySound, SOUNDKIT[kit], "Master") end
end

local function whisper(text)
    DEFAULT_CHAT_FRAME:AddMessage(("|cffd97757wai|r |cff999999whispers:|r %s"):format(text))
end

-- Streak badge: a gold count under the top of the screen that pops on each kill.
local function buildBadge()
    badge = CreateFrame("Frame", nil, UIParent)
    badge:SetSize(120, 70)
    badge:SetPoint("TOP", 0, -90)
    badge:SetFrameStrata("HIGH")
    badge.count = T.label(badge, "display", 34, C.gold)
    badge.count:SetPoint("TOP")
    badge.count:SetJustifyH("CENTER")
    badge.label = T.label(badge, "display", 10, C.goldSoft)
    badge.label:SetPoint("TOP", badge.count, "BOTTOM", 0, -4)
    badge.label:SetJustifyH("CENTER")
    badge.label:SetText("KILLSTREAK")
    badge:Hide()
    local t = 0
    badge:SetScript("OnUpdate", function(self, elapsed)
        t = t + elapsed
        local scale = 1 + 0.25 * math.max(0, 1 - t * 4) -- pop
        self.count:SetScale(scale)
        self:SetAlpha(t < 2.5 and 1 or math.max(0, 1 - (t - 2.5)))
        if t > 3.5 then self:Hide() end
    end)
    badge.restart = function() t = 0 end
end

-- Full-screen overlay used by both rewards.
local function buildOverlay()
    overlay = CreateFrame("Frame", nil, UIParent)
    overlay:SetAllPoints()
    overlay:SetFrameStrata("FULLSCREEN_DIALOG")
    overlay:EnableMouse(false)
    overlay.tint = T.solid(overlay, "BACKGROUND", C.clear)
    overlay.tint:SetAllPoints()
    overlay.vignette = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local v = T.solid(overlay, "BORDER", C.clear)
        v:SetPoint(side)
        if side == "TOP" or side == "BOTTOM" then
            v:SetPoint("LEFT")
            v:SetPoint("RIGHT")
            v:SetHeight(180)
        else
            v:SetPoint("TOP")
            v:SetPoint("BOTTOM")
            v:SetWidth(220)
        end
        v.side = side
        overlay.vignette[#overlay.vignette + 1] = v
    end
    overlay.reticle = overlay:CreateTexture(nil, "ARTWORK")
    overlay.reticle:SetTexture(T.RING)
    overlay.reticle:SetSize(220, 220)
    overlay.reticle:SetPoint("CENTER")
    overlay.cross = {}
    for i = 1, 4 do
        local l = T.solid(overlay, "ARTWORK", C.clear)
        overlay.cross[i] = l
    end
    overlay.cross[1]:SetSize(2, 70); overlay.cross[1]:SetPoint("BOTTOM", overlay.reticle, "TOP", 0, -40)
    overlay.cross[2]:SetSize(2, 70); overlay.cross[2]:SetPoint("TOP", overlay.reticle, "BOTTOM", 0, 40)
    overlay.cross[3]:SetSize(70, 2); overlay.cross[3]:SetPoint("RIGHT", overlay.reticle, "LEFT", 40, 0)
    overlay.cross[4]:SetSize(70, 2); overlay.cross[4]:SetPoint("LEFT", overlay.reticle, "RIGHT", -40, 0)
    overlay.title = T.label(overlay, "display", 30, C.gold, "OVERLAY")
    overlay.title:SetPoint("TOP", 0, -120)
    overlay.title:SetJustifyH("CENTER")
    overlay.sub = T.label(overlay, "display", 13, C.text, "OVERLAY")
    overlay.sub:SetPoint("TOP", overlay.title, "BOTTOM", 0, -8)
    overlay.sub:SetJustifyH("CENTER")
    overlay.big = T.label(overlay, "display", 120, C.red, "OVERLAY")
    overlay.big:SetPoint("CENTER")
    overlay.big:SetJustifyH("CENTER")
    overlay:Hide()
end

local function paintVignette(color, strength)
    for _, v in ipairs(overlay.vignette) do
        local edge, inner = T.alpha(color, strength), T.alpha(color, 0)
        if v.side == "TOP" then T.gradient(v, "VERTICAL", inner, edge)
        elseif v.side == "BOTTOM" then T.gradient(v, "VERTICAL", edge, inner)
        elseif v.side == "LEFT" then T.gradient(v, "HORIZONTAL", edge, inner)
        else T.gradient(v, "HORIZONTAL", inner, edge) end
    end
end

local function tintCross(color)
    overlay.reticle:SetVertexColor(color[1], color[2], color[3], 0.8)
    for _, l in ipairs(overlay.cross) do l:SetVertexColor(color[1], color[2], color[3], 0.8) end
end

-- 11: thermal-green gunner view for 10 seconds.
local function chopperGunner()
    if not overlay then buildOverlay() end
    local green = C.uncommon
    overlay.tint:SetVertexColor(green[1], green[2], green[3], 0.08)
    paintVignette({ 0, 0, 0 }, 0.85)
    tintCross(green)
    overlay.reticle:Show()
    for _, l in ipairs(overlay.cross) do l:Show() end
    overlay.title:SetTextColor(green[1], green[2], green[3])
    overlay.title:SetText("CHOPPER GUNNER")
    overlay.sub:SetText(CHOPPER .. " KILLSTREAK")
    overlay.big:SetText("")
    overlay:Show()
    sound("RAID_WARNING")
    local t = 0
    overlay:SetScript("OnUpdate", function(self, elapsed)
        t = t + elapsed
        overlay.reticle:SetRotation(t * 0.6)
        self:SetAlpha(t < 9 and 1 or math.max(0, 10 - t))
        if t >= 10 then self:Hide() end
    end)
end

-- 25: red alarm, ten-second countdown, white flash.
local function nuke()
    if not overlay then buildOverlay() end
    overlay.reticle:Hide()
    for _, l in ipairs(overlay.cross) do l:Hide() end
    overlay.title:SetTextColor(C.red[1], C.red[2], C.red[3])
    overlay.title:SetText("TACTICAL NUKE INCOMING")
    overlay.sub:SetText(NUKE .. " KILLSTREAK")
    overlay:Show()
    local t, lastSecond = 0, nil
    overlay:SetScript("OnUpdate", function(self, elapsed)
        t = t + elapsed
        self:SetAlpha(1)
        if t < 10 then
            local pulse = 0.35 + 0.35 * math.abs(math.sin(t * 3))
            paintVignette(C.red, pulse)
            overlay.tint:SetVertexColor(C.red[1], C.red[2], C.red[3], 0.05)
            local second = 10 - math.floor(t)
            overlay.big:SetText(tostring(second))
            if second ~= lastSecond then
                lastSecond = second
                sound("RAID_WARNING")
            end
        elseif t < 14 then
            overlay.big:SetText("")
            overlay.title:SetText("")
            overlay.sub:SetText("")
            paintVignette({ 1, 1, 1 }, 0)
            overlay.tint:SetVertexColor(1, 1, 1, math.max(0, 1 - (t - 10) / 4)) -- the flash
        else
            self:Hide()
        end
    end)
    sound("PVP_THROUGH_QUEUE")
end

local function kill(test)
    if WaiCharDB.killstreaksOff and not test then return end
    -- The kill and XP messages often both fire for one kill.
    if not test and GetTime() - lastKill < 1 then return end
    lastKill = GetTime()
    count = count + 1
    if not badge then buildBadge() end
    badge.count:SetText(tostring(count))
    badge.restart()
    badge:Show()
    if count == CHOPPER then chopperGunner()
    elseif count == NUKE then nuke() end
    local lines = LINES[count]
    if lines then whisper(lines[math.random(#lines)]) end
end

function streak.count()
    return count
end

-- Test hooks for the Fun menu.
function streak.addKill()
    kill(true)
end

function streak.reset()
    count = 0
end

function streak.test(which)
    if which == "nuke" then nuke() else chopperGunner() end
end

local events = CreateFrame("Frame")
for _, e in ipairs({ "CHAT_MSG_COMBAT_HOSTILE_DEATH", "CHAT_MSG_COMBAT_XP_GAIN", "PLAYER_DEAD" }) do
    pcall(events.RegisterEvent, events, e)
end
events:SetScript("OnEvent", ns.core.guard(function(_, event, text)
    if event == "PLAYER_DEAD" then
        if count >= 3 then whisper(("Streak ended at %d. Run it back."):format(count)) end
        count = 0
        return
    end
    if not ns.context.usable(text) then return end
    -- "You have slain X!" for your kills; "X dies, you gain N experience." covers kills it misses.
    if event == "CHAT_MSG_COMBAT_HOSTILE_DEATH" and not text:find("^You have slain") then return end
    if event == "CHAT_MSG_COMBAT_XP_GAIN" and not text:find(" dies, you gain ") then return end
    kill()
end))
