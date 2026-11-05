-- Pixel video. WoW only loads image files that existed at launch and caches them, so the bridge
-- sends video as frames of 12-bit colour packed in base64 (two characters per pixel), a few
-- seconds per "wai_vidNNN" load-on-demand slot, and we paint them onto a grid of blocks.
-- TikTok mode docks a looping vertical clip beside the chat with stream chat and captions.

local _, ns = ...
local T = ns.theme
local C = T.C
local video = {}
ns.video = video

local LoadAddOn = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/" -- keep in sync with bridge/src/video.ts
local DEC = {}
for i = 1, #B64 do DEC[B64:byte(i)] = i - 1 end
local BLOCK = 5 -- UI units per video pixel
local STREAM_LINES = 7
local STREAM_COLORS = { "ff6ec7", "7cf4ff", "c3ff6b", "ffd166", "b892ff", "ff9f5a", "6bffb8" }

local player, screen, blocks, lastCode = nil, nil, {}, {}
local current -- { id, title, w, h, fps, base, chunks, loop, frames, loaded, t, paused }
local stream, pendingStream, caption = {}, {}, nil
local requestedAt -- a video was requested and the bridge hasn't answered yet

local function tiktok()
    return WaiCharDB and WaiCharDB.tiktok
end

-- Player chrome --------------------------------------------------------------------------------

local function layoutBlocks(w, h)
    for i = 1, w * h do
        local b = blocks[i]
        if not b then
            b = screen:CreateTexture(nil, "ARTWORK")
            blocks[i] = b
        end
        b:ClearAllPoints()
        b:SetSize(BLOCK, BLOCK)
        b:SetPoint("TOPLEFT", ((i - 1) % w) * BLOCK, -math.floor((i - 1) / w) * BLOCK)
        b:SetColorTexture(0, 0, 0)
        b:Show()
        lastCode[i] = nil
    end
    for i = w * h + 1, #blocks do blocks[i]:Hide() end
    screen:SetSize(w * BLOCK, h * BLOCK)
end

local function place()
    player:ClearAllPoints()
    if tiktok() and WaiFrame and WaiFrame:IsShown() then
        player:SetPoint("TOPLEFT", WaiFrame, "TOPRIGHT", 12, 0)
    elseif WaiDB.videoPos then
        player:SetPoint("CENTER", UIParent, "BOTTOMLEFT", WaiDB.videoPos.x, WaiDB.videoPos.y)
    else
        player:SetPoint("CENTER", 0, 120)
    end
end

