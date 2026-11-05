// `bun run setup` in a source checkout: link the repo's addon into WoW and create the slot addons.
import { WOW_DIR } from "./files"
import { setup } from "./install"
import { ensureFfmpeg, ensureYtDlp } from "./tools"

await setup(WOW_DIR)
await Promise.all([ensureYtDlp(true), ensureFfmpeg()]).catch((error) =>
  console.error(`video tools: ${error.message}`),
)
console.log(
  `set up ${WOW_DIR}. Start the bridge (bun start), then restart WoW.`,
)
