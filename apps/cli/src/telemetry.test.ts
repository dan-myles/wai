import { afterAll, beforeAll, expect, test } from "bun:test"
import { mkdtemp, rm } from "node:fs/promises"
import { homedir, tmpdir } from "node:os"
import { join } from "node:path"

// Telemetry reads and writes under WAI_HOME, so point it at a scratch folder before importing.
const home = await mkdtemp(join(tmpdir(), "wai-telemetry-"))
process.env.WAI_HOME = home
const telemetry = await import("./telemetry")

const received: unknown[] = []
let server: ReturnType<typeof Bun.serve>
beforeAll(() => {
  server = Bun.serve({
    port: 0,
    async fetch(req) {
      received.push(...((await req.json()) as unknown[]))
      return new Response("ok")
    },
  })
})
afterAll(async () => {
  server.stop(true)
  await rm(home, { recursive: true, force: true })
})

test("scrub removes names, the home folder and caps length", () => {
  const detail = telemetry.scrub(
    `Backshot-Forever hit an error in ${homedir()}/wai/x.lua\n  at y`,
    ["Backshot-Forever", "Backshot"],
  )
  expect(detail).toBe("<name> hit an error in ~/wai/x.lua at y")
  expect(telemetry.scrub("x".repeat(1000)).length).toBe(300)
})

test("nothing is recorded until the player opts in", async () => {
  await telemetry.record("lua_error", "boom")
  expect((await telemetry.history()).queued).toHaveLength(0)
})

test("opted in without an endpoint, reports queue locally", async () => {
  telemetry.setConsent(true)
  await telemetry.record("lua_error", "first")
  const { queued } = await telemetry.history()
  expect(queued).toHaveLength(1)
  expect(JSON.parse(queued[0]!)).toMatchObject({
    detail: "first",
    event: "lua_error",
  })
})

test("with an endpoint, the queue is sent and moved to the sent log", async () => {
  process.env.WAI_TELEMETRY_URL = `http://localhost:${server.port}/v1/events`
  await telemetry.record("claude_error", "second")
  const { queued, sent } = await telemetry.history()
  expect(queued).toHaveLength(0)
  expect(sent).toHaveLength(2)
  expect(received).toHaveLength(2)
  expect(received[1]).toMatchObject({ detail: "second", event: "claude_error" })
  expect(Object.keys(received[1] as object).sort()).toEqual([
    "arch",
    "at",
    "detail",
    "event",
    "install",
    "os",
    "version",
  ])
})
