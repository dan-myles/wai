import { defineConfig } from "oxlint"
import ultracite from "ultracite/oxlint/core"

const baseConfig = defineConfig({
  extends: [ultracite],
  // Rooted at each consumer's config directory and read by the editor too.
  // App-specific paths belong in that app's config, anchored with `/`. Match
  // generated code by suffix or folder: a bare "gen" would skip `agent.ts`.
  // Presets and apps must spread these, since `extends` drops them.
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
  ],
  rules: {
    // A const and type may share a name; TypeScript rejects real redeclarations.
    "eslint/no-redeclare": "off",
    // TSDoc's @remarks carries a declaration's longer explanation.
    "jsdoc/check-tag-names": ["error", { definedTags: ["remarks"] }],
    "typescript/consistent-type-imports": "error",
    "typescript/no-import-type-side-effects": "error",
  },
})

export default baseConfig
