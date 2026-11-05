// Links the repo's addon folder into WoW and creates the files WoW must see at startup.
// Works on macOS (symlink) and Windows (directory junction, no admin needed).
import { exists, lstat, mkdir, realpath, symlink, writeFile } from "node:fs/promises";
import { join } from "node:path";
import {
  ADDON_DIR, ADDONS_DIR, MOD_SLOT_COUNT, SLOT_COUNT, VID_SLOT_COUNT, WOW_DIR, ensureStubs, modSlotFile, modSlotName,
  slotFile, slotName, vidSlotFile, vidSlotName,
} from "./files";
import { ensureYtDlp } from "./tools";

if (!(await exists(WOW_DIR))) {
  console.error(`WoW Forever not found at ${WOW_DIR}. Set WOW_DIR or "wowDir" in bridge/config.json.`);
  process.exit(1);
}
await mkdir(ADDONS_DIR, { recursive: true });

const target = join(ADDONS_DIR, "wai");
const existing = await lstat(target).catch(() => undefined);
if (!existing) {
  await symlink(ADDON_DIR, target, process.platform === "win32" ? "junction" : "dir");
  console.log(`linked ${target} -> ${ADDON_DIR}`);
} else if ((await realpath(target)) === (await realpath(ADDON_DIR))) {
  console.log(`already linked: ${target}`);
} else {
  console.error(`${target} exists and isn't a link to ${ADDON_DIR}; remove it and rerun`);
  process.exit(1);
}

await ensureStubs();

// Hidden helper addons: message slots and UI module slots, all load-on-demand.
async function makeSlots(count: number, name: (i: number) => string, file: (i: number) => string, title: string) {
  for (let i = 1; i <= count; i++) {
    const dir = join(ADDONS_DIR, name(i));
    await mkdir(dir, { recursive: true });
    const lua = file(i).slice(dir.length + 1);
    await writeFile(
      join(dir, `${name(i)}.toc`),
      `## Interface: 16001\n## Title: ${title} ${i}\n## Category: wai\n## Group: wai\n## LoadOnDemand: 1\n\n${lua}\n`,
    );
    if (!(await exists(file(i)))) await writeFile(file(i), "-- empty\n");
  }
}
await makeSlots(SLOT_COUNT, slotName, slotFile, "wai slot");
await makeSlots(MOD_SLOT_COUNT, modSlotName, modSlotFile, "wai ui");
await makeSlots(VID_SLOT_COUNT, vidSlotName, vidSlotFile, "wai video");
console.log(`created ${SLOT_COUNT} message, ${MOD_SLOT_COUNT} UI and ${VID_SLOT_COUNT} video slots in ${ADDONS_DIR}.`);

// yt-dlp for videos (ffmpeg comes from the ffmpeg-static package).
await ensureYtDlp().catch((err) => console.error(`couldn't fetch yt-dlp (videos won't work): ${err.message}`));
console.log("Start the bridge (bun start), then restart WoW.");
