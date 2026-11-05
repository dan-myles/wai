import { expect, test } from "bun:test"

import { fakeScreenshot } from "./fake-shot"
import { CAPACITY, decode, parseTga } from "./shot"

test("decodes a painted message", () => {
  const payload = "what should I do next? ünï\0character: Bob\nzone: Goldshire"
  const shot = decode(
    parseTga(fakeScreenshot({ kind: 1, payload, seq: 300, slot: 42 })),
  )
  expect(shot).toEqual({ kind: 1, payload, seq: 300, slot: 42 })
})

test("fills the full capacity", () => {
  const payload = "x".repeat(CAPACITY - 11)
  expect(
    decode(
      parseTga(fakeScreenshot({ kind: 3, payload, seq: 65535, slot: 500 })),
    )?.payload,
  ).toBe(payload)
})

test("ignores ordinary screenshots", () => {
  const img = parseTga(
    fakeScreenshot({ kind: 1, payload: "x", seq: 1, slot: 1 }).fill(30, 18),
  )
  expect(decode(img)).toBeUndefined()
})
