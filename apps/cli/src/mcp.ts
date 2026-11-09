// `wai mcp`: a stdio MCP server the bridge attaches to every agent run (Claude's --mcp-config,
// Codex's mcp_servers), so both agents get the same tools without touching the player's own CLI
// configs. Newline-delimited JSON-RPC, which is all stdio MCP needs. `--game <url>` is the bridge's
// local endpoint for questions the running client answers (index.ts).
import type { WowheadType } from "./wowhead"

import { describe } from "./curseforge"
import { EVERLOOT_TOOLS, everloot } from "./everloot"
import { VERSION } from "./version"
import { lookup, search, TYPES } from "./wowhead"

interface Request {
  id?: number | string
  method?: string
  params?: {
    protocolVersion?: string
    name?: string
    arguments?: Record<string, unknown>
  }
}

// Read-only and safe to call unprompted; Codex refuses unmarked tools when it can't ask the player.
const annotations = { readOnlyHint: true, openWorldHint: true }

export const GAME_QUERIES = [
  "training",
  "npc",
  "object",
  "quest",
  "trainers",
  "service",
] as const

const TOOLS = [
  {
    name: "search",
    annotations,
    description:
      "Search Wowhead's WoW: Forever database by name. Returns matching quests, NPCs, items, spells, objects and zones with their IDs, levels and a short description.",
    inputSchema: {
      type: "object",
      properties: {
        query: { type: "string", description: "A name, or part of one" },
      },
      required: ["query"],
    },
  },
  {
    name: "lookup",
    annotations,
    description:
      "Look up one WoW: Forever entity on Wowhead by type and ID: its tooltip (stats, effects, requirements, objectives) and, for NPCs and objects, the zone and map coordinates. Ends with the page URL; web fetch it for quest givers, drop tables and comments.",
    inputSchema: {
      type: "object",
      properties: {
        type: { type: "string", enum: TYPES },
        id: { type: "integer" },
      },
      required: ["type", "id"],
    },
  },
  {
    name: "game",
    annotations,
    description:
      "Ask the player's running WoW: Forever client; it outranks every website. training: the class trainer table bundled for Forever (WhatsTraining's data): every ability and rank by level with its cost, marked known or not for this character; pass from/to levels (default the next 10) or a spell name, and class for another class. With the player's Questie addon (QuestieDB Forever): npc and object (name or id) give spawn zones and coordinates; quest (id) gives givers, turn-ins, objectives and prerequisites; trainers gives class trainers (class optional) and service gives town NPCs by role (Banker, Innkeeper, Flight Master, Auctioneer, Repair, ...), nearest zone first.",
    inputSchema: {
      type: "object",
      properties: {
        query: { type: "string", enum: GAME_QUERIES },
        name: { type: "string" },
        id: { type: "integer" },
        class: { type: "string", description: "e.g. HUNTER" },
        service: { type: "string" },
        from: { type: "integer" },
        to: { type: "integer" },
      },
      required: ["query"],
    },
  },
  {
    name: "everloot_search",
    annotations,
    description:
      "Search Everloot's WoW: Forever knowledge (player-observed data and game files) by name or keywords; always Forever. Hits carry ids for the everloot tool.",
    inputSchema: {
      type: "object",
      properties: {
        query: { type: "string" },
        kind: {
          type: "string",
          enum: [
            "item",
            "npc",
            "object",
            "quest",
            "zone",
            "spell",
            "quest_chain",
            "faction",
            "mount",
            "instance",
          ],
        },
        limit: { type: "integer" },
      },
      required: ["query"],
    },
  },
  {
    name: "everloot",
    annotations,
    description: `Everloot's player-observed WoW: Forever data: what vendors sell and drops (prices need 3 installs agreeing, so gaps mean unrecorded, not absent), what's near a map point, how items/NPCs/quests connect, talent trees and share codes, profession paths, realm market prices, and official Forever hotfixes and blue posts. Tools and their args: ${Object.entries(
      EVERLOOT_TOOLS,
    )
      .map(([tool, args]) => `${tool}(${args})`)
      .join("; ")}.`,
    inputSchema: {
      type: "object",
      properties: {
        tool: { type: "string", enum: Object.keys(EVERLOOT_TOOLS) },
        args: { type: "object" },
      },
      required: ["tool"],
    },
  },
  {
    name: "curseforge",
    annotations,
    description:
      "Check a CurseForge addon project (by its Project ID, shown on the project's curseforge.com page) for a build that runs on WoW: Forever, before offering to install it.",
    inputSchema: {
      type: "object",
      properties: { project: { type: "integer" } },
      required: ["project"],
    },
  },
]

