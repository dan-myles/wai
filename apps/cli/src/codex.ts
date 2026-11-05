import type { OnUpdate, Reply } from "./agent"

// Codex as a wai agent: `codex exec --json`. Codex reports whole items (a message, a search, a
// command) rather than token deltas, so text arrives a message at a time.
import { basename } from "node:path"

import { requirePath, skill, streamLines } from "./agent"

interface CodexItem {
  type?: string
  text?: string
  query?: string
  changes?: { path?: string }[]
}
// The parts of Codex's JSONL events the bridge reads.
export interface CodexEvent {
  type?: string
  thread_id?: string
  item?: CodexItem
  message?: string
  error?: { message?: string }
}
export interface CodexProgress {
  text: string
  activity?: string
  sessionId?: string
  // turn.failed ends the reply; plain "error" events can be retries Codex recovers from.
  failed?: string
  lastError?: string
}

// A short, human description of what Codex is doing for the in-game activity line.
export function describeItem(item: CodexItem): string {
  switch (item.type) {
    case "web_search": {
      return item.query
        ? `Searching the web for "${item.query}"`
        : "Searching the web"
    }
    case "file_change": {
      const path = item.changes?.[0]?.path
      return path ? `Writing ${basename(path)}` : "Writing code"
    }
    case "command_execution": {
      return "Running a command"
    }
    case "mcp_tool_call": {
      return "Using a tool"
    }
    case "todo_list": {
      return "Planning"
    }
    case "reasoning": {
      return "Thinking"
    }
    default: {
      return "Working"
    }
  }
}

// Folds one event into the reply so far; returns whether the player should see a change.
export function applyEvent(p: CodexProgress, ev: CodexEvent): boolean {
  const item = ev.item ?? {}
  switch (ev.type) {
    case "thread.started": {
      p.sessionId = ev.thread_id
      return false
    }
    case "turn.failed": {
      p.failed = ev.error?.message ?? "Codex couldn't finish"
      return false
    }
    case "error": {
      p.lastError = ev.message
      return false
    }
    case "item.started":
    case "item.updated": {
      // "error" items are warnings (e.g. about the player's own config.toml), not failures.
      if (item.type === "agent_message" || item.type === "error") {
        return false
      }
      p.activity = describeItem(item)
      return true
    }
    case "item.completed": {
      if (item.type === "error") {
        return false
      }
      if (item.type === "agent_message") {
        if (item.text) {
          p.text += (p.text ? "\n\n" : "") + item.text
        }
        p.activity = undefined
      } else if (item.type === "web_search" && item.query) {
        // The query is only known once the search finishes.
        p.activity = describeItem(item)
      } else {
        p.activity = "Thinking" // a tool finished; Codex is reading the result
      }
      return true
    }
    default: {
      return false
    }
  }
}

// Codex has no system-prompt flag, so the skill goes in as developer instructions. -c values are
// TOML; a JSON string is also a valid TOML basic string.
export function codexArgs(
  bin: string,
  prompt: string,
  sessionId: string | undefined,
  instructions: string,
): string[] {
  const options = [
    "--json",
    "--skip-git-repo-check",
    "-c",
    `developer_instructions=${JSON.stringify(instructions)}`,
    // Writes stay inside the addon folder (UI modules); resume has no --sandbox flag.
    "-c",
    'sandbox_mode="workspace-write"',
    "-c",
    'web_search="live"',
  ]
  return sessionId
    ? [bin, "exec", "resume", ...options, sessionId, prompt]
    : [bin, "exec", ...options, prompt]
}

export async function runCodex(
  prompt: string,
  sessionId: string | undefined,
  onUpdate: OnUpdate,
): Promise<Reply> {
  const args = codexArgs(requirePath("codex"), prompt, sessionId, await skill())
  const progress: CodexProgress = { activity: "Thinking", text: "" }
  const { code, stderr } = await streamLines(args, (line) => {
    let ev: CodexEvent
    try {
      ev = JSON.parse(line)
    } catch {
      return
    }
    if (applyEvent(progress, ev)) {
      onUpdate(progress.text, progress.activity)
    }
  })
  if (code !== 0 || progress.failed || !progress.sessionId) {
    throw new Error(
      (
        progress.failed ||
        progress.lastError ||
        stderr ||
        `codex exited ${code}`
      )
        .trim()
        .slice(0, 300),
    )
  }
  return { sessionId: progress.sessionId, text: progress.text.trim() }
}
