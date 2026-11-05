-- wai UI: the chat window. Built from theme.lua primitives; see DESIGN.md.

local _, ns = ...
local T = ns.theme
local C, alpha = T.C, T.alpha
local guard = ns.core.guard
local ui = {}
ns.ui = ui

local TONES = {
    error = { C.redBg, C.redLine, C.red },
    warn = { T.hex("1E1708"), C.goldDim, C.gold },
    info = { T.hex("0C1626"), T.hex("1F3A60"), T.hex("8EC5FF") },
}

local PAD = 16
local GAP = 16
local AVATAR = 30
local MAX_SUGGESTIONS = 9

local MAX_TABS = 8

local frame, scroll, content, thumb, empty, banner, attachBar, suggest, composer, glow, input, placeholder, sendButton
local strip, tabButtons, addTab, renamer
local statusDot, statusText, hint
local rows, pools = {}, {}
local attachment -- subject from ns.ask, sent with the next message
local suggestions, selected = {}, 1

-- Message rows ----------------------------------------------------------------------------------

local function measureWidth(fs)
    return fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth()
end

-- Selecting text: font strings can't be highlighted, so clicking a message swaps its text for a
-- read-only edit box over the same spot, all of it selected, ready for Ctrl+C. Links stay
-- clickable until then: a click on a link never starts a selection.
local HINT = "Enter to send  ·  /help for commands"
local selector, selecting -- the shared edit box, and the row it covers

local function endSelect()
    local r = selecting
    if not r then return end
    selecting = nil -- first: ClearFocus fires OnEditFocusLost, which lands back here
    selector:ClearFocus()
    selector:Hide()
    r.text:Show()
    hint:SetText(HINT)
end

local function buildSelector()
    selector = CreateFrame("EditBox", nil, content)
    selector:SetMultiLine(true)
    selector:SetAutoFocus(false)
    selector:SetHighlightColor(C.gold[1], C.gold[2], C.gold[3], 0.35)
    selector:Hide()
    -- Read-only: any edit (typing, paste, cut) puts the message back.
    selector:SetScript("OnTextChanged", function(self, user)
        if user then
            self:SetText(self.plain)
            self:HighlightText()
        end
    end)
    selector:SetScript("OnEscapePressed", guard(endSelect))
    selector:SetScript("OnEditFocusLost", guard(endSelect))
end

local function startSelect(r)
    if selecting == r then return end
    endSelect()
    if not selector then buildSelector() end
    local holder = r.holder
    selector.plain = ns.links.plain(r.text:GetText() or "")
    selector:SetParent(holder)
    selector:SetFrameLevel(holder:GetFrameLevel() + 5)
    selector:SetFont(r.text:GetFont())
    if selector.SetSpacing then selector:SetSpacing(r.text:GetSpacing() or 0) end
    selector:SetTextColor(r.text:GetTextColor())
    selector:ClearAllPoints()
    selector:SetPoint("TOPLEFT", r.text)
    selector:SetSize(r.text:GetWidth(), math.ceil(r.text:GetStringHeight()) + 4)
    selector:SetText(selector.plain)
    selecting = r
    r.text:Hide()
    selector:Show()
    selector:SetFocus()
    selector:HighlightText()
    hint:SetText("Ctrl+C to copy  ·  Esc when done")
end

-- Left-click a message (not one of its links) to select its text.
local function selectable(r, holder)
    r.holder = holder
    holder:EnableMouse(true)
    holder:SetScript("OnMouseUp", guard(function(self, button)
        if button == "LeftButton" and not self.overLink then startSelect(r) end
    end))
end

local ROW_TYPES = {}

-- Your messages: right-aligned, tinted with your class colour.
ROW_TYPES.user = function(parent)
    local r = CreateFrame("Frame", nil, parent)
    local cc = T.classColor()
    r.bubble = CreateFrame("Frame", nil, r)
    r.bubble:SetPoint("TOPRIGHT")
    local bg = T.box(r.bubble, 10, C.panel, alpha(cc, 0.45))
    bg:SetFill({ C.panel[1] * 0.8 + cc[1] * 0.2, C.panel[2] * 0.8 + cc[2] * 0.2, C.panel[3] * 0.8 + cc[3] * 0.2, 1 })
    r.text = T.label(r.bubble, "regular", 13, C.text)
    r.text:SetPoint("TOPLEFT", 12, -9)
    r.text:SetSpacing(3)
    ns.links.enable(r.bubble)
    selectable(r, r.bubble)
    function r:Measure(text, width)
        local maxW = math.floor(width * 0.8) - 24
        self.text:SetWidth(maxW)
        self.text:SetText(text)
        local w = math.min(maxW, math.ceil(measureWidth(self.text)) + 1)
        self.text:SetWidth(w)
        local h = math.ceil(self.text:GetStringHeight())
        self.bubble:SetSize(w + 24, h + 18)
        return h + 18
    end
    return r
end

