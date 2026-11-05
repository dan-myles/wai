import { existsSync, readFileSync } from "node:fs";
import { exists, mkdir, rename, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";

// Written by the installer: { "wowDir": "<path to _forever_>", "claudePath": "<claude binary>" }.
export const CONFIG_FILE = resolve(import.meta.dir, "../config.json");

export function readConfig(): { wowDir?: string; claudePath?: string } {
  try {
    return JSON.parse(readFileSync(CONFIG_FILE, "utf8"));
  } catch {
    return {};
  }
}

const WOW_CANDIDATES =
  process.platform === "win32"
    ? ["C:\\Program Files (x86)\\World of Warcraft", "C:\\Program Files\\World of Warcraft", "C:\\World of Warcraft", "D:\\World of Warcraft", "D:\\Games\\World of Warcraft"]
    : ["/Applications/World of Warcraft", `${process.env.HOME}/Applications/World of Warcraft`];

// WOW_DIR env, then config.json, then the usual install locations.
export function findWowDir(): string | undefined {
  if (process.env.WOW_DIR) return process.env.WOW_DIR;
  const { wowDir } = readConfig();
  if (wowDir) return wowDir;
  return WOW_CANDIDATES.map((dir) => join(dir, "_forever_")).find((dir) => existsSync(dir));
}

export const WOW_DIR = findWowDir() ?? join(WOW_CANDIDATES[0]!, "_forever_");
export const ACCOUNTS_DIR = join(WOW_DIR, "WTF", "Account");
export const ADDONS_DIR = join(WOW_DIR, "Interface", "AddOns");
export const SCREENSHOTS_DIR = join(WOW_DIR, "Screenshots");
export const ADDON_DIR = resolve(import.meta.dir, "../../addon");
export const DATA_FILE = join(ADDON_DIR, "Data.lua");
export const GENERATED_FILE = join(ADDON_DIR, "Generated.lua");
export const MODULES_FILE = join(ADDON_DIR, "ModuleDefs.lua"); // not "Modules.lua": macOS/Windows would clash with modules.lua
// UI modules Claude writes (ui/<name>.lua); the bridge hot-loads them through module slots.
export const MODULES_DIR = join(ADDON_DIR, "ui");
export const STATE_FILE = resolve(import.meta.dir, "../.state.json");

// Load-on-demand addons the bridge writes into; the addon loads them live. Keep in sync with wai.lua.
export const SLOT_COUNT = 500;
export const slotName = (i: number) => `wai_slot${String(i).padStart(3, "0")}`;
export const slotFile = (i: number) => join(ADDONS_DIR, slotName(i), "slot.lua");

// Separate pool for hot-swapping UI modules: one per module change, reset on reload.
export const MOD_SLOT_COUNT = 40;
export const modSlotName = (i: number) => `wai_mod${String(i).padStart(2, "0")}`;
export const modSlotFile = (i: number) => join(ADDONS_DIR, modSlotName(i), "mod.lua");

// Pixel video chunks, a few seconds each. Reset on reload.
export const VID_SLOT_COUNT = 200;
export const vidSlotName = (i: number) => `wai_vid${String(i).padStart(3, "0")}`;
export const vidSlotFile = (i: number) => join(ADDONS_DIR, vidSlotName(i), "chunk.lua");

// Which slot the addon polls `seconds` after a send: one per second at first, then slower so a
// long task doesn't drain the pool. Must match slotOffset() in addon/wai.lua.
export function slotOffset(seconds: number) {
  if (seconds < 60) return Math.floor(seconds);
  if (seconds < 300) return 60 + Math.floor((seconds - 60) / 2);
  return 180 + Math.floor((seconds - 300) / 4);
}

export async function writeAtomic(path: string, content: string) {
  await writeFile(`${path}.tmp`, content);
  await rename(`${path}.tmp`, path);
}

// WoW only sees addon files that exist when the client starts, so these must exist up front.
export async function ensureStubs() {
  if (!(await exists(DATA_FILE))) await writeFile(DATA_FILE, "WaiData = nil\n");
  if (!(await exists(MODULES_FILE))) await writeFile(MODULES_FILE, "WaiModuleDefs = {}\n");
  if (!(await exists(GENERATED_FILE))) {
    await writeFile(GENERATED_FILE, "-- Custom UI written by wai (Claude). Loaded after the rest of the addon.\n");
  }
  await mkdir(MODULES_DIR, { recursive: true });
}