export const TOOL_NAMES = TOOLS.map((t) => t.name)

// What the in-game activity line says while the agent uses a tool (claude.ts, codex.ts).
export function activity(tool: string, args: Record<string, unknown> = {}) {
  switch (tool) {
    case "search": {
      return args.query
        ? `Searching Wowhead for "${args.query}"`
        : "Searching Wowhead"
    }
    case "lookup": {
      return "Reading Wowhead"
    }
    case "game": {
      return args.query === "training"
        ? "Checking class training"
        : "Asking the game"
    }
    case "everloot":
    case "everloot_search": {
      return "Checking Everloot"
    }
    case "curseforge": {
      return "Checking CurseForge"
    }
    default: {
      return "Working"
    }
  }
}

// The bridge's endpoint for game questions, from `--game`.
const gameUrl = () => {
  const i = process.argv.indexOf("--game")
  return i === -1 ? undefined : process.argv[i + 1]
}

async function askGame(args: Record<string, unknown>): Promise<string> {
  const url = gameUrl()
  if (!url) {
    return "The game isn't connected to this run."
  }
  const res = await fetch(url, {
    body: JSON.stringify(args),
    method: "POST",
    signal: AbortSignal.timeout(30_000),
  })
  return await res.text()
}

async function call(
  name: string | undefined,
  args: Record<string, unknown> = {},
): Promise<string> {
  if (name === "game" && GAME_QUERIES.includes(args.query as never)) {
    return await askGame(args)
  }
  if (name === "everloot_search" && typeof args.query === "string") {
    const { query, kind, limit } = args
    return await everloot("search_knowledge", { kind, limit, query })
  }
  if (name === "everloot" && typeof args.tool === "string") {
    const params =
      typeof args.args === "object" && args.args !== null
        ? (args.args as Record<string, unknown>)
        : {}
    return await everloot(args.tool, params)
  }
  if (name === "search" && typeof args.query === "string") {
    return await search(args.query)
  }
  const { type, id } = args
  if (
    name === "lookup" &&
    TYPES.includes(type as WowheadType) &&
    typeof id === "number"
  ) {
    return await lookup(type as WowheadType, id)
  }
  if (name === "curseforge" && typeof args.project === "number") {
    return await describe(args.project)
  }
  throw new Error(`bad call to ${name}: ${JSON.stringify(args)}`)
}

async function answer(req: Request): Promise<unknown> {
  switch (req.method) {
    case "initialize": {
      return {
        protocolVersion: req.params?.protocolVersion ?? "2025-06-18",
        capabilities: { tools: {} },
        serverInfo: { name: "wai", version: VERSION },
      }
    }
    case "tools/list": {
      return { tools: TOOLS }
    }
    case "tools/call": {
      try {
        const text = await call(req.params?.name, req.params?.arguments)
        return { content: [{ type: "text", text }] }
      } catch (error) {
        const text = error instanceof Error ? error.message : String(error)
        return { content: [{ type: "text", text }], isError: true }
      }
    }
    case "ping": {
      return {}
    }
    default: {
      return undefined
    }
  }
}

const send = (msg: unknown) => process.stdout.write(`${JSON.stringify(msg)}\n`)

export async function serve() {
  let buffer = ""
  for await (const chunk of process.stdin) {
    buffer += String(chunk)
    let nl = buffer.indexOf("\n")
    while (nl !== -1) {
      const line = buffer.slice(0, nl).trim()
      buffer = buffer.slice(nl + 1)
      nl = buffer.indexOf("\n")
      if (!line) {
        continue
      }
      const req = JSON.parse(line) as Request
      // Notifications (no id) need no reply.
      if (req.id === undefined) {
        continue
      }
      const result = await answer(req)
      send(
        result === undefined
          ? {
              jsonrpc: "2.0",
              id: req.id,
              error: { code: -32_601, message: `unknown method ${req.method}` },
            }
          : { jsonrpc: "2.0", id: req.id, result },
      )
    }
  }
}
