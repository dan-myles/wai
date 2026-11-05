import { expect, test } from "bun:test"

import { proxyRoot } from "./agent"
import { claudeEnv } from "./claude"

test("points Claude Code at a gateway", () => {
  expect(claudeEnv()).toEqual({})
  // No key still sets a token, so a claude.ai login never goes to the gateway.
  expect(claudeEnv({ url: "http://127.0.0.1:8317" })).toEqual({
    ANTHROPIC_AUTH_TOKEN: "wai",
    ANTHROPIC_BASE_URL: "http://127.0.0.1:8317",
  })
  const env = claudeEnv({ key: "k", model: "gpt-x", url: "http://h" })
  expect(env.ANTHROPIC_AUTH_TOKEN).toBe("k")
  expect(env.ANTHROPIC_MODEL).toBe("gpt-x")
  expect(env.ANTHROPIC_DEFAULT_HAIKU_MODEL).toBe("gpt-x")
})

test("accepts a gateway address with or without /v1", () => {
  expect(proxyRoot("http://127.0.0.1:8317/v1/")).toBe("http://127.0.0.1:8317")
  expect(proxyRoot(" http://h:1 ")).toBe("http://h:1")
})
