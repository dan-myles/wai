import type { Proxy } from "./agent"

// `wai install`, `wai uninstall` and `wai doctor`: put the addon into WoW: Forever, create the
// helper addons (the live link's lanes and the module and video slots), and run the bridge at login.
import { existsSync } from "node:fs"
import {
  exists,
  lstat,
  mkdir,
  readdir,
  readFile,
  realpath,
  rm,
  symlink,
  writeFile,
} from "node:fs/promises"
import { join } from "node:path"

import { extractAddon } from "./addon-files"
import {
  AGENTS,
  INSTALL_HINTS,
  NAMES,
  agentPath,
  currentAgent,
  proxy,
} from "./agent"
import {
  ADDON_DIR,
  COMPILED,
  CONFIG_FILE,
  HOME,
  INSTALL_RECORD,
  MOD_SLOT_COUNT,
  VID_SLOT_COUNT,
  WOW_CANDIDATES,
  ensureStubs,
  findWowDir,
  modSlotName,
  readConfig,
  vidSlotName,
} from "./files"
import { BITS, downName, upName } from "./link"
import { bridgePid, register, registered, unregister } from "./service"
import { ensureFfmpeg, ensureYtDlp, toolsPresent } from "./tools"
import { VERSION } from "./version"

const SLOT_POOLS: [number, (i: number) => string, string, string][] = [
  [MOD_SLOT_COUNT, modSlotName, "mod.lua", "wai ui"],
  [VID_SLOT_COUNT, vidSlotName, "chunk.lua", "wai video"],
]
// The link's lanes (link.ts): never loaded, only switched on and off. Named from 0.
const LANES: [string, (i: number) => string][] = [
  ["wai link up", upName],
  ["wai link down", downName],
]
const HELPERS = /^wai_(slot|mod|vid|up|dn)\d+$/

const addonsDir = (wowDir: string) => join(wowDir, "Interface", "AddOns")

// Links ADDON_DIR into AddOns/wai: a symlink on macOS, a junction on Windows (no admin needed).
async function linkAddon(wowDir: string) {
  const target = join(addonsDir(wowDir), "wai")
  const existing = await lstat(target).catch(() => {})
  if (
    existing &&
    (await realpath(target).catch(() => "")) === (await realpath(ADDON_DIR))
  ) {
    return
  }
  if (existing && !existing.isSymbolicLink()) {
    throw new Error(
      `${target} is a real folder, not wai's link. Move it away and run wai install again.`,
    )
  }
  if (existing) {
    await rm(target)
  }
  await symlink(
    ADDON_DIR,
    target,
    process.platform === "win32" ? "junction" : "dir",
  )
}

const toc = (title: string, file = "") =>
  `## Interface: 16001\n## Title: ${title}\n## Category: wai\n## Group: wai\n## LoadOnDemand: 1\n${file ? `\n${file}\n` : ""}`

// Load-on-demand helper addons the bridge writes into while you play.
async function makeSlots(wowDir: string) {
  for (const [count, name, file, title] of SLOT_POOLS) {
    for (let i = 1; i <= count; i++) {
      const dir = join(addonsDir(wowDir), name(i))
      await mkdir(dir, { recursive: true })
      await writeFile(join(dir, `${name(i)}.toc`), toc(`${title} ${i}`, file))
      if (!(await exists(join(dir, file)))) {
        await writeFile(join(dir, file), "-- empty\n")
      }
    }
  }
  for (const [title, name] of LANES) {
    for (let i = 0; i < BITS; i++) {
      const dir = join(addonsDir(wowDir), name(i))
      await mkdir(dir, { recursive: true })
      await writeFile(join(dir, `${name(i)}.toc`), toc(`${title} ${i}`))
    }
  }
  // Message slots from before the link (0.9.4-nightly.2 and earlier).
  for (const entry of await readdir(addonsDir(wowDir))) {
    if (/^wai_slot\d+$/.test(entry)) {
      await rm(join(addonsDir(wowDir), entry), { force: true, recursive: true })
    }
  }
}

// Everything except the background service. Safe to run repeatedly.
export async function setup(wowDir: string) {
  if (!(await exists(wowDir))) {
    throw new Error(`WoW: Forever not found at ${wowDir}`)
  }
  await mkdir(addonsDir(wowDir), { recursive: true })
  await mkdir(ADDON_DIR, { recursive: true })
  await ensureStubs()
  await linkAddon(wowDir)
  await makeSlots(wowDir)
}

function option(args: string[], name: string) {
  const i = args.indexOf(name)
  return i !== -1 ? args[i + 1] : undefined
}

