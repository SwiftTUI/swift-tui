import { expect, test } from "bun:test";

import {
  ghosttyThemeForStyle,
  normalizeWebTUITerminalStyle,
  webTUITerminalBackgroundColor,
} from "./WebTUITerminalStyle.ts";

test("terminal style normalization fills defaults", () => {
  const style = normalizeWebTUITerminalStyle({
    fontSize: 16,
    cursorBlink: true,
  });

  expect(style.fontSize).toBe(16);
  expect(style.cursorBlink).toBe(true);
  expect(style.fontFamily.length).toBeGreaterThan(0);
  expect(style.lightPalette.background).toBe("#ffffff");
  expect(style.darkPalette.background).toBe("#1e1e1e");
});

test("terminal style maps to ghostty theme and translucent background", () => {
  const theme = ghosttyThemeForStyle({
    lightPalette: {
      foreground: "#101010",
      background: "#fafafa",
    },
    darkPalette: {
      foreground: "#ededed",
      background: "#111111",
    },
  });

  expect(theme.foreground).toBe("#ededed");
  expect(theme.background).toBe("#111111");
  expect(
    webTUITerminalBackgroundColor(
      {
        backgroundOpacity: 0.5,
        darkPalette: {
          background: "#202020",
        },
      }
    )
  ).toBe("rgba(32, 32, 32, 0.5)");
});
