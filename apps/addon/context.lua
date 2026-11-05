-- Game context sent with every message: who you are, what you're asking about, what you remember,
-- recent combat (Blizzard's damage meter; the raw combat log is closed to addons on this client),
-- where you are and your quest log. Highest priority first: the payload is cut from the end.

local _, ns = ...
local context = {}
ns.context = context

-- Some unit APIs return "secret" values that addons may hold but not inspect; skip them.
local function usable(value)
    if issecretvalue and issecretvalue(value) then return false end
    local ok, result = pcall(function() return value ~= nil and value ~= "" end)
    return ok and result
end
context.usable = usable

local function num(v)
    if usable(v) and type(v) == "number" then return v end
end

local function short(n)
    if n >= 10000 then return ("%.1fk"):format(n / 1000) end
    return tostring(math.floor(n + 0.5))
end

function context.spellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    return (GetSpellInfo(id))
end

-- Strips WoW colour/link escapes so Claude sees plain text.
function context.plain(s)
    return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""))
end

function context.who()
    return UnitName("player") .. "-" .. GetRealmName()
end

-- Character -------------------------------------------------------------------------------------

local function talents()
    local parts = {}
    for i = 1, GetNumTalentTabs() do
        -- Return shape differs between client versions.
        local a1, a2, a3, _, a5 = GetTalentTabInfo(i)
        local name = type(a1) == "string" and a1 or a2
        local points = type(a3) == "number" and a3 or a5
        parts[#parts + 1] = ("%s %d"):format(name, points or 0)
    end
    return table.concat(parts, " / ")
end

-- One line per quest: "- [7] The Fargodeep Mine #62: Gnarlpine Fang slain: 7/15, ...". The ID lets
-- the agent look the quest up exactly; objectives say how far along it is. Returns the lines and
-- each one's quest ID (nil when the client doesn't give one).
local function questLog()
    local list, ids = {}, {}
    for i = 1, GetNumQuestLogEntries() do
        local title, level, _, isHeader, _, isComplete, _, id = GetQuestLogTitle(i)
        if usable(title) and not isHeader then
            local objectives = {}
            for j = 1, (GetNumQuestLeaderBoards and GetNumQuestLeaderBoards(i)) or 0 do
                local text = GetQuestLogLeaderBoard(j, i)
                if usable(text) then objectives[#objectives + 1] = text end
            end
            local state = isComplete == 1 and "complete" or isComplete == -1 and "failed" or table.concat(objectives, ", ")
            list[#list + 1] = ("- [%d] %s%s%s"):format(level or 0, title, num(id) and (" #" .. id) or "", state ~= "" and (": " .. state) or "")
            ids[#list] = num(id)
        end
    end
    return list, ids
end

-- Every quest this character has turned in, whichever API this client has.
local function completedIDs()
    local QL = C_QuestLog
    if QL and QL.GetAllCompletedQuestIDs then
        local ok, ids = pcall(QL.GetAllCompletedQuestIDs)
        if ok and type(ids) == "table" then return ids end
    end
    if GetQuestsCompleted then
        local ok, set = pcall(GetQuestsCompleted, {})
        if ok and type(set) == "table" then
            local ids = {}
            for id, done in pairs(set) do
                if done then ids[#ids + 1] = id end
            end
            return ids
        end
    end
    return {}
end

local function base36(n)
    local digits, out = "0123456789abcdefghijklmnopqrstuvwxyz", ""
    repeat
        local d = n % 36
        out = digits:sub(d + 1, d + 1) .. out
        n = math.floor(n / 36)
    until n == 0
    return out
end

-- Unit summary used for your target and for alt-clicked units.
function context.unit(unit)
    if not UnitExists(unit) then return end
    local parts = {}
    local function add(fn)
        local ok, v = pcall(fn)
        if ok and usable(v) then parts[#parts + 1] = tostring(v) end
    end
    add(function() return UnitName(unit) end)
    add(function()
        local level = UnitLevel(unit)
        return level == -1 and "level ??" or ("level " .. level)
    end)
    add(function()
        local c = UnitClassification(unit)
        return c ~= "normal" and c or nil
    end)
    add(function() return UnitIsPlayer(unit) and (UnitRace(unit) .. " " .. UnitClass(unit)) or UnitCreatureType(unit) end)
    add(function()
        local r = UnitReaction(unit, "player")
        return r and (r <= 3 and "hostile" or r == 4 and "neutral" or "friendly")
    end)
    add(function()
        local guild = GetGuildInfo(unit)
        return guild and ("<" .. guild .. ">")
    end)
    add(function()
        local hp, max = UnitHealth(unit), UnitHealthMax(unit)
        return max > 0 and ("%d%% health"):format(hp / max * 100)
    end)
    return table.concat(parts, ", ")
end

-- Memory ----------------------------------------------------------------------------------------

function context.notes()
    WaiCharDB.notes = WaiCharDB.notes or {}
    return WaiCharDB.notes
end

function context.remember(note)
    note = strtrim(note or "")
    if note == "" then return end
    local notes = context.notes()
    for _, existing in ipairs(notes) do
        if existing:lower() == note:lower() then return end
    end
    notes[#notes + 1] = note
    return true
end

-- Removes notes containing the given words, or all of them.
function context.forget(words)
    local notes = context.notes()
    words = strtrim(words or ""):lower()
    if words == "all" then return wipe(notes) end
    for i = #notes, 1, -1 do
        local n = notes[i]:lower()
        if n:find(words, 1, true) or words:find(n, 1, true) then table.remove(notes, i) end
    end
end

-- Combat ----------------------------------------------------------------------------------------

local DM = C_DamageMeter
local MT = Enum and Enum.DamageMeterType or {}
local ST = Enum and Enum.DamageMeterSessionType or {}

local function localSource(session)
    for _, s in ipairs(type(session) == "table" and session.combatSources or {}) do
        if usable(s.isLocalPlayer) and s.isLocalPlayer then return s end
    end
end

local function mine(sessionID, meterType)
    local ok, session = pcall(DM.GetCombatSessionFromID, sessionID, meterType)
    return ok and localSource(session)
end

local function topSpells(sessionID, meterType, guid, n)
    local ok, src = pcall(DM.GetCombatSessionSourceFromID, sessionID, meterType, guid)
    if not ok or type(src) ~= "table" then return end
    local list = {}
    for _, sp in ipairs(src.combatSpells or {}) do
        local amount = num(sp.totalAmount)
        local id = num(sp.spellID or sp.spellId)
        if amount and amount > 0 then
            local name = (id and context.spellName(id)) or sp.spellName or sp.name or "melee"
            list[#list + 1] = { name = name, amount = amount }
        end
    end
    table.sort(list, function(a, b) return a.amount > b.amount end)
    local parts = {}
    for i = 1, math.min(n, #list) do parts[i] = ("%s %s"):format(list[i].name, short(list[i].amount)) end
    return #parts > 0 and table.concat(parts, ", ") or nil
end

local function lastDeath()
    local ok, session = pcall(DM.GetCombatSessionFromType, ST.Overall, MT.Deaths)
    if not ok or type(session) ~= "table" then return end
    local best
    for _, s in ipairs(session.combatSources or {}) do
        local id = num(s.deathRecapID)
        if usable(s.isLocalPlayer) and s.isLocalPlayer and id and id > 0 and (not best or id > best) then best = id end
    end
    if not best or not (C_DeathRecap and C_DeathRecap.GetRecapEvents) then return end
    local ok2, events = pcall(C_DeathRecap.GetRecapEvents, best)
    if not ok2 or type(events) ~= "table" then return end
    local hits = {}
    for i = math.max(1, #events - 5), #events do
        local e = events[i]
        local parts = {}
        for _, key in ipairs({ "sourceName", "spellName" }) do
            if usable(e[key]) then parts[#parts + 1] = tostring(e[key]) end
        end
        if not usable(e.spellName) and num(e.spellId) then parts[#parts + 1] = context.spellName(e.spellId) end
        if num(e.amount) then parts[#parts + 1] = short(e.amount) end
        if num(e.overkill) and e.overkill > 0 then parts[#parts + 1] = "(overkill " .. short(e.overkill) .. ")" end
        if #parts > 0 then hits[#hits + 1] = table.concat(parts, " ") end
    end
    return #hits > 0 and ("last death, final hits: " .. table.concat(hits, "; ")) or nil
end

-- detailed adds more spells and fights, for "/combat".
function context.combat(detailed)
    if not (DM and DM.GetAvailableCombatSessions) then return end
    local lines = {}
    local function add(fn)
        local ok, line = pcall(fn)
        if ok and line then lines[#lines + 1] = line end
    end
    if InCombatLockdown() then lines[#lines + 1] = "in combat right now (live numbers are hidden until it ends)" end

    local ok, sessions = pcall(DM.GetAvailableCombatSessions)
    sessions = ok and type(sessions) == "table" and sessions or {}
    local last = sessions[#sessions]
    if last and num(last.sessionID) then
        local id = last.sessionID
        add(function()
            local dmg, taken, healed = mine(id, MT.DamageDone), mine(id, MT.DamageTaken), mine(id, MT.HealingDone)
            local parts = { ("last fight: %s, %ss"):format(usable(last.name) and last.name or "unknown", num(last.durationSeconds) or "?") }
            if dmg and num(dmg.totalAmount) then
                parts[#parts + 1] = ("you dealt %s (%s dps)"):format(short(dmg.totalAmount), short(num(dmg.amountPerSecond) or 0))
            end
            if taken and num(taken.totalAmount) then parts[#parts + 1] = "took " .. short(taken.totalAmount) end
            if healed and num(healed.totalAmount) and healed.totalAmount > 0 then parts[#parts + 1] = "healed " .. short(healed.totalAmount) end
            return table.concat(parts, ", ")
        end)
        add(function()
            local me = mine(id, MT.DamageDone)
            local top = me and usable(me.sourceGUID) and topSpells(id, MT.DamageDone, me.sourceGUID, detailed and 8 or 4)
            return top and ("your damage by ability: " .. top)
        end)
        add(function()
            local me = mine(id, MT.DamageTaken)
            local top = me and usable(me.sourceGUID) and topSpells(id, MT.DamageTaken, me.sourceGUID, detailed and 8 or 3)
            return top and ("damage you took by ability: " .. top)
        end)
    end
    add(function()
        local recent = {}
        for i = #sessions, math.max(1, #sessions - (detailed and 9 or 4)), -1 do
            local s = sessions[i]
            if usable(s.name) then recent[#recent + 1] = ("%s (%ss)"):format(s.name, num(s.durationSeconds) or "?") end
        end
        return #recent > 0 and ("recent fights: " .. table.concat(recent, ", ")) or nil
    end)
    add(function()
        local ok2, session = pcall(DM.GetCombatSessionFromType, ST.Overall, MT.DamageDone)
        local me = ok2 and localSource(session)
        if not (me and num(me.totalAmount)) then return end
        return ("this session: %s damage over %ss of combat (%s dps)"):format(
            short(me.totalAmount), num(session.durationSeconds) or "?", short(num(me.amountPerSecond) or 0))
    end)
    add(lastDeath)
    return #lines > 0 and table.concat(lines, "\n") or nil
end

-- Assembly --------------------------------------------------------------------------------------

-- The bridge remembers these per character (context.ts), so each goes out only when it changed;
-- one that became empty goes out as "none". Remembered against the bridge's epoch: a bridge that
-- lost its memory has a new one, and everything goes out again. An older bridge (no epoch) gets
-- everything every time.
local STICKY = { character = true, remember = true, talents = true }

local function memory()
    local epoch = ns.core.ctxEpoch()
    if not epoch then return nil end
    local m = WaiCharDB.ctxMemory
    if not m or m.epoch ~= epoch then
        m = { epoch = epoch, sent = {}, done = {} }
        WaiCharDB.ctxMemory = m
    end
    return m
end

-- Words that mean the question is about chat, which then gets more room.
local CHATTY = { "chat", "said", "say", "says", "whisper", "general", "guild", "party", "trade", "lfg", "yell" }
local function aboutChat(message)
    message = (message or ""):lower()
    for _, word in ipairs(CHATTY) do
        if message:find("%f[%a]" .. word .. "%f[%A]") then return true end
    end
end

-- subject: optional { details = "..." } for whatever the player alt-clicked or attached.
-- tab: the chat this message is for ({ name, manual }), so Claude can title it.
-- message: the player's text; it decides what's relevant (macros, chat) and how much room is left.
-- The screenshot holds about 3 KB, so fields go in priority order, each within its own budget,
-- and whatever doesn't fit (a remembered field) simply goes with a later message.
function context.collect(subject, tab, message)
    local room = ns.core.room(message)
    local mem = memory()
    local lines, used = {}, 0
    -- Remembered fields go whole or wait for a later message; the rest are shortened to fit.
    local function put(key, value, budget, whole)
        local line = key .. ": " .. value
        local cap = math.min(budget or math.huge, room - used - 1)
        if #line > cap then
            if whole or cap < 60 then return false end
            line = line:sub(1, cap - 3) .. "..."
        end
        lines[#lines + 1] = line
        used = used + #line + 1
        return true
    end
    local function add(key, fn, budget)
        local ok, value = pcall(fn)
        if not ok then return end
        if not STICKY[key] then
            if usable(value) then put(key, tostring(value), budget) end
            return
        end
        value = usable(value) and tostring(value) or "none"
        if mem and mem.sent[key] == value then return end
        if put(key, value, budget, mem ~= nil) and mem then mem.sent[key] = value end
    end
    add("character", function()
        return ("%s-%s, level %d %s %s"):format(UnitName("player"), GetRealmName(),
            UnitLevel("player"), UnitRace("player"), UnitClass("player"))
    end)
    add("subject", function() return subject and subject.details end, 900)
    add("macros", function()
        if not (message or ""):lower():find("macro") then return nil end
        return "\n" .. ns.macros.describe(message, 1000)
    end, 1100)
    add("chat title", function()
        if not tab then return nil end
        return ("%q %s"):format(tab.name, tab.manual and "(named by the player; keep it)" or "(you can retitle it)")
    end)
    add("remember", function()
        local notes = context.notes()
        return #notes > 0 and table.concat(notes, "; ") or nil
    end, 500)
    add("target", function() return context.unit("target") end, 300)
    add("zone", function()
        local sub = GetSubZoneText()
        return sub ~= "" and ("%s, %s"):format(sub, GetZoneText()) or GetZoneText()
    end)
    add("gold", function() return floor(GetMoney() / 10000) end)
    add("mode", function() return WaiCharDB.tiktok and "TikTok mode is on" or nil end)
    add("killstreak", function()
        local n = ns.streak.count()
        return n > 0 and (n .. " kills without dying (11 = Chopper Gunner, 25 = Nuke)") or nil
    end)
    add("talents", talents)
    -- The quest log: whole the first time, then only quests that changed ("quests~", by quest ID)
    -- or left the log ("quests-"), since objectives tick with every kill.
    local ok, log, ids = pcall(questLog)
    if ok then
        local keyed = #ids == #log -- every quest has an ID, so the bridge can update it in place
        if not (mem and keyed and mem.quests) then
            local value = #log > 0 and ("\n" .. table.concat(log, "\n")) or "none"
            if put("quests", value, nil, mem ~= nil) and mem and keyed then
                mem.quests = {}
                for i, line in ipairs(log) do mem.quests[ids[i]] = line end
            end
        else
            local changed, now, gone = {}, {}, {}
            for i, line in ipairs(log) do
                now[ids[i]] = line
                if mem.quests[ids[i]] ~= line then changed[#changed + 1] = ids[i] end
            end
            for id in pairs(mem.quests) do
                if not now[id] then gone[#gone + 1] = id end
            end
            local text = {}
            for _, id in ipairs(changed) do text[#text + 1] = now[id] end
            if #changed > 0 and put("quests~", "\n" .. table.concat(text, "\n"), nil, true) then
                for _, id in ipairs(changed) do mem.quests[id] = now[id] end
            end
            if #gone > 0 and put("quests-", table.concat(gone, ","), nil, true) then
                for _, id in ipairs(gone) do mem.quests[id] = nil end
            end
        end
    end
    add("combat", function() return context.combat(false) end, 600)
    -- Chat is the biggest and usually the least relevant, so it gets a budget of its own.
    local chatty = aboutChat(message)
    add("recent chat", function() return ns.ask.chatLines(chatty and 12 or 6, chatty and 1200 or 450) end)
    -- Completed quests, a chunk per message until the bridge has them all, then one per turn-in:
    -- "done" starts the bridge's list over, "done+" adds to it. Too big to resend every time, so
    -- only with a bridge that remembers.
    if mem then
        local new = {}
        for _, id in ipairs(completedIDs()) do
            if not mem.done[id] then new[#new + 1] = id end
        end
        table.sort(new)
        local key = next(mem.done) and "done+" or "done"
        local parts, prev, size = {}, 0, #key + 2
        for _, id in ipairs(new) do
            local part = base36(#parts == 0 and id or id - prev)
            if used + size + #part + 2 > room or size > 1200 then break end
            parts[#parts + 1] = part
            size, prev = size + #part + 1, id
        end
        if #parts > 0 and put(key, table.concat(parts, ",")) then
            for i = 1, #parts do mem.done[new[i]] = true end
        end
    end
    return table.concat(lines, "\n")
end
