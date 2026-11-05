-- Headless test: runs the addon against a stub of the WoW API (login, tabs, streaming, durability,
-- modules, killstreaks, video, Fun menu). Usage: luajit addon/test/headless.lua addon
local addonDir = arg[1] or "addon"
local frames, eventFrames, updaters, timers, hooks = {}, {}, {}, {}, {}
local now = 1000

local Obj = {}
Obj.__index = function(t, k)
  local v = rawget(Obj, k)
  if v ~= nil then return v end
  if type(k) == "string" and k:match("^%u") then return function() end end
  return nil
end
local function new(kind, parent, name)
  local o = setmetatable({ kind = kind, shown = true, scripts = {}, w = 400, h = 500, text = "", parent = parent, scroll = 0, name = name }, Obj)
  frames[#frames + 1] = o
  return o
end
function Obj:SetScript(name, fn) self.scripts[name] = fn; if name == "OnUpdate" then updaters[self] = fn end end
function Obj:HookScript(name, fn) local old = self.scripts[name]; self.scripts[name] = function(...) if old then old(...) end fn(...) end end
function Obj:GetScript(name) return self.scripts[name] end
function Obj:RegisterEvent(e) eventFrames[e] = eventFrames[e] or {}; table.insert(eventFrames[e], self) end
function Obj:CreateTexture() return new("Texture", self) end
function Obj:CreateMaskTexture() return new("Mask", self) end
function Obj:CreateFontString() return new("FontString", self) end
function Obj:SetText(t) self.text = t or ""; if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self) end end
function Obj:GetText() return self.text end
function Obj:SetSize(w, h) self.w, self.h = w, h end
function Obj:SetWidth(w) self.w = w end
function Obj:SetHeight(h) self.h = h end
function Obj:GetWidth() return self.w end
function Obj:GetHeight() return self.h end
function Obj:GetStringWidth() return #self.text * 6 end
function Obj:GetUnboundedStringWidth() return #self.text * 6 end
function Obj:GetStringHeight() return 14 * math.max(1, math.ceil(#self.text * 6 / math.max(1, self.w))) end
function Obj:Show() local was = self.shown; self.shown = true; if not was and self.scripts.OnShow then self.scripts.OnShow(self) end end
function Obj:Hide() local was = self.shown; self.shown = false; if was and self.scripts.OnHide then self.scripts.OnHide(self) end end
function Obj:SetPoint(...) self.points = self.points or {}; self.points[#self.points + 1] = { ... } end
function Obj:ClearAllPoints() self.points = {} end
function Obj:SetShown(s) if s then self:Show() else self:Hide() end end
function Obj:IsShown() return self.shown end
function Obj:IsMouseOver() return false end
function Obj:GetVerticalScroll() return self.scroll end
function Obj:SetVerticalScroll(v) self.scroll = v end
function Obj:SetFont() return true end
function Obj:GetLeft() return 10 end
function Obj:GetTop() return 600 end
function Obj:GetCenter() return 500, 500 end
function Obj:Cancel() self.cancelled = true end
function Obj:GetFrameLevel() return 1 end
function Obj:NumLines() return 2 end
function Obj:SetColorTexture(r, g, b) self.color = { r, g, b } end
function Obj:SetRotation(r) self.rotation = r end
function Obj:SetHyperlinksEnabled(v) self.links = v end
function Obj:EnableKeyboard(v) self.keyboard = v end
function Obj:SetParent(p) self.parent = p end

_G.CreateFrame = function(kind, name, parent) local f = new(kind, parent, name); if name then _G[name] = f end; if kind == "GameTooltip" then _G[name .. "TextLeft1"] = new("FontString"); _G[name .. "TextLeft1"].text = "Linen Cloth"; _G[name .. "TextLeft2"] = new("FontString"); _G[name .. "TextLeft2"].text = "|cff9d9d9dTrade Goods|r" end; return f end
_G.CreateFont = function() return new("Font") end
_G.UIParent = new("Frame"); UIParent.h = 768
_G.WorldFrame = new("Frame")
_G.GameTooltip = new("GameTooltip")
_G.DEFAULT_CHAT_FRAME = new("Frame")
local chatOut = {}
function DEFAULT_CHAT_FRAME:AddMessage(m) chatOut[#chatOut + 1] = m end
_G.TargetFrame = new("Button")
_G.Minimap = new("Frame"); Minimap.w, Minimap.h = 140, 140
function Minimap:GetEffectiveScale() return 1 end
_G.GetCursorPosition = function() return _G.cursorX or 0, _G.cursorY or 0 end
_G.IsShiftKeyDown = function() return _G.shift end
_G.GetBuildInfo = function() return "1.60.1", "70790" end
_G.QuestFrame = new("Frame")
_G.UISpecialFrames = {}
_G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
_G.tinsert, _G.floor, _G.wipe = table.insert, math.floor, function(t) for k in pairs(t) do t[k] = nil end return t end
_G.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
_G.print = function(...) io.write("[print] ", table.concat({ ... }, " "), "\n") end
_G.hooksecurefunc = function(a, b, c) if type(a) == "table" then local old = a[b]; a[b] = function(...) old(...); c(...) end else hooks[a] = b end end
_G.HandleModifiedItemClick = function() end
_G.SetItemRef = function(link) _G.lastItemRef = link end
_G.IsAltKeyDown = function() return _G.alt end
_G.IsControlKeyDown = function() return _G.ctrl end
-- Key bindings: key -> action, like the client's binding set.
local bindings = { W = "MOVEFORWARD" }
_G.BINDING_NAME_MOVEFORWARD = "Move Forward"
_G.GetBindingKey = function(action) local keys = {}; for k, v in pairs(bindings) do if v == action then keys[#keys + 1] = k end end; table.sort(keys); return unpack(keys) end
_G.SetBinding = function(key, action) bindings[key] = action end
_G.GetBindingAction = function(key) return bindings[key] or "" end
_G.GetBindingText = function(key) return key end
_G.GetCurrentBindingSet = function() return 2 end
_G.SaveBindings = function(set) _G.savedBindingSet = set end
_G.Ambiguate = function(n) return (n:gsub("%-.*", "")) end
_G.issecretvalue = function(v) return v == "SECRET" end
_G.GetPhysicalScreenSize = function() return 2560, 1440 end
_G.GetTime = function() return now end
_G.GetCVar = function() return "jpeg" end
_G.SetCVar = function() end
_G.InCombatLockdown = function() return _G.inCombat == true end
-- Macros: general ones at 1..n, character ones from MAX_ACCOUNT_MACROS + 1, like the client.
_G.MAX_ACCOUNT_MACROS, _G.MAX_CHARACTER_MACROS = 120, 18
local macroBook = { general = { { name = "Reload", icon = 1, body = "/reload" } }, char = { { name = "Pet", icon = 7, body = "/cast [@pet,dead] Revive Pet; Call Pet" } } }
local function macroAt(i) if i > 120 then return macroBook.char, i - 120 end return macroBook.general, i end
_G.GetNumMacros = function() return #macroBook.general, #macroBook.char end
_G.GetMacroInfo = function(i) local list, j = macroAt(i); local m = list[j]; if m then return m.name, m.icon, m.body end end
_G.CreateMacro = function(name, icon, body, perChar) if _G.inCombat then error("combat") end; local list = perChar and macroBook.char or macroBook.general; list[#list + 1] = { name = name, icon = icon, body = body } end
_G.EditMacro = function(i, name, icon, body) local list, j = macroAt(i); list[j] = { name = name, icon = icon, body = body } end
_G.DeleteMacro = function(i) local list, j = macroAt(i); table.remove(list, j) end
_G.ReloadUI = function() print("ReloadUI called") end
local shotBytes
_G.Screenshot = function() shotBytes = true end
_G.C_Timer = { After = function(delay, fn) table.insert(timers, { at = now + (delay or 0), fn = fn }) end, NewTicker = function(_, fn) local t = new("Ticker"); t.fn = fn; _G.__ticker = t; return t end }
_G.UnitName = function(u) return u == "player" and "Backshot" or "Gnarlpine Ambusher" end
_G.GetRealmName = function() return "Forever" end
_G.UnitLevel = function() return 12 end
_G.UnitRace = function() return "Night Elf" end
_G.UnitClass = function() return "Hunter", "HUNTER" end
_G.RAID_CLASS_COLORS = { HUNTER = { r = 0.67, g = 0.83, b = 0.45 } }
_G.CreateColor = function(...) return { ... } end
_G.UnitExists = function() return true end
_G.UnitClassification = function() return "normal" end
_G.UnitIsPlayer = function() return false end
_G.UnitCreatureType = function() return "Humanoid" end
_G.UnitReaction = function() return 2 end
_G.GetGuildInfo = function() return nil end
_G.UnitHealth = function() return "SECRET" end
_G.UnitHealthMax = function() return 100 end
_G.GetNumTalentTabs = function() return 0 end
_G.GetNumQuestLogEntries = function() return 1 end
_G.GetQuestLogTitle = function() return "The Fargodeep Mine", 7, nil, false, nil, nil, nil, 62 end
_G.GetQuestLink = function() return "|cffffff00|Hquest:62:7|h[The Fargodeep Mine]|h|r" end
_G.GetMoney = function() return 123456 end
_G.GetZoneText = function() return "Teldrassil" end
_G.GetSubZoneText = function() return "Dolanaar" end
_G.GetItemInfo = function(x) if x == 2589 or tostring(x):find("2589") or x == "Linen Cloth" then return "Linen Cloth", "|cffffffff|Hitem:2589::::::::|h[Linen Cloth]|h|r", 1, 5, 0, "Trade Goods", "Cloth", 20, "", 132889 end end
_G.GetInventoryItemLink = function() return nil end
_G.GetSpellLink = function() return nil end
_G.C_Spell = { GetSpellName = function(id) return ({ [75] = "Auto Shot", [2973] = "Raptor Strike" })[id] end }
_G.CreateVector2D = function(x, y) return { x = x, y = y, GetXY = function(s) return s.x, s.y end } end
_G.C_Map = {
  GetMapInfo = function(id) if id == 1438 then return { name = "Teldrassil", mapType = 3 } elseif id == 1429 then return { name = "Elwynn Forest", mapType = 3 } end end,
  GetBestMapForUnit = function() return 1438 end,
  GetPlayerMapPosition = function() return CreateVector2D(0.5, 0.5) end,
  GetWorldPosFromMapPos = function(id, v) return (id == 1438 and 1 or 0), { x = v.x * 1000, y = v.y * 1000 } end,
}
_G.GetPlayerFacing = function() return 0 end
_G.Enum = { DamageMeterType = { DamageDone = 0, DamageTaken = 7, HealingDone = 2, Deaths = 9 }, DamageMeterSessionType = { Overall = 0, Current = 1 }, UIMapType = { Zone = 3 } }
local me = { isLocalPlayer = true, name = "Backshot", totalAmount = 1234, amountPerSecond = 41.1, sourceGUID = "Player-1", deathRecapID = 3 }
_G.C_DamageMeter = {
  GetAvailableCombatSessions = function() return { { sessionID = 1, name = "Nightsaber", durationSeconds = 8 }, { sessionID = 2, name = "Gnarlpine Ambusher", durationSeconds = 30 } } end,
  GetCombatSessionFromID = function() return { combatSources = { me } } end,
  GetCombatSessionFromType = function() return { durationSeconds = 500, combatSources = { me } } end,
  GetCombatSessionSourceFromID = function() return { combatSpells = { { spellID = 75, totalAmount = 800 }, { spellID = 2973, totalAmount = 434 } } } end,
}
_G.C_DeathRecap = { GetRecapEvents = function() return { { sourceName = "Gnarlpine Ambusher", spellName = "Melee", amount = 45, overkill = 12 } } end }
_G.SlashCmdList = {}
local slotData = {}
_G.loadstring = loadstring
local modSlots = {}
vidSlots = {}
_G.C_AddOns = { GetAddOnMetadata = function(_, field) return field == "Version" and "9.9.9" or nil end, LoadAddOn = function(name)
  local vid = tonumber(name:match("^wai_vid(%d+)$"))
  if vid then _G.WaiVideoChunk = vidSlots[vid]; vidLoads = (vidLoads or 0) + 1; return true end
  local mod = tonumber(name:match("^wai_mod(%d+)$"))
  if mod then WaiModuleDefs = WaiModuleDefs or {}; for k, v in pairs(modSlots[mod] or {}) do WaiModuleDefs[k] = v end; return true end
  _G.WaiSlot = slotData.default; return true end }

local function fire(event, ...) for _, f in ipairs(eventFrames[event] or {}) do f.scripts.OnEvent(f, event, ...) end end
local function tick(dt, n)
  for _ = 1, n or 1 do
    now = now + dt
    for f, fn in pairs(updaters) do if f.scripts.OnUpdate == fn then fn(f, dt) end end
    local pending = timers; timers = {}
    for _, t in ipairs(pending) do
      if t.at <= now then t.fn() else timers[#timers + 1] = t end
    end
  end
end
local function texts(pattern)
  local out = {}
  for _, f in ipairs(frames) do if f.kind == "FontString" and f.shown and f.text:find(pattern) then out[#out + 1] = f.text end end
  return out
end

local ns = {}
_G.WaiData = { beat = 1, chats = { ["Backshot-Forever#main"] = { ackSeq = 0, messages = { { id = 1, role = "assistant", text = "Welcome back!", at = 1, done = true } } } } }
for line in io.lines(addonDir .. "/wai.toc") do
  local path = addonDir .. "/" .. line
  local exists = io.open(path) and true
  -- Data.lua, ModuleDefs.lua and Generated.lua are written by the bridge; skip them.
  if line:match("%.lua$") and exists and line ~= "Data.lua" and line ~= "Generated.lua" and line ~= "ModuleDefs.lua" then assert(loadfile(path))("wai", ns) end
end
fire("PLAYER_LOGIN")
print("login ok")

SlashCmdList.WAI("")
assert(WaiFrame:IsShown())
ns.commands.run("/help")
assert(#texts("Ask from anywhere") == 1, "help card rendered")
print("help ok")

fire("CHAT_MSG_SAY", "anyone selling linen?", "Asukax-Forever")
-- Alt-click an item in a bag.
_G.alt = true
hooks.HandleModifiedItemClick("|cffffffff|Hitem:2589::::::::|h[Linen Cloth]|h|r")
_G.alt = false
assert(#texts("ASKING ABOUT") == 1, "attachment bar shown")
print("attach ok: " .. texts("Linen Cloth")[1])

-- Send with the attachment via the composer's Enter.
local subjectInput
for _, f in ipairs(frames) do if f.kind == "EditBox" then subjectInput = f end end
subjectInput.scripts.OnEnterPressed(subjectInput)
assert(shotBytes and #WaiDB.outbox == 1, "message queued + screenshot taken")
local item = WaiDB.outbox[1]
print("sent text: " .. item.text)
assert(item.who == "Backshot-Forever")
assert(item.ctx:find("subject: item: Linen Cloth; Trade Goods"), "subject details in context")
assert(item.ctx:find("last fight: Gnarlpine Ambusher, 30s, you dealt 1234"), "combat in context")
assert(item.ctx:find("your damage by ability: Auto Shot 800, Raptor Strike 434"), "spell breakdown")
assert(item.ctx:find("last death, final hits: Gnarlpine Ambusher Melee 45"), "death recap")
assert(not item.ctx:find("health"), "secret health skipped")
assert(item.ctx:find("recent chat: \n%[say%] Asukax: anyone selling linen%?"), "recent chat in context")
print("context:\n" .. item.ctx)

-- Decode the painted grid back from the 3-bit blocks.
local grid
for _, f in ipairs(frames) do if f.kind == "Frame" and f.children == nil and f.blocksProbe then grid = f end end
local blocks = {}
for _, f in ipairs(frames) do if f.kind == "Texture" and f.color and not (f.color[1] == 1 and f.color[2] == 0 and f.color[3] == 1 and #blocks == 0) then blocks[#blocks + 1] = f end end
local bits = {}
for _, b in ipairs(blocks) do for c = 1, 3 do bits[#bits + 1] = b.color[c] end end
local bytes = {}
for i = 0, #bits / 8 - 1 do local v = 0; for j = 1, 8 do v = v * 2 + bits[i * 8 + j] end; bytes[#bytes + 1] = v end
assert(string.char(bytes[1], bytes[2], bytes[3]) == "WAI" and bytes[4] == 2, "header WAI v2")
local len = bytes[10] * 256 + bytes[11]
local payload = string.char(unpack(bytes, 12, 11 + len))
assert(payload:find("\0Backshot%-Forever$"), "who at the end")
print("grid decode ok, payload " .. len .. " bytes")
fire("SCREENSHOT_SUCCEEDED")

-- Bridge streams a reply with markup over a few polls.
local reply = "Sell [[item:2589:Linen Cloth]] or make bandages. Head to the inn [[setway:Teldrassil:56.2,60.1:Dolanaar Inn]] and talk to [[npc:Innkeeper Keldamyr]], or try [[way:Teldrassil:55,57:the trainer]]. [[remember:wants to level First Aid]]"
for step = 1, 4 do
  slotData.default = { who = "Backshot-Forever", beat = step, chats = { main = { ackSeq = item.seq, busy = step < 4, activity = step == 2 and "Searching the web for \"linen\"" or nil, messages = {
    { id = 2, role = "user", text = item.text, at = 2 },
    { id = 3, role = "assistant", text = reply:sub(1, step * 60), done = step == 4, at = 3 },
  } } } }
  now = now + 1
  __ticker.fn()
  if step == 2 then tick(0.01) assert(#texts("Searching the web for \"linen\"…") == 1, "activity line shown mid-stream") end
  tick(0.033, 40)
end
assert(#WaiDB.outbox == 0)
local rendered = texts("Hitem:2589")
assert(#rendered >= 1, "waypoint link rendered")
print("rendered reply: " .. rendered[#rendered])
assert(rendered[#rendered]:find("|Hitem:2589"), "item link")
assert(rendered[#rendered]:find("Noted: wants to level First Aid"), "remember shown")
assert(WaiCharDB.notes[1] == "wants to level First Aid", "remember stored")
print("stream + markup ok")

-- Hidden tokens on their own lines (TikTok mode's stream reactions) leave no blank space behind.
local tail = ns.links.render("Use it for travel.\n\nSources: none\n\n[[stream:a:b]]\n[[stream:c:d]]\n")
assert(tail == "Use it for travel.\n\nSources: none", "trailing hidden tokens trimmed: " .. tail)
assert(ns.links.render("[[title:Hi]]\nOne\n\n[[stream:a:b]]\n\nTwo") == "One\n\nTwo", "hidden lines collapse")
local function shownText(s) for _, f in ipairs(frames) do if f.kind == "FontString" and f.text == s and f.shown then return f end end end
assert(not shownText("Ready"), "an idle window shows no status")
print("blank lines + idle status ok")

-- The agent's setway placed the arrow on its own.
assert(WaiWaypoint and WaiWaypoint:IsShown(), "arrow set automatically")
assert(WaiCharDB.way.title == "Dolanaar Inn")
tick(0.05, 3)
print("waypoint: " .. table.concat(texts("yards"), ",") .. " rotation=" .. tostring((function() for _, f in ipairs(frames) do if f.rotation then return f.rotation end end end)()))
assert(#texts("yards") == 1)

-- Agent forgets a note and clears the arrow in a later reply.
WaiCharDB.notes[#WaiCharDB.notes + 1] = "saving for a mount"
slotData.default = { who = "Backshot-Forever", beat = 10, chats = { main = { ackSeq = item.seq, busy = false, messages = {
  { id = 4, role = "assistant", text = "Done. [[forget:first aid]] [[setway:clear]]", done = true, at = 4 },
} } } }
ns.commands.run("/help") -- any activity; then poll once
local tk = _G.__ticker
SlashCmdList.WAI("ping") ; fire("SCREENSHOT_SUCCEEDED"); now = now + 1; __ticker.fn()
assert(#WaiCharDB.notes == 1 and WaiCharDB.notes[1] == "saving for a mount", "forget removed only first aid")
assert(not WaiWaypoint:IsShown(), "arrow cleared")
for _, gone in ipairs({ "/way 1 2", "/remember x", "/combat" }) do ns.commands.run(gone) end
assert(#texts("Unknown command /way") == 1 and #texts("Unknown command /combat") == 1)
print("agent actions ok")

-- Tabs: open a second chat, send there, and get an unread reply on the first tab.
ns.commands.run("/new")
local tabs = ns.core.tabs()
assert(#tabs == 2 and tabs[2].active and tabs[2].name == "New chat", "new tab active")
SlashCmdList.WAI("best leveling route for a hunter")
local sent = WaiDB.outbox[#WaiDB.outbox]
assert(sent.tab == tabs[2].id, "message tagged with tab")
assert(ns.core.tabs()[2].name == "best leveling route fo", "tab auto-named")
fire("SCREENSHOT_SUCCEEDED")
slotData.default = { who = "Backshot-Forever", beat = 20, chats = {
  main = { ackSeq = sent.seq - 1, busy = false, messages = { { id = 9, role = "assistant", text = "Background answer in main", done = true, at = 9 } } },
  [tabs[2].id] = { ackSeq = sent.seq, busy = true, activity = "Thinking", messages = { { id = 8, role = "user", text = sent.text, at = 8 } } },
} }
now = now + 2; __ticker.fn(); tick(0.01)
assert(ns.core.tabs()[1].unread, "main tab marked unread")
assert(ns.core.tabs()[2].busy, "second tab busy")
assert(#texts("Background answer") == 0, "other tab's reply not shown in this tab")
ns.core.switchTab("main")
assert(#texts("Background answer in main") == 1 and not ns.core.tabs()[1].unread, "switching shows it and clears unread")
ns.core.renameTab(tabs[2].id, "Routes")
assert(ns.core.tabs()[2].name == "Routes")
print("tabs ok")

-- A stalled bridge: busy with no heartbeat triggers one silent re-sync ping, then an error banner.
local shotsBefore = 0
_G.Screenshot = function() shotsBefore = shotsBefore + 1 end
now = now + 30; __ticker.fn()
assert(shotsBefore == 1, "auto re-sync ping")
fire("SCREENSHOT_SUCCEEDED")
now = now + 30; __ticker.fn(); tick(0.01)
assert(#texts("Lost touch with the bridge") == 1, "stale banner")
print("durability ok")

-- UI modules: a slot snapshot announces a new module in a module slot; it loads live, then hides on request.
modSlots[1] = { ["gold-tracker"] = { version = 1, code = "local wai = ...; local f = CreateFrame('Frame', 'WaiGoldTracker', UIParent); f.madeWithTheme = wai.theme ~= nil; return f" } }
ns.core.switchTab(tabs[2].id)
SlashCmdList.WAI("build me a gold tracker"); fire("SCREENSHOT_SUCCEEDED")
local s2 = WaiDB.outbox[#WaiDB.outbox]
slotData.default = { who = "Backshot-Forever", beat = 30, modules = { ["gold-tracker"] = { version = 1, slot = 1 } }, chats = {
  [tabs[2].id] = { ackSeq = s2.seq, busy = false, messages = { { id = 12, role = "assistant", text = "Built it. [[ui:hide:gold-tracker]]", done = true, at = 12 } } },
} }
now = now + 2; __ticker.fn()
assert(WaiGoldTracker and WaiGoldTracker.madeWithTheme, "module loaded live with the wai API")
assert(not WaiGoldTracker:IsShown() and WaiCharDB.hiddenModules["gold-tracker"], "agent hid it")
print("modules ok")

-- Killstreaks: XP + slain messages for one kill count once; 11 and 25 trigger the overlays; death resets.
_G.SOUNDKIT = { RAID_WARNING = 1, PVP_THROUGH_QUEUE = 2 }
_G.PlaySound = function() end
for i = 1, 25 do
  now = now + 2
  fire("CHAT_MSG_COMBAT_HOSTILE_DEATH", "You have slain Gnarlpine Ambusher!")
  fire("CHAT_MSG_COMBAT_XP_GAIN", "Gnarlpine Ambusher dies, you gain 120 experience.")
  if i == 11 then tick(0.1, 5); assert(#texts("CHOPPER GUNNER") == 1, "chopper at 11") end
end
assert(ns.streak.count() == 25)
tick(0.5, 4)
assert(#texts("TACTICAL NUKE INCOMING") == 1, "nuke at 25")
assert(ns.context.collect():find("killstreak: 25 kills"), "streak in context")
fire("PLAYER_DEAD")
assert(ns.streak.count() == 0)
tick(1, 15)
print("killstreak ok")

-- Video: loading, then ready; 2 chunks of 24 frames, 45x80. Frame k is solid colour code k.
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function frame(code) local c = B64:sub(math.floor(code / 64) + 1, math.floor(code / 64) + 1) .. B64:sub(code % 64 + 1, code % 64 + 1); return c:rep(45 * 80) end
for chunk = 1, 2 do
  local frames = {}
  for i = 1, 24 do frames[i] = frame(((chunk - 1) * 24 + i) * 80) end
  vidSlots[chunk] = { id = "v1", chunk = chunk, frames = frames }
end
local function videoSlot(v, extra) slotData.default = { who = "Backshot-Forever", beat = 40 + (extra or 0), video = v, chats = { main = { ackSeq = WaiDB.seq, busy = false, messages = {} } } } end
ns.core.switchTab("main")
SlashCmdList.WAI("turn on tiktok mode"); fire("SCREENSHOT_SUCCEEDED")
-- The reply turns TikTok mode on and adds stream reactions; the clip is still loading.
slotData.default = { who = "Backshot-Forever", beat = 41, video = { id = "v1", status = "loading", title = "subway surfers gameplay", loop = true }, chats = { main = { ackSeq = WaiDB.seq, busy = true, activity = "Loading video", messages = {
  { id = 20, role = "assistant", text = "TikTok mode activated, no cap. [[tiktok:on]] [[clip:subway surfers gameplay]] [[stream:xXgankerXx:W streamer]] [[stream:moonkin420:subway surfers in azeroth lmao]]", done = true, at = 20 },
} } } }
now = now + 2; __ticker.fn(); tick(0.05)
assert(WaiCharDB.tiktok and WaiVideo and WaiVideo:IsShown(), "tiktok player shown")
assert(#texts("Loading video…") == 2 and #texts("^LIVE") == 1, "loading state in player and activity line")
assert(#texts("xXgankerXx") == 0, "stream tokens hidden from the reply")
videoSlot({ id = "v1", status = "ready", title = "Subway Surfers 2 Hours", w = 45, h = 80, fps = 8, base = 1, chunks = 2, loop = true }, 2)
now = now + 2; __ticker.fn()
tick(0.125, 3)
local painted = 0
for _, f in ipairs(frames) do if f.kind == "Texture" and f.color and f.parent and f.parent.kind == "Button" and f.color[1] then painted = painted + 1 end end
assert(painted >= 3600, "3600 blocks painted, got " .. painted)
tick(0.125, 30) -- past chunk 1: chunk 2 prefetched
assert(vidLoads == 2, "both chunks loaded once, got " .. tostring(vidLoads))
tick(0.125, 30) -- past the end: loops without reloading
assert(vidLoads == 2, "loop reuses frames")
tick(1.2, 3)
assert(#texts("W streamer") == 1 and #texts("subway surfers in azeroth") == 1, "stream chat dripped in")
assert(#texts("TikTok mode activated, no cap.") >= 1, "caption shown")
assert(ns.context.collect():find("mode: TikTok mode is on"), "mode in context")
ns.video.setTikTok(false)
assert(not WaiVideo:IsShown(), "tiktok off closes the looping clip")
print("video ok")

-- Fun tab in Settings: toggles and test buttons work; /fun is gone.
local function click(label)
  for _, f in ipairs(frames) do
    if f.kind == "Button" and f.label and f.label.text == label and f.scripts.OnClick then return f.scripts.OnClick(f, "LeftButton") end
  end
  error("no button " .. label)
end
local function lastPayload()
  local blocks = {}
  for _, f in ipairs(frames) do if f.kind == "Texture" and f.color and f.parent and f.parent.kind == "Frame" and not f.parent.name and #blocks < 8192 and f.color[1] ~= nil and f.w and f.w < 3 then blocks[#blocks + 1] = f end end
  local bits = {}
  for _, b in ipairs(blocks) do for c = 1, 3 do bits[#bits + 1] = b.color[c] end end
  local bytes = {}
  for i = 0, 40 do local v = 0; for j = 1, 8 do v = v * 2 + (bits[i * 8 + j] or 0) end; bytes[#bytes + 1] = v end
  return bytes[9], string.char(unpack(bytes, 12, 30))
end
ns.commands.run("/fun")
assert(#texts("Unknown command /fun") == 1, "/fun is gone")
ns.settings.toggle("fun")
assert(WaiSettings:IsShown() and ns.settings.tab() == "fun", "settings open on the Fun tab")
local toggleRows = {}
for _, f in ipairs(frames) do if f.kind == "Button" and f.label and (f.label.text == "TikTok mode" or f.label.text == "Killstreaks") then toggleRows[f.label.text] = f end end
WaiCharDB.tiktok = nil
_G.Screenshot = function() end
toggleRows["TikTok mode"].scripts.OnClick(toggleRows["TikTok mode"])
assert(WaiCharDB.tiktok and WaiVideo:IsShown(), "tiktok toggled on")
local kind, text = lastPayload()
assert(kind == 4 and text:find("^clip:subway surfers"), "requested a clip directly, got kind " .. tostring(kind) .. " " .. tostring(text))
assert(ns.video.loading(), "waiting on the clip keeps polling alive")
fire("SCREENSHOT_SUCCEEDED")
toggleRows["Killstreaks"].scripts.OnClick(toggleRows["Killstreaks"])
assert(WaiCharDB.killstreaksOff)
now = now + 5; fire("CHAT_MSG_COMBAT_HOSTILE_DEATH", "You have slain Wolf!")
assert(ns.streak.count() == 0, "killstreaks off: kills not counted")
click("+1 kill"); assert(ns.streak.count() == 1, "+1 kill test works even when off")
click("Reset streak"); assert(ns.streak.count() == 0)
click("Chopper Gunner"); tick(0.1, 2); assert(#texts("CHOPPER GUNNER") >= 1)
click("Nuke"); tick(0.5, 2); assert(#texts("TACTICAL NUKE INCOMING") >= 1)
click("Stream chat"); tick(1.2, 8); assert(#texts("chat is this real") == 1, "fake stream chat")
click("Play a video")
kind, text = lastPayload()
assert(kind == 4 and text:find("^video:subway"), "requested a landscape video")
ns.settings.toggle("about"); assert(WaiSettings:IsShown() and ns.settings.tab() == "about", "another tab switches instead of closing")
ns.settings.toggle("about"); assert(not WaiSettings:IsShown(), "the same tab closes it")
print("settings height: " .. WaiSettings:GetHeight())
assert(WaiSettings:GetHeight() < 520, "tabs keep settings well under a 768-unit screen")
print("fun tab ok")

-- Updates: a slot announces a newer release; the banner offers Update; /update sends kind 5 and
-- status lines from the bridge show up as note cards.
slotData.default = { who = "Backshot-Forever", beat = 60, update = { version = "0.2.0" }, chats = { main = { ackSeq = WaiDB.seq, busy = false, messages = {} } } }
ns.core.sync(); fire("SCREENSHOT_SUCCEEDED"); fire("SCREENSHOT_SUCCEEDED"); now = now + 2; __ticker.fn(); tick(0.01)
assert(#texts("wai 0.2.0 is available.") == 1, "update banner")
_G.Screenshot = function() end
ns.commands.run("/update")
local kindU = lastPayload()
assert(kindU == 5, "update request sent, kind " .. tostring(kindU))
fire("SCREENSHOT_SUCCEEDED")
slotData.default = { who = "Backshot-Forever", beat = 61, chats = { main = { ackSeq = WaiDB.seq, busy = false, messages = {
  { id = 30, role = "status", text = "Downloading wai 0.2.0…", done = true, at = 30 },
  { id = 31, role = "status", text = "Updated to wai 0.2.0. Restart WoW to load the new addon.", done = true, at = 31 },
} } } }
now = now + 2; __ticker.fn(); tick(0.01)
assert(#texts("Restart WoW to load the new addon") == 1 and not ns.core.view().update, "status lines shown, update notice cleared")
print("update ok")

-- Settings: /settings opens the panel; typing speed, whispers, window reset, about, updates.
ns.commands.run("/settings")
assert(WaiSettings and WaiSettings:IsShown(), "settings opens")
tick(1.1, 1)
assert(#texts("wai 9.9.9") == 1, "about shows the version")
local function clickText(label)
  for _, f in ipairs(frames) do
    if f.kind == "Button" and ((f.label and f.label.text == label) or (f.text and f.text.text == label)) and f.scripts.OnClick then return f.scripts.OnClick(f, "LeftButton") end
  end
  error("no button " .. label)
end
clickText("Instant")
assert(ns.settings.get("typing") == "instant", "typing instant")
-- Instant: a live streamed reply shows in full immediately.
ns.core.switchTab("main"); ns.ui.show()
slotData.default = { who = "Backshot-Forever", beat = 70, chats = { main = { ackSeq = WaiDB.seq, busy = true, messages = {
  { id = 40, role = "assistant", text = "Instant text appears all at once without typing", done = false, at = 40 },
} } } }
ns.core.sync(); fire("SCREENSHOT_SUCCEEDED"); now = now + 2; __ticker.fn(); tick(0.01)
assert(#texts("Instant text appears all at once without typing") >= 1, "instant typing (also captioned while TikTok mode is on)")
clickText("Normal")
-- Whispers off: a reply while wai is closed doesn't go to chat.
for _, f in ipairs(frames) do if f.kind == "Button" and f.label and f.label.text == "Whisper replies" then f.scripts.OnClick(f) end end
assert(ns.settings.get("whisper") == false, "whisper off")
WaiFrame:Hide()
local before = #chatOut
slotData.default = { who = "Backshot-Forever", beat = 71, chats = { main = { ackSeq = WaiDB.seq, busy = false, messages = {
  { id = 41, role = "assistant", text = "quiet reply", done = true, at = 41 },
} } } }
now = now + 2; __ticker.fn(); tick(0.01)
assert(#chatOut == before, "no whisper when turned off")
-- Reset window positions.
WaiDB.ui = { x = 1, y = 2, w = 3, h = 4 }
clickText("Reset window positions")
assert(WaiDB.ui == nil and WaiFrame.w == 420, "positions reset")
-- Check for updates sends an update request.
_G.Screenshot = function() end
fire("SCREENSHOT_SUCCEEDED")
clickText("Check for updates")
assert(lastPayload() == 5, "check for updates sends kind 5")
fire("SCREENSHOT_SUCCEEDED")
assert(not WaiSettings:IsShown(), "settings closed with the chat window")
ns.commands.run("/settings"); assert(WaiSettings:IsShown() and WaiFrame:IsShown(), "/settings reopens both")
ns.commands.run("/settings"); assert(not WaiSettings:IsShown(), "/settings toggles closed")
print("settings ok")

-- Minimap button: built at login; clicks open chat, settings, fun; drag saves an angle; the status
-- dot follows busy/unread tabs; Settings can hide it.
local mm = WaiMinimapButton
assert(mm and mm:IsShown(), "minimap button shown")
WaiFrame:Hide(); if WaiSettings then WaiSettings:Hide() end; 
mm.scripts.OnClick(mm, "LeftButton"); assert(WaiFrame:IsShown(), "left-click opens chat")
mm.scripts.OnClick(mm, "LeftButton"); assert(not WaiFrame:IsShown(), "left-click closes chat")
mm.scripts.OnClick(mm, "RightButton"); assert(WaiSettings:IsShown(), "right-click opens settings")
_G.shift = true; mm.scripts.OnClick(mm, "RightButton"); _G.shift = false
assert(WaiSettings:IsShown() and ns.settings.tab() == "fun", "shift-right-click switches settings to Fun")
-- Drag: cursor straight above the minimap centre (GetCenter is 500,500 in the stub) = 90 degrees.
_G.cursorX, _G.cursorY = 500, 600
mm.scripts.OnDragStart(mm); mm.scripts.OnUpdate(mm, 0.01); mm.scripts.OnDragStop(mm)
assert(math.abs(WaiDB.minimapAngle - 90) < 0.001, "drag saves the angle, got " .. tostring(WaiDB.minimapAngle))
-- Status dot: a busy tab shows it.
local badge
for _, f in ipairs(frames) do if f.kind == "Texture" and f.parent and f.parent.parent == mm and f.w == 9 then badge = f end end
WaiDB.outbox[#WaiDB.outbox + 1] = { seq = 999, tab = "main", who = "Backshot-Forever", text = "x" }
mm.scripts.OnUpdate(mm, 0.3)
assert(badge and badge:IsShown(), "status dot while busy")
table.remove(WaiDB.outbox)
for _, c in ipairs(ns.core.tabs()) do end
-- Settings toggle hides it.
local found
for _, f in ipairs(frames) do if f.kind == "Button" and f.label and f.label.text == "Minimap button" then found = f end end
assert(found, "minimap toggle in settings")
found.scripts.OnClick(found)
assert(ns.settings.get("minimap") == false and not mm:IsShown(), "toggle hides the button")
found.scripts.OnClick(found)
assert(mm:IsShown(), "toggle shows it again")
print("minimap ok")

-- Telemetry: consent banner, flags in every payload, scrubbed reports only once opted in.
local function fullPayload()
  local blocks = {}
  for _, f in ipairs(frames) do if f.kind == "Texture" and f.color and f.parent and f.parent.kind == "Frame" and not f.parent.name and #blocks < 8192 and f.color[1] ~= nil and f.w and f.w < 3 then blocks[#blocks + 1] = f end end
  local bits = {}
  for _, b in ipairs(blocks) do for c = 1, 3 do bits[#bits + 1] = b.color[c] end end
  local function byte(i) local v = 0; for j = 1, 8 do v = v * 2 + (bits[i * 8 + j] or 0) end; return v end
  local len = byte(9) * 256 + byte(10)
  local out = {}
  for i = 11, 10 + len do out[#out + 1] = string.char(byte(i)) end
  local parts, payload = {}, table.concat(out)
  for part in (payload .. "\0"):gmatch("(.-)%z") do parts[#parts + 1] = part end
  return parts -- text, ctx, who, tab, flags, reports
end
WaiDB.settings.telemetry = nil
ns.core.switchTab("main"); ns.ui.show(); tick(0.01)
assert(ns.core.view().consent and #texts("Help improve wai with anonymous error reports") == 1, "consent banner")
local noThanks
for _, f in ipairs(frames) do if f.kind == "Button" and f.label and f.label.text == "No thanks" then noThanks = f end end
noThanks.scripts.OnClick(noThanks, "LeftButton")
assert(ns.settings.get("telemetry") == false and not ns.core.view().consent, "no thanks")
_G.Screenshot = function() end
fire("SCREENSHOT_SUCCEEDED")
ns.core.report("Backshot-Forever: boom in ui.lua")
SlashCmdList.WAI("hi")
local parts = fullPayload()
assert(parts[5] == "t=0;c=1.60.1.70790" and parts[6] == "", "opted out: flag only, no reports: " .. tostring(parts[5]))
fire("SCREENSHOT_SUCCEEDED")
for _, f in ipairs(frames) do if f.kind == "Button" and f.label and f.label.text == "Error reports" then f.scripts.OnClick(f) end end
assert(ns.settings.get("telemetry") == true, "opted in from settings")
ns.core.report("Backshot hit Forever trouble")
SlashCmdList.WAI("hello again")
parts = fullPayload()
assert(parts[5] == "t=1;c=1.60.1.70790", "opted in flag")
assert(parts[6]:find("lua_error\t<name>: boom in ui.lua", 1, true), "queued report, scrubbed: " .. parts[6])
assert(parts[6]:find("lua_error\t<name> hit <name> trouble", 1, true), "name and realm scrubbed")
assert(not parts[6]:find("Backshot"), "no character name anywhere")
fire("SCREENSHOT_SUCCEEDED")
for _, f in ipairs(frames) do if f.kind == "Button" and f.label and f.label.text == "See what's sent" then f.scripts.OnClick(f, "LeftButton") end end
assert(#texts("Never your chats, quests or names") == 1, "see what's sent explains it")
print("telemetry ok")

-- Tab titles: a reply's [[title:..]] retitles its own tab (hidden from the text, animated), never a
-- tab the player named; the context tells Claude the title and whether it may change it.
ns.core.newTab()
local titled = ns.core.tabs()[#ns.core.tabs()]
SlashCmdList.WAI("whats the best way to level a hunter from 12 to 20")
local sent = WaiDB.outbox[#WaiDB.outbox]
assert(sent.ctx:find('chat title: "whats the best way to" %(you can retitle it%)'), "context offers the title: " .. sent.ctx:match("chat title[^\n]*"))
fire("SCREENSHOT_SUCCEEDED")
ns.core.switchTab("main") -- the reply arrives while another tab is open
slotData.default = { who = "Backshot-Forever", beat = 80, chats = {
  [titled.id] = { ackSeq = sent.seq, busy = false, messages = { { id = 50, role = "assistant", text = "[[title:Hunter leveling route]]Head to Westfall first.", done = true, at = 50 } } },
} }
now = now + 2; __ticker.fn(); tick(0.01)
local function tabNamed(id) for _, t in ipairs(ns.core.tabs()) do if t.id == id then return t.name end end end
assert(tabNamed(titled.id) == "Hunter leveling route", "retitled in the background: " .. tostring(tabNamed(titled.id)))
ns.core.switchTab(titled.id); tick(0.01)
assert(#texts("Head to Westfall first.") >= 1 and #texts("%[%[title") == 0, "title token hidden")
local flashing = false
for _, f in ipairs(frames) do if f.kind == "Button" and f.flash then flashing = true end end
assert(flashing, "the new title animates in")
tick(0.05, 1)
-- A tab the player renamed keeps its name.
ns.core.renameTab(titled.id, "My route")
SlashCmdList.WAI("and after 20?")
sent = WaiDB.outbox[#WaiDB.outbox]
assert(sent.ctx:find('chat title: "My route" %(named by the player; keep it%)'), "context says keep it")
fire("SCREENSHOT_SUCCEEDED")
slotData.default = { who = "Backshot-Forever", beat = 81, chats = {
  [titled.id] = { ackSeq = sent.seq, busy = false, messages = { { id = 51, role = "assistant", text = "[[title:Hunter 20 to 30]]Then Redridge.", done = true, at = 51 } } },
} }
now = now + 2; __ticker.fn(); tick(0.01)
assert(tabNamed(titled.id) == "My route", "manual name kept")
print("tab titles ok")

-- Agents: the header says who answers. /settings switches with a ping carrying "a=codex", and the
-- bridge's snapshots have the final say (it refuses an agent that isn't installed).
ns.core.switchTab("main"); ns.ui.show(); tick(0.01)
assert(ns.core.agent() == "claude" and #texts("powered by Claude") == 1, "Claude by default")
if not WaiSettings:IsShown() then ns.commands.run("/settings") end
clickText("Codex")
parts = fullPayload()
assert(parts[5]:find(";a=codex$"), "the switch carries the agent: " .. parts[5])
assert(ns.core.agent() == "codex" and #texts("powered by Codex") == 1, "header follows right away")
fire("SCREENSHOT_SUCCEEDED")
slotData.default = { who = "Backshot-Forever", beat = 90, agent = "codex", chats = { main = { ackSeq = WaiDB.seq, busy = false, messages = {
  { id = 60, role = "status", text = "Codex answers from now on.", done = true, at = 60 },
} } } }
now = now + 2; __ticker.fn(); tick(0.01)
assert(#texts("Codex answers from now on") == 1, "the bridge confirms in chat")
SlashCmdList.WAI("hi codex")
parts = fullPayload()
assert(not parts[5]:find("a="), "ordinary messages don't carry the agent: " .. parts[5])
fire("SCREENSHOT_SUCCEEDED")
slotData.default = { who = "Backshot-Forever", beat = 91, agent = "claude", chats = { main = { ackSeq = WaiDB.seq, busy = false, messages = {} } } }
now = now + 2; __ticker.fn(); tick(1.1, 1)
assert(ns.core.agent() == "claude" and #texts("powered by Claude") == 1, "the bridge's answer wins")
print("agents ok")

-- Copying: clicking a message swaps it for a read-only edit box holding its plain text, all
-- selected; a click on a link doesn't; edits revert; Esc puts the message back.
assert(ns.links.plain("|cffffffff|Hitem:2589|h[Linen Cloth]|h|r at |cff3fa0ff|Hwai:way:T:1:2:Inn|h|Tpin:13:13:0:-1|t Inn|h|r, a||rb") == "[Linen Cloth] at Inn, a|rb", "plain text for copying")
local card
for _, f in ipairs(frames) do
  if f.scripts.OnMouseUp and f.links and f.shown then
    for _, c in ipairs(frames) do if c.parent == f and c.kind == "FontString" and c.shown and c.text:find("Codex answers") then card = f end end
  end
end
assert(card, "the note row is selectable")
card.overLink = true; card.scripts.OnMouseUp(card, "LeftButton")
local function selector() for _, f in ipairs(frames) do if f.kind == "EditBox" and f.plain then return f end end end
assert(not selector(), "clicking a link doesn't select")
card.overLink = false; card.scripts.OnMouseUp(card, "LeftButton")
local sel = selector()
assert(sel and sel.shown and sel.text == "Codex answers from now on." and sel.parent == card, "click selects the message's text")
assert(#texts("Codex answers") == 0 and #texts("^Ctrl%+C to copy") == 1, "the edit box replaces the text and the footer explains")
sel.text = "Codex answers from now on.x"; sel.scripts.OnTextChanged(sel, true)
assert(sel.text == "Codex answers from now on.", "read-only")
sel.scripts.OnEscapePressed(sel)
assert(not sel.shown and #texts("Codex answers") == 1 and #texts("Enter to send") == 1, "Esc puts the message back")
print("copy ok")

-- Macros: the list rides along when the player mentions macros; a reply's macro block creates a
-- character macro (or replaces one by name), shows as a card, and combat defers it.
SlashCmdList.WAI("what does my pet macro do?")
sent = WaiDB.outbox[#WaiDB.outbox]
local listed = sent.ctx
assert(listed:find("1 of 18 character slots, 1 of 120 general slots used") and listed:find("%- Pet %(character%): /cast %[@pet,dead%] Revive Pet; Call Pet"), "macros in context: " .. sent.ctx)
SlashCmdList.WAI("hello")
assert(not WaiDB.outbox[#WaiDB.outbox].ctx:find("macros:"), "no macro list otherwise")
fire("SCREENSHOT_SUCCEEDED")
local heal = "[[macro:Mouseover Heal]]\n#showtooltip\n/cast [@mouseover,help,nodead][] Flash Heal\n[[/macro]]\nDrag it from /macro to your bars. [[macro:Pet]]\n/cast Call Pet\n[[/macro]][[macro:Wave:general]]\n/wave\n[[/macro]][[delmacro:Reload]]"
slotData.default = { who = "Backshot-Forever", beat = 95, chats = { main = { ackSeq = WaiDB.seq, busy = false, messages = {
  { id = 70, role = "assistant", text = heal:sub(1, 60), done = false, at = 70 },
} } } }
now = now + 2; __ticker.fn(); tick(1, 3)
assert(#texts("Writing a macro") == 1 and #texts("#showtooltip") == 0, "a streaming macro shows a placeholder")
assert(#macroBook.char == 1, "nothing saved before the reply is done")
slotData.default.beat = 96
slotData.default.chats.main.messages[1] = { id = 70, role = "assistant", text = heal, done = true, at = 70 }
now = now + 2; __ticker.fn(); tick(0.05, 300)
assert(macroBook.char[2] and macroBook.char[2].name == "Mouseover Heal" and macroBook.char[2].body == "#showtooltip\n/cast [@mouseover,help,nodead][] Flash Heal", "new macros are per character")
assert(macroBook.char[2].icon == "INV_MISC_QUESTIONMARK", "icon follows the spell")
assert(macroBook.char[1].body == "/cast Call Pet" and macroBook.char[1].icon == 7, "same name edits in place, keeping the icon")
assert(macroBook.general[1] and macroBook.general[1].name == "Wave", "general on request, Reload deleted")
assert(#texts("Macro Mouseover Heal %(this character%)") == 1 and #texts("Drag it from /macro") >= 1, "the macro renders as a card")
assert(#texts("Flash Heal|r\n\nDrag it from /macro to your bars%. \n|cff8c6f3aMacro Pet") == 1, "cards sit on their own lines")
assert(#texts("%[@mouseover,help,nodead%]%[%] Flash Heal") == 1 and #texts("%[%[") == 0, "body shown, no raw markup")
-- In combat the change waits for PLAYER_REGEN_ENABLED.
_G.inCombat = true
slotData.default.beat = 97
slotData.default.chats.main.messages[2] = { id = 71, role = "assistant", text = "[[macro:Pet]]\n/cast Revive Pet\n[[/macro]]", done = true, at = 71 }
now = now + 2; __ticker.fn(); tick(1, 3)
assert(macroBook.char[1].body == "/cast Call Pet" and #texts("Macro Pet changes after combat") == 1, "deferred in combat")
_G.inCombat = false
fire("PLAYER_REGEN_ENABLED")
assert(macroBook.char[1].body == "/cast Revive Pet", "applied after combat")
-- Over WoW's limits: explained, not saved.
ns.macros.save("A name far too long for wow", "/wave")
ns.macros.save("Long", ("x"):rep(256))
assert(#texts("at most 16 characters") == 1 and #texts("WoW allows 255") == 1 and #macroBook.char == 2, "limits")
print("macros ok")

-- Tab menu: right-click opens Rename / Delete instead of closing; Delete needs a second click.
ns.core.newTab()
local before = #ns.core.tabs()
local victim = ns.core.tabs()[before]
local function tabFor(id) for _, f in ipairs(frames) do if f.kind == "Button" and f.state and f.state.id == id and f.shown then return f end end end
local tb = tabFor(victim.id)
tb.scripts.OnClick(tb, "RightButton")
assert(#ns.core.tabs() == before and WaiTabMenu:IsShown(), "right-click opens the menu, keeps the tab")
clickText("Rename")
assert(not WaiTabMenu:IsShown(), "picking an item closes the menu")
local renamerBox; for _, f in ipairs(frames) do if f.kind == "EditBox" and f.id == victim.id then renamerBox = f end end
assert(renamerBox and renamerBox.shown and renamerBox.text == victim.name, "Rename edits the name inline")
renamerBox:Hide()
tb.scripts.OnClick(tb, "RightButton")
clickText("Delete")
assert(#ns.core.tabs() == before and #texts("Click again to delete") == 1, "first click asks")
clickText("Click again to delete")
assert(#ns.core.tabs() == before - 1 and not WaiTabMenu:IsShown(), "second click deletes")
-- A click anywhere else just closes it.
tb = tabFor(ns.core.tabs()[1].id)
tb.scripts.OnClick(tb, "RightButton")
local outside
for _, f in ipairs(frames) do if f.kind == "Button" and f.parent == UIParent and f.shown and not f.label and f.scripts.OnClick and not f.name then outside = f end end
outside.scripts.OnClick(outside, "LeftButton")
assert(not WaiTabMenu:IsShown() and not outside.shown, "a click outside closes the menu")
assert(#ns.core.tabs() == before - 1, "closing the menu changes nothing")
print("tab menu ok")

-- Keybind: click the key button in /settings, press a combo; it replaces wai's old key, says what
-- the new key used to do, and saves. Modifiers alone wait; Esc cancels; right-click clears.
if not WaiSettings:IsShown() then ns.commands.run("/settings") end
local keyButton
for _, f in ipairs(frames) do if f.kind == "Button" and f.label and f.label.text == "Not set" and f.scripts.OnKeyDown then keyButton = f end end
assert(keyButton, "the Toggle wai row shows Not set")
local hintClear = false
for _, f in ipairs(frames) do
  if f.kind == "FontString" and f.text == "Opens and closes the chat" then
    for _, pt in ipairs(f.points or {}) do if pt[1] == "RIGHT" and pt[2] == keyButton then hintClear = true end end
  end
end
assert(hintClear, "the hint stops at the key button")
keyButton.scripts.OnClick(keyButton, "LeftButton")
assert(keyButton.label.text == "Press a key…", "waits for a key")
keyButton.scripts.OnKeyDown(keyButton, "LCTRL")
assert(keyButton.label.text == "Press a key…", "a modifier alone isn't a key")
keyButton.scripts.OnKeyDown(keyButton, "ESCAPE")
assert(keyButton.label.text == "Not set" and next({ GetBindingKey("WAI_TOGGLE") }) == nil, "Esc cancels")
keyButton.scripts.OnClick(keyButton, "LeftButton")
_G.ctrl = true; keyButton.scripts.OnKeyDown(keyButton, "Y"); _G.ctrl = false
assert(bindings["CTRL-Y"] == "WAI_TOGGLE" and keyButton.label.text == "Ctrl-Y" and _G.savedBindingSet == 2, "binds and saves")
keyButton.scripts.OnClick(keyButton, "LeftButton")
keyButton.scripts.OnKeyDown(keyButton, "W")
assert(bindings.W == "WAI_TOGGLE" and bindings["CTRL-Y"] == nil, "a new key replaces wai's old one")
assert(#texts("^Replaced Move Forward$") == 1, "says what the key used to do")
_G.inCombat = true
keyButton.scripts.OnClick(keyButton, "LeftButton"); keyButton.scripts.OnKeyDown(keyButton, "K")
assert(bindings.K == nil and #texts("can't change in combat") == 1, "locked in combat")
_G.inCombat = false
keyButton.scripts.OnClick(keyButton, "RightButton")
assert(bindings.W == nil and keyButton.label.text == "Not set", "right-click clears")
-- Opening wai with that key doesn't type the key's character (Ctrl-` would type "`").
WaiFrame:Hide()
subjectInput:SetText("half a thought")
WaiToggle()
assert(WaiFrame:IsShown(), "the key opens wai")
subjectInput.text = "half a thought`"; subjectInput.scripts.OnChar(subjectInput, "`")
assert(subjectInput.text == "half a thought", "the key's character is dropped, the draft kept")
now = now + 1
subjectInput.text = "half a thought!"; subjectInput.scripts.OnChar(subjectInput, "!")
assert(subjectInput.text == "half a thought!", "typing afterwards works")
subjectInput:SetText("")
WaiToggle()
assert(not WaiFrame:IsShown(), "the key closes wai again")
-- While typing, bindings don't run: the input itself closes wai on the toggle key, keeping the draft.
bindings["CTRL-`"] = "WAI_TOGGLE"
WaiToggle(); now = now + 1
subjectInput:SetText("draft")
_G.ctrl = true; subjectInput.scripts.OnKeyDown(subjectInput, "`"); _G.ctrl = false
subjectInput.text = "draft`"; subjectInput.scripts.OnChar(subjectInput, "`")
assert(not WaiFrame:IsShown() and subjectInput.text == "draft", "the key closes wai from the input")
subjectInput.scripts.OnKeyDown(subjectInput, "`")
assert(not WaiFrame:IsShown(), "the plain key isn't the toggle")
WaiToggle(); now = now + 1
subjectInput.scripts.OnKeyDown(subjectInput, "`")
assert(WaiFrame:IsShown(), "without Ctrl the input keeps typing")
bindings["CTRL-`"] = nil
subjectInput:SetText("")
print("keybind ok")

-- Update track: Nightly in /settings goes to the bridge on a ping ("u=nightly"); the bridge's
-- snapshot has the final say.
assert(ns.core.track() == "stable", "stable by default")
clickText("Nightly")
parts = fullPayload()
assert(parts[5]:find(";u=nightly$"), "the switch carries the track: " .. parts[5])
assert(ns.core.track() == "nightly", "shown right away")
fire("SCREENSHOT_SUCCEEDED")
slotData.default = { who = "Backshot-Forever", beat = 120, track = "nightly", chats = { [ns.core.tabs()[1].id] = { ackSeq = WaiDB.seq, busy = false, messages = {} } } }
now = now + 2; __ticker.fn(); tick(0.01)
assert(ns.core.track() == "nightly", "bridge confirms")
slotData.default = { who = "Backshot-Forever", beat = 121, track = "stable", chats = {} }
now = now + 2; __ticker.fn(); tick(1.1, 1)
assert(ns.core.track() == "stable", "the bridge's answer wins")
ns.settings.toggle(); ns.settings.toggle() -- reopen to refresh the About lines
assert(#texts("^wai %d") == 1 and #texts("^Bridge: ") == 1 and #texts("·  bridge") == 0, "About: version and bridge on their own lines")
print("track ok")

-- Context: the bridge remembers slow fields (epoch from its snapshot), so a full quest log, talents
-- and 400 completed quests all get through even with General chat at its busiest.
_G.GetNumQuestLogEntries = function() return 20 end
local progress = {}
_G.GetQuestLogTitle = function(i) return "Quest number " .. i .. " with a long name", 10 + i, nil, false, nil, i % 5 == 0 and 1 or nil, nil, 1000 + i end
_G.GetNumQuestLeaderBoards = function() return 2 end
_G.GetQuestLogLeaderBoard = function(j, i) return ("Gnarlpine thing %d slain: %d/10"):format(j, progress[i] or 3) end
local completed = {}
for i = 1, 400 do completed[i] = (i * 7919) % 90000 + 1 end -- spread out like real IDs
_G.C_QuestLog = { GetAllCompletedQuestIDs = function() local copy = {} for i, v in ipairs(completed) do copy[i] = v end return copy end }
for i = 1, 30 do fire("CHAT_MSG_CHANNEL", ("spam %d "):format(i) .. ("x"):rep(240), "Spammer" .. i, nil, nil, nil, nil, nil, nil, "General - Teldrassil") end
slotData.default = { who = "Backshot-Forever", beat = 130, ctxEpoch = "e1", chats = {} }
now = now + 2; __ticker.fn(); tick(1.1, 1)
assert(ns.core.ctxEpoch() == "e1", "epoch from the bridge")
local function decode(value, into) local prev, n = 0, 0; for part in value:gmatch("[^,]+") do n = n + 1; local v = tonumber(part, 36); prev = n == 1 and v or prev + v; into[prev] = true end end
local got, ctxs = {}, {}
local function ask(text)
  SlashCmdList.WAI(text)
  local m = WaiDB.outbox[#WaiDB.outbox]
  ctxs[#ctxs + 1] = m.ctx
  assert(#m.text + 1 + #m.ctx <= ns.core.room("") , "fits the screenshot")
  for key, value in m.ctx:gmatch("\n?(done%+?): ([^\n]*)") do decode(value, got) end
  fire("SCREENSHOT_SUCCEEDED")
  return m.ctx
end
local first = ask("where do i go next?")
assert(first:find("character: ") and first:find("talents: ") and first:find("Quest number 20 with a long name #1020"), "the full quest log fits: " .. #first)
assert(first:find("Gnarlpine thing 2 slain: 3/10") and first:find("#1005: complete"), "objectives and completion")
local chatPart = first:match("recent chat: (.-)\n%a[%a ]*:") or first:match("recent chat: (.*)$")
assert(chatPart and #chatPart <= 450 and chatPart:find("%[General%] Spammer30: spam 30") and not chatPart:find("Teldrassil"), "chat is capped, newest first, short channel names")
local second = ask("and after that?")
assert(not second:find("character: ") and not second:find("quests") and not second:find("talents: "), "unchanged fields stay home: " .. second)
assert((first .. "\n" .. second):find("\ndone: "), "completed quests start once there's room")
local third = ask("and then?")
assert(third:find("\ndone%+: "), "completed quests continue")
for _ = 1, 10 do ask("next?") end
local count = 0; for id in pairs(got) do count = count + 1 end
assert(count == 400, "all completed quests arrive in chunks: " .. count)
for _, id in ipairs(completed) do assert(got[id], "quest " .. id) end
local quiet = ask("ok")
assert(not quiet:find("done"), "nothing left to send")
completed[#completed + 1] = 99999
progress[3] = 4
local after = ask("turned one in")
assert(after:find("done%+: 255r") and after:find("quests~: \n%- %[13%] Quest number 3 with a long name #1003: Gnarlpine thing 1 slain: 4/10"), "a turn-in and a changed objective go out")
assert(not after:find("Quest number 4 "), "only the quest that changed: " .. after)
local chatty = ask("what did they say in general chat?")
assert(#(chatty:match("recent chat: (.*)$") or "") > 450, "asking about chat gets more of it")
-- A bridge that lost its memory has a new epoch: everything goes again, completed quests from scratch.
slotData.default = { who = "Backshot-Forever", beat = 131, ctxEpoch = "e2", chats = {} }
now = now + 2; __ticker.fn(); tick(1.1, 1)
local again = ask("hi again")
local again2 = ask("and?")
assert(again:find("character: ") and again:find("quests: ") and (again .. "\n" .. again2):find("\ndone: "), "new epoch resends everything")
local f = io.open(os.getenv("WAI_CTX_DUMP") or "/dev/null", "w"); if f then f:write(table.concat(ctxs, "\0")); f:close() end
print("context ok")

-- Settings dock to the chat window: beside it (right, or left near the screen edge), opening it if
-- needed, following it when it moves and closing with it.
if WaiSettings:IsShown() then ns.settings.toggle() end
WaiFrame:Hide()
assert(not WaiSettings:IsShown(), "closes with the chat window")
ns.settings.toggle()
assert(WaiFrame:IsShown() and WaiSettings:IsShown(), "opening settings opens the chat window")
local p = WaiSettings.points[#WaiSettings.points]
assert(p[1] == "TOPLEFT" and p[2] == WaiFrame and p[3] == "TOPRIGHT", "docked on the right")
function WaiFrame:GetRight() return 1900 end
function UIParent:GetRight() return 2000 end
WaiFrame:StopMovingOrSizing()
p = WaiSettings.points[#WaiSettings.points]
assert(p[1] == "TOPRIGHT" and p[2] == WaiFrame and p[3] == "TOPLEFT", "flips left near the screen edge")
WaiFrame.GetRight, UIParent.GetRight = nil, nil
-- The key button only takes the keyboard while choosing a key.
local kb
for _, f in ipairs(frames) do if f.kind == "Button" and f.scripts.OnKeyDown and f.keyboard ~= nil then kb = f end end
assert(kb and kb.keyboard == false, "settings don't swallow keys")
-- Closing the chat with settings open brings settings back next time; closed settings stay closed.
assert(WaiSettings:IsShown())
WaiToggle()
assert(not WaiFrame:IsShown() and not WaiSettings:IsShown(), "the key closes both")
WaiToggle()
assert(WaiFrame:IsShown() and WaiSettings:IsShown(), "and reopens both")
ns.settings.toggle()
WaiToggle(); WaiToggle()
assert(WaiFrame:IsShown() and not WaiSettings:IsShown(), "closed settings stay closed")
print("settings dock ok")

-- Suggestions while typing.
subjectInput:SetText("/re")
assert(#texts("^/reload") >= 1 and #texts("^/remember") == 0, "suggestions")
subjectInput.scripts.OnTabPressed(subjectInput)
print("tab completes to: '" .. subjectInput.text .. "'")
assert(subjectInput.text == "/reload")
subjectInput:SetText("")

-- /wai with a non-command sends; with a command runs it.
SlashCmdList.WAI("hello there")
assert(WaiDB.outbox[#WaiDB.outbox].text == "hello there")
print("ALL OK")
