// Everloot (everloot.app): a public, keyless MCP server with player-observed Forever data — vendors,
// drops, map neighbours, talents, professions, realm prices and official hotfix notes. Its catalog
// mixes game versions, so the agent never reaches it directly: these wrappers allow only the tools
// that are Forever-specific and pin the version on the ones that take one.
const ENDPOINT = "https://everloot.app/mcp/public"

// Tool -> the arguments it takes, as shown to the agent. `version`/`game` are set here, not by it.
export const EVERLOOT_TOOLS: Record<string, string> = {
  auction_history: "realm, itemId",
  class_races: "class, faction?",
  entity_relations:
    "kind (item|spell|npc|object|quest|zone), id, rel? (dropped_by|sold_by|reward_from|located_in|created_by|reagent_for), direction? (from|to|both)",
  item_page: "itemId",
  market_value: "realm, itemId",
  npc_page: "npcId",
  object_page: "objectId",
  profession_path: "profession, fromSkill?, toSkill?",
  quest_page: "questId",
  recent_changes: "filter? (all|posts|hotfixes|builds), limit?",
  recipe_thresholds: "profession, recipe",
  talent_plan: "code",
  talent_tree: "class, tree?, builds?",
  vendor_page: "vendorNpcId",
  world_map_near: "zone + x + y, or npcId; radius? (yards), limit?",
}
const PINNED: Record<string, Record<string, string>> = {
  recent_changes: { game: "forever" },
  search_knowledge: { version: "forever" },
}
const MAX_CHARS = 6000

interface ToolResult {
  result?: { content?: { type?: string; text?: string }[]; isError?: boolean }
  error?: { message?: string }
}

// Calls one allowed Everloot tool and returns its text.
export async function everloot(
  tool: string,
  args: Record<string, unknown> = {},
): Promise<string> {
  if (tool !== "search_knowledge" && !(tool in EVERLOOT_TOOLS)) {
    throw new Error(
      `Everloot tool "${tool}" isn't available. Use one of: ${Object.keys(EVERLOOT_TOOLS).join(", ")}.`,
    )
  }
  const res = await fetch(ENDPOINT, {
    body: JSON.stringify({
      id: 1,
      jsonrpc: "2.0",
      method: "tools/call",
      params: { arguments: { ...args, ...PINNED[tool] }, name: tool },
    }),
    headers: {
      accept: "application/json, text/event-stream",
      "content-type": "application/json",
    },
    method: "POST",
    signal: AbortSignal.timeout(20_000),
  })
  if (!res.ok) {
    throw new Error(`Everloot answered ${res.status}`)
  }
  const body = await res.text()
  // Streamable HTTP may answer as server-sent events; the reply is the last data line.
  const json = res.headers.get("content-type")?.includes("text/event-stream")
    ? ([...body.matchAll(/^data:(.*)$/gm)].at(-1)?.[1] ?? "{}")
    : body
  const { result, error } = JSON.parse(json) as ToolResult
  if (error) {
    throw new Error(`Everloot: ${error.message ?? "error"}`)
  }
  const text = (result?.content ?? [])
    .map((c) => c.text ?? "")
    .join("\n")
    .trim()
  const out =
    text.length > MAX_CHARS ? `${text.slice(0, MAX_CHARS)}\n…(cut)` : text
  return `${out || "No data."}\nSource: Everloot (everloot.app), Forever only.`
}
