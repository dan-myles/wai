import type { OxfmtConfig } from "oxfmt"

import ultracite from "ultracite/oxfmt"

const baseConfig: OxfmtConfig = {
  ...ultracite,
  // Rooted at each consumer's config directory and read by the editor too.
  // App-specific paths belong in that app's config, anchored with `/`.
  ignorePatterns: [
    ...(ultracite.ignorePatterns ?? []),
    "**/.cache/",
    "**/.next/",
    "**/.nitro/",
    "**/.output/",
    "**/.tanstack/",
    "**/.turbo/",
    "**/dist/",
    "**/generated/**",
    "**/_generated/**",
    "**/*.gen.*",
    "**/*.generated.*",
    "**/*.tsbuildinfo",
    "**/tsconfig*.json",
  ],
  // Preserve authored manifests and Markdown wrapping.
  sortPackageJson: false,
  proseWrap: "preserve",
  printWidth: 80,
  semi: false,
  singleQuote: false,
  tabWidth: 2,
  trailingComma: "all",
  useTabs: false,
  sortImports: {
    internalPattern: ["@wai/", "#"],
    groups: [
      "type",
      { newlinesBetween: true },
      ["builtin", "external"],
      { newlinesBetween: true },
      ["internal", "subpath"],
      { newlinesBetween: true },
      ["parent", "sibling", "index"],
      "style",
      "unknown",
    ],
    newlinesBetween: true,
    sortSideEffects: false,
  },
}

export default baseConfig