local function build()
    player = CreateFrame("Frame", "WaiVideo", UIParent)
    player:SetFrameStrata("HIGH")
    player:SetMovable(true)
    player:SetClampedToScreen(true)
    player:EnableMouse(true)
    player:RegisterForDrag("LeftButton")
    player:SetScript("OnDragStart", function(self) if not tiktok() then self:StartMoving() end end)
    player:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = self:GetCenter()
        WaiDB.videoPos = { x = x, y = y }
    end)
    T.panel(player, 10)

    player.title = T.label(player, "display", 11, C.gold)
    player.title:SetPoint("TOPLEFT", 12, -10)
    player.title:SetPoint("TOPRIGHT", -36, -10)
    player.title:SetWordWrap(false)
    local close = T.button(player, "ghost", nil, { width = 22, height = 22, radius = 11, onClick = function() video.close() end })
    close:SetPoint("TOPRIGHT", -6, -5)
    close.label = T.label(close, "regular", 15, C.goldSoft)
    close.label:SetPoint("CENTER", 0, 1)
    close.label:SetText("×")
    close.Paint(false)

    screen = CreateFrame("Button", nil, player)
    screen:SetPoint("TOP", 0, -30)
    screen:RegisterForClicks("LeftButtonUp")
    screen:SetScript("OnClick", function() if current then current.paused = not current.paused end end)

    player.progress = T.solid(player, "OVERLAY", C.goldSoft)
    player.progress:SetHeight(2)
    player.track = T.solid(player, "ARTWORK", C.line)
    player.track:SetHeight(2)
    player.track:SetPoint("TOPLEFT", screen, "BOTTOMLEFT", 0, -6)
    player.track:SetPoint("TOPRIGHT", screen, "BOTTOMRIGHT", 0, -6)
    player.progress:SetPoint("TOPLEFT", player.track, "TOPLEFT")

    player.status = T.label(screen, "display", 12, C.goldSoft, "OVERLAY")
    player.status:SetPoint("CENTER")
    player.status:SetJustifyH("CENTER")

    -- TikTok overlays: captions over the lower third, stream chat bottom-left.
    player.caption = T.label(screen, "display", 15, C.text, "OVERLAY")
    player.caption:SetPoint("BOTTOMLEFT", 8, 70)
    player.caption:SetPoint("BOTTOMRIGHT", -8, 70)
    player.caption:SetJustifyH("CENTER")
    player.caption:SetJustifyV("BOTTOM")
    player.caption:SetShadowOffset(2, -2)
    player.caption:SetShadowColor(0, 0, 0, 1)
    player.stream = T.label(screen, "regular", 11, C.text, "OVERLAY")
    player.stream:SetPoint("BOTTOMLEFT", 8, 8)
    player.stream:SetPoint("BOTTOMRIGHT", -8, 8)
    player.stream:SetJustifyV("BOTTOM")
    player.stream:SetSpacing(2)
    player.stream:SetShadowOffset(1, -1)
    player.stream:SetShadowColor(0, 0, 0, 1)
    player.live = T.label(player, "display", 10, C.red)
    player.live:SetPoint("TOPRIGHT", -34, -11)
    player.live:SetText("LIVE")

    player:Hide()
end

local function resize(w, h)
    layoutBlocks(w, h)
    player:SetSize(w * BLOCK + 20, h * BLOCK + 46)
    place()
end

-- Frames ----------------------------------------------------------------------------------------

