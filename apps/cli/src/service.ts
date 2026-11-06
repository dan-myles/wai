// Runs the bridge in the background at login: launchd on macOS, Task Scheduler on Windows (through
// a tiny VBScript so no console window appears). Linux has no service; run `wai run` yourself.
import { exists, mkdir, readFile, rm, writeFile } from "node:fs/promises"
import { homedir } from "node:os"
import { join } from "node:path"

import { HOME, LOG_FILE, PID_FILE, selfCommand } from "./files"

const LABEL = "com.wai.bridge"
const PLIST = join(homedir(), "Library", "LaunchAgents", `${LABEL}.plist`)
const TASK = "wai bridge"
const VBS = join(HOME, "wai-bridge.vbs")

const xml = (s: string) =>
  s.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;")

export async function bridgePid(): Promise<number | undefined> {
  const pid = Number(await readFile(PID_FILE, "utf-8").catch(() => ""))
  if (!pid) {
    return undefined
  }
  try {
    process.kill(pid, 0)
    return pid
  } catch {
    return undefined
  }
}

async function stopBridge() {
  const pid = await bridgePid()
  if (pid && pid !== process.pid) {
    process.kill(pid)
  }
}

function launchWindows() {
  Bun.spawn(["wscript.exe", VBS], {
    stdio: ["ignore", "ignore", "ignore"],
  }).unref()
}

export async function register(): Promise<string> {
  if (process.env.WAI_NO_SERVICE) {
    return "auto-start skipped (WAI_NO_SERVICE)"
  }
  await mkdir(HOME, { recursive: true })
  const cmd = selfCommand("run")
  if (process.platform === "darwin") {
    await mkdir(join(homedir(), "Library", "LaunchAgents"), { recursive: true })
    await writeFile(
      PLIST,
      `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>${cmd.map((a) => `<string>${xml(a)}</string>`).join("")}</array>
  <key>EnvironmentVariables</key>
  <dict><key>PATH</key><string>${xml(process.env.PATH ?? "/usr/bin:/bin")}</string></dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardErrorPath</key><string>${xml(LOG_FILE)}</string>
</dict>
</plist>
`,
    )
    const uid = process.getuid?.() ?? 501
    Bun.spawnSync(["launchctl", "bootout", `gui/${uid}/${LABEL}`], {
      stderr: "ignore",
    })
    // bootout finishes asynchronously; bootstrap fails with "Input/output error" until it has.
    let res = Bun.spawnSync(["launchctl", "bootstrap", `gui/${uid}`, PLIST], {
      stderr: "pipe",
    })
    for (let i = 0; i < 20 && res.exitCode !== 0; i++) {
      await Bun.sleep(250)
      res = Bun.spawnSync(["launchctl", "bootstrap", `gui/${uid}`, PLIST], {
        stderr: "pipe",
      })
    }
    if (res.exitCode !== 0) {
      throw new Error(`launchctl: ${res.stderr.toString().trim()}`)
    }
    return "starts at login (launchd)"
  }
  if (process.platform === "win32") {
    const line = cmd.map((a) => `""${a}""`).join(" ")
    await writeFile(
      VBS,
      `CreateObject("WScript.Shell").Run "${line}", 0, False\r\n`,
    )
    const res = Bun.spawnSync(
      [
        "schtasks",
        "/Create",
        "/F",
        "/SC",
        "ONLOGON",
        "/TN",
        TASK,
        "/TR",
        `wscript.exe "${VBS}"`,
      ],
      { stderr: "pipe" },
    )
    if (res.exitCode !== 0) {
      throw new Error(`schtasks: ${res.stderr.toString().trim()}`)
    }
    await stopBridge()
    launchWindows()
    return "starts at logon (Task Scheduler)"
  }
  return "no auto-start on this OS; run `wai run`"
}

export function registered(): Promise<boolean> {
  if (process.platform === "darwin") {
    return exists(PLIST)
  }
  if (process.platform === "win32") {
    const query = Bun.spawnSync(["schtasks", "/Query", "/TN", TASK], {
      stdout: "ignore",
      stderr: "ignore",
    })
    return Promise.resolve(query.exitCode === 0)
  }
  return Promise.resolve(false)
}

// Restart the background bridge, e.g. after an update (from the CLI, not from inside the bridge).
export async function restart() {
  if (process.platform === "darwin" && (await exists(PLIST))) {
    Bun.spawnSync([
      "launchctl",
      "kickstart",
      "-k",
      `gui/${process.getuid?.() ?? 501}/${LABEL}`,
    ])
  } else if (process.platform === "win32" && (await exists(VBS))) {
    await stopBridge()
    launchWindows()
  }
}

// From inside the bridge: hand over to a fresh process (running the updated binary) and exit.
// launchd's KeepAlive restarts us on macOS; on Windows we start the new one ourselves, and it waits
// for this process to let go of the pid file.
export async function relaunchSelf(): Promise<never> {
  if (process.platform === "win32" && (await exists(VBS))) {
    launchWindows()
  } else if (process.platform !== "darwin") {
    Bun.spawn(selfCommand("run"), {
      stdio: ["ignore", "ignore", "ignore"],
    }).unref()
  }
  process.exit(0)
}

export async function unregister() {
  if (process.platform === "darwin") {
    Bun.spawnSync(
      ["launchctl", "bootout", `gui/${process.getuid?.() ?? 501}/${LABEL}`],
      { stderr: "ignore" },
    )
    await rm(PLIST, { force: true })
  } else if (process.platform === "win32") {
    Bun.spawnSync(["schtasks", "/Delete", "/F", "/TN", TASK], {
      stderr: "ignore",
    })
    await rm(VBS, { force: true })
  }
  await stopBridge()
}
