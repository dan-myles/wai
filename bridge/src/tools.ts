// External tools for video, downloaded on first use into wai's bin folder: our own yt-dlp (system
// copies are often too old for YouTube) and a static ffmpeg build. Works on macOS and Windows.
import { chmod, exists, mkdir, rename, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { gunzipSync } from "node:zlib";
import { BIN_DIR } from "./files";

const EXE = process.platform === "win32" ? ".exe" : "";
const YT_DLP = join(BIN_DIR, `yt-dlp${EXE}`);
const FFMPEG = join(BIN_DIR, `ffmpeg${EXE}`);
const YT_DLP_ASSET = process.platform === "win32" ? "yt-dlp.exe" : process.platform === "darwin" ? "yt-dlp_macos" : "yt-dlp";
// Static builds published alongside the ffmpeg-static npm package.
const FFMPEG_URL = `https://github.com/eugeneware/ffmpeg-static/releases/download/b6.0/ffmpeg-${process.platform}-${process.arch}.gz`;

async function download(url: string, to: string, gunzip = false) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`download failed (${res.status}): ${url}`);
  let bytes = new Uint8Array(await res.arrayBuffer());
  if (gunzip) bytes = gunzipSync(bytes);
  await mkdir(BIN_DIR, { recursive: true });
  await writeFile(`${to}.tmp`, bytes);
  await chmod(`${to}.tmp`, 0o755);
  await rename(`${to}.tmp`, to);
}

export async function ytDlpPath(): Promise<string> {
  await ensureYtDlp();
  return YT_DLP;
}

export async function ffmpegPath(): Promise<string> {
  await ensureFfmpeg();
  return FFMPEG;
}

export async function ensureYtDlp(update = false) {
  if (await exists(YT_DLP)) {
    if (update) Bun.spawnSync([YT_DLP, "-U"], { stdout: "ignore", stderr: "ignore" });
    return;
  }
  await download(`https://github.com/yt-dlp/yt-dlp/releases/latest/download/${YT_DLP_ASSET}`, YT_DLP);
}

export async function ensureFfmpeg() {
  if (await exists(FFMPEG)) return;
  await download(FFMPEG_URL, FFMPEG, true);
}

export async function toolsPresent() {
  return { ytDlp: await exists(YT_DLP), ffmpeg: await exists(FFMPEG) };
}
