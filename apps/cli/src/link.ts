// The live link to the game: two banks of empty helper addons whose enabled/disabled states are
// bits. The addon writes its lane ("wai_upNNNN") with EnableAddOn/DisableAddOn + SaveAddOns(), which
// rewrites the character's AddOns.txt; we read it there. We write our lane ("wai_dnNNNN") into the
// same file and the addon reads it back with ResetAddOns(). Each lane holds one frame that stays on
// disk until replaced, and every frame carries its own sequence number plus an ack of the other
// lane's: stop-and-wait in both directions, so nothing is ever resent. Layout must match link.lua.
import {
  readdir,
  readFile,
  rename,
  rm,
  stat,
  writeFile,
} from "node:fs/promises"
import { join } from "node:path"
import { crc32, deflateSync, inflateSync } from "node:zlib"

export const BITS = 1024 // per lane; keep in sync with link.lua and install.ts
export const FRAME = BITS / 8
const HEADER = 9 // magic, lane, session(2), gen, seq, ack, flags, length
const CRC = 4
export const PAYLOAD = FRAME - HEADER - CRC
const MAGIC = 0x77
export const UP = 1
export const DOWN = 2
export const FIRST = 1
export const LAST = 2
export const ZIP = 4
export const CANZIP = 8 // up only: the addon can inflate what we send

export const upName = (i: number) => `wai_up${String(i).padStart(4, "0")}`
export const downName = (i: number) => `wai_dn${String(i).padStart(4, "0")}`

export interface Frame {
  lane: number
  session: number
  gen: number // down: the bridge run; up: the run whose frames the ack refers to
  seq: number
  ack: number
  flags: number
  payload: Buffer
}

// 1..255; 0 means "nothing yet".
export const nextSeq = (s: number) => (s % 255) + 1

export function encodeFrame(f: Frame): Buffer {
  if (f.payload.length > PAYLOAD) {
    throw new Error(`frame payload too long: ${f.payload.length}`)
  }
  const b = Buffer.alloc(FRAME)
  b[0] = MAGIC
  b[1] = f.lane
  b.writeUInt16BE(f.session, 2)
  b[4] = f.gen
  b[5] = f.seq
  b[6] = f.ack
  b[7] = f.flags
  b[8] = f.payload.length
  f.payload.copy(b, HEADER)
  b.writeUInt32BE(crc32(b.subarray(0, FRAME - CRC)), FRAME - CRC)
  return b
}

export function decodeFrame(b: Buffer): Frame | undefined {
  if (b.length !== FRAME || b[0] !== MAGIC || b[8]! > PAYLOAD) {
    return undefined
  }
  if (b.readUInt32BE(FRAME - CRC) !== crc32(b.subarray(0, FRAME - CRC))) {
    return undefined
  }
  return {
    ack: b[6]!,
    flags: b[7]!,
    gen: b[4]!,
    lane: b[1]!,
    payload: Buffer.from(b.subarray(HEADER, HEADER + b[8]!)),
    seq: b[5]!,
    session: b.readUInt16BE(2),
  }
}

const LINE = /^wai_(up|dn)(\d{4}):\s*(enabled|disabled)\s*$/gm

// A lane's bytes from AddOns.txt (bit i is helper i, low bit first), or undefined while any of its
// helpers is missing from the file.
export function readLane(text: string, lane: "up" | "dn"): Buffer | undefined {
  const bytes = Buffer.alloc(FRAME)
  let seen = 0
  for (const [, which, index, state] of text.matchAll(LINE)) {
    const i = Number(index)
    if (which !== lane || i >= BITS) {
      continue
    }
    seen++
    if (state === "enabled") {
      bytes[i >> 3]! |= 1 << (i & 7)
    }
  }
  return seen === BITS ? bytes : undefined
}

// AddOns.txt with the down lane set to `bytes`; everything else in the file stays as the game wrote it.
export function writeDownLane(text: string, bytes: Buffer): string {
  const state = (i: number) =>
    (bytes[i >> 3]! >> (i & 7)) & 1 ? "enabled" : "disabled"
  const seen = new Set<number>()
  const out = text.replaceAll(LINE, (line, which, index) => {
    const i = Number(index)
    if (which !== "dn" || i >= BITS) {
      return line
    }
    seen.add(i)
    return `${downName(i)}: ${state(i)}`
  })
  const missing = []
  for (let i = 0; i < BITS; i++) {
    if (!seen.has(i)) {
      missing.push(`${downName(i)}: ${state(i)}`)
    }
  }
  if (!missing.length) {
    return out
  }
  return `${out}${out.endsWith("\n") || !out ? "" : "\n"}${missing.join("\n")}\n`
}

export interface Chunk {
  flags: number
  payload: Buffer
}

