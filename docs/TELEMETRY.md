# Telemetry

wai can send anonymous error reports so problems that only happen on other machines get fixed.
It's **off until you turn it on**, and it never includes your chats.

## Turning it on or off

- **In game:** wai asks once ("Help improve wai with anonymous error reports?"): Turn on or No thanks.
  Change it any time in `/settings` → Privacy → Error reports.
- **Terminal:** `wai telemetry on`, `wai telemetry off`, `wai telemetry` (status).

The in-game choice travels with every message to the bridge, which stores it in `~/.wai/config.json`.

## What a report contains

| Field | Example | |
|---|---|---|
| `event` | `lua_error` | what kind of problem (below) |
| `detail` | `Interface/AddOns/wai/ui.lua:12: attempt to index nil` | at most 300 characters; your character name, realm and home folder are replaced with `<name>` / `~` |
| `version` | `0.5.0` | wai version |
| `os`, `arch` | `darwin`, `arm64` | |
| `client` | `1.60.1.70790` | WoW client build |
| `install` | a random UUID | groups reports from one install; not tied to any account |
| `at` | ISO timestamp | |

Events: `lua_error` (an error in the addon), `stalled` (the addon lost touch with the bridge),
`claude_error`, `codex_error`, `video_error`, `update_error`, `install_error`, `decode_error`, `publish_error`, `scan_error`.

Never sent: your messages or the agent's replies, quest log, target, chat around you, character or
account names, file contents.

## Seeing what's sent

- In game: `/settings` → Privacy → **See what's sent** explains the format and lists what's waiting.
- Terminal: `wai telemetry show` lists everything queued and the last reports sent.

## Where reports go

Reports queue in `~/.wai/telemetry.jsonl` and are sent in batches to the collector set with
`wai telemetry url <url>` (or `WAI_TELEMETRY_URL`). With no collector configured they stay on
your machine (the newest 500).

The collector is `apps/telemetry`: a small Bun server that accepts `POST /v1/events` (a JSON array
of reports), drops anything that doesn't match the fields above exactly, and appends the rest to
`$DATA_DIR/events.jsonl`. Run it anywhere Bun runs:

```sh
PORT=8787 DATA_DIR=./data bun apps/telemetry/src/server.ts
```
