-- Answers the bridge's questions for the agent's `game` tool (apps/cli/src/mcp.ts) from this client's
-- own data: the bundled class training table (training.lua) and, when the player has Questie, its
-- Forever database (LibQuestieDB). Answers are plain text for the agent to read.

local _, ns = ...
local query = {}
ns.query = query

local MAX_IDS, MAX_ZONES, MAX_POINTS, MAX_LIST = 6, 5, 6, 20
local QUESTIE = "Source: QuestieDB Forever (database spawn points, not live sightings)."

local function has(list, value)
    for _, v in ipairs(list or {}) do
        if v == value then return true end
    end
    return false
end

-- A spell's name with its rank. Spell data the client hasn't cached yet comes back on a later ask.
local function spellName(id)
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id) or (GetSpellInfo and GetSpellInfo(id))
    if not name then
        if C_Spell and C_Spell.RequestLoadSpellData then C_Spell.RequestLoadSpellData(id) end
        return "spell " .. id
    end
    local rank = C_Spell and C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(id) or (GetSpellSubtext and GetSpellSubtext(id))
    return (rank and rank ~= "") and (name .. " (" .. rank .. ")") or name
end

local function known(id)
    if IsPlayerSpell then return IsPlayerSpell(id) end
    return IsSpellKnown and IsSpellKnown(id)
end

-- Training ------------------------------------------------------------------------------------------

