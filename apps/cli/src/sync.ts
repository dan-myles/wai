// What a running addon already has, so each live message carries only what changed: new messages
// whole, streamed text as just the new part, and other fields only when they move. The link
// delivers in order and never drops a message, so the view stays exact for the whole session.

export interface LiveMessage {
  id: number
  role: string
  text: string
  done?: boolean
  reset?: boolean
}
export interface LiveChat {
  ackSeq: number
  busy: boolean
  activity?: string
  messages: LiveMessage[]
}
export interface Live {
  top: Record<string, unknown> // agent, beat, ctxEpoch, modules, track, update, video
  chats: Record<string, LiveChat>
}

interface Seen {
  role: string
  text: string
  done?: boolean
}
interface SeenChat {
  fields: Map<string, string> // ackSeq, busy, activity as JSON
  messages: Map<number, Seen>
}
export interface View {
  top: Map<string, string>
  chats: Map<string, SeenChat>
}

export const emptyView = (): View => ({ chats: new Map(), top: new Map() })

const seenChat = (view: View, tab: string) => {
  let c = view.chats.get(tab)
  if (!c) {
    c = { fields: new Map(), messages: new Map() }
    view.chats.set(tab, c)
  }
  return c
}

// The addon's hello lists its latest messages per tab as "tab id length done role" lines. Text it
// has is taken to be the start of ours (replies only ever grow), so only the rest is sent.
export function viewFromDigest(digest: string, live: Live): View {
  const view = emptyView()
  for (const line of digest.split("\n")) {
    const [tab, id, length, done, role] = line.split(" ")
    if (!tab || !role) {
      continue
    }
    const ours = live.chats[tab]?.messages.find((m) => m.id === Number(id))
    const have = Number(length)
    if (!ours || ours.text.length < have) {
      continue
    }
    seenChat(view, tab).messages.set(Number(id), {
      done: done === "1" ? true : undefined,
      role,
      text: ours.text.slice(0, have),
    })
  }
  return view
}

// Lua has no undefined: false clears a field on the addon's side.
const value = (v: unknown) => v ?? false

// The changes from `view` to `live`, or undefined when there are none. Updates `view` to match.
export function diff(view: View, live: Live) {
  const out: Record<string, unknown> = {}
  for (const [key, v] of Object.entries(live.top)) {
    const json = JSON.stringify(v ?? null)
    if (view.top.get(key) !== json) {
      view.top.set(key, json)
      out[key] = value(v)
    }
  }
  const chats: Record<string, unknown> = {}
  for (const [tab, chat] of Object.entries(live.chats)) {
    const seen = seenChat(view, tab)
    const changes: Record<string, unknown> = {}
    for (const key of ["ackSeq", "busy", "activity"] as const) {
      const json = JSON.stringify(chat[key] ?? null)
      if (seen.fields.get(key) !== json) {
        seen.fields.set(key, json)
        changes[key] = value(chat[key])
      }
    }
    const messages = []
    for (const m of chat.messages) {
      const had = seen.messages.get(m.id)
      if (!had) {
        messages.push({
          done: m.done,
          id: m.id,
          reset: m.reset,
          role: m.role,
          text: m.text,
        })
      } else if (
        had.text !== m.text ||
        had.role !== m.role ||
        had.done !== m.done
      ) {
        const grew = m.text.startsWith(had.text)
        messages.push({
          add: grew ? m.text.slice(had.text.length) : undefined,
          done: m.done,
          id: m.id,
          role: m.role,
          text: grew ? undefined : m.text,
        })
      }
      seen.messages.set(m.id, { done: m.done, role: m.role, text: m.text })
    }
    // Older messages scroll out of the live window; the addon keeps them, the view needn't.
    const window = new Set(chat.messages.map((m) => m.id))
    for (const id of seen.messages.keys()) {
      if (!window.has(id)) {
        seen.messages.delete(id)
      }
    }
    if (messages.length) {
      changes.messages = messages
    }
    if (Object.keys(changes).length) {
      chats[tab] = changes
    }
  }
  if (Object.keys(chats).length) {
    out.chats = chats
  }
  return Object.keys(out).length ? out : undefined
}
