import { readFile } from "node:fs/promises"
import { basename, resolve } from "node:path"

import embeddedSkill from "../SKILL.md" with { type: "text" }
import { ADDON_DIR, COMPILED, readConfig } from "./files"

// Long tasks (building UI, research) can legitimately run for a while.
const TIMEOUT_MS = 30 * 60_000

// The wai skill: what the agent knows and can do. In a source checkout it's read on every call so
// edits apply immediately; the compiled binary carries its own copy.
const SKILL_FILE = resolve(import.meta.dir, "../SKILL.md")
const skill = async () =>
  COMPILED
    ? embeddedSkill
    : await readFile(SKILL_FILE, "utf-8").catch(() => embeddedSkill)
// Services started at login (launchd, Task Scheduler) have a bare PATH, so the installer records it.
const CLAUDE = process.env.CLAUDE_BIN ?? readConfig().claudePath ?? "claude"

export interface Reply {
  text: string
  sessionId: string
}
// text: the reply so far; activity: what Claude is doing right now when it isn't writing text.
type OnUpdate = (text: string, activity?: string) => void

export async function ask(
  prompt: string,
  sessionId: string | undefined,
  onUpdate: OnUpdate,
): Promise<Reply> {
  try {
    return await run(prompt, sessionId, onUpdate)
  } catch (error) {
    // A stale or missing session shouldn't wedge the chat; start a fresh one.
    if (!sessionId) {
      throw error
    }
    return run(prompt, undefined, onUpdate)
  }
}

interface ToolInput {
  query?: string
  url?: string
  file_path?: string
}

// The parts of Claude's stream-json events the bridge reads.
interface StreamEvent {
  type?: string
  result?: string
  session_id?: string
  is_error?: boolean
  message?: { content?: { type: string; name: string; input: ToolInput }[] }
  event?: {
    type?: string
    delta?: { type?: string; text?: string }
    content_block?: { type?: string; name?: string }
  }
}

// A short, human description of a tool call for the in-game activity line.
export function describe(name: string, input: ToolInput = {}): string {
  const file =
    typeof input.file_path === "string" ? basename(input.file_path) : undefined
  switch (name) {
    case "WebSearch": {
      return input.query
        ? `Searching the web for "${input.query}"`
        : "Searching the web"
    }
    case "WebFetch": {
      try {
        return `Reading ${new URL(input.url ?? "").hostname.replace(/^www\./, "")}`
      } catch {
        return "Reading a page"
      }
    }
    case "Read": {
      return file ? `Reading ${file}` : "Reading files"
    }
    case "Edit":
    case "MultiEdit":
    case "Write": {
      return file ? `Writing ${file}` : "Writing code"
    }
    case "Glob":
    case "Grep": {
      return "Looking through files"
    }
    case "Bash": {
      return "Running a command"
    }
    case "TodoWrite": {
      return "Planning"
    }
    default: {
      return "Working"
    }
  }
}

async function run(
  prompt: string,
  sessionId: string | undefined,
  onUpdate: OnUpdate,
): Promise<Reply> {
  const args = [
    CLAUDE,
    "-p",
    prompt,
    "--output-format",
    "stream-json",
    "--verbose",
    "--include-partial-messages",
    "--permission-mode",
    "acceptEdits",
    "--append-system-prompt",
    await skill(),
    "--allowedTools",
    "WebSearch",
    "WebFetch",
  ]
  if (sessionId) {
    args.push("--resume", sessionId)
  }

  const proc = Bun.spawn(args, {
    cwd: ADDON_DIR,
    stderr: "pipe",
    stdin: "ignore",
    stdout: "pipe",
  })
  const timer = setTimeout(() => proc.kill(), TIMEOUT_MS)
  const stderr = new Response(proc.stderr).text()

  let text = ""
  let activity: string | undefined = "Thinking"
  let result:
    | { result?: string; session_id?: string; is_error?: boolean }
    | undefined
  const handle = (line: string) => {
    let ev: StreamEvent
    try {
      ev = JSON.parse(line)
    } catch {
      return
    }
    if (ev.type === "result") {
      result = ev
      return
    }
    if (ev.type === "assistant") {
      // The finished message carries full tool inputs, so the activity can name the query or file.
      let tool: { name: string; input: ToolInput } | undefined
      for (const c of ev.message?.content ?? []) {
        if (c.type === "tool_use") {
          tool = c
        }
      }
      if (!tool) {
        return
      }
      activity = describe(tool.name, tool.input)
    } else if (ev.type === "user") {
      activity = "Thinking" // a tool result came back; Claude is reading it
    } else if (ev.type === "stream_event") {
      const e = ev.event
      if (e?.type === "content_block_delta" && e.delta?.type === "text_delta") {
        text += e.delta.text
        activity = undefined
      } else if (
        e?.type === "content_block_start" &&
        e.content_block?.type === "tool_use"
      ) {
        activity = describe(e.content_block.name ?? "")
      } else if (
        e?.type === "content_block_start" &&
        e.content_block?.type === "thinking"
      ) {
        activity = "Thinking"
      } else if (e?.type === "message_start" && text && !text.endsWith("\n")) {
        text += "\n\n" // separate text from successive turns
      } else {
        return
      }
    } else {
      return
    }
    onUpdate(text, activity)
  }

  const decoder = new TextDecoder()
  let buf = ""
  for await (const chunk of proc.stdout) {
    buf += decoder.decode(chunk, { stream: true })
    let nl
    while ((nl = buf.indexOf("\n")) >= 0) {
      handle(buf.slice(0, nl))
      buf = buf.slice(nl + 1)
    }
  }
  handle(buf)
  const code = await proc.exited
  clearTimeout(timer)

  if (code !== 0 || !result || result.is_error) {
    throw new Error(
      (result?.result || (await stderr) || `claude exited ${code}`)
        .trim()
        .slice(0, 300),
    )
  }
  return {
    sessionId: result.session_id ?? sessionId ?? "",
    text: (text || result.result || "").trim(),
  }
}
