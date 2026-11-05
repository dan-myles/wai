-- Slash commands typed into the wai input. Only window controls live here; everything else
-- (memory, waypoints, combat, chat) the agent does itself from what you ask. See bridge/SKILL.md.

local _, ns = ...
local commands = {}
ns.commands = commands

local GOLD, MUTED, END = "|cffffd100", "|cff9298a3", "|r"

local HELP = table.concat({
    GOLD .. "Commands" .. END,
    "/help  " .. MUTED .. "this guide" .. END,
    "/new  " .. MUTED .. "open a new chat tab" .. END .. "   " .. MUTED .. "(double-click a tab to rename, right-click to close)" .. END,
    "/reload  " .. MUTED .. "refresh the live session" .. END,
    "/fun  " .. MUTED .. "TikTok mode, killstreaks and test buttons" .. END,
    "",
    GOLD .. "Just ask" .. END,
    MUTED .. "\"Remember I'm saving for a mount.\"  \"What do you remember?\"  \"Forget that.\"" .. END,
    MUTED .. "\"Take me to the Fargodeep Mine.\"  \"How did that fight go?\"  \"Why did I die?\"  \"What's going on in chat?\"" .. END,
    MUTED .. "\"Build me a gold-per-hour tracker.\"  UI wai builds appears live, no reload." .. END,
    "",
    GOLD .. "Ask from anywhere" .. END,
    MUTED .. "Alt-click an item, a quest in your log, your target's portrait or a player's name in chat. Quest dialogs have an Ask wai button." .. END,
    "",
    GOLD .. "In replies" .. END,
    MUTED .. "Hover items, spells and quests for their tooltip; shift-click to link them in chat. Click a blue pin for a waypoint arrow; right-click the arrow to clear it." .. END,
    "",
    GOLD .. "What wai sees" .. END,
    MUTED .. "Your character, notes, target, zone, quest log, recent chat and recent fights from the damage meter. Each character has its own conversation." .. END,
}, "\n")

local LIST = {
    { name = "help", hint = "Show what wai can do", run = function() ns.core.note(HELP) end },
    { name = "new", hint = "Open a new chat tab", run = function() ns.core.newTab() end },
    { name = "reload", hint = "Refresh the live session", run = function() ns.core.reload() end },
    { name = "fun", hint = "Toggles and test buttons", run = function() ns.fun.toggle() end },
}

-- Commands whose name starts with what's typed after "/", for the suggestion list.
function commands.match(text)
    local typed = text:match("^/(%S*)$")
    if not typed then return {} end
    local found = {}
    for _, c in ipairs(LIST) do
        if c.name:sub(1, #typed) == typed:lower() then found[#found + 1] = c end
    end
    return found
end

function commands.exists(name)
    for _, c in ipairs(LIST) do
        if c.name == (name or ""):lower() then return true end
    end
    return false
end

-- Runs "/name args"; returns true if the text was a command (even an unknown one).
function commands.run(text)
    local name = text:match("^/(%S+)")
    if not name then return false end
    for _, c in ipairs(LIST) do
        if c.name == name:lower() then
            c.run()
            return true
        end
    end
    ns.core.note(("Unknown command /%s. Try /help, or just ask."):format(name))
    return true
end
