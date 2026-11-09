import { afterAll, afterEach, expect, spyOn, test } from "bun:test"
import { mkdtemp } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"

// mcp.ts loads files.ts, which fixes wai's home for the whole test run: point it at a scratch
// folder first, or tests that share this process (telemetry) would use the developer's own files.
process.env.WAI_HOME ??= await mkdtemp(join(tmpdir(), "wai-sources-"))
const { everloot } = await import("./everloot")
const { activity, TOOL_NAMES } = await import("./mcp")

const fetchSpy = spyOn(globalThis, "fetch")
afterEach(() => fetchSpy.mockReset())
// Other test files share this process and need the real fetch.
afterAll(() => fetchSpy.mockRestore())

// Each call gets a fresh Response: a body can only be read once.
const respond = (make: () => Response) =>
  fetchSpy.mockImplementation(
    Object.assign(() => Promise.resolve(make()), { preconnect: () => {} }),
  )

const json = (body: unknown, status = 200) => Response.json(body, { status })

test("Everloot calls pin Forever and refuse tools that mix versions", async () => {
  respond(() =>
    json({ result: { content: [{ text: "Hogger", type: "text" }] } }),
  )
  expect(
    await everloot("search_knowledge", { query: "Hogger", version: "classic" }),
  ).toContain("Hogger")
  const sent = JSON.parse(String(fetchSpy.mock.calls[0]![1]!.body))
  expect(sent.params).toEqual({
    arguments: { query: "Hogger", version: "forever" },
    name: "search_knowledge",
  })
  await everloot("recent_changes", { filter: "hotfixes" })
  expect(
    JSON.parse(String(fetchSpy.mock.calls[1]![1]!.body)).params.arguments,
  ).toEqual({
    filter: "hotfixes",
    game: "forever",
  })
  await expect(everloot("get_entity", { id: "x" })).rejects.toThrow(
    "isn't available",
  )
})

test("Everloot answers over server-sent events too", async () => {
  respond(
    () =>
      new Response(
        'event: message\ndata: {"result":{"content":[{"type":"text","text":"Vendor NPC 843"}]}}\n\n',
        { headers: { "content-type": "text/event-stream" } },
      ),
  )
  expect(await everloot("vendor_page", { vendorNpcId: 843 })).toStartWith(
    "Vendor NPC 843",
  )
})

test("every tool has an activity line and is allowed", () => {
  expect(TOOL_NAMES).toEqual([
    "search",
    "lookup",
    "game",
    "everloot_search",
    "everloot",
    "curseforge",
  ])
  expect(activity("game", { query: "training" })).toBe(
    "Checking class training",
  )
  expect(activity("everloot")).toBe("Checking Everloot")
  expect(activity("search", { query: "Hogger" })).toBe(
    'Searching Wowhead for "Hogger"',
  )
})
