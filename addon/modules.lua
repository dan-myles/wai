-- UI modules Claude builds (ui/<name>.lua on the bridge). At login they all come from ModuleDefs.lua;
-- during a session each change arrives in a fresh "wai_modNN" load-on-demand slot and replaces the
-- running version live. A module is a chunk that receives the wai API and returns its root frame.

local _, ns = ...
local modules = {}
ns.modules = modules

local LoadAddOn = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
local running = {} -- name -> { version, root }
local stale = false -- a module changed but the session is out of module slots

-- What module code gets as `...`: the design system and a few wai services.
local function api()
    return {
        theme = ns.theme,
        guard = ns.core.guard,
        links = ns.links,
        way = ns.way,
        note = ns.core.note,
        context = ns.context,
    }
end

local function hidden(name)
    WaiCharDB.hiddenModules = WaiCharDB.hiddenModules or {}
    return WaiCharDB.hiddenModules[name]
end

local function start(name, def)
    local fn, err = loadstring(def.code or "", "wai ui/" .. name)
    if not fn then return ns.core.report(err) end
    local ok, root = pcall(fn, api())
    if not ok then return ns.core.report(root) end
    local old = running[name]
    if old and old.root and old.root ~= root and old.root.Hide then old.root:Hide() end
    running[name] = { version = def.version, root = root }
    if root and root.Hide and hidden(name) then root:Hide() end
end

function modules.loadAll()
    for name, def in pairs(WaiModuleDefs or {}) do start(name, def) end
end

-- list: { name = { version, slot } } from a slot snapshot; it names every current module.
function modules.sync(list)
    if type(list) ~= "table" then return end
    for name, info in pairs(list) do
        local cur = running[name]
        if not cur or info.version > cur.version then
            if info.slot then
                WaiModuleDefs = WaiModuleDefs or {}
                LoadAddOn(("wai_mod%02d"):format(info.slot))
                local def = WaiModuleDefs[name]
                if def and def.version == info.version then start(name, def) end
            else
                stale = true
            end
        end
    end
    -- Modules deleted on the bridge go away.
    for name, m in pairs(running) do
        if not list[name] then
            if m.root and m.root.Hide then m.root:Hide() end
            running[name] = nil
        end
    end
end

function modules.setShown(name, shown)
    WaiCharDB.hiddenModules = WaiCharDB.hiddenModules or {}
    WaiCharDB.hiddenModules[name] = (not shown) or nil
    local m = running[name]
    if m and m.root and m.root.SetShown then m.root:SetShown(shown) end
end

function modules.needsReload()
    return stale
end
