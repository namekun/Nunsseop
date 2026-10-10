#!/bin/bash
# Renders docs/images/og.png, the 1200×630 link preview, from scripts/og/og.html in headless Chromium.
# Uses docs/images/home.png and icon.png, so run it after either changes. Needs Playwright like site-test.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
NODE_PATH="$(npm root -g)" node -e '
const path = require("path");
const { chromium } = require("playwright");
(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1200, height: 630 } });
  await page.goto("file://" + path.resolve("scripts/og/og.html"));
  await page.waitForLoadState("networkidle").catch(() => {});
  await page.evaluate(() => document.fonts.ready);
  await page.screenshot({ path: "docs/images/og.png" });
  await browser.close();
})();
'
echo docs/images/og.png
