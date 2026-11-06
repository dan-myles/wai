import { expect, test } from "bun:test"
import { mkdtemp, readFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { deflateRawSync } from "node:zlib"

import { addonFolders, foreverVersion, pickFile, unzip } from "./curseforge"

// A minimal zip writer for the reader to chew on: one stored and one deflated entry.
function zip(entries: { name: string; data: string; deflate?: boolean }[]) {
  const enc = new TextEncoder()
  const locals: Uint8Array[] = []
  const centrals: Uint8Array[] = []
  let offset = 0
  for (const e of entries) {
    const name = enc.encode(e.name)
    const raw = enc.encode(e.data)
    const body = e.deflate ? deflateRawSync(raw) : raw
    const local = new Uint8Array(30 + name.length + body.length)
    const lv = new DataView(local.buffer)
    lv.setUint32(0, 0x04_03_4b_50, true)
    lv.setUint16(8, e.deflate ? 8 : 0, true)
    lv.setUint32(18, body.length, true)
    lv.setUint32(22, raw.length, true)
    lv.setUint16(26, name.length, true)
    local.set(name, 30)
    local.set(body, 30 + name.length)
    const central = new Uint8Array(46 + name.length)
    const cv = new DataView(central.buffer)
    cv.setUint32(0, 0x02_01_4b_50, true)
    cv.setUint16(10, e.deflate ? 8 : 0, true)
    cv.setUint32(20, body.length, true)
    cv.setUint32(24, raw.length, true)
    cv.setUint16(28, name.length, true)
    cv.setUint32(42, offset, true)
    central.set(name, 46)
    locals.push(local)
    centrals.push(central)
    offset += local.length
  }
  const size = centrals.reduce((n, c) => n + c.length, 0)
  const end = new Uint8Array(22)
  const ev = new DataView(end.buffer)
  ev.setUint32(0, 0x06_05_4b_50, true)
  ev.setUint16(10, entries.length, true)
  ev.setUint32(12, size, true)
  ev.setUint32(16, offset, true)
  return new Uint8Array(Buffer.concat([...locals, ...centrals, end]))
}

test("reads stored and deflated entries", () => {
  const files = unzip(
    zip([
      { data: "## Interface: 16001", name: "Foo/Foo.toc" },
      { data: "print('hi')".repeat(50), deflate: true, name: "Foo/core.lua" },
    ]),
  )
  expect(files.map((f) => f.name)).toEqual(["Foo/Foo.toc", "Foo/core.lua"])
  expect(new TextDecoder().decode(files[1]!.data)).toBe(
    "print('hi')".repeat(50),
  )
})

test("only accepts files inside addon folders, never wai's own", () => {
  expect(
    addonFolders(["Details/Details.toc", "Details_Classic/x.lua"]),
  ).toEqual(["Details", "Details_Classic"])
  expect(() => addonFolders(["Foo/../../evil.lua"])).toThrow("unexpected path")
  expect(() => addonFolders(["readme.txt"])).toThrow("unexpected path")
  expect(() => addonFolders(["/etc/x/y"])).toThrow("unexpected path")
  expect(() => addonFolders(["wai/wai.lua"])).toThrow("wai's own")
  expect(() => addonFolders(["wai_slot001/slot.lua"])).toThrow("wai's own")
})

test("picks the newest release built for this client", () => {
  const files = [
    {
      dateCreated: "2026-11-05",
      gameVersions: ["1.15.9"],
      id: 1,
      releaseType: 1,
    },
    {
      dateCreated: "2026-11-04",
      gameVersions: ["1.60.1"],
      id: 2,
      releaseType: 2,
    },
    {
      dateCreated: "2026-10-01",
      gameVersions: ["1.60.0"],
      id: 3,
      releaseType: 1,
    },
    {
      dateCreated: "2026-09-01",
      gameVersions: ["1.60.1"],
      id: 4,
      releaseType: 1,
    },
  ]
  expect(pickFile(files, "1.60")?.id).toBe(3)
  expect(pickFile(files, "1.16")).toBeUndefined()
})

test("reads Forever's version from the launcher's build info", async () => {
  const dir = await mkdtemp(join(tmpdir(), "wai-cf-"))
  await Bun.write(
    join(dir, ".build.info"),
    "Branch!STRING:0|Version!STRING:0|Product!STRING:0\nus|1.15.9.1|wow_classic_era\nus|1.61.2.70790|wowf\n",
  )
  expect(
    foreverVersion(await readFile(join(dir, ".build.info"), "utf-8")),
  ).toBe("1.61")
  expect(foreverVersion("")).toBe("1.60")
})