export async function install(args: string[]) {
  const postUpdate = args.includes("--post-update")
  const config = readConfig()
  const wowDir =
    option(args, "--wow") ??
    args.find((a) => !a.startsWith("--")) ??
    findWowDir()
  if (!wowDir || !(await exists(wowDir))) {
    throw new Error(
      `Couldn't find WoW: Forever (looked in ${WOW_CANDIDATES.join(", ")}). Run: wai install --wow "<path to _forever_>"`,
    )
  }
  await mkdir(HOME, { recursive: true })
  // The bridge runs at login with a bare PATH, so remember where each agent CLI lives now.
  const locate = (recorded: string | undefined, name: string) =>
    recorded && existsSync(recorded) ? recorded : (Bun.which(name) ?? undefined)
  const claudePath = locate(config.claudePath, "claude")
  const codexPath = locate(config.codexPath, "codex")
  await writeFile(
    CONFIG_FILE,
    JSON.stringify({ ...config, claudePath, codexPath, wowDir }, null, 2),
  )

  const { changed } = await extractAddon()
  await setup(wowDir)
  if (postUpdate) {
    // Read by `wai update`: did addon files change (so WoW needs a restart)?
    console.log(JSON.stringify({ addonChanged: changed }))
    return
  }
  console.log(`wai ${VERSION}: addon linked into ${addonsDir(wowDir)}`)
  for (const [label, fetch] of [
    ["yt-dlp", ensureYtDlp],
    ["ffmpeg", ensureFfmpeg],
  ] as const) {
    await fetch().catch((error) =>
      console.log(
        `couldn't fetch ${label} (video won't work until it can): ${error.message}`,
      ),
    )
  }
  console.log(`bridge ${await register()}`)
  if (!claudePath && !codexPath) {
    console.log(
      `No agent found. wai talks through Claude Code or Codex: ${INSTALL_HINTS.claude} (or for Codex, ${INSTALL_HINTS.codex}), then run wai install again.`,
    )
  } else {
    console.log(
      `agent ${NAMES[currentAgent()]} (change it in /settings or with wai agent)`,
    )
  }
  console.log("Done. Restart WoW, then type /wai in game.")
}

export async function uninstall(args: string[]) {
  await unregister()
  const wowDir = findWowDir()
  if (wowDir && (await exists(addonsDir(wowDir)))) {
    const dir = addonsDir(wowDir)
    for (const entry of await readdir(dir)) {
      if (entry === "wai" || HELPERS.test(entry)) {
        await rm(join(dir, entry), { recursive: true, force: true })
      }
    }
  }
  if (args.includes("--purge")) {
    await rm(HOME, { recursive: true, force: true })
  }
  console.log("wai removed from WoW and from login items.")
  if (COMPILED) {
    console.log(`Delete the binary to finish: ${process.execPath}`)
  }
  if (!args.includes("--purge")) {
    console.log(
      `Your chats and settings are still in ${HOME} (wai uninstall --purge removes them).`,
    )
  }
}

// `wai doctor`: everything that has to be true for wai to work.
// The model list is the cheapest call an OpenAI-compatible gateway answers, and it checks the key.
async function reachable(p: Proxy): Promise<[boolean, string]> {
  try {
    const res = await fetch(`${p.url}/v1/models`, {
      headers: p.key ? { Authorization: `Bearer ${p.key}` } : {},
      signal: AbortSignal.timeout(3000),
    })
    if (!res.ok) {
      return [false, `${p.url} answered ${res.status}; check --key`]
    }
    const { data } = (await res.json().catch(() => ({}))) as {
      data?: unknown[]
    }
    return [true, `${p.url}${data ? `, ${data.length} models` : ""}`]
  } catch {
    return [false, `${p.url} isn't answering; start it or run wai proxy off`]
  }
}

export async function doctor() {
  const checks: [string, boolean, string][] = []
  const wowDir = findWowDir()
  const record = await readFile(INSTALL_RECORD, "utf-8")
    .then(JSON.parse)
    .catch(() => {})
  checks.push(
    [
      "wai",
      true,
      `${VERSION} (${COMPILED ? (record?.managed ? "managed install, self-updates" : "binary") : "source checkout"})`,
    ],
    [
      "WoW: Forever",
      !!wowDir && (await exists(wowDir)),
      wowDir ?? "not found; run wai install --wow <path>",
    ],
  )
  if (wowDir) {
    const link = join(addonsDir(wowDir), "wai")
    const linked =
      (await realpath(link).catch(() => "")) ===
      (await realpath(ADDON_DIR).catch(() => "-"))
    checks.push(["addon linked", linked, linked ? link : "run wai install"])
    const missing = [
      ...SLOT_POOLS.map(([count, name]) => name(count)),
      ...LANES.map(([, name]) => name(BITS - 1)),
    ].filter((name) => !existsSync(join(addonsDir(wowDir), name)))
    checks.push([
      "helper addons",
      missing.length === 0,
      missing.length
        ? "run wai install"
        : `link ${BITS} + ${BITS}, slots ${MOD_SLOT_COUNT} + ${VID_SLOT_COUNT}`,
    ])
  }
  // One agent is enough; the one that answers must be installed.
  const answering = currentAgent()
  for (const agent of AGENTS) {
    const path = agentPath(agent)
    const version = path
      ? Bun.spawnSync([path, "--version"]).stdout.toString().trim()
      : ""
    const using = agent === answering ? " (answering)" : ""
    checks.push([
      `${NAMES[agent]} CLI`,
      !!version || agent !== answering,
      version ? `${version}${using}` : `not installed: ${INSTALL_HINTS[agent]}`,
    ])
  }
  const gateway = proxy()
  if (gateway) {
    checks.push(["proxy", ...(await reachable(gateway))])
  }
  const pid = await bridgePid()
  checks.push([
    "bridge running",
    !!pid,
    pid ? `pid ${pid}` : "run wai install (or wai run)",
  ])
  const autostart = await registered()
  checks.push([
    "starts at login",
    autostart,
    autostart
      ? "yes"
      : process.platform === "linux"
        ? "not supported on Linux"
        : "run wai install",
  ])
  const tools = await toolsPresent()
  checks.push([
    "video tools",
    tools.ytDlp && tools.ffmpeg,
    tools.ytDlp && tools.ffmpeg
      ? "yt-dlp, ffmpeg"
      : "downloaded on first video",
  ])
  for (const [name, ok, detail] of checks) {
    console.log(
      `${ok ? "\x1b[32m✓\x1b[0m" : "\x1b[31m✗\x1b[0m"} ${name.padEnd(16)} ${detail}`,
    )
  }
  return checks.every(([, ok]) => ok)
}