// A message as frame payloads, FIRST on the first and LAST on the last.
export function chunks(body: Buffer, zip: boolean): Chunk[] {
  const count = Math.max(1, Math.ceil(body.length / PAYLOAD))
  return Array.from({ length: count }, (_, i) => ({
    flags:
      (i === 0 ? FIRST : 0) | (i === count - 1 ? LAST : 0) | (zip ? ZIP : 0),
    payload: body.subarray(i * PAYLOAD, (i + 1) * PAYLOAD),
  }))
}

export interface Peer {
  // One running addon: its character's AddOns.txt and its login session.
  file: string
  session: number
  zip: boolean
}
interface PeerState extends Peer {
  up: number // last up frame taken in
  parts?: Buffer[]
  partsZip: boolean
  down: number // last down seq handed out
  acked: number // last down seq the addon confirmed
  queue: (Chunk & { seq: number })[]
  seenAt: number
  last?: string // the up frame last taken in
  recent: Set<string> // earlier ones, to spot a file restored from an old copy
}
// Where each file's up lane was last read to, so a bridge restart neither repeats nor skips a message.
export type Cursors = Record<string, { session: number; seq: number }>

export interface Handlers {
  message: (peer: Peer, body: Buffer) => void
  // A new addon session on this file (login, reload): forget what it was sent before.
  session: (peer: Peer) => void
  // Everything queued for this peer has been confirmed.
  drained: (peer: Peer) => void
}

const FAST_MS = 5 // live files: the addon waits on our ack, so this is most of a frame's round trip
const SLOW_MS = 250 // every other AddOns.txt, to notice a login
const RESCAN_MS = 10_000
const LIVE_MS = 60 * 60_000
const FRESH_MS = 2 * 60_000
const RECENT = 32
const ADDONS_TXT = /^addons\.txt$/i

// Under the WTF account folder: <account>/<realm>/<character>/AddOns.txt (and the account's own).
async function addonsFiles(dir: string, depth = 0): Promise<string[]> {
  if (depth > 3) {
    return []
  }
  const entries = await readdir(dir, { withFileTypes: true }).catch(() => [])
  const found = await Promise.all(
    entries.map((e) => {
      const path = join(dir, e.name)
      if (e.isDirectory()) {
        return e.name === "SavedVariables" ? [] : addonsFiles(path, depth + 1)
      }
      return ADDONS_TXT.test(e.name) ? [path] : []
    }),
  )
  return found.flat()
}

function remember(p: PeerState, id: string) {
  if (p.last && p.last !== id) {
    p.recent.add(p.last)
    if (p.recent.size > RECENT) {
      p.recent.delete(p.recent.values().next().value!)
    }
  }
  p.last = id
}

export class Link {
  readonly cursors: Cursors
  private dir: string
  private gen: number
  private on: Handlers
  private peers = new Map<string, PeerState>()
  private files = new Map<string, string>() // file -> stamp last read
  private chains = new Map<string, Promise<void>>()
  private timers: Timer[] = []
  private started = Date.now()
  private slowAt = 0

  constructor(dir: string, gen: number, cursors: Cursors, on: Handlers) {
    this.dir = dir
    this.gen = gen
    this.cursors = { ...cursors }
    this.on = on
  }

  async start() {
    await this.rescan()
    await Promise.all([...this.files.keys()].map((f) => this.visit(f)))
    this.timers.push(
      setInterval(() => {
        void this.poll()
      }, FAST_MS),
      setInterval(() => {
        void this.rescan()
      }, RESCAN_MS),
    )
  }

  stop() {
    for (const t of this.timers) {
      clearInterval(t)
    }
  }

  // Queues a message for the addon. It goes out one frame per ack, after anything already queued.
  send(peer: Peer, body: Buffer) {
    const p = this.peers.get(peer.file)
    if (!p || p.session !== peer.session) {
      return
    }
    const packed =
      p.zip && body.length > PAYLOAD ? deflateSync(body, { level: 9 }) : body
    const zip = packed.length < body.length
    for (const c of chunks(zip ? packed : body, zip)) {
      p.down = nextSeq(p.down)
      p.queue.push({ ...c, seq: p.down })
    }
    this.kick(p.file)
  }

  // Nothing waiting to go out to this peer.
  idle(peer: Peer) {
    const p = this.peers.get(peer.file)
    return !p || p.session !== peer.session || p.queue.length === 0
  }

  private async rescan() {
    for (const file of await addonsFiles(this.dir)) {
      if (!this.files.has(file)) {
        this.files.set(file, "")
      }
    }
  }

  private async poll() {
    const now = Date.now()
    const slow = now - this.slowAt >= SLOW_MS
    if (slow) {
      this.slowAt = now
    }
    await Promise.all(
      [...this.files.keys()].map((file) => {
        const p = this.peers.get(file)
        const live = p && now - p.seenAt < LIVE_MS
        return live || slow ? this.visit(file) : undefined
      }),
    )
  }

  // Reads the file again if it changed since last time.
  private visit(file: string) {
    return this.serial(file, async () => {
      const s = await stat(file).catch(() => {})
      if (!s) {
        return
      }
      const stamp = `${s.ino}:${s.size}:${s.mtimeMs}`
      if (this.files.get(file) === stamp) {
        return
      }
      this.files.set(file, stamp)
      await this.read(file, s.mtimeMs)
    })
  }

