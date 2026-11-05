// Self-update from GitHub Releases, like loadout: only a "managed" binary (installed by the install
// script) replaces itself. Each release has one binary per platform plus SHA256SUMS.
import { chmod, readFile, rename, rm, writeFile } from "node:fs/promises";
import { COMPILED, INSTALL_RECORD } from "./files";
import { REPO, VERSION } from "./version";

type Release = { version: string; assets: Record<string, string> }; // asset name -> API url

export function assetName(platform = process.platform, arch = process.arch) {
  const os = platform === "win32" ? "windows" : platform;
  return `wai-${os}-${arch === "arm64" ? "arm64" : "x64"}${platform === "win32" ? ".exe" : ""}`;
}

// "0.10.0" > "0.9.3"
export function newer(a: string, b: string) {
  const pa = a.split(".").map(Number);
  const pb = b.split(".").map(Number);
  for (let i = 0; i < 3; i++) if ((pa[i] ?? 0) !== (pb[i] ?? 0)) return (pa[i] ?? 0) > (pb[i] ?? 0);
  return false;
}

// The repo is private: use a token from the environment or the GitHub CLI.
function token() {
  const env = process.env.WAI_GITHUB_TOKEN ?? process.env.GITHUB_TOKEN ?? process.env.GH_TOKEN;
  if (env) return env;
  const gh = Bun.which("gh");
  return gh ? Bun.spawnSync([gh, "auth", "token"]).stdout.toString().trim() || undefined : undefined;
}

function headers(accept: string) {
  const t = token();
  return { Accept: accept, "User-Agent": "wai", ...(t ? { Authorization: `Bearer ${t}` } : {}) };
}

export async function latestRelease(): Promise<Release> {
  const res = await fetch(`https://api.github.com/repos/${REPO}/releases/latest`, { headers: headers("application/vnd.github+json") });
  if (!res.ok) throw new Error(`couldn't read releases (${res.status}). The repo is private: sign in with \`gh auth login\` or set GITHUB_TOKEN.`);
  const body = (await res.json()) as { tag_name: string; assets: { name: string; url: string }[] };
  return { version: body.tag_name.replace(/^v/, ""), assets: Object.fromEntries(body.assets.map((a) => [a.name, a.url])) };
}

async function download(url: string) {
  const res = await fetch(url, { headers: headers("application/octet-stream") });
  if (!res.ok) throw new Error(`download failed (${res.status})`);
  return new Uint8Array(await res.arrayBuffer());
}

async function managed() {
  const record = await readFile(INSTALL_RECORD, "utf8").then(JSON.parse).catch(() => undefined);
  return COMPILED && record?.managed === true ? record : undefined;
}

// The newer version, if there is one and this install can take it.
export async function availableUpdate(): Promise<string | undefined> {
  if (!(await managed())) return undefined;
  const release = await latestRelease().catch(() => undefined);
  return release && newer(release.version, VERSION) ? release.version : undefined;
}

export type UpdateResult = { updated: boolean; version?: string; addonChanged?: boolean; message: string };

export async function update(progress: (msg: string) => void = () => {}): Promise<UpdateResult> {
  if (!COMPILED) return { updated: false, message: "This wai runs from a source checkout; update it with git pull." };
  const record = await managed();
  if (!record) return { updated: false, message: "This wai binary wasn't installed by the install script, so it won't replace itself." };

  progress("Checking for updates…");
  const release = await latestRelease();
  if (!newer(release.version, VERSION)) return { updated: false, message: `wai ${VERSION} is up to date.` };

  const name = assetName();
  const binUrl = release.assets[name];
  const sumsUrl = release.assets["SHA256SUMS"];
  if (!binUrl || !sumsUrl) throw new Error(`release ${release.version} has no ${name}`);
  progress(`Downloading wai ${release.version}…`);
  const [bin, sums] = await Promise.all([download(binUrl), download(sumsUrl)]);
  const expected = new TextDecoder().decode(sums).split("\n").find((l) => l.trim().endsWith(` ${name}`))?.split(/\s+/)[0];
  const actual = new Bun.CryptoHasher("sha256").update(bin).digest("hex");
  if (!expected || expected !== actual) throw new Error(`checksum mismatch for ${name}; nothing was replaced`);

  // Swap the binary. Renaming a running executable is fine on macOS and Windows.
  const exe = process.execPath;
  await writeFile(`${exe}.new`, bin);
  await chmod(`${exe}.new`, 0o755);
  // macOS kills unsigned arm64 binaries; an ad-hoc signature is enough.
  if (process.platform === "darwin") Bun.spawnSync(["codesign", "--force", "--sign", "-", `${exe}.new`], { stderr: "ignore" });
  await rm(`${exe}.old`, { force: true });
  await rename(exe, `${exe}.old`);
  await rename(`${exe}.new`, exe);
  await writeFile(INSTALL_RECORD, JSON.stringify({ ...record, version: release.version, updatedAt: new Date().toISOString() }, null, 2));

  // The new binary carries the new addon; let it install itself.
  progress("Installing the new addon…");
  const post = Bun.spawnSync([exe, "install", "--post-update"], { stderr: "pipe" });
  if (post.exitCode !== 0) throw new Error(`the new version couldn't install its addon: ${post.stderr.toString().trim()}`);
  const { addonChanged } = JSON.parse(post.stdout.toString().trim().split("\n").at(-1) ?? "{}");
  return {
    updated: true,
    version: release.version,
    addonChanged,
    message: `Updated to wai ${release.version}.${addonChanged ? " Restart WoW to load the new addon." : ""}`,
  };
}
