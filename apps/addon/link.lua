-- The live link to the bridge (apps/cli/src/link.ts has the full story; the layout must match it).
-- Two banks of empty helper addons are bit lanes: we set ours ("wai_upNNNN") with EnableAddOn and
-- DisableAddOn, and SaveAddOns() writes it to this character's AddOns.txt; the bridge writes its lane
-- ("wai_dnNNNN") into the same file and ResetAddOns() reads it back in. Each frame carries its
-- sequence number and an ack of the other lane, so each side sends its next frame once the last one
-- is confirmed. Reads only happen on a timer, quicker while a message is moving.

local _, ns = ...
local link = {}
ns.link = link

local BITS = 1024 -- per lane; keep in sync with bridge/src/link.ts
local FRAME = BITS / 8
local HEADER, CRC = 9, 4 -- magic, lane, session(2), gen, seq, ack, flags, length ... crc32
local PAYLOAD = FRAME - HEADER - CRC
local MAGIC, UP, DOWN = 0x77, 1, 2
local FIRST, LAST, ZIP, CANZIP = 1, 2, 4, 8
-- Seconds between reads: a message in flight, a reply on its way, nothing going on.
local MOVING, WAITING, IDLE = 0.015, 0.05, 1

local A = C_AddOns
local band, bxor, rshift
local POW = { [0] = 1, 2, 4, 8, 16, 32, 64, 128 }
local upNames, downNames = {}, {}
for i = 0, BITS - 1 do
    upNames[i + 1] = ("wai_up%04d"):format(i)
    downNames[i + 1] = ("wai_dn%04d"):format(i)
end

local handlers, character, session, ready
local zipper -- C_EncodingUtil, when the client has it
local outbox = {} -- frames waiting for the lane: { flags, payload }
local cur -- our frame on disk: { seq, flags, payload, acked }
local upSeq, downSeq, downGen = 0, 0, nil
local parts, partsZip
local written, writtenHeader, dirty = {}, nil, true -- the lane as we last set it
local lastDown -- the header of the last down frame we took in
local elapsed, ticker = 0, CreateFrame("Frame")

local crcTable
local function buildCrc()
    crcTable = {}
    for i = 0, 255 do
        local c = i
        for _ = 1, 8 do
            c = bxor(rshift(c, 1), band(c, 1) == 1 and 0xEDB88320 or 0)
        end
        crcTable[i] = c
    end
end

-- CRC-32 of a frame's bytes before the checksum, as 4 bytes, high first.
local function crc(b)
    local c = -1
    for i = 1, FRAME - CRC do
        c = bxor(rshift(c, 8), crcTable[band(bxor(c, b[i]), 255)])
    end
    c = bxor(c, -1)
    return band(rshift(c, 24), 255), band(rshift(c, 16), 255), band(rshift(c, 8), 255), band(c, 255)
end

local function nextSeq(s)
    return s % 255 + 1
end

local function readByte(names, i)
    local v, base = 0, (i - 1) * 8
    for k = 0, 7 do
        if A.GetAddOnEnableState(names[base + k + 1], character) > 0 then v = v + POW[k] end
    end
    return v
end

-- A message from the bridge is a Lua table literal, deflated when that saves room.
local function deliver(body, zip)
    if zip then body = zipper.DecompressString(body, Enum.CompressionMethod.Zlib) end
    local fn, err = loadstring("return " .. body, "wai link")
    if not fn then error(err) end
    setfenv(fn, {})
    handlers.message(fn())
end