-- wai's messages: portrait on the left, name in gold, text on a slate card.
ROW_TYPES.assistant = function(parent)
    local r = CreateFrame("Frame", nil, parent)
    r.avatar = T.portrait(r, AVATAR, T.waiIcon)
    r.avatar:SetPoint("TOPLEFT")
    r.name = T.label(r, "display", 12, C.gold)
    r.name:SetPoint("TOPLEFT", AVATAR + 10, -1)
    r.name:SetText("wai")
    r.card = CreateFrame("Frame", nil, r)
    r.card:SetPoint("TOPLEFT", AVATAR + 10, -20)
    T.box(r.card, 10, C.panel, C.line)
    r.text = T.label(r.card, "regular", 13, C.text)
    r.text:SetPoint("TOPLEFT", 12, -10)
    r.text:SetSpacing(4)
    ns.links.enable(r.card)
    selectable(r, r.card)
    function r:Measure(text, width)
        local w = width - AVATAR - 10
        self.text:SetWidth(w - 24)
        self.text:SetText(text)
        local h = math.ceil(self.text:GetStringHeight()) + 20
        self.card:SetSize(w, h)
        return 20 + h
    end
    return r
end

-- Pulsing dots plus what Claude is doing right now ("Searching the web for ...").
ROW_TYPES.thinking = function(parent)
    local r = ROW_TYPES.assistant(parent)
    r.text:Hide()
    r.dots = {}
    for i = 1, 3 do
        local d = T.dot(r.card, 6, C.goldSoft, "OVERLAY")
        d:SetPoint("LEFT", 14 + (i - 1) * 11, 0)
        r.dots[i] = d
    end
    r.activity = T.label(r.card, "regular", 12, C.muted)
    r.activity:SetPoint("LEFT", 54, 0)
    r.activity:SetWordWrap(false)
    local t = 0
    r:SetScript("OnUpdate", function(_, elapsed)
        t = t + elapsed
        for i, d in ipairs(r.dots) do d:SetAlpha(0.2 + 0.8 * math.abs(math.sin(t * 3 - i * 0.55))) end
        r.activity:SetAlpha(0.65 + 0.35 * math.abs(math.sin(t * 1.5)))
    end)
    function r:Measure(text, width)
        self.activity:SetText(text)
        local maxW = width - AVATAR - 10
        local w = text == "" and 64 or math.min(maxW, 68 + math.ceil(measureWidth(self.activity)))
        self.activity:SetWidth(math.max(0, w - 64))
        self.card:SetSize(w, 32)
        return 52
    end
    return r
end

-- Local output from commands, e.g. /help: a quiet card with a gold hairline.
ROW_TYPES.note = function(parent)
    local r = CreateFrame("Frame", nil, parent)
    T.box(r, 8, C.inset, alpha(C.goldDim, 0.6))
    r.text = T.label(r, "regular", 12, C.text)
    r.text:SetPoint("TOPLEFT", 14, -11)
    r.text:SetSpacing(4)
    ns.links.enable(r)
    selectable(r, r)
    function r:Measure(text, width)
        self.text:SetWidth(width - 28)
        self.text:SetText(text)
        return math.ceil(self.text:GetStringHeight()) + 22
    end
    return r
end

ROW_TYPES.system = function(parent)
    local r = CreateFrame("Frame", nil, parent)
    r.text = T.label(r, "display", 10, C.goldDim)
    r.text:SetPoint("CENTER")
    r.text:SetJustifyH("CENTER")
    -- Faded gold hairlines either side of the label.
    for _, side in ipairs({ "LEFT", "RIGHT" }) do
        local l = T.fadedLine(r, C.goldDim)
        l:SetPoint(side, r, side)
        l:SetPoint(side == "LEFT" and "RIGHT" or "LEFT", r.text, side, side == "LEFT" and -12 or 12, 0)
    end
    function r:Measure(text)
        self.text:SetText(text:upper())
        return 16
    end
    return r
end

ROW_TYPES.error = function(parent)
    local r = CreateFrame("Frame", nil, parent)
    T.box(r, 8, C.redBg, C.redLine)
    r.text = T.label(r, "regular", 12, C.red)
    r.text:SetPoint("TOPLEFT", 12, -10)
    selectable(r, r)
    function r:Measure(text, width)
        self.text:SetWidth(width - 24)
        self.text:SetText(text)
        return math.ceil(self.text:GetStringHeight()) + 20
    end
    return r
end

local function acquire(kind)
    local pool = pools[kind]
    local r = pool and table.remove(pool)
    if not r then
        r = ROW_TYPES[kind](content)
        r.kind = kind
    end
    return r
end

local function release(r)
    if r == selecting then endSelect() end
    r:Hide()
    r.cachedText, r.cachedWidth = nil, nil
    pools[r.kind] = pools[r.kind] or {}
    table.insert(pools[r.kind], r)
end

-- Scrolling -------------------------------------------------------------------------------------

local function scrollRange()
    return math.max(0, content:GetHeight() - scroll:GetHeight())
end

local function updateThumb()
    local range = scrollRange()
    if range <= 0 then return thumb:Hide() end
    local trackH = scroll:GetHeight()
    local h = math.max(28, trackH * trackH / content:GetHeight())
    thumb:SetHeight(h)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -4, -(trackH - h) * scroll:GetVerticalScroll() / range)
    thumb:Show()
end

local function scrollTo(y)
    scroll:SetVerticalScroll(math.max(0, math.min(scrollRange(), y)))
    updateThumb()
end

-- Layout ----------------------------------------------------------------------------------------

