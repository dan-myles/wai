# wai

Talk to Claude from inside World of Warcraft: Forever. Native addon, no overlay, no reloads.

## How it works

WoW addons can't do network or file I/O, so wai uses two client features instead:

```
Enter ─▶ addon paints message as a bit grid ─▶ Screenshot() ─▶ Screenshots/*.tga ─▶ bridge decodes
                                                                                        │ claude -p (streaming)
window ◀─ addon loads next slot addon each second ◀─ bridge writes wai_slotNNN/slot.lua ◀┘
```

- **Out:** each message becomes black/white blocks in a magenta frame. The addon takes a lossless TGA screenshot, and the bridge decodes it and deletes the file.
- **In:** 500 load-on-demand `wai_slotNNN` addons. Loading one reads its file from disk at that moment, so the bridge streams snapshots into the slots the addon will load next. Each slot can be loaded once per session, and a reload resets the pool.
- **Fallback:** `WaiDB.outbox` (SavedVariables) flushes on reload, and `addon/Data.lua` holds history. Seq numbers plus `ackSeq` make resends harmless.
- Claude runs with the addon folder as cwd and can write custom UI into `addon/Generated.lua`. It never automates gameplay.

## Install

Clone the repo, then run the installer. It installs Bun and the Claude CLI if missing, finds WoW: Forever, links the addon, creates the slot addons and starts the bridge at login.

```sh
./install.sh                                   # macOS (launchd)
./install.sh "/path/to/World of Warcraft/_forever_"
```

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1          # Windows (Task Scheduler)
powershell -ExecutionPolicy Bypass -File install.ps1 -WowDir "D:\Games\World of Warcraft\_forever_"
```

Then restart WoW (new addons load only on client start). If Claude isn't signed in yet, run `claude` once. `--uninstall` / `-Uninstall` removes the auto-start. Settings live in `bridge/config.json`.

Manual run: `cd bridge && bun install && bun run setup && bun start`.

## In game

- `/wai` toggles the window (or bind a key: Key Bindings → AddOns). Commands: `/help`, `/new`, `/reload`, and `/fun` (a menu of toggles and test buttons for TikTok mode, killstreaks and video). Everything else, just ask.
- **Ask from anywhere:** Alt-click an item, a quest in your log, your target's portrait or a player's name in chat. Quest dialogs have an Ask wai button.
- **Rich replies:** item, spell and quest links with tooltips, and blue pins that set wai's waypoint arrow.
- **Memory and actions:** each character has its own conversation. Claude saves and forgets notes and sets the waypoint arrow itself, following [bridge/SKILL.md](bridge/SKILL.md), which is injected into every prompt.
- **Context:** character, target, zone, quest log, recent chat, killstreak, and recent fights plus your last death from Blizzard's damage meter.
- **Tabs:** up to 8 parallel chats per character, each its own Claude session, with a live activity line while Claude works.
- **Live UI:** ask for UI and Claude writes a module (`addon/ui/<name>.lua`) that appears in game within seconds, no reload.
- **Killstreaks:** 11 kills without dying calls in the Chopper Gunner, and 25 drops a Nuke. Cosmetic only.
- **Video:** "show me a guide for…" plays a pixel-art clip (yt-dlp + ffmpeg, up to 2 minutes, no sound). "Turn on TikTok mode" docks a looping vertical clip with captions and stream chat.

wai doesn't depend on any other addon. Design rules live in [DESIGN.md](DESIGN.md); deferred ideas in [PARKING_LOT.md](PARKING_LOT.md).

Debugging: Lua errors print as `wai error:` in chat, and are also saved to `WTF/SavedVariables/Blizzard_Console.lua` on reload.
