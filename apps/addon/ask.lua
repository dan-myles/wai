-- "Ask wai about this": Alt-click an item, a quest in your log, your target's frame or a player's
-- name in chat, or use the button on quest dialogs. Each builds a subject that rides along with the
-- next message: { title, ref (markup shown in your bubble), prompt (default question), details }.

local _, ns = ...
local T = ns.theme
local ask = {}
ns.ask = ask

local usable = function(v) return ns.context.usable(v) end
local plain = function(s) return ns.context.plain(s) end

local SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 },
    INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 },
    INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 },
    INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 },
    INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_SHIELD = { 17 },
    INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 },
    INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}

-- Reads a tooltip as plain text, e.g. tooltipText("SetHyperlink", link).
local scanner
local function tooltipText(method, ...)
    scanner = scanner or CreateFrame("GameTooltip", "WaiScanTooltip", nil, "GameTooltipTemplate")
    scanner:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanner:ClearLines()
    if not pcall(scanner[method], scanner, ...) then return end
    local lines = {}
    for i = 1, scanner:NumLines() do
        local left = _G["WaiScanTooltipTextLeft" .. i]
        local right = _G["WaiScanTooltipTextRight" .. i]
        local l = left and left:GetText()
        local r = right and right:IsShown() and right:GetText()
        if usable(l) then lines[#lines + 1] = plain(usable(r) and (l .. "  " .. r) or l) end
    end
    scanner:Hide()
    return #lines > 0 and table.concat(lines, "; ") or nil
end

local function open(subject)
    ns.ui.attach(subject)
end

-- Subjects ------------------------------------------------------------------------------------

function ask.item(link)
    local name, _, _, _, _, _, _, _, equipLoc, icon = GetItemInfo(link)
    local id = tonumber(link:match("item:(%d+)"))
    if not name or not id then return end
    local parts = { "item: " .. (tooltipText("SetHyperlink", link) or name) }
    for _, slot in ipairs(SLOTS[equipLoc] or {}) do
        local equipped = GetInventoryItemLink("player", slot)
        if equipped then parts[#parts + 1] = "currently equipped: " .. (tooltipText("SetInventoryItem", "player", slot) or plain(equipped)) end
    end
    open({
        title = link, icon = icon,
        ref = ("[[item:%d:%s]]"):format(id, name),
        prompt = SLOTS[equipLoc] and "Is this an upgrade for me?" or "What is this and what is it good for?",
        details = table.concat(parts, "\n"),
    })
end

function ask.spell(id)
    local name = ns.context.spellName(id)
    if not name then return end
    open({
        title = "|cff71d5ff[" .. name .. "]|r",
        ref = ("[[spell:%d:%s]]"):format(id, name),
        prompt = "How should I use this?",
        details = "spell: " .. (tooltipText("SetHyperlink", "spell:" .. id) or name),
    })
end

function ask.questLog(index)
    if not index or index == 0 then return end
    local title, level, _, isHeader, _, isComplete, _, questID = GetQuestLogTitle(index)
    if not title or isHeader then return end
    local previous = GetQuestLogSelection()
    SelectQuestLogEntry(index)
    local description, objectives = GetQuestLogQuestText()
    local progress = {}
    for i = 1, GetNumQuestLeaderBoards(index) do
        local text, _, done = GetQuestLogLeaderBoard(i, index)
        if text then progress[#progress + 1] = text .. (done and " (done)" or "") end
    end
    SelectQuestLogEntry(previous or 0)
    open({
        title = "|cffffff00[" .. title .. "]|r",
        ref = questID and ("[[quest:%d:%s]]"):format(questID, title) or ("[[quest:" .. title .. "]]"),
        prompt = isComplete == 1 and "Where do I turn this in?" or "How do I do this quest?",
        details = ("quest: %s (level %d)%s\nobjectives: %s\nprogress: %s\ndescription: %s"):format(
            title, level or 0, isComplete == 1 and ", complete" or "", objectives or "",
            table.concat(progress, "; "), description or ""),
    })
end

-- The quest an NPC is offering or waiting on (quest dialog).
function ask.questDialog()
    local title = GetTitleText()
    if not usable(title) then return end
    local questID = GetQuestID and GetQuestID()
    open({
        title = "|cffffff00[" .. title .. "]|r",
        ref = (questID and questID > 0) and ("[[quest:%d:%s]]"):format(questID, title) or ("[[quest:" .. title .. "]]"),
        prompt = "Should I take this quest, and how do I do it?",
        details = ("quest offered: %s\nobjectives: %s\ntext: %s"):format(title, GetObjectiveText() or "", GetQuestText() or ""),
    })
end

function ask.unit(unit)
    local summary = ns.context.unit(unit)
    if not summary then return end
    local name = UnitName(unit)
    local isPlayer = UnitIsPlayer(unit)
    open({
        title = "|cffffd100" .. (usable(name) and name or "Target") .. "|r",
        ref = usable(name) and ("[[npc:" .. name .. "]]") or "",
        prompt = isPlayer and "What can you tell me about this player?" or "What should I know about this?",
        details = "unit: " .. summary,
    })
end

-- Recent chat, so a name in chat can be resolved to what they said.
local chat = {}
local CHAT_EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_WHISPER", "CHAT_MSG_CHANNEL", "CHAT_MSG_GUILD",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_EMOTE",
}
local chatEvents = CreateFrame("Frame")
for _, e in ipairs(CHAT_EVENTS) do pcall(chatEvents.RegisterEvent, chatEvents, e) end
chatEvents:SetScript("OnEvent", function(_, event, text, sender, _, _, _, _, _, _, channel)
    if not (usable(text) and usable(sender)) then return end
    local where = event:gsub("^CHAT_MSG_", ""):lower()
    if usable(channel) and channel ~= "" then where = channel end
    table.insert(chat, { sender = Ambiguate(sender, "none"), text = plain(text), where = where })
    if #chat > 40 then table.remove(chat, 1) end
end)

function ask.player(name)
    name = Ambiguate(name, "none")
    for i = #chat, 1, -1 do
        local m = chat[i]
        if m.sender == name then
            return open({
                title = "|cffffd100" .. name .. "|r",
                ref = "",
                prompt = "What does this mean, and how should I reply?",
                details = ("chat message from %s in %s: %s"):format(name, m.where, m.text),
            })
        end
    end
    ns.core.note(("I haven't seen %s say anything yet."):format(name))
    ns.ui.show(true)
end

-- The last n chat lines, for context.
-- Up to n of the latest lines within `budget` bytes, newest kept first. Channels drop their number
-- and zone ("1. General - Teldrassil" -> "General") and long lines are shortened.
function ask.chatLines(n, budget)
    local lines, size = {}, 0
    for i = #chat, math.max(1, #chat - n + 1), -1 do
        local m = chat[i]
        local where = m.where:gsub("^%d+%.%s*", ""):gsub("%s+%-%s+.*$", "")
        local text = #m.text > 120 and (m.text:sub(1, 117) .. "...") or m.text
        local line = ("[%s] %s: %s"):format(where, m.sender, text)
        if budget and size + #line + 1 > budget then break end
        table.insert(lines, 1, line)
        size = size + #line + 1
    end
    return #lines > 0 and ("\n" .. table.concat(lines, "\n")) or nil
end

-- Hooks ---------------------------------------------------------------------------------------

local lastAsk = 0
local function once(fn, ...)
    -- Some clicks reach us through two hooks; act on the first.
    if GetTime() - lastAsk < 0.2 then return end
    lastAsk = GetTime()
    fn(...)
end

local guard = ns.core.guard

-- Bags, character sheet, loot and other item buttons.
if HandleModifiedItemClick then
    hooksecurefunc("HandleModifiedItemClick", guard(function(link)
        if IsAltKeyDown() and type(link) == "string" and link:find("item:") then once(ask.item, link) end
    end))
end

-- Links in chat: items, spells, quests and player names.
hooksecurefunc("SetItemRef", guard(function(link, text)
    if not IsAltKeyDown() or type(link) ~= "string" then return end
    local kind, rest = link:match("^(%a+):(.*)$")
    if kind == "item" then once(ask.item, text)
    elseif kind == "spell" then once(ask.spell, tonumber(rest:match("^(%d+)")))
    elseif kind == "player" then once(ask.player, rest:match("^([^:]+)"))
    elseif kind == "quest" then
        local id = tonumber(rest:match("^(%d+)"))
        local title = text and text:match("%[(.-)%]")
        if id and title then
            open({ title = "|cffffff00[" .. title .. "]|r", ref = ("[[quest:%d:%s]]"):format(id, title),
                prompt = "How do I do this quest?", details = "quest: " .. title })
        end
    end
end))

local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_LOGIN")
login:SetScript("OnEvent", guard(function()
    -- Quest log entries.
    if QuestLogTitleButton_OnClick then
        hooksecurefunc("QuestLogTitleButton_OnClick", guard(function()
            if IsAltKeyDown() then once(ask.questLog, GetQuestLogSelection()) end
        end))
    end
    -- Your target's portrait.
    if TargetFrame then
        TargetFrame:HookScript("OnMouseUp", guard(function(_, button)
            if button == "LeftButton" and IsAltKeyDown() then once(ask.unit, "target") end
        end))
    end
    -- "Ask wai" on quest dialogs.
    if QuestFrame then
        local b = T.button(QuestFrame, "gold", "Ask wai", { height = 22, radius = 6, size = 11, padding = 18, onClick = ask.questDialog })
        b:SetPoint("TOPRIGHT", QuestFrame, "TOPRIGHT", -60, -48)
        b:SetFrameLevel(QuestFrame:GetFrameLevel() + 10)
    end
end))
