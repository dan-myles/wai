-- Runs the real link.lua against a real AddOns.txt that the real bridge (apps/cli/src/link.ts) reads
-- and writes; apps/cli/src/link.test.ts starts both. The client's addon-state calls are stood in
-- for the way the game behaves: ResetAddOns() reads the file, SaveAddOns() rewrites all of it.
-- Sends each message in SIZES, expects the bridge to echo it back as hex, prints timings. "zip"
-- gives the client compression; "chaos" makes a fifth of ResetAddOns calls keep the old state, so
-- saves put back stale bits over the bridge's writes.
-- Usage: luajit test/link-e2e.lua <addon dir> <AddOns.txt> [zip] [chaos]
local addonDir, file = arg[1], arg[2]
local zip, chaos = false, false
for i = 3, #arg do
  zip = zip or arg[i] == "zip"
  chaos = chaos or arg[i] == "chaos"
end
local ffi = require("ffi")
ffi.cdef([[
  int usleep(unsigned int usec);
  typedef struct { long tv_sec; long tv_usec; } timeval;
  int gettimeofday(timeval *tv, void *tz);
  unsigned long compressBound(unsigned long sourceLen);
  int compress2(uint8_t *dest, unsigned long *destLen, const uint8_t *source, unsigned long sourceLen, int level);
  int uncompress(uint8_t *dest, unsigned long *destLen, const uint8_t *source, unsigned long sourceLen);
]])
local tv = ffi.new("timeval")
local function clock()
  ffi.C.gettimeofday(tv, nil)
  return tonumber(tv.tv_sec) + tonumber(tv.tv_usec) / 1e6
end

-- The client's view of addon states, loaded from and saved to the file.
local order, state = {}, {}
local function load()
  local f = assert(io.open(file, "r"))
  local text = f:read("*a")
  f:close()
  for name, value in text:gmatch("([%w_]+): (%a+)") do
    if state[name] == nil then order[#order + 1] = name end
    state[name] = value == "enabled"
  end
end
load()
local saves, resets = 0, 0
_G.C_AddOns = {
  ResetAddOns = function()
    resets = resets + 1
    if chaos and math.random() < 0.2 then return end
    load()
  end,
  SaveAddOns = function()
    saves = saves + 1
    local lines = {}
    for i, name in ipairs(order) do lines[i] = name .. ": " .. (state[name] and "enabled" or "disabled") end
    local f = assert(io.open(file, "w")) -- in place, like the client: the bridge may catch it half written
    f:write(table.concat(lines, "\n"), "\n")
    f:close()
  end,
  GetAddOnEnableState = function(name) return state[name] and 2 or 0 end,
  EnableAddOn = function(name) state[name] = true end,
  DisableAddOn = function(name) state[name] = false end,
  DoesAddOnExist = function(name) return state[name] ~= nil end,
}
_G.UnitGUID = function() return "Player-1-00000001" end
_G.GetTime = clock
_G.time = os.time
_G.Enum = { CompressionMethod = { Zlib = 1 } }
if zip then
  local z = ffi.load(ffi.os == "OSX" and "z" or "libz.so.1")
  _G.C_EncodingUtil = {
    CompressString = function(s)
      local size = ffi.new("unsigned long[1]", z.compressBound(#s))
      local out = ffi.new("uint8_t[?]", size[0])
      assert(z.compress2(out, size, s, #s, 9) == 0)
      return ffi.string(out, tonumber(size[0]))
    end,
    DecompressString = function(s)
      local size = ffi.new("unsigned long[1]", 1024 * 1024)
      local out = ffi.new("uint8_t[?]", size[0])
      assert(z.uncompress(out, size, s, #s) == 0, "inflate")
      return ffi.string(out, tonumber(size[0]))
    end,
  }
end
local updater
_G.CreateFrame = function()
  return { SetScript = function(_, _, fn) updater = fn end, Show = function() end, Hide = function() end }
end

local ns = { core = {
  report = function(err) io.stderr:write("addon error: ", tostring(err), "\n"); os.exit(1) end,
  waiting = function() return true end,
} }
assert(loadfile(addonDir .. "/link.lua"))("wai", ns)

local SIZES = { 1, 115, 116, 3000, 2000 }
local sent, got, t0 = {}, {}, clock()
local function hex(s) return (s:gsub(".", function(c) return ("%02x"):format(c:byte()) end)) end
assert(ns.link.start({
  message = function(m) got[m.n] = { hex = m.hex, at = clock() } end,
}))
math.randomseed(7)
for i, size in ipairs(SIZES) do
  local bytes = {}
  for k = 1, size do
    -- Odd messages are noise (incompressible), even ones repeat (compressible).
    bytes[k] = i % 2 == 1 and math.random(0, 255) or (k % 26) + 97
  end
  sent[i] = string.char(unpack(bytes))
  assert(ns.link.send(sent[i]))
end

local last, deadline = clock(), clock() + 30
while clock() < deadline do
  local now = clock()
  updater(nil, now - last)
  last = now
  local all = true
  for i = 1, #SIZES do all = all and got[i] ~= nil end
  if all and not ns.link.busy() then break end
  ffi.C.usleep(2000)
end
for i, size in ipairs(SIZES) do
  assert(got[i], "no echo for message " .. i)
  assert(got[i].hex == hex(sent[i]), "echo " .. i .. " differs")
  print(("echo %d: %d bytes up, %d back, %.0f ms"):format(i, size, size * 2, (got[i].at - t0) * 1000))
end
print(("done %.0f ms, %d saves, %d resets"):format((clock() - t0) * 1000, saves, resets))
