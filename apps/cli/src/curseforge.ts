// Installs addons from CurseForge, and only from there. Its search sits behind a bot challenge, so
// the agent finds a project's ID on its page; these endpoints (the ones curseforge.com itself
// uses) list a project's files and hand out downloads, with no API key.
import { existsSync, readFileSync } from "node:fs"
import { mkdir, rename, rm, writeFile } from "node:fs/promises"
import { dirname, join } from "node:path"
import { inflateRawSync } from "node:zlib"

import { ADDONS_DIR, WOW_DIR } from "./files"

const API = "https://www.curseforge.com/api/v1/mods"
const HEADERS = { "user-agent": "wai (+https://github.com/dan-myles/wai)" }

export interface CfFile {
  id: number
  displayName?: string
  fileName?: string
  dateCreated?: string
  releaseType?: number // 1 release, 2 beta, 3 alpha
  gameVersions?: string[]
}

const RELEASE: Record<number, string> = { 1: "release", 2: "beta", 3: "alpha" }

// Forever's game version as CurseForge tags it ("1.60"), from the launcher's record of the
// installed client. Files tagged with any patch of it work.
export function foreverVersion(
  info = (() => {
    try {
      return readFileSync(join(dirname(WOW_DIR), ".build.info"), "utf-8")
    } catch {
      return ""
    }
  })(),
): string {
  const [header = "", ...rows] = info.split("\n")
  const columns = header.split("|").map((c) => c.split("!")[0])
  const product = columns.indexOf("Product")
  const version = columns.indexOf("Version")
  for (const row of rows) {
    const cells = row.split("|")
    const match = /^(\d+\.\d+)\./.exec(cells[version] ?? "")
    if (cells[product] === "wowf" && match) {
      return match[1]!
    }
  }
  return "1.60"
}

const fits = (f: CfFile, version: string) =>
  (f.gameVersions ?? []).some(
    (v) => v === version || v.startsWith(`${version}.`),
  )

// The newest file for this client, releases before betas before alphas.
export function pickFile(files: CfFile[], version: string): CfFile | undefined {
  return [...files]
    .filter((f) => fits(f, version))
    .sort(
      (a, b) =>
        (a.releaseType ?? 9) - (b.releaseType ?? 9) ||
        (b.dateCreated ?? "").localeCompare(a.dateCreated ?? ""),
    )[0]
}

export async function projectFiles(projectId: number): Promise<CfFile[]> {
  const res = await fetch(
    `${API}/${projectId}/files?pageIndex=0&pageSize=50&sort=dateCreated&sortDescending=true`,
    { headers: HEADERS, signal: AbortSignal.timeout(15_000) },
  )
  if (!res.ok) {
    throw new Error(
      `CurseForge answered ${res.status} for project ${projectId}`,
    )
  }
  const { data = [] } = (await res.json()) as { data?: CfFile[] }
  return data
}

// What the agent sees before offering an install.
export async function describe(projectId: number): Promise<string> {
  const files = await projectFiles(projectId)
  if (files.length === 0) {
    return `CurseForge has no files for project ${projectId}. Check the ID on the project's page.`
  }
  const version = foreverVersion()
  const file = pickFile(files, version)
  if (!file) {
    const newest = files[0]!
    return `No build for WoW: Forever (${version}.x) in project ${projectId}'s recent files. The newest, ${newest.displayName}, is for ${newest.gameVersions?.join(", ")}. Don't offer it.`
  }
  return `Forever build: ${file.displayName} (${RELEASE[file.releaseType ?? 0] ?? "file"}, ${file.dateCreated?.slice(0, 10)}, for ${file.gameVersions?.filter((v) => v.startsWith(version)).join(", ")}). Offer it with [[addon:${projectId}:Addon Name]].`
}

// A zip's files, read from its central directory. Addon zips are small, so no zip64.
export function unzip(zip: Uint8Array): { name: string; data: Uint8Array }[] {
  const view = new DataView(zip.buffer, zip.byteOffset, zip.byteLength)
  let end = zip.length - 22
  while (end >= 0 && view.getUint32(end, true) !== 0x06_05_4b_50) {
    end--
  }
  if (end < 0) {
    throw new Error("the download isn't a zip")
  }
  const count = view.getUint16(end + 10, true)
  let at = view.getUint32(end + 16, true)
  const decoder = new TextDecoder()
  const out: { name: string; data: Uint8Array }[] = []
  for (let i = 0; i < count; i++) {
    if (view.getUint32(at, true) !== 0x02_01_4b_50) {
      throw new Error("the zip is damaged")
    }
    const method = view.getUint16(at + 10, true)
    const size = view.getUint32(at + 20, true)
    const nameLength = view.getUint16(at + 28, true)
    const extra = view.getUint16(at + 30, true)
    const comment = view.getUint16(at + 32, true)
    const local = view.getUint32(at + 42, true)
    const name = decoder.decode(zip.subarray(at + 46, at + 46 + nameLength))
    at += 46 + nameLength + extra + comment
    if (name.endsWith("/")) {
      continue
    }
    const start =
      local +
      30 +
      view.getUint16(local + 26, true) +
      view.getUint16(local + 28, true)
    const raw = zip.subarray(start, start + size)
    if (method !== 0 && method !== 8) {
      throw new Error(`${name} uses an unsupported compression`)
    }
    out.push({ data: method === 8 ? inflateRawSync(raw) : raw, name })
  }
  return out
}

// Every file must sit inside a top-level addon folder; wai's own folders are never replaced.
export function addonFolders(names: string[]): string[] {
  const folders = new Set<string>()
  for (const name of names) {
    const parts = name.replaceAll("\\", "/").split("/")
    const [folder = ""] = parts
    if (
      parts.length < 2 ||
      parts.some((p) => p === ".." || p === ".") ||
      !/^[\w .!+-]+$/.test(folder)
    ) {
      throw new Error(`the zip has an unexpected path: ${name}`)
    }
    if (/^wai(_|$)/i.test(folder)) {
      throw new Error(`the zip would replace wai's own ${folder} folder`)
    }
    folders.add(folder)
  }
  if (folders.size === 0) {
    throw new Error("the zip is empty")
  }
  return [...folders]
}

export interface Installed {
  file: CfFile
  folders: string[]
  updated: boolean
}

export async function install(
  projectId: number,
  addons = ADDONS_DIR,
): Promise<Installed> {
  const file = pickFile(await projectFiles(projectId), foreverVersion())
  if (!file) {
    throw new Error("this addon has no build for WoW: Forever")
  }
  const res = await fetch(`${API}/${projectId}/files/${file.id}/download`, {
    headers: HEADERS,
    signal: AbortSignal.timeout(120_000),
  })
  if (!res.ok) {
    throw new Error(`CurseForge answered ${res.status} for the download`)
  }
  const entries = unzip(new Uint8Array(await res.arrayBuffer()))
  const folders = addonFolders(entries.map((e) => e.name))
  // Unpacked beside AddOns first, so a failed download never leaves half an addon behind.
  const staging = join(dirname(addons), `.wai-install-${projectId}`)
  await rm(staging, { force: true, recursive: true })
  for (const { name, data } of entries) {
    const path = join(staging, name.replaceAll("\\", "/"))
    await mkdir(dirname(path), { recursive: true })
    await writeFile(path, data)
  }
  let updated = false
  for (const folder of folders) {
    const target = join(addons, folder)
    updated ||= existsSync(target)
    await rm(target, { force: true, recursive: true })
    await rename(join(staging, folder), target)
  }
  await rm(staging, { force: true, recursive: true })
  return { file, folders, updated }
}
