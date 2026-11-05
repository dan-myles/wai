-- Macros the agent writes ([[macro:Name]] ... [[/macro]], [[delmacro:Name]]) and the list it sees
-- when the player talks about macros. The macro API is closed in combat, so changes asked for
-- then wait for PLAYER_REGEN_ENABLED.

local _, ns = ...
local macros = {}
ns.macros = macros

local ICON = "INV_MISC_QUESTIONMARK" -- WoW then shows the icon of the macro's first spell
local MAX_NAME, MAX_BODY = 16, 255
local RED, MUTED, END = "|cffff5a5a", "|cff9298a3", "|r"
local pending = {}

local function limits()
    return MAX_ACCOUNT_MACROS or 120, MAX_CHARACTER_MACROS or 18
end

-- Every macro as { index, name, body, character }, character-specific ones first.
function macros.list()
    local maxAccount = limits()
    local numAccount, numChar = GetNumMacros()
    local out = {}
    local function add(i, character)
        local name, _, body = GetMacroInfo(i)
        if name then out[#out + 1] = { index = i, name = name, body = body or "", character = character } end
    end
    for i = 1, numChar or 0 do add(maxAccount + i, true) end
    for i = 1, numAccount or 0 do add(i, false) end
    return out
end

local function find(name)
    name = name:lower()
    for _, m in ipairs(macros.list()) do
        if m.name:lower() == name then return m end
    end
end

-- Same name replaces the macro wherever it lives (keeping its icon); new ones go where asked.
local function save(op)
    local existing = find(op.name)
    if existing then
        local _, icon = GetMacroInfo(existing.index)
        EditMacro(existing.index, existing.name, icon or ICON, op.body)
        return
    end
    local maxAccount, maxChar = limits()
    local numAccount, numChar = GetNumMacros()
    if op.general and numAccount >= maxAccount then return "your general macro slots are full" end
    if not op.general and numChar >= maxChar then return "your character macro slots are full" end
    CreateMacro(op.name, ICON, op.body, not op.general)
end

local function remove(op)
    local existing = find(op.name)
    if not existing then return "there's no macro called " .. op.name end
    DeleteMacro(existing.index)
end

local function run(op)
    local ok, err = pcall(op.delete and remove or save, op)
    if not ok or err then
        local verb = op.delete and "delete" or "save"
        ns.core.note(("%sCouldn't %s macro %s: %s%s"):format(RED, verb, op.name, tostring(err), END))
    end
end

local function apply(op)
    if InCombatLockdown() then
        pending[#pending + 1] = op
        ns.core.note(("%sMacro %s changes after combat.%s"):format(MUTED, op.name, END))
        return
    end
    run(op)
end

-- head: "Name" or "Name:general"; body: the macro text, one command per line.
function macros.save(head, body)
    local name, general = ns.links.macroHead(head)
    body = strtrim(body or "")
    if name == "" then return end
    if #name > MAX_NAME then
        return ns.core.note(("%sMacro names are at most %d characters: %s%s"):format(RED, MAX_NAME, name, END))
    end
    if #body > MAX_BODY then
        return ns.core.note(("%sMacro %s is %d characters; WoW allows %d.%s"):format(RED, name, #body, MAX_BODY, END))
    end
    apply({ name = name, body = body, general = general })
end

function macros.delete(name)
    name = strtrim(name)
    if name ~= "" then apply({ name = name, delete = true }) end
end

-- The [game] block's macro list: macros named in the message first, then the character's, then
-- general ones, within `budget` bytes so the rest of the context still fits.
function macros.describe(message, budget)
    local list = macros.list()
    if #list == 0 then return "none yet" end
    local text = (message or ""):lower()
    local function named(m) return text:find(m.name:lower(), 1, true) ~= nil end
    table.sort(list, function(a, b)
        if named(a) ~= named(b) then return named(a) end
        if a.character ~= b.character then return a.character end
        return a.index < b.index
    end)
    local maxAccount, maxChar = limits()
    local numAccount, numChar = GetNumMacros()
    local lines = { ("%d of %d character slots, %d of %d general slots used"):format(numChar, maxChar, numAccount, maxAccount) }
    local used = #lines[1]
    for i, m in ipairs(list) do
        local line = ("- %s (%s): %s"):format(m.name, m.character and "character" or "general", (m.body:gsub("\n", "\\n")))
        if used + #line > budget then
            lines[#lines + 1] = ("(+%d more)"):format(#list - i + 1)
            break
        end
        lines[#lines + 1] = line
        used = used + #line + 1
    end
    return table.concat(lines, "\n")
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", ns.core.guard(function()
    local queued = pending
    pending = {}
    for _, op in ipairs(queued) do run(op) end
end))
