// External tools for video, resolved portably: ffmpeg ships via the ffmpeg-static package,
// yt-dlp is our own copy in bridge/bin (system copies are often too old for YouTube).
import { chmod, exists, mkdir, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import ffmpegStatic from "ffmpeg-static";

const BIN_DIR = resolve(import.meta.dir, "../bin");
const YT_DLP_FILE = join(BIN_DIR, process.platform === "win32" ? "yt-dlp.exe" : "yt-dlp");
const YT_DLP_ASSET = process.platform === "win32" ? "yt-dlp.exe" : process.platform === "darwin" ? "yt-dlp_macos" : "yt-dlp";

export function ffmpegPath(): string {
  return (ffmpegStatic as unknown as string | null) ?? Bun.which("ffmpeg") ?? "ffmpeg";
}

export async function ytDlpPath(): Promise<string> {
  if (await exists(YT_DLP_FILE)) return YT_DLP_FILE;
  return Bun.which("yt-dlp") ?? YT_DLP_FILE;
}

// Downloads the standalone yt-dlp binary for this platform, or updates the one we have.
export async function ensureYtDlp() {
  if (await exists(YT_DLP_FILE)) {
    Bun.spawnSync([YT_DLP_FILE, "-U"], { stdout: "ignore", stderr: "ignore" });
    return;
  }
  await mkdir(BIN_DIR, { recursive: true });
  const res = await fetch(`https://github.com/yt-dlp/yt-dlp/releases/latest/download/${YT_DLP_ASSET}`);
  if (!res.ok) throw new Error(`yt-dlp download failed: ${res.status}`);
  await writeFile(YT_DLP_FILE, new Uint8Array(await res.arrayBuffer()));
  await chmod(YT_DLP_FILE, 0o755);
}
