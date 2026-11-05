/*
 * Opt-in, anonymous error reports (docs/TELEMETRY.md). Nothing is recorded or sent unless the
 * player turned it on, in game (/settings) or with `wai telemetry on`. Events carry no chat text
 * and no character names: details are scrubbed and capped. Reports queue in ~/.wai and go to
 * `telemetryUrl` (config) or WAI_TELEMETRY_URL; without an endpoint they stay queued locally.
 */
import { appendFile, readFile, writeFile } from "node:fs/promises"
import { homedir } from "node:os"
import { join } from "node:path"

import { HOME, readConfig, writeConfig } from "./files"
import { VERSION } from "./version"

const QUEUE = join(HOME, "telemetry.jsonl")
const SENT = join(HOME, "telemetry-sent.jsonl")
const MAX_QUEUED = 500
const MAX_DETAIL = 300

export interface TelemetryEvent {
  event: string
  detail: string
  version: string
  os: string
  arch: string
  client?: string
  install: string
  at: string
}

export function enabled() {
  return readConfig().telemetry === true
}

export function endpoint() {
  return process.env.WAI_TELEMETRY_URL ?? readConfig().telemetryUrl
}

export function setConsent(on: boolean) {
  if (readConfig().telemetry !== on) {
    writeConfig({ telemetry: on })
  }
}

function installId() {
  const id = readConfig().installId
  if (id) {
    return id
  }
  const fresh = crypto.randomUUID()
  writeConfig({ installId: fresh })
  return fresh
}

// Removes what could identify the player: their character name and realm, their home folder.
export function scrub(detail: string, names: string[] = []) {
  let out = detail.replaceAll(homedir(), "~")
  for (const name of names.filter((n) => n.length > 1)) {
    out = out.replaceAll(name, "<name>")
  }
  return out.replaceAll(/\s+/g, " ").trim().slice(0, MAX_DETAIL)
}

let client: string | undefined
export function setClient(build: string) {
  client = build
}

let flushing: Promise<void> | undefined

// Records an event if the player opted in, then tries to send the queue.
export async function record(
  event: string,
  detail: string,
  names: string[] = [],
) {
  if (!enabled()) {
    return
  }
  const entry: TelemetryEvent = {
    arch: process.arch,
    at: new Date().toISOString(),
    client,
    detail: scrub(detail, names),
    event,
    install: installId(),
    os: process.platform,
    version: VERSION,
  }
  await appendFile(QUEUE, `${JSON.stringify(entry)}\n`)
  flushing ??= flush().finally(() => {
    flushing = undefined
  })
  await flushing
}

async function readLines(path: string) {
  const text = await readFile(path, "utf-8").catch(() => "")
  return text.split("\n").filter(Boolean)
}

// Sends queued events in one batch. Keeps them (capped) when there's no endpoint or it fails.
export async function flush() {
  const lines = await readLines(QUEUE)
  if (!lines.length) {
    return
  }
  const url = endpoint()
  if (!(url && enabled())) {
    await writeFile(QUEUE, `${lines.slice(-MAX_QUEUED).join("\n")}\n`)
    return
  }
  const res = await fetch(url, {
    body: `[${lines.join(",")}]`,
    headers: { "Content-Type": "application/json" },
    method: "POST",
  }).catch(() => {})
  if (!res?.ok) {
    return
  }
  await writeFile(QUEUE, "")
  const sent = [...(await readLines(SENT)), ...lines].slice(-MAX_QUEUED)
  await writeFile(SENT, `${sent.join("\n")}\n`)
}

// For `wai telemetry show`: what's waiting and what was sent.
export async function history() {
  return { queued: await readLines(QUEUE), sent: await readLines(SENT) }
}