local function take(b)
    local gen, seq, ack, flags, len = b[5], b[6], b[7], b[8], b[9]
    if gen ~= downGen then
        -- A new bridge run starts its own count; one that restarted mid-session needs a hello.
        if downGen and handlers.restart then handlers.restart() end
        downGen, downSeq, parts = gen, 0, nil
    end
    if cur and cur.written and ack == cur.seq then cur.acked = true end
    if seq == 0 or seq ~= nextSeq(downSeq) then return end
    downSeq = seq
    if band(flags, FIRST) ~= 0 then parts, partsZip = {}, band(flags, ZIP) ~= 0 end
    if not parts then return end
    parts[#parts + 1] = len > 0 and string.char(unpack(b, HEADER + 1, HEADER + len)) or ""
    if band(flags, LAST) ~= 0 then
        local body = table.concat(parts)
        parts = nil
        local ok, err = pcall(deliver, body, partsZip)
        if not ok then ns.core.report("link: " .. tostring(err)) end
    end
end

-- Reads the bridge's lane: the header always, the rest only when the header changed.
local function readDown()
    local b = {}
    for i = 1, HEADER do b[i] = readByte(downNames, i) end
    if b[1] ~= MAGIC or b[2] ~= DOWN or b[3] * 256 + b[4] ~= session or b[9] > PAYLOAD then return end
    local key = table.concat(b, ",", 5, HEADER)
    if key == lastDown then return end
    local len = b[9]
    for i = HEADER + 1, HEADER + len do b[i] = readByte(downNames, i) end
    for i = HEADER + len + 1, FRAME - CRC do b[i] = 0 end
    local c1, c2, c3, c4 = crc(b)
    if readByte(downNames, FRAME - 3) ~= c1 or readByte(downNames, FRAME - 2) ~= c2
        or readByte(downNames, FRAME - 1) ~= c3 or readByte(downNames, FRAME) ~= c4 then
        return
    end
    lastDown = key
    take(b)
end

local function encode()
    local flags = cur.flags + (zipper and CANZIP or 0)
    local b = { MAGIC, UP, math.floor(session / 256), session % 256, downGen or 0, cur.seq, downSeq, flags, #cur.payload }
    for i = 1, #cur.payload do b[HEADER + i] = cur.payload:byte(i) end
    for i = HEADER + #cur.payload + 1, FRAME - CRC do b[i] = 0 end
    b[FRAME - 3], b[FRAME - 2], b[FRAME - 1], b[FRAME] = crc(b)
    return b
end

-- Sets our lane to `b` and saves. Only bits that changed are touched, unless the file was replaced
-- under us (then every bit, since the client now holds whatever the file had).
local function writeUp(b)
    for i = 1, FRAME do
        local byte, base = b[i], (i - 1) * 8
        for k = 0, 7 do
            local on = band(byte, POW[k]) ~= 0
            local n = base + k + 1
            if dirty or written[n] ~= on then
                if on then A.EnableAddOn(upNames[n], character) else A.DisableAddOn(upNames[n], character) end
                written[n] = on
            end
        end
    end
    A.SaveAddOns()
    writtenHeader = table.concat(b, ",", 1, HEADER)
    dirty = false
end

-- The bridge saved the file from a copy older than our last write: our frame is gone from disk.
local function checkUp()
    if not writtenHeader or not cur or cur.acked then return end
    local b = {}
    for i = 1, HEADER do b[i] = readByte(upNames, i) end
    if table.concat(b, ",") ~= writtenHeader then dirty = true end
end

local function step()
    -- The AddOns list keeps unsaved choices in the same state; reading or saving would discard them.
    if AddonList and AddonList:IsShown() then return end
    A.ResetAddOns()
    readDown()
    checkUp()
    if (not cur or cur.acked) and #outbox > 0 then
        local f = table.remove(outbox, 1)
        upSeq = nextSeq(upSeq)
        cur = { seq = upSeq, flags = f.flags, payload = f.payload }
    end
    if not cur then return end
    -- Unconfirmed for a while: the file may hold bits we think are set. Write every bit again,
    -- less often each time (the bridge may simply be down).
    if cur.written and not cur.acked and GetTime() >= cur.retryAt then
        dirty = true
        cur.wait = math.min(cur.wait * 2, 16)
    end
    -- Rewrite when the frame is new, its ack moved, or the file lost it.
    local key = downSeq * 256 + (downGen or 0)
    if cur.written and cur.key == key and not dirty then return end
    writeUp(encode())
    cur.wait = cur.wait or 1
    cur.written, cur.key, cur.retryAt = true, key, GetTime() + cur.wait
end

function link.busy()
    return #outbox > 0 or (cur ~= nil and not cur.acked) or parts ~= nil
end

local function interval()
    if link.busy() then return MOVING end
    return ns.core.waiting() and WAITING or IDLE
end

local function onUpdate(_, dt)
    elapsed = elapsed + dt
    if elapsed < MOVING or elapsed < interval() then return end
    elapsed = 0
    local ok, err = pcall(step)
    if not ok then
        ns.core.report("link: " .. tostring(err))
        elapsed = -5 -- back off rather than repeat the error every frame
    end
end

local function exists(name)
    if A.DoesAddOnExist then return A.DoesAddOnExist(name) end
    local ok, found = pcall(A.GetAddOnInfo, name)
    return ok and found ~= nil
end

-- Nil when the link can run here, else why not.
local function missing()
    if type(bit) ~= "table" then return "bit" end
    for _, fn in ipairs({ "ResetAddOns", "SaveAddOns", "GetAddOnEnableState", "EnableAddOn", "DisableAddOn" }) do
        if type(A) ~= "table" or type(A[fn]) ~= "function" then return "C_AddOns." .. fn end
    end
    -- Helper addons only appear after a full client restart.
    for _, name in ipairs({ upNames[1], upNames[BITS], downNames[1], downNames[BITS] }) do
        if not exists(name) then return "helpers" end
    end
end

-- h: { message = fn(table), restart = fn() }. Returns true once the link is running.
function link.start(h)
    if ready then return true end
    local why = missing()
    if why then return false, why end
    character = UnitGUID("player")
    if not character then return false, "guid" end
    band, bxor, rshift = bit.band, bit.bxor, bit.rshift
    buildCrc()
    if C_EncodingUtil and C_EncodingUtil.CompressString and C_EncodingUtil.DecompressString
        and Enum.CompressionMethod and Enum.CompressionMethod.Zlib then
        zipper = C_EncodingUtil
    end
    handlers = h
    session = (time() * 7919 + math.random(0, 65535)) % 65535 + 1
    ready = true
    ticker:SetScript("OnUpdate", onUpdate)
    return true
end

function link.ready()
    return ready == true
end

-- Queues a message (a string) for the bridge. Messages go out whole and in order.
function link.send(body)
    if not ready then return false end
    local zip = false
    if zipper and #body > PAYLOAD then
        local ok, packed = pcall(zipper.CompressString, body, Enum.CompressionMethod.Zlib)
        if ok and type(packed) == "string" and #packed < #body then body, zip = packed, true end
    end
    local count = math.max(1, math.ceil(#body / PAYLOAD))
    for i = 1, count do
        local flags = (i == 1 and FIRST or 0) + (i == count and LAST or 0) + (zip and ZIP or 0)
        outbox[#outbox + 1] = { flags = flags, payload = body:sub((i - 1) * PAYLOAD + 1, i * PAYLOAD) }
    end
    elapsed = interval() -- go now
    return true
end
