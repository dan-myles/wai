# wai design language

Modern Warcraft: a UI that feels native in World of Warcraft without the medieval ornament. Think a
well-made modern unit frame: dark slate panels, thin gold lines, round portraits, Friz Quadrata for
titles, quiet motion. Everything is drawn from plain textures in `addon/theme.lua`; no Blizzard
frame templates, no other addons.

## Principles

1. **Native, not nostalgic.** Use WoW's visual vocabulary (gold, Friz Quadrata, quality colours, ringed portraits), skip parchment, filigree and bevels.
2. **Calm surfaces, gold accents.** Panels are dark and flat. Gold marks what matters: titles, the primary action, focus, borders.
3. **Readable first.** Display text is Friz Quadrata. Anything you read for more than a line is Geist.
4. **One system.** Every wai surface (chat window, waypoint arrow, quest-dialog button) uses `theme.lua` primitives. New UI adds a primitive there instead of one-off drawing.
5. **Quiet motion.** Short fades, pulsing dots for "working", a typewriter for streamed text. Nothing bounces.

## Colour

Defined in `T.C` (`theme.lua`).

| Token | Hex | Use |
|---|---|---|
| `bg` | `#0D1016` | Window background |
| `panel` | `#141922` | Cards, buttons, banners |
| `panelHover` | `#1A202B` | Hovered outline buttons |
| `inset` | `#090B0F` | Recessed fields (input, notes, portrait backs) |
| `line` | `#262C36` | Hairline borders on cards and inputs |
| `lineStrong` | `#39414E` | Stronger dividers |
| `gold` | `#FFD100` | Titles, names, hovered text (WoW's own gold) |
| `goldSoft` | `#C9A24B` | Primary buttons, rings, focus, the arrow |
| `goldDim` | `#8C6F3A` | Window border, section labels, faded dividers |
| `text` | `#ECE6D6` | Body text, a warm off-white |
| `muted` | `#9298A3` | Secondary text, hints |
| `subtle` | `#5F6672` | Placeholders, disabled text |
| `ink` | `#1A1206` | Text and icons on gold |
| `uncommon` | `#1EFF00` | Status: ready, arrived |
| `rare` | `#3FA0FF` | Status: thinking or writing; waypoint pins |
| `red` / `redBg` / `redLine` | `#FF5A5A` / `#220C0E` / `#6E2228` | Errors |

Your messages use your **class colour** at 20% over `panel`, with a 45% class-colour border.
Status colours borrow WoW's item-quality colours so they read instantly.
Link colours follow WoW: items by quality, spells `#71D5FF`, quests `#FFFF00`, NPC names `#FFD100`.

## Type

| Face | File | Use |
|---|---|---|
| Display | `Fonts\FRIZQT__.TTF` (Friz Quadrata) | Titles, names, buttons, status, section labels. Always with a 1px black drop shadow. |
| Regular | `media/Geist-Regular.ttf` | Message text, input, hints |
| Medium | `media/Geist-Medium.ttf` | Banner text |

Sizes: 17 empty-state title · 15 window title · 13 messages and input · 12 names, buttons, notes · 11 hints, small buttons · 10 status and uppercase section labels (`NEW CONVERSATION`, `ASKING ABOUT`).
Line spacing 3–4px on multi-line text.

## Shape and depth

- **Radius:** 10 window and cards · 8 notes, banners, chips, attachment bar · 6 small buttons · fully round for icon buttons, the send button and portraits.
- **Borders:** 1 physical pixel (`T.px()`), never thicker. The window border is `goldDim` at 85%. Cards use `line`.
- **Dividers:** `T.fadedLine`, a gold hairline that fades out at both ends. Never a hard full-width rule.
- **Shadow:** three stacked rounded rects at 35/16/7% black, spreading 4/8/12px (`T.panel`).
- **Depth:** the window gets a faint vertical gradient, and the header a 7% gold sheen falling from the top edge.
- **Portraits:** round art in a gold ring (`T.portrait`); wai's is the Arcane Intellect icon.

## Components

- **Window** (`ui.lua`): header (portrait, title, subtitle, New Chat, close), message list, banner, attachment bar, input, footer (hint, status dot, resize grip). Drag by the header, resize from the corner, Esc closes.
- **Messages:** yours are right-aligned class-tinted bubbles. wai's sit on a slate card beside a portrait, with the name in gold. Notes (command output) are inset cards with a dim gold border. Errors are red cards. New conversations are a centred uppercase label between faded lines.
- **Thinking:** three gold dots pulsing in sequence, followed by a softly pulsing activity line ("Searching the web for …"). The line also appears under a streaming reply while a tool runs.
- **Tabs:** a strip under the header. The active tab has gold Friz text, a 7% gold wash and a 2px `goldSoft` underline; inactive tabs are muted. A pulsing `rare` dot means working and a gold dot means unread. `+` adds a tab; double-click renames inline; right-click opens a small menu (a panel with Rename and a red Delete that asks for a second click, "Clear chat" on the last tab); middle-click closes. When wai retitles a tab, the new name fades in from 30% under a gold wash that settles over about 0.8s.
- **Killstreak:** a large gold count with a `KILLSTREAK` label that pops under the top of the screen. Chopper Gunner is a thermal-green tint, black vignette and rotating reticle. Nuke is a pulsing red vignette with a 120pt red countdown, ending in a white flash.
- **Buttons** (`T.button`): `gold` filled call to action with ink text; `outline` slate with a hairline that turns gold on hover; `ghost` text-only gold. Disabled buttons drop to `panel` and `subtle`.
- **Input:** recessed `inset` field. On focus the border turns `goldSoft` with a soft gold glow behind it. Round gold send button with an arrow.
- **Toggles** (`T.toggle`): a label (Geist 13, gold on hover) with an optional muted hint, and a 36×20 rounded track on the right. Off is an `inset` track, `line` border and muted knob. On is a `goldSoft` track with an `ink` knob that slides across.
- **Segmented control** (`T.segmented`): a label and hint on the left; on the right a 24px `inset` track with a hairline border holding pill segments in Geist Medium 11. The selected segment fills `goldSoft` with `ink` text; the others are muted and turn gold on hover.
- **Macro cards:** a macro in a reply renders on its own lines: "Macro Name (this character)" in dim gold, then each line of the body in muted grey. While it streams in, a single "Writing a macro…" line stands in for it.
- **Selecting text:** clicking a message (not a link) swaps its text for a read-only edit box in the same font and spot, fully highlighted in translucent gold; the footer hint turns into "Ctrl+C to copy · Esc when done". Links, colours and pins drop out of the copied text.
- **Settings panel** (`/settings`, or the gear in the chat header): a 340px floating panel in the same chrome as the Fun menu, with `GENERAL` (starting with the Claude | Codex agent switch and the Open wai key picker, an outline button showing the key that reads "Press a key…" while it listens), `PRIVACY`, `WINDOWS` and `ABOUT` (starting with the Stable | Nightly updates switch) sections. Rows are toggles, segmented controls and outline buttons, each with a one-line hint. The About line shows the version in gold and the bridge's last contact in muted text.
- **Minimap button:** a 32px wai portrait (gold ring, arcane icon) on the minimap ring. On hover the ring turns full `gold` and an 18% gold halo appears behind it. A 9px status dot at the top right pulses `rare` blue while wai works and holds `gold` when a reply is unread.
- **Fun menu** (`/fun`): a 300px floating panel with a portrait, "Fun" title and ×. `TOGGLES` and `TEST` section labels sit beside faded gold lines; test actions are a two-column grid of outline buttons.
- **Banners:** one line plus an optional gold action and an optional ghost secondary action to its left (the privacy consent banner's "No thanks"). Tones: warn (gold), error (red), info (blue).
- **Attachment bar:** `ASKING ABOUT` label, item icon, the link, and a × to remove.
- **Suggestions:** a slate list above the input. The command name is gold Friz, the hint is muted and right-aligned, and the selected row gets an 8% gold wash.
- **Waypoint arrow** (`waypoint.lua`): a 58px dark disc in a gold ring with a gold arrowhead inside, on a faint gold halo. Place name in gold Friz and distance in muted Geist underneath. When you arrive, it turns `uncommon` green and fades out.
- **Tooltips** (`T.tooltip`): gold title, muted wrapped lines.
- **Video player:** a standard panel with the title in gold Friz, a ×, a 5-unit block grid and a 2px gold progress bar on a `line` track. Click the picture to pause. In TikTok mode it docks 12px to the right of the chat window with a pulsing red `LIVE` tag, 15pt Friz captions with a heavy shadow over the lower third, and stream chat bottom-left with names in bright neon colours.
- **UI modules** that Claude builds use these same primitives; module code gets `theme.lua` as `wai.theme`.

## Motion

- Windows and the arrow fade in over 0.12–0.2s.
- Streamed text types at 90 characters per second, speeding up to catch up so it never lags the stream.
- "Working" states pulse; idle states stay still.

## Copy

Short, warm, a little in-world ("Well met, adventurer"), never cute. Commands and hints are plain imperatives ("Set a waypoint arrow"). Error copy says what to do next ("Is the bridge running?").

## Assets

All in `addon/media`, generated as 32-bit TGA (white, tinted in game, except `pin.tga`, which is pre-coloured `rare` blue):
`circle.tga` (rounded corners, dots, masks), `ring.tga` (portrait rings), `arrow.tga` (send), `nav.tga` (waypoint arrowhead), `pin.tga` (inline waypoint pin). Fonts: Geist (OFL, `LICENSE-Geist.txt`).
New addon files and textures only load after a full client restart.
