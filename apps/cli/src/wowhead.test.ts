import { expect, test } from "bun:test"

import { formatResults, formatTooltip, htmlText } from "./wowhead"

test("tooltip HTML becomes plain lines with money", () => {
  expect(
    htmlText(
      '<table><tr><td><b>Potion</b></td></tr></table><table><tr><td>Requires Level <!--rlvl-->21<br>Use: Restores &lt;455&gt; health.<div class="whtt-sellprice">Sell Price: <span class="moneysilver">1</span> <span class="moneycopper">25</span></div></td></tr></table>',
    ),
  ).toBe(
    "Potion\nRequires Level 21\nUse: Restores <455> health.\nSell Price: 1s 25c",
  )
})

test("search results name the type, ID and where they belong", () => {
  const text = formatResults([
    {
      type: 5,
      id: 166,
      name: "The Defias Brotherhood",
      pinFooterText: "Level: 22",
      pinBreadcrumb: ["Dungeons", "The Deadmines"],
      pinDescription: "Edwin VanCleef must be <br />assassinated.",
    },
    { type: 99, id: 1, name: "unknown type" },
  ])
  expect(text).toBe(
    "- quest 166: The Defias Brotherhood (Level: 22, Dungeons > The Deadmines)\n  Edwin VanCleef must be assassinated.",
  )
  expect(formatResults([])).toContain("No Forever results")
})

test("NPC tooltips carry their zone and coordinates", () => {
  const text = formatTooltip(
    "npc",
    3519,
    {
      name: "Sentinel Arynia Cloudsbreak",
      tooltip:
        '<table><tr><td><b class="q">Sentinel Arynia Cloudsbreak</b></td></tr><tr><td>Level 10 Humanoid (Normal)</td></tr></table>',
      map: { zone: 141, coords: { "0": [[38.2, 34.4]] } },
    },
    "Teldrassil",
  )
  expect(text).toBe(
    "npc 3519: Sentinel Arynia Cloudsbreak\nLevel 10 Humanoid (Normal)\nLocation: Teldrassil at 38.2,34.4\nPage: https://www.wowhead.com/forever/npc=3519",
  )
})
