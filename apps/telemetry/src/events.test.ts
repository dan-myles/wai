import { expect, test } from "bun:test"

import { MAX_EVENTS, parseReports } from "./events"

const report = {
  arch: "arm64",
  at: "2026-11-05T06:00:00.000Z",
  detail: "Interface/AddOns/wai/ui.lua:12: attempt to index nil",
  event: "lua_error",
  install: "0b0d7c1e-2c55-4f7a-9a5f-6c1f3b2a1d00",
  os: "darwin",
  version: "0.5.0",
}

test("accepts documented reports", () => {
  expect(
    parseReports(
      JSON.stringify([report, { ...report, client: "1.60.1.70790" }]),
    ),
  ).toHaveLength(2)
})

test("drops anything with extra or oversized fields", () => {
  const body = JSON.stringify([
    { ...report, chat: "hello" },
    { ...report, detail: "x".repeat(301) },
    { ...report, event: "Not An Event" },
    { ...report, version: 5 },
    report,
  ])
  expect(parseReports(body)).toEqual([report])
})

test("rejects bodies that aren't arrays, are malformed, or too big", () => {
  expect(parseReports(JSON.stringify(report))).toEqual([])
  expect(parseReports("{nope")).toEqual([])
  expect(parseReports(`[${" ".repeat(70_000)}]`)).toEqual([])
  expect(
    parseReports(JSON.stringify(Array.from({ length: 80 }, () => report))),
  ).toHaveLength(MAX_EVENTS)
})