-- a: { class, from, to, name }. Another class's table is shown whole; the player's own is filtered
-- to their race and faction and marked with what they know.
local function training(a)
    local _, mine = UnitClass("player")
    local class = tostring(a.class or mine):upper()
    local data = ns.training.ClassData[class]
    if not data then return "There's no training table for " .. class .. "." end
    local own = class == mine
    local level = UnitLevel("player")
    local wanted = a.name and tostring(a.name):lower()
    local from = tonumber(a.from) or (wanted and 1 or level)
    local to = tonumber(a.to) or (wanted and 60 or math.min(60, level + 10))
    local faction, race = UnitFactionGroup("player"), select(3, UnitRace("player"))
    local rows = {}
    local function add(lvl, id, text)
        local name = spellName(id)
        if wanted and not name:lower():find(wanted, 1, true) then return end
        local tags = own and known(id) and " (known)" or ""
        rows[#rows + 1] = { lvl = lvl, text = ("%d: %s [spell %d], %s%s"):format(lvl, name, id, text, tags) }
    end
    for lvl = from, to do
        for _, sp in ipairs(data.spellsByLevel[lvl] or {}) do
            local fits = not own or ((not sp.faction or sp.faction == faction)
                and (not (sp.race or sp.races) or sp.race == race or has(sp.races, race)))
            if fits then
                local need = sp.requiredTalentId and ("; needs the talent " .. spellName(sp.requiredTalentId)) or ""
                add(lvl, sp.id, ns.context.money(sp.cost) .. need)
            end
        end
    end
    for id, entries in pairs(ns.training.QuestSpells[class] or {}) do
        for _, e in ipairs(entries) do
            if (not own or not e.races or has(e.races, race)) and e.level >= from and e.level <= to then
                add(e.level, id, "from a quest (quest " .. table.concat(e.quests or {}, ", quest ") .. ")")
                break
            end
        end
    end
    table.sort(rows, function(x, y) return x.lvl < y.lvl end)
    local lines = { ("%s training, levels %d-%d%s:"):format(class, from, to, own and (" (the character is level " .. level .. ")") or "") }
    for _, r in ipairs(rows) do lines[#lines + 1] = r.text end
    if #rows == 0 then lines[#lines + 1] = "Nothing in that range." end
    lines[#lines + 1] = "Trainer costs are base prices before reputation discounts. Source: WhatsTraining's Forever tables, bundled with wai."
    return table.concat(lines, "\n")
end

-- Questie ---------------------------------------------------------------------------------------------

local function questie()
    local db = LibQuestieDB
    if type(db) ~= "table" or type(db.flavor) ~= "table" or db.flavor.expansion ~= "Forever" then
        return nil, "QuestieDB for Forever isn't loaded: the player doesn't have Questie (it's on CurseForge) or it's turned off. Use Wowhead instead."
    end
    return db
end

local function module(name)
    if not (QuestieLoader and QuestieLoader.ImportModule) then return end
    local ok, m = pcall(QuestieLoader.ImportModule, QuestieLoader, name)
    if ok then return m end
end

local function zoneOf(areaId, zoneDB)
    if zoneDB and zoneDB.GetUiMapIdByAreaId then
        local ok, uiMap = pcall(zoneDB.GetUiMapIdByAreaId, zoneDB, areaId)
        local info = ok and uiMap and C_Map.GetMapInfo(uiMap)
        if info then return info.name, uiMap end
    end
    return C_Map.GetAreaInfo and C_Map.GetAreaInfo(areaId)
end

-- QuestieDB keeps some points in Classic's map frame. Only points its projection leaves unchanged are
-- certainly right on Forever's maps; the rest are counted, not guessed at.
local function onForeverMap(db, areaId, x, y)
    if not db.EraToForever then return false end
    local px, py = db.EraToForever(areaId, x, y)
    return type(px) == "number" and type(py) == "number" and math.abs(px - x) < 0.01 and math.abs(py - y) < 0.01
end

local function friendly(entity, id)
    local f = entity.Get(id, "friendlyToFaction")
    if not f then return true end
    return f:find(UnitFactionGroup("player") == "Horde" and "H" or "A", 1, true) ~= nil
end

-- An NPC's or object's spawns as "Zone x,y; x,y" lines, the player's zone first, and whether the
-- first line is the player's zone.
local function spawns(db, entity, id)
    local zoneDB, here = module("ZoneDB"), C_Map.GetBestMapForUnit("player")
    local zones, skipped = {}, 0
    for areaId, points in pairs(entity.Get(id, "spawns") or {}) do
        local zone, uiMap = zoneOf(areaId, zoneDB)
        local pts = {}
        for _, p in ipairs(type(points) == "table" and points or {}) do
            local x, y = p[1], p[2]
            if type(x) == "number" and type(y) == "number" and x >= 0 and x <= 100 and y >= 0 and y <= 100 then
                if onForeverMap(db, areaId, x, y) then
                    pts[#pts + 1] = ("%.1f,%.1f"):format(x, y)
                else
                    skipped = skipped + 1
                end
            end
        end
        if zone and #pts > 0 then zones[#zones + 1] = { zone = zone, here = uiMap and uiMap == here, pts = pts } end
    end
    table.sort(zones, function(a, b)
        if a.here ~= b.here then return a.here == true end
        return #a.pts > #b.pts
    end)
    local out = {}
    for i = 1, math.min(#zones, MAX_ZONES) do
        local z = zones[i]
        local shown = { unpack(z.pts, 1, math.min(#z.pts, MAX_POINTS)) }
        local more = #z.pts > MAX_POINTS and (" (+" .. (#z.pts - MAX_POINTS) .. " more)") or ""
        out[#out + 1] = ("  %s %s%s"):format(z.zone, table.concat(shown, "; "), more)
    end
    if skipped > 0 then out[#out + 1] = ("  (%d spawn points left out: not confirmed on Forever's maps)"):format(skipped) end
    if #out == 0 then out[1] = "  no confirmed spawn points" end
    return out, zones[1] ~= nil and zones[1].here == true
end

local function describe(db, entity, kind, id)
    local sub = kind == "npc" and entity.Get(id, "subName")
    local lines = { ("%s %d: %s%s"):format(kind, id, entity.Get(id, "name") or "?", sub and (" <" .. sub .. ">") or "") }
    for _, l in ipairs(spawns(db, entity, id)) do lines[#lines + 1] = l end
    return table.concat(lines, "\n")
end

-- a: { name or id }. kind: "npc" | "object".
local function entities(kind, a)
    local db, why = questie()
    if not db then return why end
    local entity = db[kind == "npc" and "Npc" or "Object"]
    if not (entity and entity.Get and entity.Exists) then return "This QuestieDB can't look up " .. kind .. "s." end
    local ids = a.id and { tonumber(a.id) } or (a.name and entity.IdsByName and entity.IdsByName(tostring(a.name))) or {}
    local out = {}
    for _, id in ipairs(ids) do
        if #out >= MAX_IDS then break end
        if entity.Exists(id) and (kind ~= "npc" or friendly(entity, id)) then out[#out + 1] = describe(db, entity, kind, id) end
    end
    if #out == 0 then
        return ("QuestieDB has no %s %s (names must match exactly; try Wowhead's search for the id)."):format(kind, a.id and ("with id " .. a.id) or ('called "' .. tostring(a.name) .. '"'))
    end
    out[#out + 1] = QUESTIE
    return table.concat(out, "\n")
end

-- NPCs by role, friendly to the player, with the first spawn of each; the player's zone first.
local function npcList(db, ids, title)
    local entity, rows = db.Npc, {}
    for _, id in ipairs(ids or {}) do
        if entity.Exists(id) and friendly(entity, id) then
            local where, here = spawns(db, entity, id)
            local sub = entity.Get(id, "subName")
            rows[#rows + 1] = {
                here = here,
                text = ("npc %d: %s%s: %s"):format(id, entity.Get(id, "name") or "?", sub and (" <" .. sub .. ">") or "", strtrim(where[1])),
            }
        end
    end
    table.sort(rows, function(a, b)
        if a.here ~= b.here then return a.here end
        return a.text < b.text
    end)
    local lines = { title }
    for i = 1, math.min(#rows, MAX_LIST) do lines[#lines + 1] = rows[i].text end
    if #rows > MAX_LIST then lines[#lines + 1] = ("(+%d more)"):format(#rows - MAX_LIST) end
    if #rows == 0 then lines[#lines + 1] = "None found." end
    lines[#lines + 1] = QUESTIE
    return table.concat(lines, "\n")
end

local function trainers(a)
    local db, why = questie()
    if not db then return why end
    local townsfolk = module("Townsfolk")
    if not (townsfolk and townsfolk.GetClassTrainers) then return "This Questie has no class-trainer index." end
    local _, mine = UnitClass("player")
    local class = tostring(a.class or mine):upper()
    return npcList(db, townsfolk.GetClassTrainers()[class], class .. " trainers:")
end

local function service(a)
    local db, why = questie()
    if not db then return why end
    local townsfolk = module("Townsfolk")
    local index = townsfolk and townsfolk.townsfolk
    if type(index) ~= "table" then return "This Questie has no town-service index." end
    local wanted, names = tostring(a.service or ""):lower():gsub("%s", ""), {}
    for role, ids in pairs(index) do
        if role:lower():gsub("%s", "") == wanted then return npcList(db, ids, role .. ":") end
        names[#names + 1] = role
    end
    table.sort(names)
    return "No service called " .. tostring(a.service) .. ". Questie knows: " .. table.concat(names, ", ") .. "."
end

local function names(db, kind, ids)
    local out = {}
    for _, id in ipairs(type(ids) == "table" and ids or {}) do
        out[#out + 1] = ("%s %d %s"):format(kind, id, db[kind == "quest" and "Quest" or "Npc"].Get(id, "name") or "")
    end
    return table.concat(out, ", ")
end

local function quest(a)
    local db, why = questie()
    if not db then return why end
    local q, id = db.Quest, tonumber(a.id)
    if not (q and q.Get and id and q.Exists(id)) then return "QuestieDB has no quest " .. tostring(a.id) .. "." end
    local function get(field) return q.Get(id, field) end
    local lines = { ("quest %d: %s (level %s, requires %s)"):format(id, get("name") or "?", tostring(get("questLevel") or "?"), tostring(get("requiredLevel") or "?")) }
    local function people(label, by)
        if type(by) ~= "table" then return end
        for _, npc in ipairs(type(by[1]) == "table" and by[1] or {}) do
            if db.Npc.Exists(npc) then lines[#lines + 1] = label .. " " .. describe(db, db.Npc, "npc", npc) end
        end
        for _, obj in ipairs(type(by[2]) == "table" and by[2] or {}) do
            if db.Object.Exists(obj) then lines[#lines + 1] = label .. " " .. describe(db, db.Object, "object", obj) end
        end
        for _, item in ipairs(type(by[3]) == "table" and by[3] or {}) do lines[#lines + 1] = label .. " item " .. item end
    end
    people("Starts at", get("startedBy"))
    people("Turn in at", get("finishedBy"))
    local text = get("objectivesText")
    if type(text) == "table" and #text > 0 then lines[#lines + 1] = "Objectives: " .. table.concat(text, " ") end
    if get("preQuestSingle") then lines[#lines + 1] = "After any of: " .. names(db, "quest", get("preQuestSingle")) end
    if get("preQuestGroup") then lines[#lines + 1] = "After all of: " .. names(db, "quest", get("preQuestGroup")) end
    if get("nextQuestInChain") and get("nextQuestInChain") ~= 0 then lines[#lines + 1] = "Next: " .. names(db, "quest", { get("nextQuestInChain") }) end
    lines[#lines + 1] = "Requirements here aren't an eligibility check. " .. QUESTIE
    return table.concat(lines, "\n")
end

local QUERIES = {
    training = training,
    npc = function(a) return entities("npc", a) end,
    object = function(a) return entities("object", a) end,
    quest = quest,
    trainers = trainers,
    service = service,
}

-- a: { query, ... } from the bridge. Always returns text, errors included.
function query.run(a)
    local fn = QUERIES[a.query]
    if not fn then return "The game doesn't know the question " .. tostring(a.query) .. "." end
    local ok, text = pcall(fn, a)
    if not ok then
        ns.core.report("query " .. tostring(a.query) .. ": " .. tostring(text))
        return "The game couldn't answer: " .. tostring(text)
    end
    return text
end
