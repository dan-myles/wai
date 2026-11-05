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

local function quests()
    local list = {}
    for i = 1, GetNumQuestLogEntries() do
        local title, level, _, isHeader, _, isComplete = GetQuestLogTitle(i)
        if usable(title) and not isHeader then
            list[#list + 1] = ("%s (%d%s)"):format(title, level or 0, isComplete == 1 and ", complete" or "")
        end
    end
    return #list > 0 and table.concat(list, "; ") or nil
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

-- subject: optional { details = "..." } for whatever the player alt-clicked or attached.
function context.collect(subject)
    local lines = {}
    local function add(key, fn)
        local ok, value = pcall(fn)
        if ok and usable(value) then lines[#lines + 1] = key .. ": " .. tostring(value) end
    end
    add("character", function()
        return ("%s-%s, level %d %s %s"):format(UnitName("player"), GetRealmName(),
            UnitLevel("player"), UnitRace("player"), UnitClass("player"))
    end)
    add("subject", function() return subject and subject.details end)
    add("remember", function()
        local notes = context.notes()
        return #notes > 0 and table.concat(notes, "; ") or nil
    end)
    add("target", function() return context.unit("target") end)
    add("zone", function()
        local sub = GetSubZoneText()
        return sub ~= "" and ("%s, %s"):format(sub, GetZoneText()) or GetZoneText()
    end)
    add("combat", function() return context.combat(false) end)
    add("mode", function() return WaiCharDB.tiktok and "TikTok mode is on" or nil end)
    add("killstreak", function()
        local n = ns.streak.count()
        return n > 0 and (n .. " kills without dying (11 = Chopper Gunner, 25 = Nuke)") or nil
    end)
    add("recent chat", function() return ns.ask.chatLines(8) end)
    add("talents", talents)
    add("gold", function() return floor(GetMoney() / 10000) end)
    add("quests", quests)
    return table.concat(lines, "\n")
end
