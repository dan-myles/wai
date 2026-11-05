// Pixel video: WoW only loads image files that existed at launch and caches them, so video is
// a grid of coloured blocks fed through load-on-demand "wai_vidNNN" slots. Each slot holds a
// few seconds of frames; each pixel is 12-bit colour as two base64 characters.
import { mkdtemp, readdir, rm } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"

import { toLua } from "./lua"
import { ffmpegPath, ytDlpPath } from "./tools"

export const FPS = 8
export const CHUNK_FRAMES = FPS * 3
export const MAX_SECONDS = 120
export const SIZES = { landscape: { h: 45, w: 80 }, portrait: { h: 80, w: 45 } }
export type Orientation = keyof typeof SIZES

const B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

// rgb24 frame -> two chars per pixel: r4 g4 b4 packed into 12 bits. Must match video.lua.
export function encodeFrame(rgb: Uint8Array): string {
  let out = ""
  for (let i = 0; i < rgb.length; i += 3) {
    const v =
      ((rgb[i]! >> 4) << 8) | ((rgb[i + 1]! >> 4) << 4) | (rgb[i + 2]! >> 4)
    out += B64[v >> 6]! + B64[v & 63]!
  }
  return out
}

async function run(cmd: string[]) {
  const proc = Bun.spawn(cmd, { stderr: "pipe", stdout: "pipe" })
  const [out, err, code] = await Promise.all([
    new Response(proc.stdout).arrayBuffer(),
    new Response(proc.stderr).text(),
    proc.exited,
  ])
  if (code !== 0) {
    throw new Error(err.trim().split("\n").at(-1) ?? `${cmd[0]} exited ${code}`)
  }
  return new Uint8Array(out)
}

export interface Video {
  title: string
  w: number
  h: number
  fps: number
  frames: string[]
}

// query: a URL or search words. Downloads a small rendition and converts it to block frames.
export async function fetchVideo(
  query: string,
  orientation: Orientation,
): Promise<Video> {
  const dir = await mkdtemp(join(tmpdir(), "wai-video-"))
  try {
    const target = /^https?:\/\//.test(query) ? query : `ytsearch1:${query}`
    const titleOut = await run([
      await ytDlpPath(),
      "--no-playlist",
      "--quiet",
      "--no-warnings",
      // YouTube needs a JS runtime for its player; Bun is already here.
      "--js-runtimes",
      `bun:${process.execPath}`,
      "--remote-components",
      "ejs:github",
      "-f",
      "worst[height>=144][ext=mp4]/worst[ext=mp4]/worst",
      "--ffmpeg-location",
      await ffmpegPath(),
      "--download-sections",
      `*0-${MAX_SECONDS}`,
      "-o",
      join(dir, "source.%(ext)s"),
      "--print",
      "after_move:title",
      "--no-simulate",
      target,
    ])
    const source = (await readdir(dir)).find((f) => f.startsWith("source."))
    if (!source) {
      throw new Error("download produced no file")
    }
    const { w, h } = SIZES[orientation]
    // Fill the frame (crop, don't letterbox) so portrait clips feel like TikTok.
    const raw = await run([
      await ffmpegPath(),
      "-loglevel",
      "error",
      "-i",
      join(dir, source),
      "-t",
      String(MAX_SECONDS),
      "-vf",
      `fps=${FPS},scale=${w}:${h}:force_original_aspect_ratio=increase,crop=${w}:${h},eq=saturation=1.25`,
      "-f",
      "rawvideo",
      "-pix_fmt",
      "rgb24",
      "-",
    ])
    const frameBytes = w * h * 3
    const frames: string[] = []
    for (let i = 0; i + frameBytes <= raw.length; i += frameBytes) {
      frames.push(encodeFrame(raw.subarray(i, i + frameBytes)))
    }
    if (!frames.length) {
      throw new Error("video had no frames")
    }
    return {
      fps: FPS,
      frames,
      h,
      title: new TextDecoder().decode(titleOut).trim().split("\n")[0] || query,
      w,
    }
  } finally {
    await rm(dir, { force: true, recursive: true })
  }
}

// One slot file's content: a chunk of frames.
export function chunkLua(id: string, chunk: number, frames: string[]) {
  return `WaiVideoChunk = ${toLua({ chunk, frames, id })}\n`
}