local function entries(view)
    local render = ns.links.render
    local list = {}
    for _, m in ipairs(view.messages) do
        if m.text ~= "" then
            local kind = m.role
            local text = m.text:sub(1, m.shown)
            if kind == "system" then
                kind = m.text:find("^Error") and "error" or "system"
                if kind == "system" then text = "New conversation" end
            elseif kind == "status" then
                kind = "note"
            elseif kind ~= "note" then
                text = render(text)
            end
            list[#list + 1] = { key = m.id, kind = kind, text = text }
        end
    end
    for _, item in ipairs(view.outbox) do
        if item.text then list[#list + 1] = { key = "p" .. item.seq, kind = "user", text = render((item.text:gsub("|", "||"))) } end
    end
    local activity = view.activity and (view.activity .. "…") or ""
    if view.thinking then
        list[#list + 1] = { key = "thinking", kind = "thinking", text = activity }
    elseif view.streaming and view.activity then
        list[#list + 1] = { key = "activity", kind = "thinking", text = activity }
    end
    return list
end

local function setStatus(view)
    local color, text = C.uncommon, "Ready"
    if view.notice and view.notice.tone == "error" then
        color, text = C.red, "Offline"
    elseif view.streaming then
        color, text = C.rare, "Writing"
    elseif view.thinking then
        color, text = C.rare, "Thinking"
    end
    statusDot:SetVertexColor(color[1], color[2], color[3])
    statusDot.pulse = color == C.rare
    statusText:SetText(text)
end

local function setBanner(view)
    local n = view.full and {
        tone = "warn", text = "This live session is full. Reload to keep chatting.", action = "Reload", run = ns.core.reload,
    } or view.modulesNeedReload and {
        tone = "info", text = "New UI from wai is ready. Reload to load it.", action = "Reload", run = ns.core.reload,
    } or view.notice or view.update and {
        tone = "info", text = ("wai %s is available."):format(view.update), action = "Update", run = ns.core.requestUpdate,
    } or view.consent and {
        tone = "info", text = "Help improve wai with anonymous error reports? Never chats or names.",
        action = "Turn on", run = function() ns.settings.set("telemetry", true) end,
        secondary = "No thanks", runSecondary = function() ns.settings.set("telemetry", false) end,
    }
    if not n then return banner:Hide() end
    local tone = TONES[n.tone] or TONES.info
    banner.bg:SetFill(tone[1])
    banner.bg:SetBorder(tone[2])
    banner.text:SetTextColor(tone[3][1], tone[3][2], tone[3][3])
    banner.text:SetText(n.text)
    banner.icon:SetVertexColor(tone[3][1], tone[3][2], tone[3][3])
    banner.run = n.run
    if n.action then
        banner.action.label:SetText(n.action)
        banner.action:SetWidth(math.ceil(banner.action.label:GetStringWidth()) + 22)
        banner.action:Show()
    else
        banner.action:Hide()
    end
    banner.runSecondary = n.runSecondary
    if n.secondary then
        banner.secondary.label:SetText(n.secondary)
        banner.secondary:SetWidth(math.ceil(banner.secondary.label:GetStringWidth()) + 18)
        banner.secondary:Show()
        banner.text:SetPoint("RIGHT", banner.secondary, "LEFT", -6, 0)
    else
        banner.secondary:Hide()
        banner.text:SetPoint("RIGHT", banner.action, "LEFT", -10, 0)
    end
    banner:Show()
end

local function setAttachment()
    if not attachment then
        attachBar:Hide()
        placeholder:SetText("Ask wai anything…")
        return
    end
    attachBar.title:SetText(attachment.title)
    if attachment.icon then
        attachBar.icon:SetTexture(attachment.icon)
        attachBar.icon:Show()
        attachBar.label:SetPoint("LEFT", attachBar.icon, "RIGHT", 8, 0)
    else
        attachBar.icon:Hide()
        attachBar.label:SetPoint("LEFT", 12, 0)
    end
    placeholder:SetText(attachment.prompt .. "  (Enter)")
    attachBar:Show()
end

-- Stack from the bottom: composer, attachment, banner, then the message list fills the rest.
local function stack()
    local anchor = composer
    for _, f in ipairs({ attachBar, banner }) do
        if f:IsShown() then
            f:ClearAllPoints()
            f:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 8)
            f:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 8)
            anchor = f
        end
    end
    scroll:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 14, 8)
end

-- Tabs --------------------------------------------------------------------------------------------

local function paintTab(b, hovered)
    local active = b.state and b.state.active
    local color = active and C.gold or (hovered and C.text or C.muted)
    b.label:SetTextColor(color[1], color[2], color[3])
    b.bg:SetFill(active and alpha(C.gold, 0.07) or (hovered and alpha(C.gold, 0.04) or C.clear))
    b.underline:SetShown(active)
end

local function startRename(b)
    renamer:ClearAllPoints()
    renamer:SetAllPoints(b)
    renamer.id = b.state.id
    renamer:SetText(b.state.name)
    renamer:Show()
    renamer:SetFocus()
    renamer:HighlightText()
end

-- Right-click menu for a tab: Rename, and Delete, which asks for a second click since a deleted
-- chat is gone. A full-screen catcher behind it closes it on any click elsewhere.
local tabMenu, catcher

local function hideTabMenu()
    if tabMenu then
        tabMenu:Hide()
        catcher:Hide()
    end
end

local function menuRow(text, color, hover, onClick)
    local row = CreateFrame("Button", nil, tabMenu)
    row:SetHeight(26)
    row:SetPoint("LEFT", 6, 0)
    row:SetPoint("RIGHT", -6, 0)
    row.bg = T.box(row, 5, C.clear)
    row.label = T.label(row, "regular", 12, color)
    row.label:SetPoint("LEFT", 10, 0)
    row.label:SetText(text)
    row:SetScript("OnEnter", function() row.bg:SetFill(hover) end)
    row:SetScript("OnLeave", function() row.bg:SetFill(C.clear) end)
    row:SetScript("OnClick", guard(onClick))
    return row
end

local function buildTabMenu()
    catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:RegisterForClicks("AnyUp")
    catcher:SetScript("OnClick", hideTabMenu)
    catcher:Hide()
    tabMenu = CreateFrame("Frame", "WaiTabMenu", UIParent)
    tabMenu:SetFrameStrata("FULLSCREEN_DIALOG")
    tabMenu:SetFrameLevel(catcher:GetFrameLevel() + 10)
    tabMenu:SetSize(170, 66)
    tabMenu:EnableMouse(true)
    tabMenu:SetClampedToScreen(true)
    T.panel(tabMenu, 8)
    tinsert(UISpecialFrames, "WaiTabMenu") -- Esc closes it
    tabMenu:SetScript("OnHide", function() catcher:Hide() end) -- Esc hides only the menu
    tabMenu.rename = menuRow("Rename", C.text, alpha(C.gold, 0.08), function()
        local b = tabMenu.tab
        hideTabMenu()
        startRename(b)
    end)
    tabMenu.rename:SetPoint("TOP", 0, -6)
    tabMenu.delete = menuRow("Delete", C.red, alpha(C.red, 0.1), function(row)
        if not tabMenu.confirming then
            tabMenu.confirming = true
            row.label:SetText(tabMenu.last and "Click again to clear" or "Click again to delete")
            return
        end
        local id = tabMenu.tab.state.id
        hideTabMenu()
        ns.core.closeTab(id)
    end)
    tabMenu.delete:SetPoint("TOP", tabMenu.rename, "BOTTOM", 0, -2)
    tabMenu:Hide()
end

local function showTabMenu(b)
    if not tabMenu then buildTabMenu() end
    tabMenu.tab, tabMenu.confirming = b, nil
    -- Deleting the only chat starts it over instead (core.closeTab), so say that.
    tabMenu.last = #ns.core.tabs() == 1
    tabMenu.delete.label:SetText(tabMenu.last and "Clear chat" or "Delete")
    tabMenu:ClearAllPoints()
    tabMenu:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -4)
    catcher:Show()
    tabMenu:Show()
