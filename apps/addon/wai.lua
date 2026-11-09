-- wai: chat with Claude or Codex from inside WoW, without reloading. This file is chat state; link.lua
-- carries messages both ways live, and ui.lua draws. Each message out is one string; each one in is
-- what changed since the last (merged by id). WaiDB.outbox (SavedVariables) and Data.lua (WaiData)
-- are the reload fallback and history.
-- Each character has tabs; each tab is its own conversation on the bridge ("Name-Realm#tab").

local _, ns = ...
local core = {}
ns.core = core
-- link.lua replaces this when it loads. A client started before it was installed can't see the new
-- file (or the helper addons) until it restarts.
ns.link = {
    busy = function() return false end,
    send = function() return false end,
    start = function() return false, "helpers" end,
    ready = function() return false end,
}

local ACK_TIMEOUT = 12 -- bridge hasn't acknowledged a message
local STALE_AFTER = 25 -- bridge says it's busy but its heartbeat stopped
local MAX_TABS = 8
-- A message's size before compression: text and context together. More takes longer to send.
local CAPACITY = 3072
local HEADER_BYTES = 3 -- kind, seq(2)
local DIGEST_MESSAGES = 8 -- per tab, in the hello; the bridge's live window is 6
local KINDS = { chat = 1, reset = 2, ping = 3, video = 4, update = 5, hello = 6 } -- bridge/src/index.ts
local CHARS_PER_SEC = { normal = 90, fast = 260 } -- by the "typing" setting; "instant" skips typing

local LoadAddOn = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn

local who -- "Name-Realm"
local chats = {} -- tab id -> { messages, byId, ackSeq, busy, activity, unread }
local notice
local watch, watchTicker -- while waiting on the bridge: { t0, retried, resynced }
local offline -- why the live link isn't running, shown with a Reload button
local lastBeatAt = 0 -- when the bridge was last heard from while watching
local updateAvailable -- a newer wai release the bridge found
local agent -- which agent the bridge answers with ("claude" | "codex")
local track -- the bridge's update track ("stable" | "nightly")
local ctxEpoch -- the bridge's context memory; context.lua resends everything when it changes
local contactAt -- when a live message from the bridge last arrived
local localId = 0
local typer = CreateFrame("Frame")

-- Error reports for opt-in telemetry (docs/TELEMETRY.md): event type and a scrubbed detail.
local reports = {}

-- Strips the character's name and realm from anything that might be reported.
local function scrub(text)
    text = tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("[\r\n\t]", " ")
    for _, name in ipairs({ who or "", UnitName and UnitName("player") or "", GetRealmName and GetRealmName() or "" }) do
        if #name > 1 then text = text:gsub(name:gsub("%p", "%%%0"), "<name>") end
    end
    return text:sub(1, 280)
end

