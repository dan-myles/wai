import type { CodexProgress } from "./codex"

import { expect, test } from "bun:test"

import { applyEvent, codexArgs } from "./codex"

// Events as `codex exec --json` printed them for a search, a file write and two messages.
const RUN = [
  { thread_id: "01a1ac44", type: "thread.started" },
  {
    item: { message: "`features.rmcp_client` is ignored.", type: "error" },
    type: "item.completed",
  },
  { type: "turn.started" },
  {
    item: { text: "Checking the patch notes.", type: "agent_message" },
    type: "item.completed",
  },
  { item: { query: "", type: "web_search" }, type: "item.started" },
  {
    item: { query: "classic patch notes", type: "web_search" },
    type: "item.completed",
  },
  { item: { type: "command_execution" }, type: "item.started" },
  { item: { type: "command_execution" }, type: "item.completed" },
  {
    item: { changes: [{ path: "/x/addon/ui/gold.lua" }], type: "file_change" },
    type: "item.started",
  },
  { message: "Reconnecting... 1/5", type: "error" },
  {
    item: { text: "Patch 1.15.9 is live.", type: "agent_message" },
    type: "item.completed",
  },
  { type: "turn.completed", usage: {} },
]

test("folds a Codex run into text, activity and a session", () => {
  const p: CodexProgress = { text: "" }
  const seen: (string | undefined)[] = []
  for (const ev of RUN) {
    if (applyEvent(p, ev)) {
      seen.push(p.activity)
    }
  }
  expect(p.sessionId).toBe("01a1ac44")
  expect(p.text).toBe("Checking the patch notes.\n\nPatch 1.15.9 is live.")
  expect(p.activity).toBeUndefined()
  expect(seen).toEqual([
    undefined,
    "Searching the web",
    'Searching the web for "classic patch notes"',
    "Running a command",
    "Thinking",
    "Writing gold.lua",
    undefined,
  ])
  // A retry message isn't a failure; turn.failed is.
  expect(p.failed).toBeUndefined()
  applyEvent(p, { error: { message: "quota exceeded" }, type: "turn.failed" })
  expect(p.failed).toBe("quota exceeded")
})

test("passes the skill as TOML developer instructions and resumes by id", () => {
  const skill = 'Say "hi"\nthen \\ stop'
  const fresh = codexArgs("codex", "[game]\nhello", undefined, skill)
  expect(fresh.slice(0, 2)).toEqual(["codex", "exec"])
  expect(fresh.at(-1)).toBe("[game]\nhello")
  const instructions = fresh.find((a) =>
    a.startsWith("developer_instructions="),
  )
  expect(instructions).toBe(
    'developer_instructions="Say \\"hi\\"\\nthen \\\\ stop"',
  )
  const resumed = codexArgs("codex", "again", "01a1ac44", skill)
  expect(resumed.slice(0, 3)).toEqual(["codex", "exec", "resume"])
  expect(resumed.slice(-2)).toEqual(["01a1ac44", "again"])
  expect(resumed).toContain('sandbox_mode="workspace-write"')
})

test("attaches wai's Wowhead server without touching the player's config", () => {
  const args = codexArgs("codex", "hi", undefined, "skill", undefined, {
    command: "C:\\wai\\wai.exe",
    args: ["mcp"],
  })
  expect(args).toContain('mcp_servers.wowhead.command="C:\\\\wai\\\\wai.exe"')
  expect(args).toContain('mcp_servers.wowhead.args=["mcp"]')
})

test("sends Codex through a gateway without touching config.toml", () => {
  const args = codexArgs("codex", "hi", undefined, "skill", {
    key: "sk-1",
    model: "gpt-x",
    url: "http://127.0.0.1:8317",
  })
  expect(args).toContain('model_provider="wai_proxy"')
  expect(args).toContain(
    'model_providers.wai_proxy.base_url="http://127.0.0.1:8317/v1"',
  )
  expect(args).toContain('model_providers.wai_proxy.env_key="WAI_PROXY_KEY"')
  expect(args).toContain('model="gpt-x"')
  // The key itself never appears in the process list.
  expect(args.some((a) => a.includes("sk-1"))).toBe(false)
  expect(codexArgs("codex", "hi", undefined, "skill").join(" ")).not.toContain(
    "wai_proxy",
  )
})