end

local function tabButton()
    local b = CreateFrame("Button", nil, strip)
    b:SetHeight(26)
    b.bg = T.box(b, 6, C.clear)
    b.label = T.label(b, "display", 11, C.muted)
    b.label:SetPoint("LEFT", 10, 0)
    b.label:SetPoint("RIGHT", -10, 0)
    b.label:SetJustifyH("CENTER")
    b.label:SetWordWrap(false)
    b.dot = T.dot(b, 6, C.rare, "OVERLAY")
    b.dot:SetPoint("LEFT", 8, 0)
    b.underline = T.solid(b, "OVERLAY", C.goldSoft)
    b.underline:SetHeight(2)
    b.underline:SetPoint("BOTTOMLEFT", 8, 0)
    b.underline:SetPoint("BOTTOMRIGHT", -8, 0)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
    b:SetScript("OnClick", guard(function(self, button)
        if button == "LeftButton" then
            ns.core.switchTab(self.state.id)
        elseif button == "RightButton" then
            GameTooltip:Hide()
            showTabMenu(self)
        else
            ns.core.closeTab(self.state.id) -- middle-click, like a browser tab
        end
    end))
    b:SetScript("OnDoubleClick", guard(function(self) startRename(self) end))
    b:SetScript("OnEnter", function(self)
        paintTab(self, true)
        T.tooltip(self, self.state.name, "Double-click to rename. Right-click for options.")
    end)
    b:SetScript("OnLeave", function(self)
        paintTab(self, false)
        GameTooltip:Hide()
    end)
    return b
end

