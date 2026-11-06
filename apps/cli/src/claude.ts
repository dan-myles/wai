import type { OnUpdate, Proxy, Reply } from "./agent"

// Claude Code as a wai agent: `claude -p` with stream-json, so text streams token by token.
import { basename } from "node:path"

import {
  MCP_NAME,
  mcpServer,
  proxy,
  requirePath,
  skill,
  streamLines,
} from "./agent"

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
    case `mcp__${MCP_NAME}__search`: {
      return input.query
        ? `Searching Wowhead for "${input.query}"`
        : "Searching Wowhead"
    }
    case `mcp__${MCP_NAME}__lookup`: {
      return "Reading Wowhead"
    }
    case "TodoWrite": {
      return "Planning"
    }
    default: {
      return "Working"
    }
  }
}

// Points Claude Code at the gateway. The token is always set so a claude.ai login is never sent
// to the gateway; a model also replaces the tier defaults, because Claude Code uses the small one
// for background work (reading fetched pages) that the gateway may have no route for.
export function claudeEnv(p?: Proxy): Record<string, string> {
  if (!p) {
    return {}
  }
  const env: Record<string, string> = {
    ANTHROPIC_AUTH_TOKEN: p.key ?? "wai",
    ANTHROPIC_BASE_URL: p.url,
  }
  if (p.model) {
    for (const tier of [
      "MODEL",
      "DEFAULT_OPUS_MODEL",
      "DEFAULT_SONNET_MODEL",
      "DEFAULT_HAIKU_MODEL",
    ]) {
      env[`ANTHROPIC_${tier}`] = p.model
    }
  }
  return env
}

export async function runClaude(
  prompt: string,
  sessionId: string | undefined,
  onUpdate: OnUpdate,
): Promise<Reply> {
  const args = [
    requirePath("claude"),
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
    "--mcp-config",
    JSON.stringify({ mcpServers: { [MCP_NAME]: mcpServer() } }),
    "--allowedTools",
    "WebSearch",
    "WebFetch",
    `mcp__${MCP_NAME}__search`,
    `mcp__${MCP_NAME}__lookup`,
  ]
  if (sessionId) {
    args.push("--resume", sessionId)
  }

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

  const { code, stderr } = await streamLines(args, handle, claudeEnv(proxy()))

  if (code !== 0 || !result || result.is_error) {
    throw new Error(
      (result?.result || stderr || `claude exited ${code}`)
        .trim()
        .slice(0, 300),
    )
  }
  return {
    sessionId: result.session_id ?? sessionId ?? "",
    text: (text || result.result || "").trim(),
  }
}
