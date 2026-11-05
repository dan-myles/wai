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
function Obj:Hide() self.shown = false end
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

_G.CreateFrame = function(kind, name, parent) local f = new(kind, parent, name); if name then _G[name] = f end; if kind == "GameTooltip" then _G[name .. "TextLeft1"] = new("FontString"); _G[name .. "TextLeft1"].text = "Linen Cloth"; _G[name .. "TextLeft2"] = new("FontString"); _G[name .. "TextLeft2"].text = "|cff9d9d9dTrade Goods|r" end; return f end
_G.CreateFont = function() return new("Font") end
_G.UIParent = new("Frame"); UIParent.h = 768
_G.WorldFrame = new("Frame")
_G.GameTooltip = new("GameTooltip")
_G.DEFAULT_CHAT_FRAME = new("Frame")
local chatOut = {}
function DEFAULT_CHAT_FRAME:AddMessage(m) chatOut[#chatOut + 1] = m end
_G.TargetFrame = new("Button")
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
_G.Ambiguate = function(n) return (n:gsub("%-.*", "")) end
_G.issecretvalue = function(v) return v == "SECRET" end
_G.GetPhysicalScreenSize = function() return 2560, 1440 end
_G.GetTime = function() return now end
_G.GetCVar = function() return "jpeg" end
_G.SetCVar = function() end
_G.InCombatLockdown = function() return false end
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

-- Fun menu: /fun opens it; toggles and test buttons work.
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
assert(WaiFunMenu and WaiFunMenu:IsShown(), "fun menu opens")
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
ns.commands.run("/fun"); assert(not WaiFunMenu:IsShown(), "/fun toggles it closed")
print("fun menu ok")

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
ns.commands.run("/settings"); assert(not WaiSettings:IsShown(), "/settings toggles closed")
print("settings ok")

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
