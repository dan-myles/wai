-- Settings (/settings, or the gear in the header): a panel docked to the chat window, with tabs
-- (General, Fun, About) of grouped preferences. Values live in WaiDB.settings (account-wide)
-- unless an item says otherwise. Add a setting by adding an item to TABS; anything else reads it
-- with ns.settings.get(key).

local _, ns = ...
local T = ns.theme
local C = T.C
local settings = {}
ns.settings = settings

local WIDTH = 340
local DEFAULTS = {
    typing = "normal", -- "instant" | "fast" | "normal"
    whisper = true, -- finished replies also go to chat while the window is closed
}

function settings.get(key)
    local saved = WaiDB.settings and WaiDB.settings[key]
    if saved == nil then return DEFAULTS[key] end
    return saved
end

function settings.set(key, value)
    WaiDB.settings = WaiDB.settings or {}
    WaiDB.settings[key] = value
end

-- Where each movable wai frame goes after "Reset window positions".
local HOMES = {
    WaiFrame = { "CENTER", 0, 0 },
    WaiVideo = { "CENTER", 0, 120 },
    WaiWaypoint = { "TOP", 0, -140 },
}

local function resetPositions()
    WaiDB.ui, WaiDB.videoPos, WaiDB.wayPos = nil, nil, nil
    for name, home in pairs(HOMES) do
        local f = _G[name]
        if f then
            f:ClearAllPoints()
            f:SetPoint(home[1], UIParent, home[1], home[2], home[3])
        end
    end
    if WaiFrame then WaiFrame:SetSize(420, 560) end
end

local function version()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    return get and get("wai", "Version") or "?"
end

-- Key binding ------------------------------------------------------------------------------------

local BINDING = "WAI_TOGGLE" -- declared in Bindings.xml; also under Key Bindings > AddOns
local MODIFIERS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true, LMETA = true, RMETA = true }

-- "CTRL-SHIFT-W" -> "Ctrl-Shift-W"; named keys ("NUMPAD1") use the client's own label.
local function keyText(key)
    if not key then return "Not set" end
    local mods, base = key:match("^(.-)([^-]+)$")
    local ok, label = pcall(GetBindingText, base)
    if not (ok and label and label ~= "") then label = base end
    return mods:gsub("CTRL%-", "Ctrl-"):gsub("ALT%-", "Alt-"):gsub("SHIFT%-", "Shift-"):gsub("META%-", "Cmd-") .. label
end

-- A key press as a binding string, in WoW's order (ALT-CTRL-SHIFT-KEY); nil for a modifier alone.
function settings.combo(key)
    if MODIFIERS[key] then return nil end
    return (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "") .. (IsShiftKeyDown() and "SHIFT-" or "") .. key
end

-- Whether a key press is wai's toggle key.
function settings.isToggleKey(key)
    local combo = settings.combo(key)
    for _, bound in ipairs({ GetBindingKey(BINDING) }) do
        if combo == bound then return true end
    end
    return false
end

-- Binds `key` (nil clears) to toggling wai in place of wai's old keys. Returns what that key did
-- before, or an error. Bindings are locked in combat.
local function bind(key)
    if InCombatLockdown() then return nil, "Key bindings can't change in combat." end
    for _, old in ipairs({ GetBindingKey(BINDING) }) do SetBinding(old) end
    local replaced
    if key then
        local action = GetBindingAction(key)
        if action and action ~= "" and action ~= BINDING then replaced = _G["BINDING_NAME_" .. action] or action end
        SetBinding(key, BINDING)
    end
    SaveBindings(GetCurrentBindingSet())
    return replaced
end

