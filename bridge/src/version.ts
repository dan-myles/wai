import pkg from "../package.json";

export const VERSION: string = pkg.version;
// Where releases are published.
export const REPO = process.env.WAI_REPO ?? "dan-myles/wai";
