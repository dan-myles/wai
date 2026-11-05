#!/usr/bin/env bash
# wai installer for macOS. Installs Bun and the Claude CLI if missing, links the addon into
# WoW: Forever, creates the slot addons and starts the bridge at login (launchd).
#   ./install.sh                     auto-detect WoW
#   ./install.sh "/path/to/_forever_"
#   ./install.sh --uninstall         stop the bridge and remove auto-start
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BRIDGE="$ROOT/bridge"
LABEL="com.wai.bridge"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

say() { printf "\033[1;33mwai\033[0m %s\n" "$*"; }
fail() { printf "\033[1;31mwai\033[0m %s\n" "$*" >&2; exit 1; }

if [[ "${1:-}" == "--uninstall" ]]; then
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  rm -f "$PLIST"
  say "Bridge stopped and removed from login items. Delete Interface/AddOns/wai* in WoW to remove the addon."
  exit 0
fi

# 1. Bun
if ! command -v bun >/dev/null; then
  say "Installing Bun…"
  curl -fsSL https://bun.sh/install | bash
  export PATH="$HOME/.bun/bin:$PATH"
fi

# 2. Claude CLI
if ! command -v claude >/dev/null; then
  say "Installing the Claude CLI…"
  curl -fsSL https://claude.ai/install.sh | bash
  export PATH="$HOME/.local/bin:$PATH"
fi
command -v claude >/dev/null || fail "Claude CLI not found after install. Open a new terminal and rerun."

# 3. WoW: Forever
WOW_DIR="${1:-}"
if [[ -z "$WOW_DIR" ]]; then
  for candidate in "/Applications/World of Warcraft/_forever_" "$HOME/Applications/World of Warcraft/_forever_"; do
    [[ -d "$candidate" ]] && WOW_DIR="$candidate" && break
  done
fi
[[ -n "$WOW_DIR" && -d "$WOW_DIR" ]] || fail "Couldn't find WoW: Forever. Run: ./install.sh \"/path/to/World of Warcraft/_forever_\""
say "WoW: Forever at $WOW_DIR"

cat > "$BRIDGE/config.json" <<EOF
{
  "wowDir": "$WOW_DIR",
  "claudePath": "$(command -v claude)"
}
EOF

# 4. Bridge + addon
cd "$BRIDGE"
bun install
bun run setup

# 5. Start the bridge now and at every login.
mkdir -p "$(dirname "$PLIST")"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>$(command -v bun)</string><string>src/index.ts</string></array>
  <key>WorkingDirectory</key><string>$BRIDGE</string>
  <key>EnvironmentVariables</key>
  <dict><key>PATH</key><string>$PATH</string></dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$BRIDGE/bridge.log</string>
  <key>StandardErrorPath</key><string>$BRIDGE/bridge.log</string>
</dict>
</plist>
EOF
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
pkill -f "bun src/index.ts" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
say "Bridge running (log: $BRIDGE/bridge.log) and set to start at login."

if ! claude -p "reply with ok" --output-format json >/dev/null 2>&1; then
  say "Sign in to Claude once: run 'claude' in a terminal and follow the prompts."
fi
say "Done. Restart WoW, then type /wai in game."
