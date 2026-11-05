// wai bridge. Receives messages from screenshots (live) or the SavedVariables outbox (on reload),
// asks Claude, and streams replies back through slot addons (live) and Data.lua (on reload).
// Every chat is keyed "Name-Realm#tab": each character has its own tabs, each with its own Claude session.
import { watch } from "node:fs";
import { mkdir, readdir, readFile, stat, unlink } from "node:fs/promises";
import { join } from "node:path";
import { ask } from "./claude";
import {
  ACCOUNTS_DIR, DATA_FILE, MODULES_DIR, MODULES_FILE, MOD_SLOT_COUNT, SCREENSHOTS_DIR, SLOT_COUNT, STATE_FILE,
  VID_SLOT_COUNT, ensureStubs, modSlotFile, slotFile, slotOffset, vidSlotFile, writeAtomic,
} from "./files";
import { CHUNK_FRAMES, chunkLua, fetchVideo } from "./video";
import { parseSavedVariables, toLua } from "./lua";
import { IncompleteError, decode, parseTga } from "./shot";

type Message = { id: number; role: "user" | "assistant" | "system"; text: string; at: number; done?: boolean; reset?: boolean };
type Chat = { lastSeq: number; sessionId?: string; messages: Message[]; activity?: string };
type Module = { version: number; hash: string };
type State = { nextId: number; chats: Record<string, Chat>; modules: Record<string, Module> };
type Item = { seq: number; kind: string; who: string; tab: string; text?: string; ctx?: string | Record<string, unknown>; slot: number };

const KEEP = 200;
const DATA_MESSAGES = 50;
const SLOT_MESSAGES = 6;
// Slots the addon might load next, around where the shared schedule says it is.
const SLOTS_BEHIND = 30;
const SLOTS_AHEAD = 20;
const STREAM_THROTTLE_MS = 500;
const HEARTBEAT_MS = 2000;
const now = () => Math.floor(Date.now() / 1000);
const chatKey = (who: string, tab: string) => `${who}#${tab || "main"}`;

const loaded = await readFile(STATE_FILE, "utf8").then((s) => JSON.parse(s)).catch(() => undefined);
const state: State = { nextId: loaded?.nextId ?? 1, chats: loaded?.chats ?? {}, modules: loaded?.modules ?? {} };
// Per-character conversations from before tabs become each character's "main" tab.
for (const [who, chat] of Object.entries<Chat>(loaded?.chars ?? {})) state.chats[chatKey(who, "main")] ??= chat;
// Replies cut off by a bridge restart can't resume; close them out so the addon stops waiting.
for (const chat of Object.values(state.chats)) {
  chat.activity = undefined;
  for (const m of chat.messages) {
    if (m.done !== false) continue;
    m.done = true;
    if (m.text) m.text += "\n\n(Interrupted: the bridge restarted. Ask again to continue.)";
    else Object.assign(m, { role: "system", text: "Error: the bridge restarted before replying. Ask again." });
  }
}

const queue: Item[] = [];
let inFlight: string | undefined; // chat key
let draining = false;
let beat = 0; // bumps on every publish so the addon can tell a live bridge from a stalled one
// Where the addon started polling: slot k0 at time `start`, for character `who`.
let schedule: { k0: number; start: number; who: string } | undefined;

const chat = (key: string) => (state.chats[key] ??= { lastSeq: 0, messages: [] });
const busy = (key: string) => inFlight === key || queue.some((i) => chatKey(i.who, i.tab) === key);

function say(key: string, role: Message["role"], text: string, extra: Partial<Message> = {}) {
  const m: Message = { id: state.nextId++, role, text, at: now(), ...extra };
  chat(key).messages.push(m);
  return m;
}

function snapshot(key: string, limit: number) {
  const c = chat(key);
  return {
    ackSeq: c.lastSeq,
    busy: busy(key),
    activity: c.activity?.replaceAll("|", "||"),
    // "|" starts a WoW escape sequence; "||" renders a literal pipe.
    messages: c.messages.slice(-limit).map((m) => ({ ...m, text: m.text.replaceAll("|", "||") })),
  };
}

// --- UI modules ------------------------------------------------------------------------------

const moduleCode = new Map<string, string>();
// Module slots used since the addon last reloaded; each change takes a fresh one.
let modSlotsUsed = 0;
const moduleSlots = new Map<string, number>();

