// The game context from the addon (context.lua). Each message holds about 3 KB, so slow-changing
// fields (STICKY) only come when they change; the bridge keeps the latest per character and puts
// them in every prompt. The rest arrive with each message. A bridge that lost its memory gets a new
// epoch, which tells the addon to send everything again.
export const STICKY = ["character", "remember", "talents"] as const

export interface Memory {
  fields: Record<string, string>
  done: number[] // completed quest IDs in the order they arrived, so new ones are at the end
  // The quest log, one line per quest keyed by quest ID ("- [7] Name #62: 3/10 ..."). "quests"
  // replaces it; then "quests~" brings changed or new lines and "quests-" removed IDs.
  quests?: [string, string][]
}

const questId = (line: string, i: number) =>
  / #(\d+)(?::|$)/.exec(line)?.[1] ?? `line${i}`

function questLines(value: string) {
  return value
    .split("\n")
    .filter((l) => l.startsWith("- "))
    .map((l, i): [string, string] => [questId(l, i), l])
}

// "key: value" lines; a line that doesn't start with a key continues the previous value.
export function parseContext(ctx: string): [string, string][] {
  const blocks: [string, string][] = []
  for (const line of ctx.split("\n")) {
    const m = /^([a-z][a-z +~-]*): ?(.*)$/.exec(line)
    const last = blocks.at(-1)
    if (m) {
      blocks.push([m[1]!, m[2]!])
    } else if (last) {
      last[1] += `\n${line}`
    } else if (line) {
      blocks.push(["", line])
    }
  }
  return blocks
}

// Completed quests travel as base-36 numbers: the first absolute, then gaps ("1q,2,a" = 62, 64, 74).
export function decodeIds(value: string): number[] {
  const ids: number[] = []
  let prev = 0
  for (const [i, part] of value.split(",").entries()) {
    const n = Number.parseInt(part, 36)
    if (Number.isNaN(n)) {
      continue
    }
    prev = i === 0 ? n : prev + n
    ids.push(prev)
  }
  return ids
}

// Folds a message's context into the character's memory; returns the fields that only apply to
// this message, in the order they came.
export function remember(memory: Memory, ctx: string): [string, string][] {
  const rest: [string, string][] = []
  for (const [key, value] of parseContext(ctx)) {
    if ((STICKY as readonly string[]).includes(key)) {
      memory.fields[key] = value
    } else if (key === "quests") {
      memory.quests = questLines(value)
    } else if (key === "quests~") {
      const log = new Map(memory.quests)
      for (const [id, line] of questLines(value)) {
        log.set(id, line)
      }
      memory.quests = [...log]
    } else if (key === "quests-") {
      const gone = new Set(value.split(",").map((s) => s.trim()))
      memory.quests = (memory.quests ?? []).filter(([id]) => !gone.has(id))
    } else if (key === "done" || key === "done+") {
      // "done" starts the list over (first sync after a new epoch); "done+" adds to it.
      if (key === "done") {
        memory.done = []
      }
      const known = new Set(memory.done)
      for (const id of decodeIds(value)) {
        if (!known.has(id)) {
          known.add(id)
          memory.done.push(id)
        }
      }
    } else {
      rest.push([key, value])
    }
  }
  return rest
}

// The [game] block: who you are, this message's fields, then everything remembered. Completed
// quests are long, so a session sees the full list once and afterwards only what's new (`shown`
// is how many IDs this session has already seen).
export function gameBlock(
  memory: Memory,
  current: [string, string][],
  shown: number,
): string {
  const lines: string[] = []
  const field = (key: string) => {
    const value = memory.fields[key]
    if (value !== undefined && value !== "none") {
      lines.push(`${key}: ${value}`)
    }
  }
  field("character")
  for (const [key, value] of current) {
    lines.push(key ? `${key}: ${value}` : value)
  }
  field("remember")
  field("talents")
  if (memory.quests) {
    lines.push(
      memory.quests.length
        ? `quests:\n${memory.quests.map(([, l]) => l).join("\n")}`
        : "quests: none",
    )
  }
  const { done } = memory
  // A list that started over (new epoch) is shown in full again.
  if (done.length && (shown === 0 || shown > done.length)) {
    const sorted = [...done].sort((a, b) => a - b)
    lines.push(`completed quests: ${done.length} (IDs: ${sorted.join(", ")})`)
  } else if (done.length > shown) {
    lines.push(
      `completed quests: ${done.length} (the list is earlier in this conversation; new since then: ${done.slice(shown).join(", ")})`,
    )
  } else if (done.length) {
    lines.push(
      `completed quests: ${done.length} (unchanged; the list is earlier in this conversation)`,
    )
  }
  return lines.join("\n")
}
