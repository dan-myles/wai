-- Reply markup -> rich text. Claude writes [[kind:...]] tokens (see bridge/src/claude.ts);
-- we turn them into real item/spell/quest links, coloured names, waypoint pins and memory notes.

local _, ns = ...
local T = ns.theme
local links = {}
ns.links = links

local PIN = "|T" .. T.PIN .. ":13:13:0:-1|t"
local waiting = {} -- itemIDs whose data we requested; re-render when it arrives

local function split(body)
    local id, rest = body:match("^(%d+):(.*)$")
    if id then return tonumber(id), rest end
    return nil, body
end

local function questLogLink(name)
    for i = 1, GetNumQuestLogEntries() do
        local title = GetQuestLogTitle(i)
        if title and title:lower() == name:lower() and GetQuestLink then return GetQuestLink(i) end
    end
end

local RENDER = {}

function RENDER.item(body)
    local id, name = split(body)
    local _, link = GetItemInfo(id or name)
    if link then return link end
    if id then
        waiting[id] = true
        return ("|cffffffff|Hitem:%d|h[%s]|h|r"):format(id, name ~= "" and name or ("item " .. id))
    end
    return ("|cffffffff[%s]|r"):format(name)
end

function RENDER.spell(body)
    local id, name = split(body)
    local getLink = (C_Spell and C_Spell.GetSpellLink) or GetSpellLink
    local ok, link = pcall(getLink, id or name)
    if ok and link then return link end
    if id then return ("|cff71d5ff|Hspell:%d|h[%s]|h|r"):format(id, name) end
    return ("|cff71d5ff[%s]|r"):format(name)
end

function RENDER.quest(body)
    local id, name = split(body)
    local link = questLogLink(name)
    if link then return link end
    if id then return ("|cffffff00|Hquest:%d:0|h[%s]|h|r"):format(id, name) end
    return ("|cffffff00[%s]|r"):format(name)
end

function RENDER.npc(body)
    return "|cffffd100" .. body .. "|r"
end

-- "Zone Name:X,Y:Label" -> zone, x, y, label (x, y as map percentages)
function links.parseWay(body)
    local zone, x, y, label = body:match("^([^:]*):%s*([%d%.]+)%s*,%s*([%d%.]+)%s*:?(.*)$")
    if not x then return end
    return zone, tonumber(x), tonumber(y), label ~= "" and label or zone
end

local function pin(zone, x, y, label, text)
    return ("|cff3fa0ff|Hwai:way:%s:%s:%s:%s|h%s %s|h|r"):format(zone, x, y, label, PIN, text)
end

-- [[way:Zone Name:X,Y:Label]] is a pin to click; [[setway:...]] sets the arrow when the reply is done.
function RENDER.way(body)
    local zone, x, y, label = links.parseWay(body)
    return zone and pin(zone, x, y, label, label)
end

function RENDER.setway(body)
    if body == "clear" then return "|cff8c6f3aWaypoint cleared|r" end
    local zone, x, y, label = links.parseWay(body)
    return zone and pin(zone, x, y, label, "Waypoint: " .. label)
end

function RENDER.remember(body)
    return "|cff8c6f3aNoted: " .. body .. "|r"
end

function RENDER.ui(body)
    local verb, name = body:match("^(%a+):(.+)$")
    if not name then return nil end
    return ("|cff8c6f3a%s %s|r"):format(verb == "hide" and "Hid" or "Showing", name)
end

function RENDER.video(body)
    return "|cff3fa0ffPlaying: " .. body .. "|r"
end
RENDER.clip = RENDER.video

function RENDER.tiktok(body)
    return "|cff8c6f3aTikTok mode " .. (body == "off" and "off" or "on") .. "|r"
end

-- Stream chat lines only appear in the TikTok overlay; titles only in the tab strip.
function RENDER.stream()
    return ""
end
RENDER.title = RENDER.stream

function RENDER.forget(body)
    return "|cff8c6f3aForgot: " .. body .. "|r"
end

-- Emoji and other 4-byte characters: WoW's fonts can't draw them.
function links.plainGlyphs(text)
    return (text:gsub("[\240-\244][\128-\191][\128-\191][\128-\191]", ""))
end

-- Rendered text -> what the player reads, without colour, link and texture codes (for copying).
-- Escaped pipes are parked first so a typed "||r" isn't mistaken for a code.
function links.plain(text)
    return (text:gsub("||", "\1"):gsub("|T.-|t ?", ""):gsub("|H.-|h(.-)|h", "%1")
        :gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("\1", "|"))
end

