-- wai design system: palette, type and drawing primitives shared by every wai surface.
-- See DESIGN.md for the rules behind these values.

local _, ns = ...
local T = {}
ns.theme = T

local MEDIA = "Interface\\AddOns\\wai\\media\\"
T.MEDIA = MEDIA
T.CIRCLE = MEDIA .. "circle.tga"
T.RING = MEDIA .. "ring.tga"
T.ARROW = MEDIA .. "arrow.tga"
T.NAV = MEDIA .. "nav.tga"
T.PIN = MEDIA .. "pin.tga"
T.SOLID = "Interface\\Buttons\\WHITE8X8"
T.WAI_ICON = "Interface\\Icons\\Spell_Holy_MagicalSentry"

local FONTS = {
    display = "Fonts\\FRIZQT__.TTF",
    regular = MEDIA .. "Geist-Regular.ttf",
    medium = MEDIA .. "Geist-Medium.ttf",
}

function T.hex(h, a)
    return { tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255, a or 1 }
end
local hex = T.hex
function T.alpha(c, a) return { c[1], c[2], c[3], a } end
local alpha = T.alpha

T.C = {
    bg = hex("0D1016"), panel = hex("141922"), panelHover = hex("1A202B"), inset = hex("090B0F"),
    line = hex("262C36"), lineStrong = hex("39414E"),
    gold = hex("FFD100"), goldSoft = hex("C9A24B"), goldDim = hex("8C6F3A"), goldDeep = hex("3A2E14"),
    text = hex("ECE6D6"), muted = hex("9298A3"), subtle = hex("5F6672"), ink = hex("1A1206"),
    uncommon = hex("1EFF00"), rare = hex("3FA0FF"), red = hex("FF5A5A"),
    redBg = hex("220C0E"), redLine = hex("6E2228"),
    clear = hex("000000", 0), shadow = hex("000000"),
}
local C = T.C

-- One physical pixel in UI units, for crisp hairlines.
function T.px()
    return UIParent:GetHeight() / select(2, GetPhysicalScreenSize())
end
local px = T.px

function T.classColor()
    local _, class = UnitClass("player")
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    return c and { c.r, c.g, c.b, 1 } or C.goldSoft
end

local fontObjects, fontLoads = {}, {}
function T.font(face, size)
    local key = face .. size
    if not fontObjects[key] then
        local path = FONTS[face]
        if fontLoads[path] == nil then
            local probe = UIParent:CreateFontString()
            fontLoads[path] = probe:SetFont(path, size, "") and true or false
            probe:Hide()
            if not fontLoads[path] then print("|cffd97757wai:|r couldn't load " .. path .. ", using the default font") end
        end
        local f = CreateFont("WaiFont_" .. key)
        f:SetFont(fontLoads[path] and path or STANDARD_TEXT_FONT, size, "")
        fontObjects[key] = f
    end
    return fontObjects[key]
end

function T.label(parent, face, size, color, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFontObject(T.font(face, size))
    fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    if face == "display" then
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, 0.9)
    end
    return fs
end

function T.solid(parent, layer, color, sublevel)
    local t = parent:CreateTexture(nil, layer, nil, sublevel)
    t:SetTexture(T.SOLID)
    t:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
    return t
end

-- Two-stop gradient across client API generations.
function T.gradient(tex, orientation, from, to)
    tex:SetVertexColor(1, 1, 1, 1)
    if tex.SetGradient and CreateColor and pcall(tex.SetGradient, tex, orientation,
            CreateColor(from[1], from[2], from[3], from[4]), CreateColor(to[1], to[2], to[3], to[4])) then
        return
    end
    if tex.SetGradientAlpha then
        tex:SetGradientAlpha(orientation, from[1], from[2], from[3], from[4], to[1], to[2], to[3], to[4])
    end
end

-- A horizontal hairline that fades out at both ends.
function T.fadedLine(parent, color)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(px())
    local left, right = T.solid(f, "ARTWORK", C.clear), T.solid(f, "ARTWORK", C.clear)
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMRIGHT", f, "BOTTOM")
    right:SetPoint("TOPLEFT", f, "TOP")
    right:SetPoint("BOTTOMRIGHT")
    T.gradient(left, "HORIZONTAL", alpha(color, 0), color)
    T.gradient(right, "HORIZONTAL", color, alpha(color, 0))
    return f
end