function modulesSnapshot() {
  return Object.fromEntries(
    Object.entries(state.modules).map(([name, m]) => [name, { version: m.version, slot: moduleSlots.get(name) }]),
  );
}

async function scanModules(force = false) {
  const files = (await readdir(MODULES_DIR).catch(() => [])).filter((f) => /^[\w-]+\.lua$/.test(f));
  const seen = new Set<string>();
  let changed = false;
  for (const file of files) {
    const name = file.slice(0, -4);
    seen.add(name);
    const code = await readFile(join(MODULES_DIR, file), "utf8");
    moduleCode.set(name, code);
    const hash = String(Bun.hash(code));
    if (state.modules[name]?.hash === hash) continue;
    const version = (state.modules[name]?.version ?? 0) + 1;
    state.modules[name] = { version, hash };
    changed = true;
    if (modSlotsUsed < MOD_SLOT_COUNT) {
      const slot = ++modSlotsUsed;
      moduleSlots.set(name, slot);
      await writeAtomic(modSlotFile(slot), `WaiModuleDefs = WaiModuleDefs or {}\nWaiModuleDefs[${toLua(name)}] = ${toLua({ version, code })}\n`);
    } else {
      moduleSlots.delete(name); // the addon will ask for a reload to pick it up
    }
    console.log(`wai: module ${name} v${version}`);
  }
  for (const name of Object.keys(state.modules)) {
    if (seen.has(name)) continue;
    delete state.modules[name];
    moduleSlots.delete(name);
    moduleCode.delete(name);
    changed = true;
  }
  if (!changed && !force) return;
  // ModuleDefs.lua carries every module for the next reload or login.
  const defs = Object.fromEntries([...moduleCode].map(([name, code]) => [name, { version: state.modules[name]!.version, code }]));
  await writeAtomic(MODULES_FILE, `-- Generated by the wai bridge from ui/*.lua. Do not edit.\nWaiModuleDefs = ${toLua(defs)}\n`);
  await publish();
}

// --- Video ------------------------------------------------------------------------------------

type VideoState = {
  id: string; title: string; status: "loading" | "ready" | "error"; loop: boolean;
  w?: number; h?: number; fps?: number; base?: number; chunks?: number; error?: string;
};
const videos = new Map<string, VideoState>(); // who -> what they're watching
let vidSlotsUsed = 0;
let videosLoading = 0;

// [[video:query or URL]] plays a landscape video; [[clip:query]] a looping vertical clip (TikTok mode).
async function playVideo(who: string, kind: string, query: string) {
  const id = String(Date.now());
  const state: VideoState = { id, title: query, status: "loading", loop: kind === "clip" };
  videos.set(who, state);
  videosLoading++;
  await publish();
  try {
    const video = await fetchVideo(query, kind === "clip" ? "portrait" : "landscape");
    const free = VID_SLOT_COUNT - vidSlotsUsed;
    if (free <= 0) throw new Error("Out of video slots for this session. Reload to free them.");
    const chunks = Math.min(free, Math.ceil(video.frames.length / CHUNK_FRAMES));
    const base = vidSlotsUsed + 1;
    for (let i = 0; i < chunks; i++) {
      const frames = video.frames.slice(i * CHUNK_FRAMES, (i + 1) * CHUNK_FRAMES);
      await writeAtomic(vidSlotFile(base + i), chunkLua(id, i + 1, frames));
    }
    vidSlotsUsed += chunks;
    Object.assign(state, { status: "ready", title: video.title, w: video.w, h: video.h, fps: video.fps, base, chunks });
    console.log(`wai: video "${video.title}" in slots ${base}-${base + chunks - 1}`);
  } catch (err) {
    Object.assign(state, { status: "error", error: (err instanceof Error ? err.message : String(err)).slice(0, 200) });
    console.error("wai: video failed", err);
  } finally {
    videosLoading--;
  }
}

// --- Publishing ------------------------------------------------------------------------------

async function writeSlots() {
  if (!schedule) return;
  const est = schedule.k0 + slotOffset((Date.now() - schedule.start) / 1000);
  const from = Math.max(schedule.k0, est - SLOTS_BEHIND);
  const to = Math.min(SLOT_COUNT, est + SLOTS_AHEAD);
  if (from > to) return;
  const prefix = `${schedule.who}#`;
  const chats = Object.fromEntries(
    Object.keys(state.chats)
      .filter((k) => k.startsWith(prefix))
      .map((k) => [k.slice(prefix.length), snapshot(k, SLOT_MESSAGES)]),
  );
  const content = `WaiSlot = ${toLua({ who: schedule.who, beat, modules: modulesSnapshot(), video: videos.get(schedule.who), chats })}\n`;
  const writes = [];
  for (let i = from; i <= to; i++) writes.push(writeAtomic(slotFile(i), content));
  await Promise.all(writes);
}