local function queueReport(event, detail)
    if #reports >= 10 then return end
    local line = event .. "\t" .. scrub(detail)
    for _, r in ipairs(reports) do
        if r == line then return end
    end
    reports[#reports + 1] = line
end

local function report(err)
    print("|cffd97757wai error:|r " .. tostring(err))
    queueReport("lua_error", err)
end
core.report = report

-- Lua errors are hidden by default, so surface anything a handler throws.
function core.guard(fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then report(err) end
    end
end
local guard = core.guard

local function changed()
    if ns.ui then ns.ui.update() end
end

local function chatFor(tab)
    chats[tab] = chats[tab] or { messages = {}, byId = {}, ackSeq = 0, busy = false }
    return chats[tab]
end

local function tabs()
    return WaiCharDB.tabs
end

local function activeTab()
    return tabs().active
end

local function findTab(id)
    for i, t in ipairs(tabs().list) do
        if t.id == id then return t, i end
    end
end

local function pendingFor(tab)
    local n = 0
    for _, item in ipairs(WaiDB.outbox) do
        if item.tab == tab then n = n + 1 end
    end
    return n
end

local function waiting()
    if #WaiDB.outbox > 0 or ns.link.busy() or (ns.video and ns.video.loading()) then return true end
    for _, c in pairs(chats) do
        if c.busy then return true end
    end
    return false
end
core.waiting = waiting

-- Messages --------------------------------------------------------------------------------------

-- Advances one visible character, never splitting a UTF-8 sequence or a "||" escape.
local function nextChar(s, i)
    i = i + 1
    if s:sub(i, i + 1) == "||" then return i + 1 end
    while i < #s do
        local b = s:byte(i + 1)
        if b < 0x80 or b >= 0xC0 then break end
        i = i + 1
    end
    return i
end

-- Typewriter: reveal streamed text, speeding up when far behind so it never lags the stream.
typer:Hide()
typer:SetScript("OnUpdate", guard(function(self, elapsed)
    local moved = false
    for _, c in pairs(chats) do
        for _, m in ipairs(c.messages) do
            if m.shown < #m.text then
                local speed = CHARS_PER_SEC[ns.settings.get("typing")] or CHARS_PER_SEC.normal
                m.budget = (m.budget or 0) + elapsed * math.max(speed, (#m.text - m.shown) * 2)
                while m.budget >= 1 and m.shown < #m.text do
                    m.shown = nextChar(m.text, m.shown)
                    m.budget = m.budget - 1
                end
                moved = true
            end
        end
    end
    if moved then changed() else self:Hide() end
end))

local function sortMessages(c)
    table.sort(c.messages, function(a, b) return a.id < b.id end)
    while #c.messages > 100 do c.byId[table.remove(c.messages, 1).id] = nil end
end

-- A local-only message (command output) in the active tab. Sorts after everything so far.
function core.note(text)
    local c = chatFor(activeTab())
    localId = localId + 1
    local last = c.messages[#c.messages]
    local m = { id = math.floor(last and last.id or 0) + localId / 1000, role = "note", text = text, done = true, shown = #text, announced = true }
    c.messages[#c.messages + 1] = m
    c.byId[m.id] = m
    sortMessages(c)
    if ns.ui then ns.ui.show() end
    changed()
end

-- Runs what the agent asked for in a finished reply (notes, waypoint, UI), once per reply.
local function capture(m)
    WaiCharDB.captured = WaiCharDB.captured or {}
    if m.role ~= "assistant" or not m.done or WaiCharDB.captured[m.id] then return end
    WaiCharDB.captured[m.id] = true
    for _, a in ipairs(ns.links.actions(m.text)) do
        if a.kind == "remember" then
            ns.context.remember(a.body)
        elseif a.kind == "forget" then
            ns.context.forget(a.body)
        elseif a.kind == "title" then
            -- Retitle this reply's tab unless the player named it themselves.
            local tab = findTab(m.tab)
            local title = strtrim(ns.links.plainGlyphs(a.body)):sub(1, 24)
            if tab and not tab.manual and title ~= "" then
                tab.name, tab.auto = title, nil
            end
        elseif a.kind == "tiktok" then
            ns.video.setTikTok(a.body ~= "off")
        elseif a.kind == "stream" then
            local name, text = a.body:match("^([^:]+):(.+)$")
            if name then ns.video.stream(name, text) end
        elseif a.kind == "macro" then
            ns.macros.save(a.body, a.text)
        elseif a.kind == "delmacro" then
            ns.macros.delete(a.body)
        elseif a.kind == "ui" then
            local verb, name = a.body:match("^(%a+):(.+)$")
            if name then ns.modules.setShown(name, verb ~= "hide") end
        elseif a.body == "clear" then
            ns.way.clear()
        else
            local zone, x, y, label = ns.links.parseWay(a.body)
            if zone then ns.way.setByZone(zone, x, y, label) end
        end
    end
end

-- Merges one tab's snapshot (from Data.lua) or its changes (from the link) into local state. A field
-- that's missing didn't change; false clears it. A message's `add` is text to append.
local function merge(tab, snap, live)
    if type(snap) ~= "table" or not findTab(tab) then return end
    local c = chatFor(tab)
    c.ackSeq = math.max(c.ackSeq, snap.ackSeq or 0)
    if snap.busy ~= nil then c.busy = snap.busy == true end
    if snap.activity ~= nil then c.activity = snap.activity or nil end
    local visible = ns.ui.isShown() and tab == activeTab()
    for _, m in ipairs(snap.messages or {}) do
        if m.reset and not c.byId[m.id] then c.messages, c.byId = {}, {} end
        local cur = c.byId[m.id]
        if not cur then
            cur = { id = m.id, shown = 0, announced = not live }
            c.byId[m.id] = cur
            c.messages[#c.messages + 1] = cur
        end
        cur.role, cur.done, cur.tab = m.role or cur.role, m.done, tab
        if m.add then cur.text = (cur.text or "") .. m.add else cur.text = m.text or cur.text or "" end
        if not live or cur.role ~= "assistant" or not visible or ns.settings.get("typing") == "instant" then cur.shown = #cur.text end
        cur.shown = math.min(cur.shown, #cur.text)
        capture(cur)
        if cur.done and not cur.announced then
            cur.announced = true
            if cur.role == "assistant" and not visible then c.unread = true end
            -- With the window closed, finished replies show up as a whisper instead.
            if cur.role == "assistant" and not ns.ui.isShown() and ns.settings.get("whisper") then
                -- wai's own links (waypoints) only work inside the wai window.
                local text = ns.links.render(cur.text):gsub("|Hwai:.-|h(.-)|h", "%1")
                local name = #tabs().list > 1 and (" (" .. findTab(tab).name .. ")") or ""
                DEFAULT_CHAT_FRAME:AddMessage(("|cffd97757wai%s|r |cff999999whispers:|r %s"):format(name, text))
            end
        end
    end
    sortMessages(c)

    local pending = {}
    for _, item in ipairs(WaiDB.outbox) do
        local ack = chats[item.tab] and chats[item.tab].ackSeq or 0
        if item.who == who and item.seq > ack and findTab(item.tab) then pending[#pending + 1] = item end
    end
    WaiDB.outbox = pending
    typer:Show()
end

-- Watching the bridge -------------------------------------------------------------------------

local function stopWatching(n)
    if n and n.tone == "error" then queueReport("stalled", n.text) end
    watch = nil
    if watchTicker then watchTicker:Cancel() end
    watchTicker = nil
    notice = n
    changed()
end

local ping, hello

-- Keeps the live view honest: retries silently once, then says what's wrong.
local function checkHealth()
    if not watch then return end
    local t = GetTime()
    if not waiting() then return stopWatching() end
    if #WaiDB.outbox > 0 and t - watch.t0 > ACK_TIMEOUT then
        if watch.retried then
            return stopWatching({ tone = "error", text = "Couldn't reach the bridge. Is it running?", action = "Retry", run = core.sync })
        end
        watch.retried, watch.t0 = true, t
        core.sync()
    elseif t - lastBeatAt > STALE_AFTER then
        if watch.resynced then
            return stopWatching({ tone = "error", text = "Lost touch with the bridge.", action = "Retry", run = core.sync })
        end
        watch.resynced = true
        lastBeatAt = t
        ping()
    end
end

local function startWatching()
    watch = { t0 = GetTime(), retried = watch and watch.retried, resynced = watch and watch.resynced }
    lastBeatAt = GetTime()
    watchTicker = watchTicker or C_Timer.NewTicker(1, guard(checkHealth))
    changed()
end

-- Inbound: what changed on the bridge, over the link ----------------------------------------------

local function apply(msg)
    if type(msg) ~= "table" then return end
    lastBeatAt, contactAt = GetTime(), GetTime()
    if msg.hello then return hello() end -- the bridge restarted and wants to know what we have
    if msg.update ~= nil then updateAvailable = msg.update and msg.update.version or nil end
    if msg.agent then agent = msg.agent end
    if msg.track then track = msg.track end
    if msg.ctxEpoch ~= nil then ctxEpoch = msg.ctxEpoch or nil end
    for tab, snap in pairs(msg.chats or {}) do merge(tab, snap, true) end
    if msg.modules ~= nil then ns.modules.sync(msg.modules) end
    if msg.video ~= nil then ns.video.sync(msg.video) end
    changed()
end

-- Outbound ----------------------------------------------------------------------------------------

-- The player's telemetry choice and the client build (and an agent or update-track switch, on the
-- ping that asks for it), plus queued reports if they opted in.
local function flags(item)
    local choice = ns.settings.get("telemetry")
    local out = choice == true and "t=1" or choice == false and "t=0" or ""
    local version, build
    if GetBuildInfo then version, build = GetBuildInfo() end
    if version then out = out .. ";c=" .. version .. "." .. tostring(build) end
    if item.agent then out = out .. ";a=" .. item.agent end
    if item.track then out = out .. ";u=" .. item.track end
    if item.install then out = out .. ";i=" .. item.install end
    return out
end

-- Everything after the context: who, tab and flags. Reports are added in whatever room is left.
local function fixedTail(item)
    return "\0" .. who .. "\0" .. (item.tab or activeTab()) .. "\0" .. flags(item) .. "\0"
end

-- Bytes the context may use for a message with this text (context.lua budgets within it).
function core.room(text)
    return CAPACITY - HEADER_BYTES - #(text or "") - 1 - #fixedTail({})
end

function core.ctxEpoch()
    return ctxEpoch
end

-- kind, seq(2), then text \0 context \0 who \0 tab \0 flags \0 telemetry reports.
local function encode(item)
    local tail = fixedTail(item)
    local payload = (item.text or "") .. "\0" .. (item.ctx or "")
    payload = payload:sub(1, CAPACITY - HEADER_BYTES - #tail)
    -- Error reports (opted in) only take room the message doesn't need; the rest wait.
    if ns.settings.get("telemetry") == true and #reports > 0 then
        local lines = table.concat(reports, "\n"):sub(1, math.min(900, CAPACITY - HEADER_BYTES - #tail - #payload))
        if #lines > 0 then reports = {} end
        tail = tail .. lines
    end
    local seq = item.seq or 0
    return string.char(KINDS[item.kind] or KINDS.chat, floor(seq / 256) % 256, seq % 256) .. payload .. tail
end

-- Sends now over the link; without it, chat messages wait in WaiDB.outbox for a reload.
local function transmit(item)
    if not ns.link.send(encode(item)) then return false end
    startWatching()
    return true
end

-- Asks the bridge to send what changed.
ping = function()
    transmit({ kind = "ping" })
end

-- Tells the bridge what this session already has (from Data.lua or earlier messages), so it sends
-- only what's new: per tab, the latest messages as "tab id length done role".
hello = function()
    local lines = {}
    for _, tab in ipairs(tabs().list) do
        local c = chats[tab.id]
        local count = 0
        for i = #(c and c.messages or {}), 1, -1 do
            local m = c.messages[i]
            if m.role ~= "note" and m.id % 1 == 0 then
                lines[#lines + 1] = ("%s %d %d %d %s"):format(tab.id, m.id, #m.text, m.done and 1 or 0, m.role)
                count = count + 1
                if count >= DIGEST_MESSAGES then break end
            end
        end
    end
    ns.link.send(encode({ kind = "hello", text = table.concat(lines, "\n") }))
end

-- Asks the bridge for a video directly (kind "video" or "clip"), without going through Claude.
function core.requestVideo(kind, query)
    transmit({ kind = "video", text = kind .. ":" .. query })
end

-- Reports waiting to go with the next message (for "See what's sent").
function core.pendingReports()
    return reports
end

-- Seconds since the bridge was last heard from this session, or nil.
function core.lastContact()
    return contactAt and (GetTime() - contactAt)
end

-- In-game /update: the bridge updates wai and reports progress as status lines in this chat.
function core.requestUpdate()
    updateAvailable = nil
    notice = nil
    -- Keep watching until the bridge reports back.
    chatFor(activeTab()).busy = transmit({ kind = "update" })
    changed()
end

function core.agent()
    return agent or "claude"
end

-- /settings choices the bridge owns go out on a ping; it confirms with a note in this chat.
local function askBridge(fields)
    fields.kind = "ping"
    notice = nil
    -- Keep watching until the bridge's note arrives.
    chatFor(activeTab()).busy = transmit(fields)
    changed()
end

function core.setAgent(name)
    if name == core.agent() then return end
    agent = name -- shown right away; the bridge's next snapshot has the final say
    askBridge({ agent = name })
end

function core.track()
    return track or "stable"
end

function core.setTrack(name)
    if name == core.track() then return end
    track = name
    askBridge({ track = name })
end

-- The bridge downloads it from CurseForge and posts the result as a note.
function core.installAddon(id, name)
    core.note(("|cff9298a3Installing %s from CurseForge…|r"):format(name))
    askBridge({ install = id })
end

-- Public API ------------------------------------------------------------------------------------

local function enqueue(item)
    WaiDB.seq = WaiDB.seq + 1
    item.seq = WaiDB.seq
    item.who = who
    item.tab = activeTab()
    table.insert(WaiDB.outbox, item) -- also flushed on reload, as a fallback
    notice = nil
    if watch then watch.retried, watch.resynced = nil, nil end
    transmit(item)
    changed()
end

-- subject: optional attachment from ns.ask ({ ref, prompt, details }).
function core.send(msg, subject)
    msg = strtrim(msg or "")
    if msg == "" and subject then msg = subject.prompt end
    if msg == "" then return end
    local tab = findTab(activeTab())
    if tab and tab.auto then
        -- Name a fresh tab after its first message.
        local title = ns.context.plain(msg):gsub("%[%[.-%]%]", ""):gsub("%s+", " ")
        tab.name = strtrim(strtrim(title):sub(1, 22))
        tab.auto = nil
    end
    if subject and subject.ref ~= "" then msg = msg .. "  " .. subject.ref end
    enqueue({ kind = "chat", text = msg, ctx = ns.context.collect(subject, tab, msg) })
end

function core.reset()
    enqueue({ kind = "reset" })
end

-- Resends anything the bridge hasn't confirmed, or pings so it sends what changed. Whatever the
-- link still holds is on its way already; copies would only queue behind it.
function core.sync()
    notice = nil
    if ns.link.busy() then return changed() end
    if #WaiDB.outbox == 0 then return ping() end
    for _, item in ipairs(WaiDB.outbox) do transmit(item) end
    changed()
end

function core.reload()
    if InCombatLockdown() then
        notice = { tone = "info", text = "Can't reload in combat. Try again after." }
        return changed()
    end
    WaiDB.reopen = ns.ui.isShown()
    ReloadUI()
end

-- Tabs ----------------------------------------------------------------------------------------

function core.tabs()
    local list = {}
    for _, t in ipairs(tabs().list) do
        local c = chats[t.id]
        list[#list + 1] = {
            id = t.id, name = t.name, active = t.id == activeTab(),
            busy = (c and c.busy) or pendingFor(t.id) > 0, unread = c and c.unread,
        }
    end
    return list
end

function core.switchTab(id)
    if not findTab(id) then return end
    tabs().active = id
    local c = chatFor(id)
    c.unread = false
    for _, m in ipairs(c.messages) do m.shown = #m.text end
    changed()
end

function core.newTab()
    local t = tabs()
    if #t.list >= MAX_TABS then return core.note(("You can have up to %d chats. Delete one first (right-click its tab)."):format(MAX_TABS)) end
    local id = "t" .. t.next
    t.next = t.next + 1
    table.insert(t.list, { id = id, name = "New chat", auto = true })
    core.switchTab(id)
end

function core.closeTab(id)
    local t = tabs()
    local _, index = findTab(id)
    if not index then return end
    if #t.list == 1 then return core.reset() end -- the last chat just starts over
    table.remove(t.list, index)
    chats[id] = nil
    if t.active == id then core.switchTab(t.list[math.min(index, #t.list)].id) end
    changed()
end

function core.renameTab(id, name)
    local tab = findTab(id)
    name = strtrim(name or "")
    if not tab or name == "" then return end
    tab.name = name:sub(1, 24)
    tab.auto = nil
    tab.manual = true -- the player's name sticks; wai won't retitle this tab
    changed()
end

function core.view()
    local c = chatFor(activeTab())
    local last = c.messages[#c.messages]
    local streaming = last and last.role == "assistant" and not last.done and last.text ~= ""
    local outbox = {}
    for _, item in ipairs(WaiDB.outbox) do
        if item.tab == activeTab() then outbox[#outbox + 1] = item end
    end
    return {
        messages = c.messages,
        outbox = outbox,
        streaming = streaming,
        thinking = (#outbox > 0 or c.busy) and not streaming,
        activity = c.activity or (#outbox > 0 and "Sending") or nil,
        notice = notice,
        offline = offline,
        modulesNeedReload = ns.modules.needsReload(),
        update = updateAvailable,
        agent = core.agent(),
        -- Ask about error reports once, after the player has used wai a little.
        consent = ns.settings.get("telemetry") == nil and #c.messages > 0,
        tabs = core.tabs(),
    }
end

-- The link needs the character's GUID, which a cold login can be slow to have.
local function startLink(attempt)
    local ok, why = ns.link.start({ message = guard(apply), restart = guard(function() hello() end) })
    if ok then
        offline = nil
        return hello()
    end
    if why == "guid" and (attempt or 0) < 10 then
        return C_Timer.After(1, function() startLink((attempt or 0) + 1) end)
    end
    offline = why == "helpers" and "Restart WoW once to finish updating wai. Until then, messages send when you reload."
        or "wai can't reach the bridge live in this client. Messages send when you reload."
    queueReport("link_unavailable", why)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", guard(function()
    WaiDB = WaiDB or {}
    WaiDB.outbox = WaiDB.outbox or {}
    WaiDB.seq = WaiDB.seq or 0
    WaiDB.probe = nil
    WaiCharDB = WaiCharDB or {}
    WaiCharDB.tabs = WaiCharDB.tabs or { list = { { id = "main", name = "Chat" } }, active = "main", next = 2 }
    who = ns.context.who()
    WaiDB.who = who -- tells the bridge whose outbox this is when it reads SavedVariables

    ns.ui.build()
    local data = WaiData or {}
    updateAvailable = data.update and data.update.version
    agent = data.agent
    track = data.track
    ctxEpoch = data.ctxEpoch
    local prefix = who .. "#"
    for key, snap in pairs(data.chats or {}) do
        if key:sub(1, #prefix) == prefix then merge(key:sub(#prefix + 1), snap, false) end
    end
    -- Never reuse a seq the bridge already acknowledged.
    for _, c in pairs(chats) do WaiDB.seq = math.max(WaiDB.seq, c.ackSeq) end
    ns.modules.loadAll()
    ns.way.restore()
    if WaiDB.reopen then ns.ui.show() end
    WaiDB.reopen = nil
    startLink()
    -- A reload flushed any pending outbox to the bridge; watch for its reply.
    if waiting() then startWatching() end
    changed()
end))

function WaiToggle()
    ns.ui.toggleFromKey()
end

BINDING_HEADER_WAI = "wai"
BINDING_NAME_WAI_TOGGLE = "Toggle wai"

SLASH_WAI1 = "/wai"
SlashCmdList.WAI = guard(function(msg)
    msg = strtrim(msg or "")
    if msg == "" then return ns.ui.toggle() end
    ns.ui.show()
    -- "/wai help" runs a command; anything else is a message.
    if ns.commands.exists(msg:match("^(%S+)")) then ns.commands.run("/" .. msg) else core.send(msg) end
end)