local function renderTabs(list)
    local available = strip:GetWidth() - 30
    local natural, total = {}, 0
    for i, t in ipairs(list) do
        local b = tabButtons[i] or tabButton()
        tabButtons[i] = b
        if b.shownName and b.shownName ~= t.name and b.state and b.state.id == t.id then b.flash = 1 end
        b.shownName = t.name
        b.label:SetText(t.name)
        natural[i] = math.ceil(b.label:GetStringWidth()) + 22 + ((t.busy or t.unread) and 10 or 0)
        total = total + natural[i] + 4
    end
    local scale = total > available and available / total or 1
    local x = 0
    for i, t in ipairs(list) do
        local b = tabButtons[i]
        b.state = t
        b:ClearAllPoints()
        b:SetPoint("LEFT", strip, "LEFT", x, 0)
        b:SetWidth(math.floor(natural[i] * scale))
        b.dot:SetShown(t.busy or t.unread)
        local dotColor = t.busy and C.rare or C.gold
        b.dot:SetVertexColor(dotColor[1], dotColor[2], dotColor[3])
        b.dot.pulse = t.busy
        b.label:SetPoint("LEFT", (t.busy or t.unread) and 18 or 10, 0)
        paintTab(b, b:IsMouseOver())
        b:Show()
        x = x + b:GetWidth() + 4
    end
    for i = #list + 1, #tabButtons do tabButtons[i]:Hide() end
    addTab:ClearAllPoints()
    addTab:SetPoint("LEFT", strip, "LEFT", x, 0)
    addTab:SetShown(#list < MAX_TABS)
end

local function buildTabs(header)
    strip = CreateFrame("Frame", nil, frame)
    strip:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 12, -6)
    strip:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -12, -6)
    strip:SetHeight(26)
    tabButtons = {}
    addTab = T.button(strip, "ghost", "+", { width = 26, height = 24, radius = 6, size = 15, face = "regular", onClick = function() ns.core.newTab() end })
    addTab:SetScript("OnEnter", function(self)
        self.Paint(true)
        T.tooltip(self, "New chat", "Each tab is its own conversation.")
    end)
    addTab:SetScript("OnLeave", function(self)
        self.Paint(false)
        GameTooltip:Hide()
    end)
    local t = 0
    strip:SetScript("OnUpdate", function(_, elapsed)
        t = t + elapsed
        for _, b in ipairs(tabButtons) do
            b.dot:SetAlpha(b.dot.pulse and (0.4 + 0.6 * math.abs(math.sin(t * 2.5))) or 1)
            -- A retitled tab fades its new name in under a soft gold glow.
            if b.flash then
                b.flash = math.max(0, b.flash - elapsed * 1.25)
                b.label:SetAlpha(1 - b.flash * 0.7)
                b.bg:SetFill(alpha(C.gold, 0.04 + 0.16 * b.flash))
                if b.flash == 0 then
                    b.flash = nil
                    paintTab(b, b:IsMouseOver())
                end
            end
        end
    end)

    renamer = CreateFrame("EditBox", nil, strip)
    renamer:SetFrameLevel(strip:GetFrameLevel() + 10)
    T.box(renamer, 6, C.inset, C.goldSoft)
    renamer:SetFontObject(T.font("display", 11))
    renamer:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    renamer:SetJustifyH("CENTER")
    renamer:SetMaxLetters(24)
    renamer:SetAutoFocus(false)
    renamer:SetScript("OnEnterPressed", guard(function(self)
        ns.core.renameTab(self.id, self:GetText())
        self:Hide()
    end))
    renamer:SetScript("OnEscapePressed", function(self) self:Hide() end)
    renamer:SetScript("OnEditFocusLost", function(self) self:Hide() end)
    renamer:Hide()

    local line = T.fadedLine(frame, C.line)
    line:SetPoint("TOPLEFT", strip, "BOTTOMLEFT", -12, -5)
    line:SetPoint("TOPRIGHT", strip, "BOTTOMRIGHT", 12, -5)
end