-- Label and hint on the left, the current key on the right. Click, then press a key (with any
-- modifiers); Esc cancels and right-click clears.
local function keybindRow(parent, item)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(40)
    local button = T.button(row, "outline", "Not set", { width = 112, height = 26, radius = 6, size = 11 })
    button:SetPoint("RIGHT", 0, 2)
    -- Label and hint stop short of the button instead of running under it.
    local label = T.label(row, "regular", 13, C.text)
    label:SetPoint("TOPLEFT", 0, -3)
    label:SetPoint("RIGHT", button, "LEFT", -10, 0)
    label:SetWordWrap(false)
    label:SetText(item.label)
    local hint = T.label(row, "regular", 11, C.muted)
    hint:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
    hint:SetPoint("RIGHT", button, "LEFT", -10, 0)
    hint:SetWordWrap(false)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local capturing, message

    function row:Refresh()
        if capturing then return end
        button.label:SetText(keyText((GetBindingKey(BINDING))))
        hint:SetText(message or item.hint)
    end
    local function stop()
        capturing = false
        button:EnableKeyboard(false)
        row:Refresh()
    end
    local function finish(key)
        local replaced, err = bind(key)
        message = err or (replaced and ("Replaced " .. replaced)) or nil
        stop()
    end

    button:SetScript("OnClick", ns.core.guard(function(_, mouse)
        if mouse == "RightButton" then return finish(nil) end
        capturing, message = true, nil
        button.label:SetText("Press a key…")
        hint:SetText("Esc cancels · right-click clears")
        button:EnableKeyboard(true)
        -- Keep the key away from the game while choosing (otherwise W would also walk forward).
        if button.SetPropagateKeyboardInput then button:SetPropagateKeyboardInput(false) end
    end))
    button:SetScript("OnKeyDown", ns.core.guard(function(_, key)
        if not capturing or MODIFIERS[key] then return end
        if key == "ESCAPE" then return stop() end
        finish(settings.combo(key))
    end))
    button:SetScript("OnHide", function() if capturing then stop() end end)
    -- Setting OnKeyDown turns keyboard input on, which would swallow every key (movement, wai's own
    -- key) while settings are open. Only listen while choosing a key.
    button:EnableKeyboard(false)
    return row
end

-- The Fun tab: cosmetic extras and buttons to try them on demand.
local CLIP = "subway surfers gameplay"
local FAKE_CHAT = {
    { "xX_GankLord_Xx", "W streamer" }, { "moonglade_mommy", "chat is this real" },
    { "feral_frank", "LMAO the pet" }, { "auberdine_andy", "first" },
    { "tauren_tim", "drop the gold route" }, { "gnomer_gwen", "no way he pulled that" },
}

local TABS = {
    {
        id = "general", label = "General",
        sections = {
            {
                title = "GENERAL",
                items = {
                    {
                        kind = "segmented", label = "Agent", hint = "Who answers; chats carry over",
                        options = { { "claude", "Claude" }, { "codex", "Codex" } },
                        get = function() return ns.core.agent() end,
                        set = function(name) ns.core.setAgent(name) end,
                    },
                    { kind = "keybind", label = "Toggle wai", hint = "Opens and closes the chat" },
                    {
                        kind = "segmented", key = "typing", label = "Typing speed", hint = "How replies appear",
                        options = { { "instant", "Instant" }, { "fast", "Fast" }, { "normal", "Normal" } },
                    },
                    { kind = "toggle", key = "whisper", label = "Whisper replies", hint = "Also post replies in chat while wai is closed" },
                },
            },
            {
                title = "WINDOWS",
                items = {
                    { kind = "button", label = "Reset window positions", run = resetPositions },
                },
            },
        },
    },
    {
        id = "fun", label = "Fun",
        sections = {
            {
                title = "FUN",
                items = {
                    {
                        kind = "toggle", label = "TikTok mode", hint = "Looping clip, captions and stream chat",
                        get = function() return WaiCharDB.tiktok end,
                        set = function(on)
                            ns.video.setTikTok(on)
                            if on then ns.video.request("clip", CLIP) end
                        end,
                    },
                    {
                        kind = "toggle", label = "Killstreaks", hint = "Chopper Gunner at 11, Nuke at 25 (this character)",
                        get = function() return not WaiCharDB.killstreaksOff end,
                        set = function(on) WaiCharDB.killstreaksOff = (not on) or nil end,
                    },
                    { kind = "grid", label = "Try it", buttons = {
                        { "Chopper Gunner", function() ns.streak.test("chopper") end },
                        { "Nuke", function() ns.streak.test("nuke") end },
                        { "+1 kill", function() ns.streak.addKill() end },
                        { "Reset streak", function() ns.streak.reset() end },
                        { "Play a video", function() ns.video.request("video", CLIP) end },
                        { "Stream chat", function()
                            for _, line in ipairs(FAKE_CHAT) do ns.video.stream(line[1], line[2]) end
                        end },
                    } },
                },
            },
        },
    },
    {
        id = "about", label = "About",
        sections = {
            {
                title = "PRIVACY",
                items = {
                    {
                        kind = "toggle", key = "telemetry", label = "Error reports", hint = "Anonymous; never your chats or names",
                        get = function() return settings.get("telemetry") == true end,
                    },
                    { kind = "button", label = "See what's sent", run = function() settings.showTelemetry() end },
                },
            },
            {
                title = "ABOUT",
                items = {
                    {
                        kind = "segmented", label = "Updates", hint = "Nightly gets new features first",
                        options = { { "stable", "Stable" }, { "nightly", "Nightly" } },
                        get = function() return ns.core.track() end,
                        set = function(name) ns.core.setTrack(name) end,
                    },
                    { kind = "about" },
                    { kind = "buttons", buttons = {
                        { "Check for updates", function() ns.core.requestUpdate() end },
                        { "Help", function() ns.commands.run("/help") end },
                    } },
                },
            },
        },
    },
}

