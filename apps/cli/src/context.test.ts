import type { Memory } from "./context"

import { expect, test } from "bun:test"

import { decodeIds, gameBlock, parseContext, remember } from "./context"

test("parses multi-line fields", () => {
  expect(
    parseContext(
      "zone: Dolanaar\nrecent chat: \n[General] Bob: hi: there\nquests: none",
    ),
  ).toEqual([
    ["zone", "Dolanaar"],
    ["recent chat", "\n[General] Bob: hi: there"],
    ["quests", "none"],
  ])
})

test("decodes completed quests as base 36 gaps", () => {
  expect(decodeIds("1q,2,a")).toEqual([62, 64, 74])
  expect(decodeIds("")).toEqual([])
})

test("remembers slow fields and adds them to every prompt", () => {
  const memory: Memory = { done: [], fields: {} }
  const first = remember(
    memory,
    "character: Backshot-Forever, level 12\nzone: Dolanaar\ntalents: Beast Mastery 3\nquests: \n- [7] The Fargodeep Mine #62: Explore 0/1\ndone: 1q,2",
  )
  expect(first).toEqual([["zone", "Dolanaar"]])
  // The next message carries only what changed: the bridge fills in the rest.
  const second = remember(memory, "zone: Shadowglen\ndone+: kr")
  const block = gameBlock(memory, second, 0)
  expect(block).toContain("character: Backshot-Forever, level 12")
  expect(block).toContain("zone: Shadowglen")
  expect(block).toContain("talents: Beast Mastery 3")
  expect(block).toContain("- [7] The Fargodeep Mine #62: Explore 0/1")
  // Quest log changes come by quest ID.
  remember(
    memory,
    "quests~: \n- [7] The Fargodeep Mine #62: complete\n- [8] Wolves #33: 2/8\nquests-: 99",
  )
  remember(memory, "quests-: 33")
  expect(gameBlock(memory, [], 0)).toContain(
    "quests:\n- [7] The Fargodeep Mine #62: complete\ncompleted",
  )
  expect(block).toContain("completed quests: 3 (IDs: 62, 64, 747)")
  expect(block).not.toContain("Dolanaar")
  // A field that became empty arrives as "none".
  remember(memory, "remember: none")
  expect(gameBlock(memory, [], 0)).not.toContain("remember:")
})

test("a session sees the full quest history once, then only what's new", () => {
  const memory: Memory = { done: [], fields: {} }
  remember(memory, "done: 1q,2")
  expect(gameBlock(memory, [], 0)).toContain("(IDs: 62, 64)")
  expect(gameBlock(memory, [], 2)).toContain("completed quests: 2 (unchanged")
  remember(memory, "done+: 1")
  expect(gameBlock(memory, [], 2)).toContain("new since then: 1")
  // "done" starts over: a session that saw more gets the full list again.
  remember(memory, "done: 2s")
  expect(gameBlock(memory, [], 3)).toContain("completed quests: 1 (IDs: 100)")
})
