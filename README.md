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

wai is one binary per platform (bridge, CLI and addon together). The installer picks yours, checks its SHA-256, installs it to `~/.local/bin` and runs `wai install`, which finds WoW: Forever, links the addon, creates the slot addons and starts the bridge at login.

```sh
# macOS / Linux
curl -fsSL https://raw.githubusercontent.com/dan-myles/wai/main/install.sh | sh
```

```powershell
# Windows
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/dan-myles/wai/main/install.ps1)))
```

The repo is private, so sign in with the GitHub CLI first (`gh auth login`). The script then downloads through `gh`, and for the script itself use `gh api repos/dan-myles/wai/contents/install.sh -H "Accept: application/vnd.github.raw" | sh`. Options: `--version v0.1.0`, `--wow "<path to _forever_>"` (`-Version`, `-WowDir` on Windows). You also need the [Claude CLI](https://claude.ai/install), signed in once with `claude`. Then restart WoW.

| Command | |
|---|---|
| `wai install [--wow <path>]` | link the addon, create slots, start the bridge at login |
| `wai update` | update to the latest release (also `/update` in game) |
| `wai status` | check everything wai needs (`doctor`) |
| `wai logs [-f]` | show or follow the bridge log |
| `wai uninstall [--purge]` | remove wai from WoW and login items |

**Development:** run from a source checkout with `cd bridge && bun install && bun run setup && bun start`, or `bun src/cli.ts <command>`. Tests: `bun test` and `bun run test:addon` (needs `luajit`). Releases: bump `bridge/package.json`, add a `CHANGELOG.md` section, push a `vX.Y.Z` tag, and GitHub Actions builds and publishes the binaries.

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
