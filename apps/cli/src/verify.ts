// After each reply, the bridge checks what it named against Wowhead's Forever database: links whose
// ID and name disagree, names Forever doesn't have, and waypoints far from where Wowhead puts that
// NPC. Problems are shown under the reply and handed to the agent with the next message. Wowhead
// still carries some Classic leftovers, so this catches inventions, not every stale fact.
import type { WowheadType } from "./wowhead"

import { searchResults, tooltip, typeOf, zoneName } from "./wowhead"

type Kind = Extract<WowheadType, "npc" | "item" | "spell" | "quest">
export interface Claim {
  kind: Kind
  id?: number
  name: string
}
export interface Pin {
  zone: string
  x: number
  y: number
  label: string
}

const MAX_CHECKS = 15
// Map units (percent of the zone map) a pin may sit from the nearest spawn.
const NEAR = 3

const norm = (s: string) =>
  s
    .toLowerCase()
    .replaceAll(/\(rank \d+\)/g, "")
    .replaceAll(/[^a-z0-9]/g, "")

export function claims(text: string): { names: Claim[]; pins: Pin[] } {
  const names = new Map<string, Claim>()
  for (const [, kind, body = ""] of text.matchAll(
    /\[\[(npc|item|spell|quest):([^\]]+)\]\]/g,
  )) {
    const m = /^(\d+):(.*)$/.exec(body)
    const claim: Claim = m
      ? { id: Number(m[1]), kind: kind as Kind, name: m[2]!.trim() }
      : { kind: kind as Kind, name: body.trim() }
    names.set(`${claim.kind}:${claim.id ?? ""}:${norm(claim.name)}`, claim)
  }
  const pins: Pin[] = []
  for (const [, body = ""] of text.matchAll(/\[\[(?:set)?way:([^\]]+)\]\]/g)) {
    const m = /^([^:]*):\s*([\d.]+)\s*,\s*([\d.]+)\s*:?(.*)$/.exec(body)
    if (m) {
      pins.push({
        label: m[4]!.trim(),
        x: Number(m[2]),
        y: Number(m[3]),
        zone: m[1]!.trim(),
      })
    }
  }
  return { names: [...names.values()], pins }
}

const KIND_NAMES: Record<Kind, string> = {
  item: "item",
  npc: "NPC",
  quest: "quest",
  spell: "spell",
}

export async function checkName(c: Claim): Promise<string | undefined> {
  const kind = KIND_NAMES[c.kind]
  if (c.id) {
    const tip = await tooltip(c.kind, c.id)
    if (!tip.name) {
      return `${kind} ${c.id} isn't in Forever's database`
    }
    if (c.name && norm(tip.name) !== norm(c.name)) {
      return `${kind} ${c.id} is "${tip.name}", not "${c.name}"`
    }
    return undefined
  }
  const results = await searchResults(c.name)
  const found = results.some(
    (r) => typeOf(r) === c.kind && norm(r.name ?? "") === norm(c.name),
  )
  return found ? undefined : `no ${kind} called "${c.name}"`
}

// Only pins labelled with an NPC's name can be checked; places have no single spawn point.
export async function checkPin(p: Pin): Promise<string | undefined> {
  const label = p.label.replace(/\s*\(.*\)$/, "").trim()
  if (!label) {
    return undefined
  }
  const npc = (await searchResults(label)).find(
    (r) => typeOf(r) === "npc" && norm(r.name ?? "") === norm(label),
  )
  if (!npc?.id) {
    return undefined
  }
  const tip = await tooltip("npc", npc.id)
  const spawns = Object.values(tip.map?.coords ?? {}).flat()
  if (!tip.map?.zone || spawns.length === 0) {
    return undefined
  }
  const zone = await zoneName(tip.map.zone)
  const [first] = spawns
  if (!zone || !first) {
    return undefined
  }
  const at = `${zone} ${first[0]},${first[1]}`
  if (norm(zone) !== norm(p.zone)) {
    return `Wowhead has ${label} in ${at}, not ${p.zone}`
  }
  const near = spawns.some(([x, y]) => Math.hypot(x - p.x, y - p.y) <= NEAR)
  return near ? undefined : `Wowhead has ${label} at ${at}, not ${p.x},${p.y}`
}

// Problems in a finished reply. A check Wowhead can't answer is skipped, never reported.
export async function check(text: string): Promise<string[]> {
  const { names, pins } = claims(text)
  const jobs = [
    ...names.map((c) => () => checkName(c)),
    ...pins.map((p) => () => checkPin(p)),
  ].slice(0, MAX_CHECKS)
  const results = await Promise.all(jobs.map((job) => job().catch(() => {})))
  return results.filter((r): r is string => r !== undefined)
}