// Writes are chained so concurrent callers never interleave on the same tmp files.
let writing = Promise.resolve();
function publish() {
  const write = async () => {
    beat++;
    for (const c of Object.values(state.chats)) c.messages = c.messages.slice(-KEEP);
    await writeAtomic(STATE_FILE, JSON.stringify(state, null, 2));
    const chats = Object.fromEntries(Object.keys(state.chats).map((k) => [k, snapshot(k, DATA_MESSAGES)]));
    await writeAtomic(DATA_FILE, `-- Generated by the wai bridge. Do not edit.\nWaiData = ${toLua({ beat, chats })}\n`);
    await writeSlots();
  };
  return (writing = writing.then(write, write).catch((err) => console.error("wai: publish failed", err)));
}

let streamTimer: Timer | undefined;
function publishSoon() {
  streamTimer ??= setTimeout(() => {
    streamTimer = undefined;
    void publish();
  }, STREAM_THROTTLE_MS);
}

// While Claude works (even silently, e.g. a long tool call), keep the addon's view fresh.
setInterval(() => {
  if (inFlight || videosLoading) void publish();
}, HEARTBEAT_MS);

// --- Conversation ----------------------------------------------------------------------------

async function receive(items: Item[]) {
  const fresh = items.filter((i) => i.seq > chat(chatKey(i.who, i.tab)).lastSeq).sort((a, b) => a.seq - b.seq);
  if (!fresh.length) return;
  for (const item of fresh) {
    const key = chatKey(item.who, item.tab);
    const c = chat(key);
    c.lastSeq = item.seq;
    if (item.kind === "reset") {
      c.sessionId = undefined;
      c.messages = [];
      for (let i = queue.length - 1; i >= 0; i--) if (chatKey(queue[i]!.who, queue[i]!.tab) === key) queue.splice(i, 1);
      say(key, "system", "Started a new conversation.", { reset: true });
    } else if (item.text) {
      item.text = item.text.replaceAll("||", "|");
      say(key, "user", item.text);
      queue.push(item);
    }
  }
  const last = fresh.at(-1)!;
  schedule = { k0: last.slot, start: Date.now(), who: last.who };
  console.log(`wai: ${chatKey(last.who, last.tab)} sent through seq ${last.seq} (slot ${last.slot})`);
  await publish();
  void drain();
}

function prompt(item: Item) {
  const ctx =
    typeof item.ctx === "string"
      ? item.ctx
      : Object.entries(item.ctx ?? {})
          .map(([k, v]) => `${k}: ${Array.isArray(v) ? v.join("; ") : v}`)
          .join("\n");
  return `[game]\n${ctx}\n[/game]\n\n${item.text}`;
}

async function drain() {
  if (draining) return;
  draining = true;
  while (queue.length) {
    const item = queue.shift()!;
    const key = chatKey(item.who, item.tab);
    const c = chat(key);
    inFlight = key;
    c.activity = "Thinking";
    const reply = say(key, "assistant", "", { done: false });
    try {
      const res = await ask(prompt(item), c.sessionId, (text, activity) => {
        reply.text = text;
        c.activity = activity;
        publishSoon();
      });
      c.sessionId = res.sessionId;
      reply.text = res.text;
      console.log(`wai: answered seq ${item.seq}`);
      // Fetch any video the reply asked for before finishing, so the addon is still polling.
      const video = res.text.match(/\[\[(video|clip):([^\]]+)\]\]/);
      if (video) {
        c.activity = "Loading video";
        await playVideo(item.who, video[1]!, video[2]!.trim());
      }
    } catch (err) {
      reply.role = "system";
      reply.text = `Error: ${err instanceof Error ? err.message : String(err)}`;
      console.error(`wai: seq ${item.seq} failed`, err);
    }
    reply.done = true;
    c.activity = undefined;
    inFlight = undefined;
    clearTimeout(streamTimer);
    streamTimer = undefined;
    await scanModules(); // catch module writes the watcher hasn't reported yet
    await publish();
  }
  draining = false;
}

