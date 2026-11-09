import { expect, test } from "bun:test"
import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join, resolve } from "node:path"

import {
  BITS,
  DOWN,
  FIRST,
  LAST,
  Link,
  PAYLOAD,
  UP,
  chunks,
  decodeFrame,
  downName,
  encodeFrame,
  nextSeq,
  readLane,
  upName,
  writeDownLane,
} from "./link"
import { toLuaCompact } from "./lua"

const frame = (over: Partial<Parameters<typeof encodeFrame>[0]> = {}) => ({
  ack: 4,
  flags: FIRST | LAST,
  gen: 9,
  lane: UP,
  payload: Buffer.from("hello"),
  seq: 5,
  session: 4242,
  ...over,
})

test("frames round-trip and reject damage", () => {
  const bytes = encodeFrame(frame())
  expect(decodeFrame(bytes)).toEqual(frame())
  bytes[20]! ^= 1
  expect(decodeFrame(bytes)).toBeUndefined()
  expect(() =>
    encodeFrame(frame({ payload: Buffer.alloc(PAYLOAD + 1) })),
  ).toThrow()
})

test("sequence numbers skip 0", () => {
  expect(nextSeq(0)).toBe(1)
  expect(nextSeq(254)).toBe(255)
  expect(nextSeq(255)).toBe(1)
})

test("messages split into flagged chunks", () => {
  expect(chunks(Buffer.alloc(0), false)).toEqual([
    { flags: FIRST | LAST, payload: Buffer.alloc(0) },
  ])
  const parts = chunks(Buffer.alloc(PAYLOAD * 2 + 1), true)
  expect(parts.map((c) => [c.flags, c.payload.length])).toEqual([
    [FIRST | 4, PAYLOAD],
    [4, PAYLOAD],
    [LAST | 4, 1],
  ])
})

const lines = (prefix: (i: number) => string, bytes?: Buffer) =>
  Array.from(
    { length: BITS },
    (_, i) =>
      `${prefix(i)}: ${bytes && (bytes[i >> 3]! >> (i & 7)) & 1 ? "enabled" : "disabled"}`,
  )

test("lanes read from and write into AddOns.txt, leaving other lines alone", () => {
  const up = encodeFrame(frame())
  const text = [
    "Pawn: enabled",
    ...lines(upName, up),
    "wai: enabled",
    ...lines(downName),
  ].join("\n")
  expect(readLane(text, "up")).toEqual(up)
  expect(readLane("Pawn: enabled", "up")).toBeUndefined()
  const down = encodeFrame(frame({ lane: DOWN }))
  const written = writeDownLane(text, down)
  expect(readLane(written, "dn")).toEqual(down)
  expect(readLane(written, "up")).toEqual(up)
  expect(written.split("\n").slice(0, 1)).toEqual(["Pawn: enabled"])
  // A file the client hasn't listed the down lane in yet gets it appended.
  expect(readLane(writeDownLane("Pawn: enabled\n", down), "dn")).toEqual(down)
})

// The real addon side (link.lua, in luajit) against the real bridge side over one file.
const luajit = Bun.which("luajit")
for (const mode of [[], ["zip"], ["chaos"]]) {
  const zip = mode.includes("zip")
  test.skipIf(!luajit)(
    `addon and bridge talk over AddOns.txt ${mode.join(" ") || "plain"}`,
    async () => {
      const dir = await mkdtemp(join(tmpdir(), "wai-link-"))
      const charDir = join(dir, "ACCOUNT", "Realm", "Backshot")
      await mkdir(charDir, { recursive: true })
      const file = join(charDir, "AddOns.txt")
      await writeFile(
        file,
        ["Pawn: enabled", "wai: enabled", ...lines(upName), ...lines(downName)]
          .map((l) => l.replace("disabled", "enabled"))
          .join("\n"),
      )
      let peerZip = false
      const link = new Link(
        dir,
        7,
        {},
        {
          drained: () => {},
          message: (peer, body) => {
            peerZip ||= peer.zip
            echoed += 1
            const n = echoed
            link.send(
              peer,
              Buffer.from(toLuaCompact({ hex: body.toString("hex"), n })),
            )
          },
          session: () => {},
        },
      )
      let echoed = 0
      await link.start()
      try {
        const run = Bun.spawn(
          [luajit!, "test/link-e2e.lua", ".", file, ...mode],
          {
            cwd: resolve(import.meta.dir, "../../addon"),
            stderr: "pipe",
            stdout: "pipe",
          },
        )
        const [out, err, code] = await Promise.all([
          new Response(run.stdout).text(),
          new Response(run.stderr).text(),
          run.exited,
        ])
        console.log(out.trim())
        expect(err).toBe("")
        expect(code).toBe(0)
        expect(out).toContain("done")
        expect(echoed).toBe(5)
        expect(peerZip).toBe(zip)
      } finally {
        link.stop()
        await rm(dir, { force: true, recursive: true })
      }
    },
    40_000,
  )
}