local panel, rows, about = nil, {}, nil
local current = "general" -- the open tab, kept for the session

local function paintTab(tab, hovered)
    local b, active = tab.button, tab.id == current
    local color = active and C.gold or (hovered and C.text or C.muted)
    b.label:SetTextColor(color[1], color[2], color[3])
    b.bg:SetFill(active and T.alpha(C.gold, 0.07) or (hovered and T.alpha(C.gold, 0.04) or C.clear))
    b.underline:SetShown(active)
end

local function choose(id)
    current = id
    for _, tab in ipairs(TABS) do
        tab.page:SetShown(tab.id == id)
        paintTab(tab, false)
    end
end

-- The panel sits beside the chat window, on the right if the screen has room, otherwise the left.
-- Anchored, not positioned, so dragging the chat window carries it along.
local function dock()
    local right = (WaiFrame:GetRight() or 0) + 12 + WIDTH <= (UIParent:GetRight() or math.huge)
    panel:ClearAllPoints()
    if right then
        panel:SetPoint("TOPLEFT", WaiFrame, "TOPRIGHT", 12, 0)
    else
        panel:SetPoint("TOPRIGHT", WaiFrame, "TOPLEFT", -12, 0)
    end
end

local function section(parent, text, y)
    local label = T.label(parent, "display", 10, C.goldDim)
    label:SetPoint("TOPLEFT", 16, y)
    label:SetText(text)
    local line = T.fadedLine(parent, C.goldDim)
    line:SetPoint("LEFT", label, "RIGHT", 10, 0)
    line:SetPoint("RIGHT", parent, "RIGHT", -16, 0)
    return y - 22
end

local function accessors(item)
    return item.get or function() return settings.get(item.key) end,
        item.set or function(value) settings.set(item.key, value) end
end

local function refreshAbout()
    local seen = ns.core.lastContact()
    -- The addon only polls while it waits for a reply, so no contact yet just means no messages yet.
    local bridge = seen and (seen < 90 and "in touch" or ("last heard %dm ago"):format(seen / 60)) or "no messages yet this session"
    about:SetText("wai " .. version())
    about.status:SetText("Bridge: " .. bridge)
end

