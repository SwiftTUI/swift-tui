import { expect, test } from "bun:test";

import {
  decodeWebTUITerminalRenderStyleBase64,
  encodeWebTUITerminalRenderStyleBase64,
  ghosttyThemeForStyle,
  normalizeWebTUITerminalStyle,
  resolveWebTUITerminalRenderStyle,
  webTUITerminalBackgroundColor,
} from "./WebTUITerminalStyle.ts";

test("terminal style normalization fills default variants", () => {
  const style = normalizeWebTUITerminalStyle({
    fontSize: 16,
    cursorBlink: true,
  });

  expect(style.fontSize).toBe(16);
  expect(style.cursorBlink).toBe(true);
  expect(style.fontFamily.length).toBeGreaterThan(0);
  expect(style.colorSchemeMode).toBe("dark");
  expect(style.light.theme.background).toBe("#ffffff");
  expect(style.dark.theme.background).toBe("#1e1e1e");
  expect(style.dark.palette.background).toBe("#1e1e1e");
});

test("terminal style resolves host-owned theme payloads", () => {
  const style = {
    colorSchemeMode: "system" as const,
    light: {
      palette: {
        foreground: "#101010",
        background: "#fafafa",
        cursor: "#101010",
        selectionBackground: "#d0e4ff",
        selectionForeground: "#101010",
      },
      theme: {
        foreground: "#111111",
        background: "#fafafa",
        tint: "#0f62fe",
        separator: "#d0d0d0",
        selection: "#d0e4ff",
        placeholder: "#707070",
        link: "#0f62fe",
        fill: "#f4f4f4",
        windowBackground: "#ffffff",
        success: "#198038",
        warning: "#b46e00",
        danger: "#da1e28",
        info: "#0f62fe",
        muted: "#525252",
      },
    },
    dark: {
      palette: {
        foreground: "#ededed",
        background: "#111111",
        cursor: "#ffffff",
        selectionBackground: "#264f78",
        selectionForeground: "#ffffff",
      },
      theme: {
        foreground: "#ededed",
        background: "#111111",
        tint: "#56b6c2",
        separator: "#4c566a",
        selection: "#2e3440",
        placeholder: "#8c92ac",
        link: "#5ba3ff",
        fill: "#2b303b",
        windowBackground: "#15181e",
        success: "#61c67b",
        warning: "#ebb33c",
        danger: "#e05757",
        info: "#56b6c2",
        muted: "#8c92ac",
      },
    },
  };

  const resolved = resolveWebTUITerminalRenderStyle(style, "dark");
  expect(resolved.appearance.foregroundColor).toBe("#ededed");
  expect(resolved.appearance.backgroundColor).toBe("#111111");
  expect(resolved.appearance.colorScheme).toBe("dark");
  expect(resolved.theme?.warning).toBe("#ebb33c");
  expect(encodeWebTUITerminalRenderStyleBase64(style, "dark")).toBeDefined();
  expect(
    decodeWebTUITerminalRenderStyleBase64(
      encodeWebTUITerminalRenderStyleBase64(style, "dark")
    )?.appearance.backgroundColor
  ).toBe("#111111");
});

test("terminal style maps to ghostty theme and translucent background", () => {
  const style = {
    backgroundOpacity: 0.5,
    dark: {
      palette: {
        foreground: "#ededed",
        background: "#202020",
        cursor: "#ffffff",
        selectionBackground: "#264f78",
        selectionForeground: "#ffffff",
      },
      theme: {
        foreground: "#ededed",
        background: "#202020",
        tint: "#56b6c2",
        separator: "#4c566a",
        selection: "#2e3440",
        placeholder: "#8c92ac",
        link: "#5ba3ff",
        fill: "#2b303b",
        windowBackground: "#15181e",
        success: "#61c67b",
        warning: "#ebb33c",
        danger: "#e05757",
        info: "#56b6c2",
        muted: "#8c92ac",
      },
    },
  };

  expect(ghosttyThemeForStyle(style, "dark").foreground).toBe("#ededed");
  expect(ghosttyThemeForStyle(style, "dark").background).toBe("#202020");
  expect(webTUITerminalBackgroundColor(style, "dark")).toBe(
    "rgba(32, 32, 32, 0.5)"
  );
  expect(resolveWebTUITerminalRenderStyle(style, "dark").appearance.palette["0"]).toBe(
    "#000000"
  );
});