-- Macro bodies span lines and use [brackets] themselves, so a macro is a block, not a token:
-- [[macro:Name]] or [[macro:Name:general]], the body, then [[/macro]].
local MACRO = "%[%[macro:([^%]]-)%]%][ \t]*\n?(.-)%s*%[%[/macro%]%]"

function RENDER.delmacro(body)
    return "|cff8c6f3aDeleted macro: " .. body .. "|r"
end

-- Text without its macros, finished or still streaming (captions have no room for them).
function links.dropMacros(text)
    return (text:gsub(MACRO, ""):gsub("%[%[macro:[^%]]-%]%].*$", ""))
end

-- "Name" or "Name:general" -> name, general
function links.macroHead(head)
    local name, scope = head:match("^(.-):(%a+)$")
    return strtrim(name or head), scope == "general"
end

-- A macro card always sits on lines of its own.
local function macroCard(before, head, body)
    local name, general = links.macroHead(head)
    local lines = strtrim(body):gsub("||", "|"):gsub("|", "||"):gsub("\n", "|r\n|cff9298a3")
    return before .. (before ~= "" and "\n" or "") .. ("|cff8c6f3aMacro %s (%s)|r\n|cff9298a3%s|r\n"):format(name, general and "all characters" or "this character", lines)
end

-- Renders markup in (possibly still streaming) text; a half-received token stays hidden.
function links.render(text)
    text = links.plainGlyphs(text)
    local open = text:find("%[%[[^%]]*$")
    if open then text = text:sub(1, open - 1) end
    text = text:gsub("([^\n]?)" .. MACRO, macroCard):gsub("\n+$", "")
    -- A macro still streaming in: its body would flash up as plain text.
    text = text:gsub("%[%[macro:[^%]]-%]%].*$", "|cff8c6f3aWriting a macro…|r")
    text = text:gsub("%[%[(%a+):([^%]]-)%]%]", function(kind, body)
        local fn = RENDER[kind]
        if not fn then return nil end
        local ok, out = pcall(fn, body)
        return ok and out or body
    end)
    -- Hidden tokens on lines of their own ([[title:..]] first, [[stream:..]] last) leave empty
    -- lines behind, which would show as blank space in the card.
    text = text:gsub("\n[ \t]*\n%s*\n", "\n\n")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Actions the agent asked for in a finished reply, in order: { kind, body }.
local ACTIONS = { remember = true, forget = true, setway = true, ui = true, tiktok = true, stream = true, title = true, delmacro = true }
function links.actions(text)
    local list = {}
    for head, body in text:gmatch(MACRO) do
        list[#list + 1] = { kind = "macro", body = head, text = body }
    end
    for kind, body in text:gmatch("%[%[(%a+):([^%]]-)%]%]") do
        if ACTIONS[kind] then list[#list + 1] = { kind = kind, body = body } end
    end
    return list
end

-- Hyperlink handling ----------------------------------------------------------------------------

local function parseWay(link)
    local zone, x, y, label = link:match("^wai:way:([^:]*):([^:]+):([^:]+):(.*)$")
    if x then return zone, tonumber(x), tonumber(y), label end
end

local function onEnter(self, link)
    self.overLink = true
    local zone, x, y, label = parseWay(link)
    if zone then
        return T.tooltip(self, label, ("%s  %.1f, %.1f"):format(zone, x, y), "Click to set a waypoint arrow.")
    end
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
    if pcall(GameTooltip.SetHyperlink, GameTooltip, link) then GameTooltip:Show() else GameTooltip:Hide() end
end

local function onClick(self, link, text, button)
    local zone, x, y, label = parseWay(link)
    if zone then
        local ok, err = ns.way.setByZone(zone, x, y, label)
        if not ok then ns.core.note("|cffff5a5a" .. err .. "|r") end
        return
    end
    -- Blizzard's handler: tooltip popup, shift-click to link in chat, ctrl-click to try on.
    SetItemRef(link, text, button, self)
end

-- Makes a frame's font strings' links hoverable and clickable.
function links.enable(f)
    f:SetHyperlinksEnabled(true)
    f:SetScript("OnHyperlinkEnter", onEnter)
    f:SetScript("OnHyperlinkLeave", function(self)
        self.overLink = false
        GameTooltip:Hide()
    end)
    f:SetScript("OnHyperlinkClick", ns.core.guard(onClick))
end

local events = CreateFrame("Frame")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
events:SetScript("OnEvent", function(_, _, itemID)
    if waiting[itemID] then
        waiting[itemID] = nil
        if ns.ui then ns.ui.invalidate() end
    end
end)
