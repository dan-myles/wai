// `wai install`, `wai uninstall` and `wai doctor`: put the addon into WoW: Forever, create the
// helper slot addons, and run the bridge at login.
import { existsSync } from "node:fs";
import { exists, lstat, mkdir, readdir, readFile, realpath, rm, symlink, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { extractAddon } from "./addon-files";
import {
  ADDON_DIR, COMPILED, CONFIG_FILE, HOME, INSTALL_RECORD, MOD_SLOT_COUNT, SLOT_COUNT, VID_SLOT_COUNT, WOW_CANDIDATES,
  ensureStubs, findWowDir, modSlotName, readConfig, slotName, vidSlotName,
} from "./files";
import { bridgePid, register, registered, unregister } from "./service";
import { ensureFfmpeg, ensureYtDlp, toolsPresent } from "./tools";
import { VERSION } from "./version";

const SLOT_POOLS: [number, (i: number) => string, string, string][] = [
  [SLOT_COUNT, slotName, "slot.lua", "wai slot"],
  [MOD_SLOT_COUNT, modSlotName, "mod.lua", "wai ui"],
  [VID_SLOT_COUNT, vidSlotName, "chunk.lua", "wai video"],
];

const addonsDir = (wowDir: string) => join(wowDir, "Interface", "AddOns");

// Links ADDON_DIR into AddOns/wai: a symlink on macOS, a junction on Windows (no admin needed).
async function linkAddon(wowDir: string) {
  const target = join(addonsDir(wowDir), "wai");
  const existing = await lstat(target).catch(() => undefined);
  if (existing && (await realpath(target).catch(() => "")) === (await realpath(ADDON_DIR))) return;
  if (existing && !existing.isSymbolicLink()) {
    throw new Error(`${target} is a real folder, not wai's link. Move it away and run wai install again.`);
  }
  if (existing) await rm(target);
  await symlink(ADDON_DIR, target, process.platform === "win32" ? "junction" : "dir");
}

// Load-on-demand helper addons the bridge writes into while you play.
async function makeSlots(wowDir: string) {
  for (const [count, name, file, title] of SLOT_POOLS) {
    for (let i = 1; i <= count; i++) {
      const dir = join(addonsDir(wowDir), name(i));
      await mkdir(dir, { recursive: true });
      await writeFile(join(dir, `${name(i)}.toc`),
        `## Interface: 16001\n## Title: ${title} ${i}\n## Category: wai\n## Group: wai\n## LoadOnDemand: 1\n\n${file}\n`);
      if (!(await exists(join(dir, file)))) await writeFile(join(dir, file), "-- empty\n");
    }
  }
}

// Everything except the background service. Safe to run repeatedly.
export async function setup(wowDir: string) {
  if (!(await exists(wowDir))) throw new Error(`WoW: Forever not found at ${wowDir}`);
  await mkdir(addonsDir(wowDir), { recursive: true });
  await mkdir(ADDON_DIR, { recursive: true });
  await ensureStubs();
  await linkAddon(wowDir);
  await makeSlots(wowDir);
}

function option(args: string[], name: string) {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : undefined;
}

export async function install(args: string[]) {
  const postUpdate = args.includes("--post-update");
  const config = readConfig();
  const wowDir = option(args, "--wow") ?? args.find((a) => !a.startsWith("--")) ?? findWowDir();
  if (!wowDir || !(await exists(wowDir))) {
    throw new Error(`Couldn't find WoW: Forever (looked in ${WOW_CANDIDATES.join(", ")}). Run: wai install --wow "<path to _forever_>"`);
  }
  await mkdir(HOME, { recursive: true });
  const claudePath = config.claudePath && existsSync(config.claudePath) ? config.claudePath : Bun.which("claude") ?? undefined;
  await writeFile(CONFIG_FILE, JSON.stringify({ ...config, wowDir, claudePath }, null, 2));

  const { changed } = await extractAddon();
  await setup(wowDir);
  if (postUpdate) {
    // Read by `wai update`: did addon files change (so WoW needs a restart)?
    console.log(JSON.stringify({ addonChanged: changed }));
    return;
  }
  console.log(`wai ${VERSION}: addon linked into ${addonsDir(wowDir)}`);
  for (const [label, fetch] of [["yt-dlp", ensureYtDlp], ["ffmpeg", ensureFfmpeg]] as const) {
    await fetch().catch((err) => console.log(`couldn't fetch ${label} (video won't work until it can): ${err.message}`));
  }
  console.log(`bridge ${await register()}`);
  if (!claudePath) {
    console.log("Claude CLI not found. Install it (https://claude.ai/install), sign in by running `claude` once, then run wai install again.");
  }
  console.log("Done. Restart WoW, then type /wai in game.");
}

export async function uninstall(args: string[]) {
  await unregister();
  const wowDir = findWowDir();
  if (wowDir && (await exists(addonsDir(wowDir)))) {
    const dir = addonsDir(wowDir);
    for (const entry of await readdir(dir)) {
      if (entry === "wai" || /^wai_(slot|mod|vid)\d+$/.test(entry)) await rm(join(dir, entry), { recursive: true, force: true });
    }
  }
  if (args.includes("--purge")) await rm(HOME, { recursive: true, force: true });
  console.log("wai removed from WoW and from login items.");
  if (COMPILED) console.log(`Delete the binary to finish: ${process.execPath}`);
  if (!args.includes("--purge")) console.log(`Your chats and settings are still in ${HOME} (wai uninstall --purge removes them).`);
}

// `wai doctor`: everything that has to be true for wai to work.
export async function doctor() {
  const checks: [string, boolean, string][] = [];
  const config = readConfig();
  const wowDir = findWowDir();
  const record = await readFile(INSTALL_RECORD, "utf8").then(JSON.parse).catch(() => undefined);
  checks.push(["wai", true, `${VERSION} (${COMPILED ? (record?.managed ? "managed install, self-updates" : "binary") : "source checkout"})`]);
  checks.push(["WoW: Forever", !!wowDir && (await exists(wowDir)), wowDir ?? "not found; run wai install --wow <path>"]);
  if (wowDir) {
    const link = join(addonsDir(wowDir), "wai");
    const linked = (await realpath(link).catch(() => "")) === (await realpath(ADDON_DIR).catch(() => "-"));
    checks.push(["addon linked", linked, linked ? link : "run wai install"]);
    const missing = SLOT_POOLS.filter(([count, name]) => !existsSync(join(addonsDir(wowDir), name(count))));
    checks.push(["slot addons", missing.length === 0, missing.length ? "run wai install" : `${SLOT_COUNT} + ${MOD_SLOT_COUNT} + ${VID_SLOT_COUNT}`]);
  }
  const claude = config.claudePath ?? Bun.which("claude");
  const claudeVersion = claude ? Bun.spawnSync([claude, "--version"]).stdout.toString().trim() : "";
  checks.push(["Claude CLI", !!claudeVersion, claudeVersion || "install it from https://claude.ai/install, then sign in with `claude`"]);
  const pid = await bridgePid();
  checks.push(["bridge running", !!pid, pid ? `pid ${pid}` : "run wai install (or wai run)"]);
  const autostart = await registered();
  checks.push(["starts at login", autostart, autostart ? "yes" : process.platform === "linux" ? "not supported on Linux" : "run wai install"]);
  const tools = await toolsPresent();
  checks.push(["video tools", tools.ytDlp && tools.ffmpeg, tools.ytDlp && tools.ffmpeg ? "yt-dlp, ffmpeg" : "downloaded on first video"]);
  for (const [name, ok, detail] of checks) console.log(`${ok ? "\x1b[32m✓\x1b[0m" : "\x1b[31m✗\x1b[0m"} ${name.padEnd(16)} ${detail}`);
  return checks.every(([, ok]) => ok);
}