  // Runs again from the top for this file: our own state changed and the lane may need a write.
  private kick(file: string) {
    this.files.set(file, "")
    void this.visit(file)
  }

  private serial(file: string, job: () => Promise<void>) {
    const run = (this.chains.get(file) ?? Promise.resolve()).then(job, job)
    const tail = run.catch((error) => console.error("wai: link", error))
    this.chains.set(file, tail)
    return tail
  }

  private async read(file: string, mtime: number) {
    const text = await readFile(file, "utf-8").catch(() => {})
    const lane = text ? readLane(text, "up") : undefined
    const frame = lane ? decodeFrame(lane) : undefined
    if (!text || !lane || frame?.lane !== UP) {
      return
    }
    let p = this.peers.get(file)
    if (!p || p.session !== frame.session) {
      p = this.open(file, frame, Date.now() - mtime < FRESH_MS)
    }
    p.seenAt = Date.now()
    const id = lane.toString("hex")
    // A save from a stale copy of the file can bring back a frame we already took in; skip it.
    if (id === p.last || !p.recent.has(id)) {
      remember(p, id)
      const { bodies, drained } = this.receive(p, frame)
      for (const body of bodies) {
        this.on.message(p, body)
      }
      if (drained) {
        this.on.drained(p)
      }
    }
    await this.write(file, text, p)
  }

  private open(file: string, frame: Frame, fresh: boolean): PeerState {
    const cursor = this.cursors[file]
    // A session's first message starts at seq 1. Any other frame of a session we haven't met was
    // written before this bridge started: take it as read (the addon resends unconfirmed messages).
    let up = frame.seq
    if (cursor?.session === frame.session) {
      up = cursor.seq
    } else if (frame.seq === 1 && frame.flags & FIRST && fresh) {
      up = 0
    }
    const p: PeerState = {
      acked: 0,
      down: 0,
      file,
      partsZip: false,
      queue: [],
      recent: new Set(),
      seenAt: Date.now(),
      session: frame.session,
      up,
      zip: false,
    }
    this.peers.set(file, p)
    this.cursors[file] = { seq: up, session: frame.session }
    this.on.session(p)
    return p
  }

  private receive(p: PeerState, f: Frame) {
    const bodies: Buffer[] = []
    let drained = false
    p.zip = (f.flags & CANZIP) !== 0
    const [head] = p.queue
    if (head && f.gen === this.gen && f.ack === head.seq) {
      p.queue.shift()
      p.acked = head.seq
      drained = p.queue.length === 0
    }
    if (f.seq !== p.up) {
      const inOrder = f.seq === nextSeq(p.up)
      p.up = f.seq
      if (f.flags & FIRST) {
        p.parts = []
        p.partsZip = (f.flags & ZIP) !== 0
      } else if (!inOrder) {
        // Frames went by unseen (the bridge was down); this message can't be completed.
        p.parts = undefined
      }
      p.parts?.push(f.payload)
      if (f.flags & LAST && p.parts) {
        const body = Buffer.concat(p.parts)
        p.parts = undefined
        try {
          bodies.push(p.partsZip ? inflateSync(body) : body)
        } catch (error) {
          console.error("wai: link dropped a damaged message", error)
        }
      }
    }
    this.cursors[p.file] = { seq: p.up, session: p.session }
    return { bodies, drained }
  }

  // What our lane should hold now: the oldest unconfirmed frame, or a bare ack.
  private lane(p: PeerState) {
    const [head] = p.queue
    return encodeFrame({
      ack: p.up,
      flags: head?.flags ?? 0,
      gen: this.gen,
      lane: DOWN,
      payload: head?.payload ?? Buffer.alloc(0),
      seq: head?.seq ?? p.acked,
      session: p.session,
    })
  }

  private async write(file: string, text: string, p: PeerState) {
    const want = this.lane(p)
    if (readLane(text, "dn")?.equals(want)) {
      return
    }
    const tmp = `${file}.wai-tmp`
    await writeFile(tmp, writeDownLane(text, want))
    // The game may have saved since we read; never undo its write. The next poll tries again.
    const current = await readFile(file, "utf-8").catch(() => {})
    if (current !== text) {
      await rm(tmp, { force: true })
      this.files.set(file, "")
      return
    }
    await renameRetrying(tmp, file)
  }
}

// Windows refuses to replace a file the game has open for a moment.
async function renameRetrying(from: string, to: string) {
  for (let attempt = 0; ; attempt++) {
    try {
      return await rename(from, to)
    } catch (error) {
      const code = (error as NodeJS.ErrnoException).code ?? ""
      if (attempt >= 8 || !["EBUSY", "EPERM", "EACCES"].includes(code)) {
        throw error
      }
      await Bun.sleep(5 * (attempt + 1))
    }
  }
}
