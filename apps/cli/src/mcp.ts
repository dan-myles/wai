// `wai mcp`: a stdio MCP server the bridge attaches to every agent run (Claude's --mcp-config,
// Codex's mcp_servers), so both agents get the same tools without touching the player's own CLI
// configs. Newline-delimited JSON-RPC, which is all stdio MCP needs.
import type { WowheadType } from "./wowhead"

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
]

async function call(
  name: string | undefined,
  args: Record<string, unknown> = {},
): Promise<string> {
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
  throw new Error(`bad call to ${name}: ${JSON.stringify(args)}`)
}

async function answer(req: Request): Promise<unknown> {
  switch (req.method) {
    case "initialize": {
      return {
        protocolVersion: req.params?.protocolVersion ?? "2025-06-18",
        capabilities: { tools: {} },
        serverInfo: { name: "wowhead", version: VERSION },
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