// --- Inbound: screenshots (live) -------------------------------------------------------------

const KINDS: Record<number, string> = { 1: "chat", 2: "reset", 3: "ping", 4: "video" };
const reading = new Set<string>();

async function readShot(path: string) {
  if (reading.has(path)) return;
  reading.add(path);
  try {
    // The client may still be writing the file when the watcher fires.
    for (let attempt = 0; attempt < 30; attempt++) {
      try {
        const shot = decode(parseTga(await readFile(path)));
        if (!shot) return; // a real screenshot, leave it alone
        await unlink(path);
        const [text, ctx, who = "", tab = "main"] = shot.payload.split("\0");
        if (KINDS[shot.kind] === "ping" || KINDS[shot.kind] === "video") {
          schedule = { k0: shot.slot, start: Date.now(), who };
          // A direct video request from the Fun menu: "clip:query" or "video:query", no Claude involved.
          const request = KINDS[shot.kind] === "video" && text?.match(/^(video|clip):(.+)$/);
          if (request) await playVideo(who, request[1]!, request[2]!);
          await publish();
          return;
        }
        await receive([{ seq: shot.seq, kind: KINDS[shot.kind] ?? "chat", who, tab, text, ctx, slot: shot.slot }]);
        return;
      } catch (err) {
        if (!(err instanceof IncompleteError) && (err as NodeJS.ErrnoException).code !== "ENOENT") throw err;
      }
      await Bun.sleep(100);
    }
  } catch (err) {
    console.error(`wai: failed to read ${path}`, err);
  } finally {
    reading.delete(path);
  }
}

// --- Inbound: SavedVariables outbox (on reload) -----------------------------------------------

async function latestSavedVariables() {
  let best: { path: string; mtime: number } | undefined;
  for (const account of await readdir(ACCOUNTS_DIR).catch(() => [])) {
    const path = join(ACCOUNTS_DIR, account, "SavedVariables", "wai.lua");
    const s = await stat(path).catch(() => undefined);
    if (s && (!best || s.mtimeMs > best.mtime)) best = { path, mtime: s.mtimeMs };
  }
  return best;
}

async function scan() {
  const sv = await latestSavedVariables();
  if (!sv) return;
  const db = parseSavedVariables(await readFile(sv.path, "utf8")).WaiDB as { outbox?: unknown; who?: unknown } | undefined;
  // SavedVariables are written on reload/logout: the addon polls from slot 1 again, and every
  // module is now in ModuleDefs.lua, so the module slots start over.
  schedule = { k0: 1, start: Date.now(), who: typeof db?.who === "string" ? db.who : "" };
  modSlotsUsed = 0;
  moduleSlots.clear();
  vidSlotsUsed = 0;
  videos.clear();
  const outbox = (Array.isArray(db?.outbox) ? db.outbox : []) as Omit<Item, "slot">[];
  await receive(
    outbox
      .filter((i) => typeof i?.seq === "number")
      .map((i) => ({
        ...i,
        kind: i.kind ?? "chat",
        who: typeof i.who === "string" ? i.who : "",
        tab: typeof i.tab === "string" ? i.tab : "main",
        slot: 1,
      })),
  );
  if (inFlight) await publish();
}

let scanning = Promise.resolve();
const rescan = () => (scanning = scanning.then(scan).catch((err) => console.error("wai: scan failed", err)));

let debounce: Timer | undefined;
watch(ACCOUNTS_DIR, { recursive: true }, (_, filename) => {
  if (!filename?.toString().endsWith(join("SavedVariables", "wai.lua"))) return;
  clearTimeout(debounce);
  debounce = setTimeout(rescan, 250);
});

await mkdir(SCREENSHOTS_DIR, { recursive: true });
watch(SCREENSHOTS_DIR, (_, filename) => {
  if (filename?.toString().endsWith(".tga")) void readShot(join(SCREENSHOTS_DIR, filename.toString()));
});

await ensureStubs();
let moduleDebounce: Timer | undefined;
watch(MODULES_DIR, () => {
  clearTimeout(moduleDebounce);
  moduleDebounce = setTimeout(() => void scanModules().catch((err) => console.error("wai: module scan failed", err)), 300);
});

await scanModules(true);
await publish();
console.log(`wai bridge: watching ${ACCOUNTS_DIR}, ${SCREENSHOTS_DIR} and ${MODULES_DIR}`);
rescan();
