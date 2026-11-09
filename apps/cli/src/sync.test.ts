import type { Live } from "./sync"

import { expect, test } from "bun:test"

import { diff, emptyView, viewFromDigest } from "./sync"

const live = (text: string, done = false): Live => ({
  chats: {
    main: {
      ackSeq: 3,
      busy: !done,
      activity: done ? undefined : "Thinking",
      messages: [
        { id: 1, role: "user", text: "hi" },
        { id: 2, role: "assistant", text, done },
      ],
    },
  },
  top: { agent: "claude", beat: 1, update: undefined },
})

test("a fresh view gets everything, then only changes", () => {
  const view = emptyView()
  expect(diff(view, live("Hel"))).toEqual({
    agent: "claude",
    beat: 1,
    chats: {
      main: {
        ackSeq: 3,
        activity: "Thinking",
        busy: true,
        messages: [
          { id: 1, role: "user", text: "hi" },
          { done: false, id: 2, role: "assistant", text: "Hel" },
        ],
      },
    },
    update: false,
  })
  expect(diff(view, live("Hel"))).toBeUndefined()
  // Streaming text goes as the new part; a cleared field goes as false.
  expect(diff(view, live("Hello there", true))).toEqual({
    chats: {
      main: {
        activity: false,
        busy: false,
        messages: [{ add: "lo there", done: true, id: 2, role: "assistant" }],
      },
    },
  })
})

test("text that was replaced goes whole", () => {
  const view = emptyView()
  diff(view, live("partial"))
  const changes = diff(view, live("Error: something else", true)) as {
    chats: { main: { messages: unknown[] } }
  }
  expect(changes.chats.main.messages).toEqual([
    { done: true, id: 2, role: "assistant", text: "Error: something else" },
  ])
})

test("a hello's digest means only what the addon lacks is sent", () => {
  const now = live("Hello there", true)
  const view = viewFromDigest(
    "main 1 2 0 user\nmain 2 5 0 assistant\nother 9 3 1 user",
    now,
  )
  const changes = diff(view, now) as {
    chats: { main: { messages: unknown[] } }
  }
  expect(changes.chats.main.messages).toEqual([
    { add: " there", done: true, id: 2, role: "assistant" },
  ])
})
