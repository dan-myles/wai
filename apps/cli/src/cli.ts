// The `wai` command. One binary per platform (see scripts/build.ts); in a source checkout run it
// with `bun src/cli.ts <command>`.
import {
  appendFileSync,
  existsSync,
  readFileSync,
  renameSync,
  statSync,
  unlinkSync,
  watch,
  writeFileSync,
} from "node:fs"
import { mkdir, readFile } from "node:fs/promises"

import {
  AGENTS,
  INSTALL_HINTS,
  NAMES,
  DEFAULT_PROXY,
  agentPath,
  currentAgent,
  isAgent,
  proxy,
  proxyRoot,
} from "./agent"
import { HOME, LOG_FILE, PID_FILE, writeConfig } from "./files"
import { doctor, install, uninstall } from "./install"
import { bridgePid, restart } from "./service"
import { enabled, endpoint, flush, history, setConsent } from "./telemetry"
import { TRACKS, currentTrack, isTrack, update } from "./update"
import { VERSION } from "./version"

const HELP = `wai ${VERSION}: Claude or Codex inside World of Warcraft: Forever

Usage: wai <command>

  install [--wow <path>]   link the addon into WoW, create helper addons, start the bridge at login
  run                      run the bridge (the background service does this for you)
  update                   update wai to the latest release (alias: upgrade)
  status                   check that everything wai needs is in place (alias: doctor)
  logs [-f]                show the bridge log, or follow it
  agent [claude|codex]     show or choose which agent answers (also /settings in game)
  track [stable|nightly]   show or choose the update track (also /settings in game)
  proxy [on|off|<url>] [--key <key>] [--model <model>]
                           send both agents through an API gateway like CLIProxyAPI (on: ${DEFAULT_PROXY})
  uninstall [--purge]      remove wai from WoW and login items (--purge also deletes chats and settings)
  telemetry [on|off|show|url <url>]
                           anonymous error reports: off until you turn them on (see docs/TELEMETRY.md)
  version                  print the version

In game, type /wai to open the chat, /help for commands, /update to update from inside WoW.`

// Tee console output into the log file, rotating at 5 MB, so background runs leave a trail.
function logToFile() {
  for (const level of ["log", "error"] as const) {
    const original = console[level]
    console[level] = (...args: unknown[]) => {
      original(...args)
      try {
        if (existsSync(LOG_FILE) && statSync(LOG_FILE).size > 5_000_000) {
          renameSync(LOG_FILE, `${LOG_FILE}.1`)
        }
        const line = args
          .map((a) =>
            a instanceof Error
              ? a.stack
              : typeof a === "string"
                ? a
                : JSON.stringify(a),
          )
          .join(" ")
        appendFileSync(LOG_FILE, `${new Date().toISOString()} ${line}\n`)
      } catch {
        // Logging must never take the bridge down.
      }
    }
  }
}

// One bridge at a time. A freshly updated bridge waits for the old one to exit first.
async function claimPidFile() {
  for (let i = 0; ; i++) {
    const pid = await bridgePid()
    if (!pid || pid === process.pid) {
      break
    }
    if (i >= 30) {
      console.error(`wai bridge already running (pid ${pid})`)
      process.exit(0)
    }
    await Bun.sleep(500)
  }
  writeFileSync(PID_FILE, String(process.pid))
  const release = () => {
    try {
      if (
        existsSync(PID_FILE) &&
        Number(readFileSync(PID_FILE, "utf-8")) === process.pid
      ) {
        unlinkSync(PID_FILE)
      }
    } catch {
      // Exiting anyway; a stale pid file is ignored by the next run.
    }
  }
  process.on("exit", release)
  for (const sig of ["SIGINT", "SIGTERM"] as const) {
    process.on(sig, () => process.exit(0))
  }
}

async function telemetry(args: string[]) {
  const [action, value] = args
  if (action === "on" || action === "off") {
    setConsent(action === "on")
  }
  if (action === "url") {
    writeConfig({ telemetryUrl: value || undefined })
  }
  if (action === "show") {
    const { queued, sent } = await history()
    console.log(
      `queued (${queued.length}):\n${queued.slice(-20).join("\n")}\n\nsent (${sent.length}):\n${sent.slice(-20).join("\n")}`,
    )
    return
  }
  await flush()
  console.log(
    `error reports: ${enabled() ? "on" : "off"}${endpoint() ? ` (sending to ${endpoint()})` : " (no endpoint set; reports stay queued on this machine)"}`,
  )
}