local function build()
    panel = CreateFrame("Frame", "WaiSettings", UIParent)
    panel:SetWidth(WIDTH)
    panel:SetFrameStrata("DIALOG")
    panel:SetToplevel(true)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    tinsert(UISpecialFrames, "WaiSettings")
    T.panel(panel, 10)

    local avatar = T.portrait(panel, 30, T.waiIcon)
    avatar:SetPoint("TOPLEFT", 14, -14)
    local title = T.label(panel, "display", 15, C.gold)
    title:SetPoint("TOPLEFT", avatar, "TOPRIGHT", 10, -1)
    title:SetText("Settings")
    local sub = T.label(panel, "regular", 11, C.muted)
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    sub:SetText("Make wai yours")
    local close = T.button(panel, "ghost", nil, { width = 24, height = 24, radius = 12, onClick = function() panel:Hide() end })
    close:SetPoint("TOPRIGHT", -10, -12)
    close.label = T.label(close, "regular", 16, C.goldSoft)
    close.label:SetPoint("CENTER", 0, 1)
    close.label:SetText("×")
    close.Paint(false)

    -- Tabs under the header, in the chat window's style: gold text, a soft wash and an underline
    -- on the active one.
    local strip = CreateFrame("Frame", nil, panel)
    strip:SetPoint("TOPLEFT", 12, -56)
    strip:SetPoint("TOPRIGHT", -12, -56)
    strip:SetHeight(28)
    local rule = T.solid(strip, "BORDER", T.alpha(C.goldSoft, 0.35))
    rule:SetHeight(1)
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    local x = 0
    for _, tab in ipairs(TABS) do
        local b = CreateFrame("Button", nil, strip)
        b:SetHeight(26)
        b:SetPoint("BOTTOMLEFT", x, 1)
        b.bg = T.box(b, 6, C.clear)
        b.label = T.label(b, "display", 12, C.muted)
        b.label:SetPoint("CENTER", 0, 1)
        b.label:SetText(tab.label)
        b:SetWidth(math.ceil(b.label:GetStringWidth()) + 24)
        b.underline = T.solid(b, "OVERLAY", C.goldSoft)
        b.underline:SetHeight(2)
        b.underline:SetPoint("BOTTOMLEFT", 8, 0)
        b.underline:SetPoint("BOTTOMRIGHT", -8, 0)
        b:SetScript("OnClick", ns.core.guard(function() choose(tab.id) end))
        b:SetScript("OnEnter", function() paintTab(tab, true) end)
        b:SetScript("OnLeave", function() paintTab(tab, false) end)
        tab.button = b
        x = x + b:GetWidth() + 4
    end

    -- One page per tab. The panel keeps the tallest page's height so switching never jumps.
    local tallest = 0
    for _, tab in ipairs(TABS) do
        local page = CreateFrame("Frame", nil, panel)
        page:SetPoint("TOPLEFT", 0, -96)
        page:SetPoint("TOPRIGHT", 0, -96)
        local y = 0
        for _, sec in ipairs(tab.sections) do
            y = section(page, sec.title, y)
            for _, item in ipairs(sec.items) do
                local row
                if item.kind == "toggle" or item.kind == "segmented" then
                    local get, set = accessors(item)
                    local make = item.kind == "toggle" and T.toggle or T.segmented
                    row = make(page, { label = item.label, hint = item.hint, options = item.options, get = get, set = set })
                    rows[#rows + 1] = row
                elseif item.kind == "keybind" then
                    row = keybindRow(page, item)
                    rows[#rows + 1] = row
                elseif item.kind == "button" then
                    row = T.button(page, "outline", item.label, { height = 30, radius = 8, size = 12, onClick = item.run })
                    row:SetPoint("TOPLEFT", 16, y)
                    row:SetPoint("TOPRIGHT", -16, y)
                elseif item.kind == "buttons" then
                    row = CreateFrame("Frame", nil, page)
                    row:SetHeight(30)
                    local w = (WIDTH - 32 - 8) / #item.buttons
                    for i, b in ipairs(item.buttons) do
                        local btn = T.button(row, "outline", b[1], { width = w, height = 30, radius = 8, size = 12, onClick = b[2] })
                        btn:SetPoint("LEFT", (i - 1) * (w + 8), 0)
                    end
                elseif item.kind == "grid" then
                    -- A small label over three columns of compact buttons.
                    row = CreateFrame("Frame", nil, page)
                    local label = T.label(row, "regular", 11, C.muted)
                    label:SetPoint("TOPLEFT")
                    label:SetText(item.label)
                    local w = (WIDTH - 32 - 12) / 3
                    for i, b in ipairs(item.buttons) do
                        local btn = T.button(row, "outline", b[1], { width = w, height = 26, radius = 6, size = 11, onClick = b[2] })
                        btn:SetPoint("TOPLEFT", ((i - 1) % 3) * (w + 6), -20 - math.floor((i - 1) / 3) * 32)
                    end
                    row:SetHeight(20 + math.ceil(#item.buttons / 3) * 32 - 6)
                elseif item.kind == "about" then
                    -- Version and bridge status on lines of their own: a nightly version is long.
                    row = CreateFrame("Frame", nil, page)
                    row:SetHeight(34)
                    about = T.label(row, "regular", 12, C.gold)
                    about:SetPoint("TOPLEFT")
                    about:SetPoint("TOPRIGHT")
                    about:SetWordWrap(false)
                    row.status = T.label(row, "regular", 11, C.muted)
                    row.status:SetPoint("TOPLEFT", about, "BOTTOMLEFT", 0, -4)
                    row.status:SetPoint("RIGHT")
                    row.status:SetWordWrap(false)
                    about.status = row.status
                end
                row:SetPoint("TOPLEFT", 16, y)
                row:SetPoint("TOPRIGHT", -16, y)
                y = y - row:GetHeight() - 10
            end
            y = y - 6
        end
        page:SetHeight(-y)
        tallest = math.max(tallest, -y)
        tab.page = page
    end
    panel:SetHeight(96 + tallest + 4)
    choose(current)

    -- Docked to the chat window: it moves with it, closes with it, and comes back with it if it was
    -- open (for this session).
    hooksecurefunc(WaiFrame, "StopMovingOrSizing", function()
        if panel:IsShown() then dock() end
    end)
    local reopen = false
    WaiFrame:HookScript("OnHide", function()
        reopen = panel:IsShown()
        panel:Hide()
    end)
    WaiFrame:HookScript("OnShow", function()
        if not reopen then return end
        reopen = false
        dock()
        for _, row in ipairs(rows) do row:Refresh() end
        refreshAbout()
        panel:Show()
    end)
    local t = 0
    panel:SetScript("OnUpdate", function(_, elapsed)
        t = t + elapsed
        if t > 1 then
            t = 0
            -- Some values come from the bridge (the agent), so they can change while the panel is open.
            for _, row in ipairs(rows) do row:Refresh() end
            refreshAbout()
        end
    end)
    panel:Hide()
end

function settings.tab()
    return current
end

-- tab: open on that tab ("general", "fun", "about"). Asking for another tab while open switches
-- to it instead of closing.
function settings.toggle(tab)
    if not panel then build() end
    if panel:IsShown() and (not tab or tab == current) then return panel:Hide() end
    if tab then choose(tab) end
    if panel:IsShown() then return end
    if not WaiFrame:IsShown() then ns.ui.show() end -- it belongs to the chat window
    dock()
    for _, row in ipairs(rows) do row:Refresh() end
    refreshAbout()
    panel:Show()
    T.fadeIn(panel, 0.12)
end

-- A note in the chat explaining exactly what error reports contain, and what's queued now.
function settings.showTelemetry()
    local on = settings.get("telemetry") == true
    local lines = {
        "|cffffd100Error reports|r  " .. (on and "on" or "off"),
        "|cff9298a3Each report holds an event type (lua_error, stalled, claude_error, codex_error, ...), a short detail with your character name and realm removed, the wai version, OS, client build and a random install id. Never your chats, quests or names. Off unless you turn it on. In a terminal, `wai telemetry show` lists everything queued and sent.|r",
    }
    local pending = ns.core.pendingReports()
    lines[#lines + 1] = ("|cffffd100Waiting to send|r  %d"):format(#pending)
    for _, r in ipairs(pending) do lines[#lines + 1] = "|cff9298a3" .. r:gsub("\t", ": ") .. "|r" end
    ns.core.note(table.concat(lines, "\n"))
end

-- For later releases: add a section or an item (and its default) without touching the panel code.
settings.TABS = TABS
settings.DEFAULTS = DEFAULTS
