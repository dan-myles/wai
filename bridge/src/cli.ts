// The `wai` command. One binary per platform (see scripts/build.ts); in a source checkout run it
// with `bun src/cli.ts <command>`.
import { appendFileSync, existsSync, readFileSync, renameSync, statSync, unlinkSync, watch, writeFileSync } from "node:fs";
import { mkdir, readFile } from "node:fs/promises";
import { HOME, LOG_FILE, PID_FILE } from "./files";
import { doctor, install, uninstall } from "./install";
import { bridgePid, restart } from "./service";
import { update } from "./update";
import { VERSION } from "./version";

const HELP = `wai ${VERSION}: Claude inside World of Warcraft: Forever

Usage: wai <command>

  install [--wow <path>]   link the addon into WoW, create slot addons, start the bridge at login
  run                      run the bridge (the background service does this for you)
  update                   update wai to the latest release (alias: upgrade)
  status                   check that everything wai needs is in place (alias: doctor)
  logs [-f]                show the bridge log, or follow it
  uninstall [--purge]      remove wai from WoW and login items (--purge also deletes chats and settings)
  version                  print the version

In game, type /wai to open the chat, /help for commands, /update to update from inside WoW.`;

// Tee console output into the log file, rotating at 5 MB, so background runs leave a trail.
function logToFile() {
  for (const level of ["log", "error"] as const) {
    const original = console[level];
    console[level] = (...args: unknown[]) => {
      original(...args);
      try {
        if (existsSync(LOG_FILE) && statSync(LOG_FILE).size > 5_000_000) renameSync(LOG_FILE, `${LOG_FILE}.1`);
        const line = args.map((a) => (a instanceof Error ? a.stack : typeof a === "string" ? a : JSON.stringify(a))).join(" ");
        appendFileSync(LOG_FILE, `${new Date().toISOString()} ${line}\n`);
      } catch {}
    };
  }
}

// One bridge at a time. A freshly updated bridge waits for the old one to exit first.
async function claimPidFile() {
  for (let i = 0; ; i++) {
    const pid = await bridgePid();
    if (!pid || pid === process.pid) break;
    if (i >= 30) {
      console.error(`wai bridge already running (pid ${pid})`);
      process.exit(0);
    }
    await Bun.sleep(500);
  }
  writeFileSync(PID_FILE, String(process.pid));
  const release = () => {
    try {
      if (existsSync(PID_FILE) && Number(readFileSync(PID_FILE, "utf8")) === process.pid) unlinkSync(PID_FILE);
    } catch {}
  };
  process.on("exit", release);
  for (const sig of ["SIGINT", "SIGTERM"] as const) process.on(sig, () => process.exit(0));
}

async function logs(follow: boolean) {
  const text = await readFile(LOG_FILE, "utf8").catch(() => "");
  console.log(text.split("\n").slice(-80).join("\n"));
  if (!follow) return;
  let size = text.length;
  watch(LOG_FILE, async () => {
    const now = await readFile(LOG_FILE, "utf8").catch(() => "");
    if (now.length > size) process.stdout.write(now.slice(size));
    size = now.length;
  });
  await new Promise(() => {});
}

const [command = "help", ...args] = process.argv.slice(2);
try {
  switch (command) {
    case "run":
      await mkdir(HOME, { recursive: true });
      logToFile();
      await claimPidFile();
      console.log(`wai ${VERSION} bridge starting`);
      await import("./index");
      break;
    case "install":
      await install(args);
      break;
    case "update":
    case "upgrade": {
      const result = await update((msg) => console.log(msg));
      console.log(result.message);
      if (result.updated) await restart();
      break;
    }
    case "status":
    case "doctor":
      process.exitCode = (await doctor()) ? 0 : 1;
      break;
    case "logs":
      await logs(args.includes("-f") || args.includes("--follow"));
      break;
    case "uninstall":
      await uninstall(args);
      break;
    case "version":
    case "--version":
    case "-v":
      console.log(`wai ${VERSION}`);
      break;
    default:
      console.log(HELP);
      if (command !== "help" && command !== "--help" && command !== "-h") process.exitCode = 1;
  }
} catch (err) {
  console.error(`wai: ${err instanceof Error ? err.message : String(err)}`);
  process.exit(1);
}
