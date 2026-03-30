import { expect, test } from "bun:test";

import { defaultStyle, fallbackManifest } from "./app-data.ts";

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
