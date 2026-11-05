import { defineConfig } from "oxlint"

import baseConfig from "@wai/oxlint-config/base"

export default defineConfig({
  extends: [baseConfig],
  ignorePatterns: baseConfig.ignorePatterns,
})
