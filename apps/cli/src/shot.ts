// Decodes a message the addon drew into a screenshot: bit blocks inside a magenta frame.
// Each block carries 3 bits, one per colour channel (fully on or off, so gamma can't blur them).
// Layout must match shootNext() in wai.lua.
import { readFile } from "node:fs/promises"

export const COLS = 128
export const ROWS = 64
const MARGIN = 2
const BITS_PER_BLOCK = 3
export const CAPACITY = (COLS * ROWS * BITS_PER_BLOCK) / 8
const HEADER = 11 // "WAI", version, seq(2), slot(2), kind, length(2)
const VERSION = 2

export interface Image {
  width: number
  height: number
  rgb: (x: number, y: number) => [number, number, number]
}
export interface Shot {
  seq: number
  slot: number
  kind: number
  payload: string
}

export class IncompleteError extends Error {
  override name = "IncompleteError"
}

export function parseTga(buf: Buffer): Image {
  if (buf.length < 18) {
    throw new IncompleteError("tga header")
  }
  const idLength = buf[0]!
  const type = buf[2]!
  const width = buf.readUInt16LE(12)
  const height = buf.readUInt16LE(14)
  const bpp = buf[16]! / 8
  const topOrigin = (buf[17]! & 0x20) !== 0
  if ((type !== 2 && type !== 10) || (bpp !== 3 && bpp !== 4)) {
    throw new Error(`unsupported tga type=${type} bpp=${bpp * 8}`)
  }

  const size = width * height * bpp
  let pos = 18 + idLength
  let pixels: Buffer
  if (type === 2) {
    if (buf.length < pos + size) {
      throw new IncompleteError("tga pixels")
    }
    pixels = buf.subarray(pos, pos + size)
  } else {
    pixels = Buffer.alloc(size)
    let out = 0
    while (out < size) {
      if (pos >= buf.length) {
        throw new IncompleteError("tga rle")
      }
      const header = buf[pos++]!
      const count = (header & 0x7f) + 1
      if (header & 0x80) {
        const px = buf.subarray(pos, pos + bpp)
        pos += bpp
        for (let i = 0; i < count; i++, out += bpp) {
          px.copy(pixels, out)
        }
      } else {
        buf.copy(pixels, out, pos, pos + count * bpp)
        pos += count * bpp
        out += count * bpp
      }
    }
  }
  return {
    height,
    rgb(x, y) {
      const i = ((topOrigin ? y : height - 1 - y) * width + x) * bpp
      return [pixels[i + 2]!, pixels[i + 1]!, pixels[i]!]
    },
    width,
  }
}

const isMagenta = ([r, g, b]: [number, number, number]) =>
  r > 200 && g < 60 && b > 200

// The frame's top edge is the first long horizontal magenta run; stray magenta elsewhere is too short.
function findFrame(img: Image) {
  const minRun = (COLS + 2 * MARGIN) * 2
  for (let y = 0; y < img.height; y++) {
    let run = 0
    for (let x = 0; x <= img.width; x++) {
      if (x < img.width && isMagenta(img.rgb(x, y))) {
        run++
        continue
      }
      if (run >= minRun) {
        const left = x - run
        let h = 0
        while (y + h < img.height && isMagenta(img.rgb(left + 1, y + h))) {
          h++
        }
        const expected = (run * (ROWS + 2 * MARGIN)) / (COLS + 2 * MARGIN)
        if (Math.abs(h - expected) <= expected * 0.1) {
          return { left, top: y, width: run, height: h }
        }
      }
      run = 0
    }
  }
}

export function decode(img: Image): Shot | undefined {
  const frame = findFrame(img)
  if (!frame) {
    return undefined
  }
  const bw = frame.width / (COLS + 2 * MARGIN)
  const bh = frame.height / (ROWS + 2 * MARGIN)
  const bytes = new Uint8Array(CAPACITY)
  for (let i = 0; i < COLS * ROWS; i++) {
    const rgb = img.rgb(
      Math.floor(frame.left + (MARGIN + (i % COLS) + 0.5) * bw),
      Math.floor(frame.top + (MARGIN + Math.floor(i / COLS) + 0.5) * bh),
    )
    for (let c = 0; c < BITS_PER_BLOCK; c++) {
      const k = i * BITS_PER_BLOCK + c
      if (rgb[c]! > 127) {
        bytes[k >> 3]! |= 1 << (7 - (k & 7))
      }
    }
  }
  if (
    bytes[0] !== 87 ||
    bytes[1] !== 65 ||
    bytes[2] !== 73 ||
    bytes[3] !== VERSION
  ) {
    return undefined
  }
  const length = (bytes[9]! << 8) | bytes[10]!
  return {
    kind: bytes[8]!,
    payload: Buffer.from(bytes.subarray(HEADER, HEADER + length)).toString(
      "utf8",
    ),
    seq: (bytes[4]! << 8) | bytes[5]!,
    slot: (bytes[6]! << 8) | bytes[7]!,
  }
}

if (import.meta.main) {
  const t = performance.now()
  const shot = decode(parseTga(await readFile(process.argv[2]!)))
  console.log(JSON.stringify(shot), `${(performance.now() - t).toFixed(0)}ms`)
}
