import { defineConfig } from "oxlint"

import baseConfig from "@wai/oxlint-config/base"

/*
 * The bridge is binary codecs (screenshots, video frames, TGA parsing) and ordered file IO, so a
 * few ultracite rules work against it. Each exemption below says why; don't add more without one.
 */
export default defineConfig({
  extends: [baseConfig],
  ignorePatterns: [
    ...(baseConfig.ignorePatterns ?? []),
    "src/embedded-addon.ts",
  ],
  rules: {
    // Bit packing is how the screenshot grid, video frames and TGA files are encoded.
    "eslint/no-bitwise": "off",
    // Slot files, chunks and messages are written strictly in order on purpose.
    "eslint/no-await-in-loop": "off",
    // Parsed buffers are indexed after explicit bounds checks; `!` marks those reads.
    "typescript/no-non-null-assertion": "off",
    // Lua string quoting and TGA headers use control characters and hex escapes deliberately.
    "eslint/no-control-regex": "off",
    "unicorn/no-hex-escape": "off",
    "unicorn/escape-case": "off",
    // Style rules the existing code predates; follow them in new code where it reads well.
    "eslint/func-style": "off",
    "eslint/no-plusplus": "off",
    "eslint/no-inline-comments": "off",
    "eslint/sort-keys": "off",
    "eslint/no-use-before-define": "off",
    "eslint/no-nested-ternary": "off",
    "eslint/no-negated-condition": "off",
    "eslint/complexity": "off",
    "eslint/require-unicode-regexp": "off",
    "eslint/prefer-named-capture-group": "off",
    "eslint/no-empty-function": "off",
    "unicorn/import-style": "off",
    "unicorn/no-array-sort": "off",
    "unicorn/prefer-code-point": "off",
    "unicorn/no-negated-condition": "off",
    "unicorn/numeric-separators-style": "off",
    "unicorn/text-encoding-identifier-case": "off",
    "unicorn/consistent-function-scoping": "off",
    "unicorn/no-await-expression-member": "off",
    "promise/avoid-new": "off",
    "promise/prefer-await-to-then": "off",
    "promise/prefer-await-to-callbacks": "off",
  },
})