-- A rounded rectangle from 7 non-overlapping textures, so translucent fills stay even.
function T.shape(parent, layer, sublevel, inset, radius)
    local parts = {}
    local function tex(file)
        local t = parent:CreateTexture(nil, layer, nil, sublevel)
        t:SetTexture(file)
        parts[#parts + 1] = t
        return t
    end
    local corners = {
        { "TOPLEFT", 0, .5, 0, .5, 1, -1 }, { "TOPRIGHT", .5, 1, 0, .5, -1, -1 },
        { "BOTTOMLEFT", 0, .5, .5, 1, 1, 1 }, { "BOTTOMRIGHT", .5, 1, .5, 1, -1, 1 },
    }
    for _, c in ipairs(corners) do
        local t = tex(T.CIRCLE)
        t:SetTexCoord(c[2], c[3], c[4], c[5])
        t:SetSize(radius, radius)
        t:SetPoint(c[1], parent, c[1], c[6] * inset, c[7] * inset)
    end
    local mid = tex(T.SOLID)
    mid:SetPoint("TOPLEFT", inset + radius, -inset)
    mid:SetPoint("BOTTOMRIGHT", -inset - radius, inset)
    local left = tex(T.SOLID)
    left:SetPoint("TOPLEFT", inset, -inset - radius)
    left:SetPoint("BOTTOMRIGHT", parent, "BOTTOMLEFT", inset + radius, inset + radius)
    local right = tex(T.SOLID)
    right:SetPoint("TOPRIGHT", -inset, -inset - radius)
    right:SetPoint("BOTTOMLEFT", parent, "BOTTOMRIGHT", -inset - radius, inset + radius)
    return {
        SetColor = function(_, c)
            for _, t in ipairs(parts) do t:SetVertexColor(c[1], c[2], c[3], c[4] or 1) end
        end,
    }
end

-- Filled rounded box with an optional hairline border.
function T.box(parent, radius, fill, border, layer)
    layer = layer or "BACKGROUND"
    local b = {}
    local inset = 0
    if border then
        b.border = T.shape(parent, layer, 1, 0, radius)
        b.border:SetColor(border)
        inset = px()
    end
    b.fill = T.shape(parent, layer, 2, inset, radius - inset)
    b.fill:SetColor(fill)
    function b:SetFill(c) self.fill:SetColor(c) end
    function b:SetBorder(c) if self.border then self.border:SetColor(c) end end
    return b
end

-- Panel chrome: soft shadow, gold hairline frame, slate fill with a little depth.
function T.panel(f, radius)
    for i, a in ipairs({ 0.35, 0.16, 0.07 }) do
        local spread = i * 4
        T.shape(f, "BACKGROUND", -8 + i, -spread, radius + spread):SetColor(alpha(C.shadow, a))
    end
    T.box(f, radius, C.bg, alpha(C.goldDim, 0.85))
end

function T.dot(parent, size, color, layer)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:SetTexture(T.CIRCLE)
    t:SetSize(size, size)
    t:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
    return t
end

-- Round portrait in a gold ring, like a unit frame.
function T.portrait(parent, size, setTexture)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    local back = T.dot(f, size, C.inset, "BACKGROUND")
    back:SetPoint("CENTER")
    local art = f:CreateTexture(nil, "ARTWORK")
    art:SetPoint("TOPLEFT", 2, -2)
    art:SetPoint("BOTTOMRIGHT", -2, 2)
    setTexture(art)
    local masked = f.CreateMaskTexture and pcall(function()
        local mask = f:CreateMaskTexture()
        mask:SetTexture(T.CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(art)
        art:AddMaskTexture(mask)
    end)
    if not masked then art:SetTexCoord(0.1, 0.9, 0.1, 0.9) end
    f.ring = f:CreateTexture(nil, "OVERLAY")
    f.ring:SetTexture(T.RING)
    f.ring:SetAllPoints()
    f.ring:SetVertexColor(C.goldSoft[1], C.goldSoft[2], C.goldSoft[3])
    f.art = art
    return f
end

function T.waiIcon(tex)
    tex:SetTexture(T.WAI_ICON)
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
end

-- Fades a frame in using its own driver, so the frame's OnUpdate stays free.
function T.fadeIn(f, duration)
    f.fader = f.fader or CreateFrame("Frame", nil, f)
    f:SetAlpha(0)
    local t = 0
    f.fader:SetScript("OnUpdate", function(self, elapsed)
        t = t + elapsed
        f:SetAlpha(math.min(1, t / duration))
        if t >= duration then self:SetScript("OnUpdate", nil) end
    end)
end

-- variant: "gold" (filled call to action), "outline", "ghost"
local VARIANTS = {
    gold = { fill = C.goldSoft, hover = hex("E3BE63"), text = C.ink, hoverText = C.ink, face = "display" },
    outline = { fill = C.panel, hover = C.panelHover, border = C.line, hoverBorder = C.goldDim, text = C.text, hoverText = C.gold, face = "regular" },
    ghost = { fill = C.clear, hover = hex("FFD100", 0.08), text = C.goldSoft, hoverText = C.gold, face = "display" },
}

function T.button(parent, variant, text, opts)
    opts = opts or {}
    local v = VARIANTS[variant]
    local b = CreateFrame("Button", nil, parent)
    local h = opts.height or 28
    b.bg = T.box(b, opts.radius or 6, v.fill, v.border, "BACKGROUND")
    if text then
        b.label = T.label(b, opts.face or v.face, opts.size or 12, v.text)
        b.label:SetPoint("CENTER", 0, 0)
        b.label:SetJustifyH("CENTER")
        b.label:SetText(text)
        b:SetSize(opts.width or math.ceil(b.label:GetStringWidth()) + (opts.padding or 24), h)
    else
        b:SetSize(opts.width or h, h)
    end
    local function paint(hovered)
        local disabled = b.disabled
        b.bg:SetFill(disabled and C.panel or (hovered and v.hover or v.fill))
        if v.border then b.bg:SetBorder(hovered and v.hoverBorder or v.border) end
        local tc = disabled and C.subtle or (hovered and v.hoverText or v.text)
        if b.label then b.label:SetTextColor(tc[1], tc[2], tc[3]) end
        if b.icon then b.icon:SetVertexColor(tc[1], tc[2], tc[3]) end
    end
    b.Paint = paint
    function b:SetDisabled(d)
        self.disabled = d
        paint(self:IsMouseOver())
    end
    b:SetScript("OnEnter", function() paint(true) end)
    b:SetScript("OnLeave", function() paint(false) end)
    if opts.onClick then
        b:SetScript("OnClick", ns.core.guard(function(_, mouse) if not b.disabled then opts.onClick(mouse) end end))
    end
    return b
end

-- A labelled on/off switch: a rounded track that fills gold when on, with the knob sliding across.
-- opts: { label, hint, get = function() -> bool, set = function(on) }
function T.toggle(parent, opts)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(opts.hint and 40 or 26)
    row.label = T.label(row, "regular", 13, C.text)
    row.label:SetPoint("TOPLEFT", 0, opts.hint and -3 or -6)
    if opts.hint then
        row.hint = T.label(row, "regular", 11, C.muted)
        row.hint:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -4)
        row.hint:SetPoint("RIGHT", -50, 0)
        row.hint:SetWordWrap(false)
        row.hint:SetText(opts.hint)
    end
    row.label:SetText(opts.label)
    local track = CreateFrame("Frame", nil, row)
    track:SetSize(36, 20)
    track:SetPoint("RIGHT")
    track.bg = T.box(track, 10, C.inset, C.line)
    local knob = T.dot(track, 14, C.muted, "OVERLAY")
    local pos, target = 0, 0
    track:SetScript("OnUpdate", function()
        if pos == target then return end
        pos = pos + (target - pos) * 0.35
        if math.abs(target - pos) < 0.02 then pos = target end
        knob:SetPoint("LEFT", 3 + pos * 16, 0)
    end)
    function row:Refresh()
        local on = opts.get() and true or false
        target = on and 1 or 0
        track.bg:SetFill(on and C.goldSoft or C.inset)
        track.bg:SetBorder(on and C.goldSoft or C.line)
        local k = on and C.ink or C.muted
        knob:SetVertexColor(k[1], k[2], k[3])
    end
    knob:SetPoint("LEFT", 3, 0)
    row:SetScript("OnClick", ns.core.guard(function()
        opts.set(not opts.get())
        row:Refresh()
    end))
    row:SetScript("OnEnter", function() row.label:SetTextColor(C.gold[1], C.gold[2], C.gold[3]) end)
    row:SetScript("OnLeave", function() row.label:SetTextColor(C.text[1], C.text[2], C.text[3]) end)
    row:Refresh()
    return row
end

-- Tooltip helper so every wai hover reads the same: gold title, muted body lines.
function T.tooltip(owner, title, ...)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, C.gold[1], C.gold[2], C.gold[3])
    for i = 1, select("#", ...) do
        GameTooltip:AddLine((select(i, ...)), C.muted[1], C.muted[2], C.muted[3], true)
    end
    GameTooltip:Show()
end
