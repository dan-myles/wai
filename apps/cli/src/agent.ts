import type { Config } from "./files"

// What every agent backend shares: which CLIs exist, the wai skill, and a JSONL process reader.
// Each agent (claude.ts, codex.ts) runs its CLI headless in the addon folder with the skill
// injected, reports progress, and returns a session id the next message in that chat resumes.
import { readFile } from "node:fs/promises"
import { resolve } from "node:path"

import embeddedSkill from "../SKILL.md" with { type: "text" }
import { ADDON_DIR, COMPILED, readConfig } from "./files"

export const AGENTS = ["claude", "codex"] as const
export type Agent = (typeof AGENTS)[number]
export const isAgent = (value: unknown): value is Agent =>
  AGENTS.includes(value as Agent)

export const NAMES: Record<Agent, string> = { claude: "Claude", codex: "Codex" }
export const INSTALL_HINTS: Record<Agent, string> = {
  claude:
    "install it from https://claude.ai/install, then sign in by running `claude` once",
  codex:
    "install it with `npm install -g @openai/codex`, then sign in by running `codex` once",
}

// Long tasks (building UI, research) can legitimately run for a while.
const TIMEOUT_MS = 30 * 60_000

export interface Reply {
  text: string
  sessionId: string
}
// text: the reply so far; activity: what the agent is doing right now when it isn't writing text.
export type OnUpdate = (text: string, activity?: string) => void

// Services started at login (launchd, Task Scheduler) have a bare PATH, so the installer records
// where each CLI lives. CLAUDE_BIN / CODEX_BIN override for development.
export function agentPath(agent: Agent): string | undefined {
  const config = readConfig()
  const env =
    agent === "claude" ? process.env.CLAUDE_BIN : process.env.CODEX_BIN
  const recorded = agent === "claude" ? config.claudePath : config.codexPath
  return env ?? recorded ?? Bun.which(agent) ?? undefined
}

// The player's choice (in game or `wai agent`), else whichever CLI is installed, Claude first.
export function currentAgent(): Agent {
  const chosen = readConfig().agent
  if (isAgent(chosen)) {
    return chosen
  }
  return AGENTS.find((a) => agentPath(a)) ?? "claude"
}

// CLIProxyAPI's default address. One gateway serves both agents: Claude Code speaks the Messages
// API at the root, Codex the Responses API under /v1.
export const DEFAULT_PROXY = "http://127.0.0.1:8317"
export type Proxy = NonNullable<Config["proxy"]>
export const proxy = (): Proxy | undefined => readConfig().proxy
// Accepts the address with or without /v1 so either form from a gateway's docs works.
export const proxyRoot = (url: string) =>
  url.trim().replace(/\/+$/, "").replace(/\/v1$/, "")

// The wai skill: what the agent knows and can do. In a source checkout it's read on every call so
// edits apply immediately; the compiled binary carries its own copy.
const SKILL_FILE = resolve(import.meta.dir, "../SKILL.md")
export const skill = async () =>
  COMPILED
    ? embeddedSkill
    : await readFile(SKILL_FILE, "utf-8").catch(() => embeddedSkill)

// Runs an agent CLI in the addon folder and hands each stdout line to `onLine`. `env` adds to the
// bridge's own environment (proxy settings), never replaces it.
export async function streamLines(
  args: string[],
  onLine: (line: string) => void,
  env: Record<string, string> = {},
): Promise<{ code: number; stderr: string }> {
  const proc = Bun.spawn(args, {
    cwd: ADDON_DIR,
    env: { ...process.env, ...env },
    stderr: "pipe",
    stdin: "ignore",
    stdout: "pipe",
  })
  const timer = setTimeout(() => proc.kill(), TIMEOUT_MS)
  const stderr = new Response(proc.stderr).text()
  const decoder = new TextDecoder()
  let buf = ""
  for await (const chunk of proc.stdout) {
    buf += decoder.decode(chunk, { stream: true })
    let nl
    while ((nl = buf.indexOf("\n")) >= 0) {
      onLine(buf.slice(0, nl))
      buf = buf.slice(nl + 1)
    }
  }
  onLine(buf)
  const code = await proc.exited
  clearTimeout(timer)
  return { code, stderr: await stderr }
}

// The CLI to run, or a clear error the player sees in chat when it isn't installed.
export function requirePath(agent: Agent): string {
  const path = agentPath(agent)
  if (!path) {
    throw new Error(
      `${NAMES[agent]} isn't installed: ${INSTALL_HINTS[agent]}, then run wai install.`,
    )
  }
  return path
}
