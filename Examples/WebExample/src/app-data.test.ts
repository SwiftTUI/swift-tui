import { expect, test } from "bun:test";

import { defaultStyle, fallbackManifest, marketingStyle } from "./app-data.ts";

test("fallback manifest provides a default scene", () => {
  expect(fallbackManifest.defaultSceneId).toBe("main");
  expect(fallbackManifest.scenes).toHaveLength(2);
  expect(fallbackManifest.scenes[0]?.isDefault).toBe(true);
  expect(fallbackManifest.scenes[1]?.id).toBe("details");
});

test("default style keeps a readable terminal baseline", () => {
  expect(defaultStyle.fontSize).toBe(15);
  expect(defaultStyle.cursorBlink).toBe(false);
  expect(defaultStyle.backgroundOpacity).toBe(0.94);
});

test("marketing style matches the website palette", () => {
  // Background and foreground match Website/src/styles/site.css --bg / --ink
  expect(marketingStyle.palette?.background).toBe("#0a0a0a");
  expect(marketingStyle.palette?.foreground).toBe("#ededed");
  expect(marketingStyle.theme?.background).toBe("#0a0a0a");
  expect(marketingStyle.theme?.foreground).toBe("#ededed");

  // Tint / success / cursor are the site emerald accent (--accent).
  expect(marketingStyle.theme?.tint).toBe("#34d399");
  expect(marketingStyle.theme?.success).toBe("#34d399");
  expect(marketingStyle.palette?.cursor).toBe("#34d399");
  expect(marketingStyle.palette?.ansi?.green).toBe("#34d399");

  // Warning is the site amber (--warn).
  expect(marketingStyle.theme?.warning).toBe("#f59e0b");

  // Marketing embed paints opaque to seam cleanly into the chrome bg.
  expect(marketingStyle.backgroundOpacity).toBe(1);

  // Inherits the readable baseline from defaultStyle.
  expect(marketingStyle.fontSize).toBe(defaultStyle.fontSize);
  expect(marketingStyle.fontFamily).toBe(defaultStyle.fontFamily);
});
