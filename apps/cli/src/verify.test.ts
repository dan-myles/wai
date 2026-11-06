import { expect, test } from "bun:test"

import { claims } from "./verify"

test("finds links and pins in a reply", () => {
  const { names, pins } = claims(
    "Talk to [[npc:Gina MacGregor]] for a [[item:7005:Skinning Knife]], twice: [[npc:Gina MacGregor]]. [[setway:Westfall:57.6,53.9:Gina MacGregor (knives)]] [[setway:clear]] [[stream:a:b]]",
  )
  expect(names).toEqual([
    { kind: "npc", name: "Gina MacGregor" },
    { id: 7005, kind: "item", name: "Skinning Knife" },
  ])
  expect(pins).toEqual([
    { label: "Gina MacGregor (knives)", x: 57.6, y: 53.9, zone: "Westfall" },
  ])
})
