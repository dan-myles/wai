/*
 * POST /v1/events with a JSON array of reports; valid ones are appended to $DATA_DIR/events.jsonl
 * with the time they arrived. GET /health for uptime checks. Run anywhere Bun runs:
 *   PORT=8787 DATA_DIR=./data bun src/server.ts
 */
import { appendFile, mkdir } from "node:fs/promises"
import path from "node:path"

import { parseReports } from "./events"

const port = Number(process.env.PORT ?? 8787)
const dataDir = process.env.DATA_DIR ?? "data"
const file = path.join(dataDir, "events.jsonl")
await mkdir(dataDir, { recursive: true })

export const server = Bun.serve({
  async fetch(req) {
    const url = new URL(req.url)
    if (req.method === "GET" && url.pathname === "/health") {
      return new Response("ok")
    }
    if (req.method !== "POST" || url.pathname !== "/v1/events") {
      return new Response("not found", { status: 404 })
    }
    const reports = parseReports(await req.text())
    if (reports.length) {
      const receivedAt = new Date().toISOString()
      await appendFile(
        file,
        `${reports.map((r) => JSON.stringify({ ...r, receivedAt })).join("\n")}\n`,
      )
    }
    return Response.json({ accepted: reports.length })
  },
  port,
})

console.log(`wai telemetry collector on :${server.port}, writing ${file}`)
