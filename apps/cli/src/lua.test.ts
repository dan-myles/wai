import { expect, test } from "bun:test"

import { parseSavedVariables, toLua } from "./lua"

test("parses WoW-written SavedVariables", () => {
  const src = `
WaiDB = {
["seq"] = 2,
["reopen"] = true,
["outbox"] = {
{
["seq"] = 2,
["kind"] = "chat",
["text"] = "say \\"hi\\"\\nnow",
["ctx"] = {
["gold"] = 12,
["quests"] = {
"The Fargodeep Mine (7)", -- [1]
"Lost Necklace (5)", -- [2]
},
},
}, -- [1]
},
}
Other = nil
`
  const sv = parseSavedVariables(src)
  expect(sv.Other).toBeNull()
  expect(sv.WaiDB).toEqual({
    outbox: [
      {
        seq: 2,
        kind: "chat",
        text: 'say "hi"\nnow',
        ctx: {
          gold: 12,
          quests: ["The Fargodeep Mine (7)", "Lost Necklace (5)"],
        },
      },
    ],
    reopen: true,
    seq: 2,
  })
})

test("round-trips through toLua", () => {
  const data = {
    ackSeq: 3,
    busy: false,
    empty: [],
    messages: [{ role: "assistant", text: 'a\\b "c"\n\td', at: 1 }],
  }
  const sv = parseSavedVariables(`WaiData = ${toLua(data)}`)
  expect(sv.WaiData).toEqual(data)
})