// The running bridge reads the choice on every message, so no restart is needed.
function agent(args: string[]) {
  const [choice] = args
  if (choice) {
    if (!isAgent(choice)) {
      throw new Error(`unknown agent "${choice}"; use ${AGENTS.join(" or ")}`)
    }
    if (!agentPath(choice)) {
      throw new Error(
        `${NAMES[choice]} isn't installed: ${INSTALL_HINTS[choice]}`,
      )
    }
    writeConfig({ agent: choice })
  }
  for (const a of AGENTS) {
    const mark = a === currentAgent() ? "●" : agentPath(a) ? "○" : "✗"
    console.log(`${mark} ${a}${agentPath(a) ? "" : " (not installed)"}`)
  }
}

// Like the agent choice, read on every message: no restart needed.
function gateway(args: string[]) {
  const flag = (name: string) => {
    const i = args.indexOf(`--${name}`)
    return i !== -1 ? args[i + 1] : undefined
  }
  const [target] = args
  const current = proxy()
  if (target === "off") {
    writeConfig({ proxy: undefined })
  } else if (target) {
    const url =
      target === "on" || target.startsWith("--")
        ? (current?.url ?? DEFAULT_PROXY)
        : proxyRoot(target)
    if (!/^https?:\/\/[^/]/.test(url)) {
      throw new Error(`"${target}" isn't a URL; use e.g. ${DEFAULT_PROXY}`)
    }
    // An empty value clears a key or model: --model ""
    const key = flag("key") ?? current?.key
    const model = flag("model") ?? current?.model
    writeConfig({
      proxy: { key: key || undefined, model: model || undefined, url },
    })
  }
  const now = proxy()
  console.log(
    now
      ? `proxy on: ${now.url}${now.key ? " (with key)" : ""}${now.model ? `, model ${now.model}` : ""}`
      : "proxy off: agents use their own sign-in",
  )
}

async function logs(follow: boolean) {
  const text = await readFile(LOG_FILE, "utf-8").catch(() => "")
  console.log(text.split("\n").slice(-80).join("\n"))
  if (!follow) {
    return
  }
  let size = text.length
  watch(LOG_FILE, async () => {
    const now = await readFile(LOG_FILE, "utf-8").catch(() => "")
    if (now.length > size) {
      process.stdout.write(now.slice(size))
    }
    size = now.length
  })
  await new Promise(() => {})
}

const [command = "help", ...args] = process.argv.slice(2)
try {
  switch (command) {
    case "run": {
      await mkdir(HOME, { recursive: true })
      logToFile()
      await claimPidFile()
      console.log(`wai ${VERSION} bridge starting`)
      await import("./index")
      break
    }
    case "install": {
      await install(args)
      break
    }
    case "update":
    case "upgrade": {
      const result = await update((msg) => console.log(msg))
      console.log(result.message)
      if (result.updated) {
        await restart()
      }
      break
    }
    case "status":
    case "doctor": {
      process.exitCode = (await doctor()) ? 0 : 1
      break
    }
    case "logs": {
      await logs(args.includes("-f") || args.includes("--follow"))
      break
    }
    case "telemetry": {
      await telemetry(args)
      break
    }
    case "agent": {
      agent(args)
      break
    }
    case "track": {
      const [choice] = args
      if (choice) {
        if (!isTrack(choice)) {
          throw new Error(
            `unknown track "${choice}"; use ${TRACKS.join(" or ")}`,
          )
        }
        writeConfig({ track: choice })
      }
      console.log(`update track: ${currentTrack()}`)
      break
    }
    case "mcp": {
      // Started by the agent CLIs themselves, not by players.
      await (await import("./mcp")).serve()
      break
    }
    case "proxy": {
      gateway(args)
      break
    }
    case "uninstall": {
      await uninstall(args)
      break
    }
    case "version":
    case "--version":
    case "-v": {
      console.log(`wai ${VERSION}`)
      break
    }
    default: {
      console.log(HELP)
      if (command !== "help" && command !== "--help" && command !== "-h") {
        process.exitCode = 1
      }
    }
  }
} catch (error) {
  console.error(
    `wai: ${error instanceof Error ? error.message : String(error)}`,
  )
  process.exit(1)
}
