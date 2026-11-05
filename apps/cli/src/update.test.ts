import { expect, test } from "bun:test"

import { newer } from "./update"

test("orders releases and their nightlies", () => {
  const order = [
    "0.9.2",
    "0.9.3-nightly.1",
    "0.9.3-nightly.2",
    "0.9.3-nightly.10",
    "0.9.3",
    "0.10.0-nightly.1",
    "0.10.0",
  ]
  for (let i = 1; i < order.length; i++) {
    expect(newer(order[i]!, order[i - 1]!)).toBe(true)
    expect(newer(order[i - 1]!, order[i]!)).toBe(false)
  }
  expect(newer("0.9.3", "0.9.3")).toBe(false)
  expect(newer("0.9.3-nightly.1", "0.9.3-nightly.1")).toBe(false)
})