local function loadChunk(n)
    if not current or n > current.chunks or current.loaded[n] then return end
    current.loaded[n] = true
    WaiVideoChunk = nil
    LoadAddOn(("wai_vid%03d"):format(current.base + n - 1))
    local chunk = WaiVideoChunk
    WaiVideoChunk = nil
    if type(chunk) ~= "table" or chunk.id ~= current.id then return end
    current.chunkFrames = current.chunkFrames or #chunk.frames
    for i, f in ipairs(chunk.frames) do current.frames[(n - 1) * current.chunkFrames + i] = f end
    current.total = math.max(current.total or 0, (n - 1) * current.chunkFrames + #chunk.frames)
end

local function draw(s)
    local w, k = current.w, 0
    for row = 0, current.h - 1 do
        local bytes = { s:byte(row * w * 2 + 1, (row + 1) * w * 2) }
        for col = 0, w - 1 do
            k = k + 1
            local code = DEC[bytes[col * 2 + 1]] * 64 + DEC[bytes[col * 2 + 2]]
            if lastCode[k] ~= code then
                lastCode[k] = code
                blocks[k]:SetColorTexture(floor(code / 256) / 15, floor(code / 16) % 16 / 15, code % 16 / 15)
            end
        end
    end
end

local function renderStream()
    local lines = {}
    for i = math.max(1, #stream - STREAM_LINES + 1), #stream do
        local s = stream[i]
        lines[#lines + 1] = ("|cff%s%s|r  %s"):format(s.color, s.name, s.text)
    end
    player.stream:SetText(table.concat(lines, "\n"))
end

local elapsedStream = 0
local function tick(_, elapsed)
    -- Stream chat drips in one line at a time.
    elapsedStream = elapsedStream + elapsed
    if #pendingStream > 0 and elapsedStream > 1.1 then
        elapsedStream = 0
        table.insert(stream, table.remove(pendingStream, 1))
        if #stream > 30 then table.remove(stream, 1) end
        renderStream()
    end
    player.live:SetAlpha(0.5 + 0.5 * math.abs(math.sin(GetTime() * 2)))
    if not current or current.paused or not current.ready then return end
    current.t = current.t + elapsed
    local idx = math.floor(current.t * current.fps) + 1
    local chunkFrames = current.chunkFrames or 24
    local chunk = math.floor((idx - 1) / chunkFrames) + 1
    loadChunk(chunk)
    if (idx - 1) % chunkFrames > chunkFrames / 2 then loadChunk(chunk + 1) end -- prefetch
    if current.total and idx > current.total and chunk > current.chunks then
        if current.loop then
            current.t = 0
            idx = 1
        else
            current.paused = true
            return
        end
    end
    local frame = current.frames[idx]
    if frame and idx ~= current.drawn then
        current.drawn = idx
        draw(frame)
    end
    if current.total then
        local total = current.chunks * chunkFrames
        player.progress:SetWidth(math.max(1, player.track:GetWidth() * math.min(1, idx / total)))
    end
end

-- API ---------------------------------------------------------------------------------------------

-- v: the bridge's video state for this character (from a slot snapshot).
function video.sync(v)
    if type(v) ~= "table" then return end
    if not player then
        build()
        player:SetScript("OnUpdate", ns.core.guard(tick))
    end
    if current and current.id == v.id and current.status == v.status then return end
    requestedAt = nil
    if v.status == "error" then
        if not (current and current.id == v.id) then ns.core.note("|cffff5a5aCouldn't play that video: " .. (v.error or "unknown error") .. "|r") end
        current = { id = v.id, status = "error" }
        return video.close()
    end
    current = {
        id = v.id, status = v.status, title = v.title, w = v.w or 45, h = v.h or 80, fps = v.fps or 8,
        base = v.base, chunks = v.chunks or 0, loop = v.loop, frames = {}, loaded = {}, t = 0,
        ready = v.status == "ready",
    }
    player.title:SetText(v.title or "")
    player.status:SetText(current.ready and "" or "Loading video…")
    player.live:SetShown(tiktok() and true or false)
    resize(current.w, current.h)
    player:Show()
    T.fadeIn(player, 0.2)
end

function video.loading()
    if requestedAt and GetTime() - requestedAt < 30 then return true end
    return current ~= nil and current.status == "loading"
end

-- Asks the bridge for a video directly. kind: "video" (landscape) or "clip" (vertical, loops).
function video.request(kind, query)
    requestedAt = GetTime()
    ns.core.requestVideo(kind, query)
end

function video.close()
    if player then player:Hide() end
    if current then current.paused = true end
end

function video.stream(name, text)
    text = ns.links.plainGlyphs(text)
    table.insert(pendingStream, { name = name, text = text, color = STREAM_COLORS[math.random(#STREAM_COLORS)] })
end

-- Captions follow wai's latest reply while TikTok mode is on.
function video.caption(text)
    if not player or not tiktok() then return end
    text = ns.links.plainGlyphs(text or ""):gsub("%[%[.-%]%]", ""):gsub("%s+", " ")
    -- The last sentence or so, like burned-in captions.
    local tail = text:match("([^%.!%?]+[%.!%?]?)%s*$") or text
    if #tail > 90 then tail = "…" .. tail:sub(-90) end
    if tail ~= caption then
        caption = tail
        player.caption:SetText(strtrim(tail))
    end
end

function video.setTikTok(on)
    WaiCharDB.tiktok = on or nil
    if not player then build(); player:SetScript("OnUpdate", ns.core.guard(tick)) end
    player.live:SetShown(on and true or false)
    player.caption:SetText("")
    player.stream:SetText("")
    stream, pendingStream = {}, {}
    if on then
        if not current then
            current = { id = "pending", status = "loading", w = 45, h = 80, fps = 8, chunks = 0, frames = {}, loaded = {}, t = 0 }
            player.title:SetText("TikTok mode")
            player.status:SetText("Loading clip…")
            resize(45, 80)
        end
        place()
        player:Show()
    elseif current and current.loop then
        video.close()
    end
end

function video.place()
    if player and player:IsShown() then place() end
end
