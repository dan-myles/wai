-- Settings (/settings, or the gear in the header): a floating panel of grouped preferences.
-- Values live in WaiDB.settings (account-wide) unless an item says otherwise. Add a setting by
-- adding an item to SECTIONS; anything else reads it with ns.settings.get(key).

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
    WaiFunMenu = { "CENTER", -240, 0 },
    WaiVideo = { "CENTER", 0, 120 },
    WaiWaypoint = { "TOP", 0, -140 },
}

local function resetPositions()
    WaiDB.ui, WaiDB.funPos, WaiDB.settingsPos, WaiDB.videoPos, WaiDB.wayPos = nil, nil, nil, nil, nil
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
        -- WoW's own order: ALT-CTRL-SHIFT-KEY.
        finish((IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "") .. (IsShiftKeyDown() and "SHIFT-" or "") .. key)
    end))
    button:SetScript("OnHide", function() if capturing then stop() end end)
    return row
end

local SECTIONS = {
    {
        title = "GENERAL",
        items = {
            {
                kind = "segmented", label = "Agent", hint = "Who answers; chats carry over",
                options = { { "claude", "Claude" }, { "codex", "Codex" } },
                get = function() return ns.core.agent() end,
                set = function(name) ns.core.setAgent(name) end,
            },
            { kind = "keybind", label = "Open wai", hint = "Opens and closes the chat" },
            {
                kind = "segmented", key = "typing", label = "Typing speed", hint = "How replies appear",
                options = { { "instant", "Instant" }, { "fast", "Fast" }, { "normal", "Normal" } },
            },
            { kind = "toggle", key = "whisper", label = "Whisper replies", hint = "Also post replies in chat while wai is closed" },
            {
                kind = "toggle", label = "Killstreaks", hint = "Chopper Gunner at 11, Nuke at 25 (this character)",
                get = function() return not WaiCharDB.killstreaksOff end,
                set = function(on) WaiCharDB.killstreaksOff = (not on) or nil end,
            },
        },
    },
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
        title = "WINDOWS",
        items = {
            { kind = "button", label = "Reset window positions", run = resetPositions },
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
}

local panel, rows, about = nil, {}, nil

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

    local y = -62
    for _, sec in ipairs(SECTIONS) do
        y = section(panel, sec.title, y)
        for _, item in ipairs(sec.items) do
            local row
            if item.kind == "toggle" or item.kind == "segmented" then
                local get, set = accessors(item)
                local make = item.kind == "toggle" and T.toggle or T.segmented
                row = make(panel, { label = item.label, hint = item.hint, options = item.options, get = get, set = set })
                rows[#rows + 1] = row
            elseif item.kind == "keybind" then
                row = keybindRow(panel, item)
                rows[#rows + 1] = row
            elseif item.kind == "button" then
                row = T.button(panel, "outline", item.label, { height = 30, radius = 8, size = 12, onClick = item.run })
                row:SetPoint("TOPLEFT", 16, y)
                row:SetPoint("TOPRIGHT", -16, y)
            elseif item.kind == "buttons" then
                row = CreateFrame("Frame", nil, panel)
                row:SetHeight(30)
                local w = (WIDTH - 32 - 8) / #item.buttons
                for i, b in ipairs(item.buttons) do
                    local btn = T.button(row, "outline", b[1], { width = w, height = 30, radius = 8, size = 12, onClick = b[2] })
                    btn:SetPoint("LEFT", (i - 1) * (w + 8), 0)
                end
            elseif item.kind == "about" then
                -- Version and bridge status on lines of their own: a nightly version is long.
                row = CreateFrame("Frame", nil, panel)
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
    panel:SetHeight(-y + 6)

    -- Docked to the chat window: it moves with it and closes with it.
    hooksecurefunc(WaiFrame, "StopMovingOrSizing", function()
        if panel:IsShown() then dock() end
    end)
    WaiFrame:HookScript("OnHide", function() panel:Hide() end)
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

function settings.toggle()
    if not panel then build() end
    if panel:IsShown() then return panel:Hide() end
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
settings.SECTIONS = SECTIONS
settings.DEFAULTS = DEFAULTS