function ui.update()
    if not frame or not frame:IsShown() then return end
    local view = ns.core.view()
    frame.subtitle:SetText(view.agent == "codex" and "Your companion, powered by Codex" or "Your companion, powered by Claude")
    renderTabs(view.tabs)
    setBanner(view)
    setAttachment()
    stack()
    local width = math.floor(scroll:GetWidth() - 2 * PAD)
    if width <= 0 then return end

    local atBottom = scroll:GetVerticalScroll() >= scrollRange() - 6
    local list = entries(view)
    local used, y = {}, PAD
    for _, e in ipairs(list) do
        local r = rows[e.key]
        if r and r.kind ~= e.kind then
            release(r)
            r = nil
        end
        if not r then
            r = acquire(e.kind)
            rows[e.key] = r
        end
        used[e.key] = true
        if r.cachedText ~= e.text or r.cachedWidth ~= width then
            if r == selecting then endSelect() end -- the text moved under the selection
            r.h = r:Measure(e.text, width)
            r.cachedText, r.cachedWidth = e.text, width
        end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, -y)
        r:SetSize(width, r.h)
        r:Show()
        y = y + r.h + GAP
    end
    for key, r in pairs(rows) do
        if not used[key] then
            release(r)
            rows[key] = nil
        end
    end

    if ns.video then
        local last = view.messages[#view.messages]
        if last and last.role == "assistant" then ns.video.caption(last.text:sub(1, last.shown)) end
    end
    content:SetSize(scroll:GetWidth(), y)
    scroll:UpdateScrollChildRect()
    if atBottom then scrollTo(scrollRange()) else updateThumb() end
    empty:SetShown(#list == 0)
    setStatus(view)
    sendButton:SetDisabled(strtrim(input:GetText()) == "" and not attachment)
end

-- Re-render every row, e.g. once item data arrives for a link.
function ui.invalidate()
    for _, r in pairs(rows) do r.cachedText = nil end
    ui.update()
end

-- Command suggestions -----------------------------------------------------------------------------

local function renderSuggestions()
    suggestions = ns.commands.match(input:GetText())
    if #suggestions == 0 then return suggest:Hide() end
    selected = math.min(selected, #suggestions)
    for i, row in ipairs(suggest.rows) do
        local c = suggestions[i]
        row:SetShown(c ~= nil)
        if c then
            row.name:SetText("/" .. c.name .. (c.args and ("  |cff5f6672" .. c.args .. "|r") or ""))
            row.hint:SetText(c.hint)
            row.bg:SetFill(i == selected and alpha(C.gold, 0.08) or C.clear)
        end
    end
    suggest:SetHeight(#suggestions * 26 + 10)
    suggest:Show()
end

local function complete(i)
    local c = suggestions[i or selected]
    if not c then return end
    input:SetText("/" .. c.name .. (c.args and " " or ""))
    input:SetCursorPosition(#input:GetText())
    if not c.args then
        selected = 1
        renderSuggestions()
    end
end

local function buildSuggestions()
    suggest = CreateFrame("Frame", nil, frame)
    suggest:SetPoint("BOTTOMLEFT", composer, "TOPLEFT", 0, 6)
    suggest:SetPoint("BOTTOMRIGHT", composer, "TOPRIGHT", 0, 6)
    suggest:SetFrameLevel(composer:GetFrameLevel() + 20)
    T.box(suggest, 10, C.panel, alpha(C.goldDim, 0.7))
    suggest.rows = {}
    for i = 1, MAX_SUGGESTIONS do
        local row = CreateFrame("Button", nil, suggest)
        row:SetHeight(26)
        row:SetPoint("TOPLEFT", 5, -5 - (i - 1) * 26)
        row:SetPoint("TOPRIGHT", -5, -5 - (i - 1) * 26)
        row.bg = T.box(row, 6, C.clear)
        row.name = T.label(row, "display", 11, C.gold)
        row.name:SetPoint("LEFT", 10, 0)
        row.hint = T.label(row, "regular", 11, C.muted)
        row.hint:SetPoint("RIGHT", -10, 0)
        row.hint:SetJustifyH("RIGHT")
        row:SetScript("OnEnter", function()
            selected = i
            renderSuggestions()
        end)
        row:SetScript("OnClick", guard(function()
            complete(i)
            input:SetFocus()
        end))
        suggest.rows[i] = row
    end
    suggest:Hide()
end

-- Window ----------------------------------------------------------------------------------------

local function savePosition()
    WaiDB.ui = { x = frame:GetLeft(), y = frame:GetTop(), w = frame:GetWidth(), h = frame:GetHeight() }
end

local function submit()
    local text = strtrim(input:GetText())
    if suggest:IsShown() and text:match("^/%S*$") and not ns.commands.exists(text:sub(2)) then
        return complete()
    end
    if text == "" and not attachment then return input:ClearFocus() end
    input:SetText("")
    if text:sub(1, 1) == "/" then
        ns.commands.run(text)
    else
        local subject = attachment
        attachment = nil
        ns.core.send(text, subject)
    end
    ui.update()
end

local function buildHeader()
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(58)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() frame:StartMoving() end)
    header:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        savePosition()
    end)

    -- Faint gold sheen falling from the top edge.
    local sheen = T.solid(header, "BACKGROUND", C.clear, 3)
    sheen:SetPoint("TOPLEFT", 10, -1)
    sheen:SetPoint("BOTTOMRIGHT", -10, 0)
    T.gradient(sheen, "VERTICAL", alpha(C.goldSoft, 0), alpha(C.goldSoft, 0.07))

    local avatar = T.portrait(header, 36, T.waiIcon)
    avatar:SetPoint("LEFT", 14, 0)

    local title = T.label(header, "display", 15, C.gold)
    title:SetPoint("TOPLEFT", avatar, "TOPRIGHT", 11, -2)
    title:SetText("wai")
    local subtitle = T.label(header, "regular", 11, C.muted)
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    subtitle:SetText("Your companion, powered by Claude")
    frame.subtitle = subtitle

    local close = T.button(header, "ghost", nil, { width = 26, height = 26, radius = 13, onClick = function() frame:Hide() end })
    close:SetPoint("RIGHT", -12, 0)
    close.label = T.label(close, "regular", 17, C.goldSoft)
    close.label:SetPoint("CENTER", 0, 1)
    close.label:SetText("×")
    close.Paint(false)

    local gear = T.button(header, "ghost", nil, { width = 26, height = 26, radius = 13, onClick = function() ns.settings.toggle() end })
    gear:SetPoint("RIGHT", close, "LEFT", -2, 0)
    gear.icon = gear:CreateTexture(nil, "OVERLAY")
    gear.icon:SetTexture(T.GEAR)
    gear.icon:SetSize(15, 15)
    gear.icon:SetPoint("CENTER")
    gear.Paint(false)
    gear:HookScript("OnEnter", function(self) T.tooltip(self, "Settings", "Typing speed, whispers, window positions.") end)
    gear:HookScript("OnLeave", function() GameTooltip:Hide() end)

    local divider = T.fadedLine(header, C.goldDim)
    divider:SetPoint("BOTTOMLEFT", 0, 0)
    divider:SetPoint("BOTTOMRIGHT", 0, 0)
    return header
end

local function buildEmpty()
    empty = CreateFrame("Frame", nil, frame)
    empty:SetPoint("TOPLEFT", scroll, "TOPLEFT")
    empty:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT")

    local avatar = T.portrait(empty, 56, T.waiIcon)
    avatar:SetPoint("CENTER", 0, 84)
    local halo = T.dot(empty, 120, alpha(C.goldSoft, 0.06), "BACKGROUND")
    halo:SetPoint("CENTER", avatar, "CENTER")

    local title = T.label(empty, "display", 17, C.gold)
    title:SetPoint("TOP", avatar, "BOTTOM", 0, -16)
    title:SetJustifyH("CENTER")
    title:SetText("Well met, adventurer")
    local sub = T.label(empty, "regular", 12, C.muted)
    sub:SetPoint("TOP", title, "BOTTOM", 0, -8)
    sub:SetWidth(270)
    sub:SetJustifyH("CENTER")
    sub:SetSpacing(3)
    sub:SetText("Ask me anything, or Alt-click something in the world. Type /help to see everything I can do.")

    local ideas = { "What should I do next?", "How do I play my class better?", "How did my last fight go?" }
    local prev = sub
    for i, s in ipairs(ideas) do
        local chip = T.button(empty, "outline", s, { height = 32, radius = 8, padding = 30, size = 12, onClick = function() ns.core.send(s) end })
        chip:SetPoint("TOP", prev, "BOTTOM", 0, i == 1 and -20 or -8)
        prev = chip
    end
end

local function buildBanner()
    banner = CreateFrame("Frame", nil, frame)
    banner:SetHeight(40)
    banner.bg = T.box(banner, 8, C.panel, C.line)
    banner.icon = T.dot(banner, 6, C.text, "OVERLAY")
    banner.icon:SetPoint("LEFT", 14, 0)
    banner.text = T.label(banner, "medium", 12, C.text)
    banner.text:SetPoint("LEFT", banner.icon, "RIGHT", 10, 0)
    banner.text:SetJustifyV("MIDDLE")
    banner.action = T.button(banner, "gold", "Retry", { height = 26, radius = 6, size = 11, onClick = function()
        if banner.run then banner.run() end
        ui.update()
    end })
    banner.action:SetPoint("RIGHT", -7, 0)
    banner.secondary = T.button(banner, "ghost", "No thanks", { height = 26, radius = 6, size = 11, padding = 16, onClick = function()
        if banner.runSecondary then banner.runSecondary() end
        ui.update()
    end })
    banner.secondary:SetPoint("RIGHT", banner.action, "LEFT", -4, 0)
    banner.text:SetPoint("RIGHT", banner.action, "LEFT", -10, 0)
    banner:Hide()
end

-- "Asking about [Linen Cloth]": what the next message is about, with a remove button.
local function buildAttachBar()
    attachBar = CreateFrame("Frame", nil, frame)
    attachBar:SetHeight(34)
    T.box(attachBar, 8, C.panel, alpha(C.goldDim, 0.7))
    attachBar.icon = attachBar:CreateTexture(nil, "ARTWORK")
    attachBar.icon:SetSize(20, 20)
    attachBar.icon:SetPoint("LEFT", 8, 0)
    attachBar.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    attachBar.label = T.label(attachBar, "display", 10, C.goldDim)
    attachBar.label:SetPoint("LEFT", 12, 0)
    attachBar.label:SetText("ASKING ABOUT")
    attachBar.title = T.label(attachBar, "regular", 12, C.text)
    attachBar.title:SetPoint("LEFT", attachBar.label, "RIGHT", 8, 0)
    attachBar.title:SetPoint("RIGHT", -36, 0)
    attachBar.title:SetWordWrap(false)
    ns.links.enable(attachBar)
    local remove = T.button(attachBar, "ghost", nil, { width = 22, height = 22, radius = 11, onClick = function()
        attachment = nil
        ui.update()
    end })
    remove:SetPoint("RIGHT", -6, 0)
    remove.label = T.label(remove, "regular", 15, C.goldSoft)
    remove.label:SetPoint("CENTER", 0, 1)
    remove.label:SetText("×")
    remove.Paint(false)
    attachBar:Hide()
end

local function buildComposer()
    composer = CreateFrame("Frame", nil, frame)
    composer:SetHeight(46)
    composer:SetPoint("BOTTOMLEFT", 14, 36)
    composer:SetPoint("BOTTOMRIGHT", -14, 36)
    -- Gold glow behind the field while typing.
    glow = T.shape(composer, "BACKGROUND", 0, -3, 13)
    glow:SetColor(C.clear)
    composer.bg = T.box(composer, 10, C.inset, C.line, "BORDER")

    input = CreateFrame("EditBox", nil, composer)
    input:SetPoint("TOPLEFT", 14, 0)
    input:SetPoint("BOTTOMRIGHT", -48, 0)
    input:SetFontObject(T.font("regular", 13))
    input:SetTextColor(C.text[1], C.text[2], C.text[3])
    input:SetAutoFocus(false)
    input:SetMaxLetters(1000)
    input:SetScript("OnEnterPressed", guard(submit))
    input:SetScript("OnTabPressed", guard(function() complete() end))
    input:SetScript("OnEscapePressed", function(self)
        if suggest:IsShown() then return suggest:Hide() end
        self:ClearFocus()
    end)
    input:SetScript("OnArrowPressed", function(_, key)
        if not suggest:IsShown() then return end
        selected = (selected - 1 + (key == "UP" and -1 or 1)) % #suggestions + 1
        renderSuggestions()
    end)
    input:SetScript("OnEditFocusGained", function()
        composer.bg:SetBorder(C.goldSoft)
        glow:SetColor(alpha(C.goldSoft, 0.14))
    end)
    input:SetScript("OnEditFocusLost", function()
        composer.bg:SetBorder(C.line)
        glow:SetColor(C.clear)
    end)
    input:SetScript("OnTextChanged", guard(function(self)
        if not sendButton then return end
        placeholder:SetShown(self:GetText() == "")
        sendButton:SetDisabled(strtrim(self:GetText()) == "" and not attachment)
        selected = 1
        renderSuggestions()
    end))

    placeholder = T.label(input, "regular", 13, C.subtle)
    placeholder:SetPoint("LEFT", 0, 0)
    placeholder:SetPoint("RIGHT", 0, 0)
    placeholder:SetWordWrap(false)
    placeholder:SetText("Ask wai anything…")

    sendButton = T.button(composer, "gold", nil, { width = 32, height = 32, radius = 16, onClick = submit })
    sendButton:SetPoint("RIGHT", -7, 0)
    sendButton.icon = sendButton:CreateTexture(nil, "OVERLAY")
    sendButton.icon:SetTexture(T.ARROW)
    sendButton.icon:SetSize(16, 16)
    sendButton.icon:SetPoint("CENTER")
    sendButton:SetDisabled(true)

    composer:EnableMouse(true)
    composer:SetScript("OnMouseDown", function() input:SetFocus() end)
end

local function buildFooter()
    hint = T.label(frame, "regular", 11, C.subtle)
    hint:SetPoint("BOTTOMLEFT", 18, 13)
    hint:SetText(HINT)

    statusText = T.label(frame, "display", 10, C.muted)
    statusText:SetPoint("BOTTOMRIGHT", -32, 13)
    statusDot = T.dot(frame, 7, C.uncommon, "OVERLAY")
    statusDot:SetPoint("RIGHT", statusText, "LEFT", -6, 0)
    local t = 0
    local pulser = CreateFrame("Frame", nil, frame)
    pulser:SetScript("OnUpdate", function(_, elapsed)
        t = t + elapsed
        statusDot:SetAlpha(statusDot.pulse and (0.45 + 0.55 * math.abs(math.sin(t * 2.5))) or 1)
    end)

    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -4, 4)
    for i = 1, 3 do
        for j = 1, i do
            local d = T.dot(grip, 2.5, C.goldDim)
            d:SetPoint("BOTTOMRIGHT", -(3 + (j - 1) * 4), 3 + (i - j) * 4)
        end
    end
    grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        savePosition()
    end)
end

function ui.build()
    frame = CreateFrame("Frame", "WaiFrame", UIParent)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    if frame.SetResizeBounds then frame:SetResizeBounds(340, 400, 1000, 1400)
    elseif frame.SetMinResize then frame:SetMinResize(340, 400) end
    frame:EnableMouse(true)
    local pos = WaiDB.ui
    if pos and pos.x then
        frame:SetSize(pos.w, pos.h)
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
    else
        frame:SetSize(420, 560)
        frame:SetPoint("CENTER")
    end
    frame:Hide()
    tinsert(UISpecialFrames, "WaiFrame")

    T.panel(frame, 10)
    local depth = T.solid(frame, "BACKGROUND", C.clear, 3)
    depth:SetPoint("TOPLEFT", 10, -10)
    depth:SetPoint("BOTTOMRIGHT", -10, 10)
    T.gradient(depth, "VERTICAL", alpha(C.shadow, 0.25), alpha(C.panel, 0.35))

    local header = buildHeader()
    buildTabs(header)
    buildComposer()
    buildFooter()

    scroll = CreateFrame("ScrollFrame", nil, frame)
    scroll:SetPoint("TOPLEFT", strip, "BOTTOMLEFT", -12, -6)
    scroll:SetPoint("BOTTOMRIGHT", composer, "TOPRIGHT", 14, 8)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta) scrollTo(scroll:GetVerticalScroll() - delta * 48) end)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)

    thumb = CreateFrame("Frame", nil, frame)
    thumb:SetWidth(3)
    T.box(thumb, 1.5, C.goldDim, nil, "OVERLAY")
    thumb:Hide()

    buildEmpty()
    buildBanner()
    buildAttachBar()
    buildSuggestions()

    frame:SetScript("OnSizeChanged", guard(ui.update))
    hooksecurefunc(frame, "StopMovingOrSizing", function() ns.video.place() end)
    frame:SetScript("OnShow", guard(function()
        T.fadeIn(frame, 0.12)
        ui.update()
        scrollTo(scrollRange())
    end))
    frame:SetScript("OnHide", guard(function()
        endSelect()
        hideTabMenu()
    end))
end

-- Sets what the next message is about and puts the cursor in the input.
function ui.attach(subject)
    attachment = subject
    ui.show(true)
    ui.update()
end

function ui.isShown()
    return frame ~= nil and frame:IsShown()
end

function ui.show(focus)
    if not frame then return end
    if not frame:IsShown() then frame:Show() end
    if focus then input:SetFocus() end
end

function ui.toggle()
    if frame:IsShown() then frame:Hide() else ui.show(true) end
end
