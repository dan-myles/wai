// Wowhead's Forever database, through the two JSON endpoints its own site and tooltip widget use.
// Full pages sit behind a bot challenge for anything that isn't a browser, so they stay with the
// agent's web fetch; these answer names, IDs, tooltips and map coordinates in a fraction of the time.
const SITE = "https://www.wowhead.com/forever"
const TOOLTIP = "https://nether.wowhead.com/forever/tooltip"
// Wowhead sees who is asking (the search endpoint refuses requests without a user agent).
const HEADERS = { "user-agent": "wai (+https://github.com/dan-myles/wai)" }

export const TYPES = [
  "quest",
  "npc",
  "item",
  "spell",
  "object",
  "zone",
] as const
export type WowheadType = (typeof TYPES)[number]
// Wowhead's numeric types, as the search endpoint reports them.
const TYPE_IDS: Record<number, WowheadType> = {
  1: "npc",
  2: "object",
  3: "item",
  5: "quest",
  6: "spell",
  7: "zone",
}

export interface SearchResult {
  type?: number
  id?: number
  name?: string
  typeName?: string
  pinFooterText?: string
  pinDescription?: string
  pinBreadcrumb?: string[]
}
export interface Tooltip {
  name?: string
  tooltip?: string
  map?: { zone?: number; coords?: Record<string, [number, number][]> }
}

const MAX_RESULTS = 10
const MAX_COORDS = 8

export const pageUrl = (type: string, id: number) => `${SITE}/${type}=${id}`

const ENTITIES: Record<string, string> = {
  amp: "&",
  gt: ">",
  lt: "<",
  nbsp: " ",
  quot: '"',
}

// Tooltip HTML as plain lines: breaks and table rows become newlines, money gets its g/s/c.
export function htmlText(html: string): string {
  return html
    .replaceAll(/<!--.*?-->/g, "")
    .replaceAll(
      /<span class="money(gold|silver|copper)">([^<]*)<\/span>/g,
      (_, coin: string, n: string) => `${n}${coin[0]}`,
    )
    .replaceAll(/<br\s*\/?>|<\/tr>|<\/?div[^>]*>/g, "\n")
    .replaceAll(/<[^>]+>/g, "")
    .replaceAll(/&(#\d+|[a-z]+);/g, (whole, name: string) =>
      name.startsWith("#")
        ? String.fromCodePoint(Number(name.slice(1)))
        : (ENTITIES[name] ?? whole),
    )
    .split("\n")
    .map((l) => l.replaceAll(/\s+/g, " ").trim())
    .filter(Boolean)
    .join("\n")
}

async function get<T>(url: string): Promise<T> {
  const res = await fetch(url, {
    headers: HEADERS,
    signal: AbortSignal.timeout(10_000),
  })
  if (!res.ok) {
    throw new Error(`Wowhead answered ${res.status} for ${url}`)
  }
  return (await res.json()) as T
}

export function formatResults(results: SearchResult[]): string {
  const lines = results.flatMap((r) => {
    const type = r.type === undefined ? undefined : TYPE_IDS[r.type]
    if (!type || r.id === undefined) {
      return []
    }
    const facts = [r.pinFooterText, r.pinBreadcrumb?.join(" > ")].filter(
      Boolean,
    )
    const about = r.pinDescription ? htmlText(r.pinDescription) : ""
    return [
      `- ${type} ${r.id}: ${r.name}${facts.length ? ` (${facts.join(", ")})` : ""}${about ? `\n  ${about.replaceAll("\n", " ").slice(0, 200)}` : ""}`,
    ]
  })
  return lines.length
    ? lines.slice(0, MAX_RESULTS).join("\n")
    : "No Forever results. Try a shorter name, or web search."
}

export async function search(query: string): Promise<string> {
  const { results = [] } = await get<{ results?: SearchResult[] }>(
    `${SITE}/search/suggestions-template?q=${encodeURIComponent(query)}`,
  )
  return formatResults(results)
}

export function formatTooltip(
  type: WowheadType,
  id: number,
  tip: Tooltip,
  zone?: string,
): string {
  const lines = [`${type} ${id}: ${tip.name ?? "unknown"}`]
  if (tip.tooltip) {
    // The name is already the first line.
    lines.push(...htmlText(tip.tooltip).split("\n").slice(1))
  }
  const coords = Object.values(tip.map?.coords ?? {}).flat()
  if (coords.length) {
    const shown = coords
      .slice(0, MAX_COORDS)
      .map(([x, y]) => `${x},${y}`)
      .join("; ")
    const more =
      coords.length > MAX_COORDS
        ? ` (+${coords.length - MAX_COORDS} more spawns)`
        : ""
    lines.push(
      `Location: ${zone ?? `zone ${tip.map?.zone}`} at ${shown}${more}`,
    )
  }
  lines.push(`Page: ${pageUrl(type, id)}`)
  return lines.join("\n")
}

export async function lookup(type: WowheadType, id: number): Promise<string> {
  const tip = await get<Tooltip>(`${TOOLTIP}/${type}/${id}`)
  if (!tip.name) {
    return `No Forever ${type} with ID ${id}.`
  }
  // Coordinates come with a zone ID; the agent needs its name for [[setway:...]].
  let zone: string | undefined
  if (tip.map?.zone) {
    try {
      zone = (await get<Tooltip>(`${TOOLTIP}/zone/${tip.map.zone}`)).name
    } catch {
      // The coordinates still help with the zone's ID in place of its name.
    }
  }
  return formatTooltip(type, id, tip, zone)
}
