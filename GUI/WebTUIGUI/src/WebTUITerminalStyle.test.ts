import { expect, test } from "bun:test";
import { readFileSync } from "node:fs";

import {
  decodeWebTUITerminalRenderStyleBase64,
  encodeWebTUITerminalRenderStyleBase64,
  normalizeWebTUITerminalStyle,
  resolveWebTUITerminalRenderStyle,
  webTUITerminalBackgroundColor,
} from "./WebTUITerminalStyle.ts";

test("terminal style normalization fills default palette and theme", () => {
  const style = normalizeWebTUITerminalStyle({
    fontSize: 16,
    cursorBlink: true,
  });

  expect(style.fontSize).toBe(16);
  expect(style.cursorBlink).toBe(true);
  expect(style.fontFamily.length).toBeGreaterThan(0);
  expect(style.theme.background).toBe("#1e222a");
  expect(style.palette.background).toBe("#1e222a");
});

test("terminal style resolves host-owned theme payloads", () => {
  const style = {
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
  };

  const resolved = resolveWebTUITerminalRenderStyle(style);
  expect(resolved.appearance.foregroundColor).toBe("#111111");
  expect(resolved.appearance.backgroundColor).toBe("#fafafa");
  expect(resolved.theme?.warning).toBe("#b46e00");
  expect(encodeWebTUITerminalRenderStyleBase64(style)).toBeDefined();
  expect(
    decodeWebTUITerminalRenderStyleBase64(
      encodeWebTUITerminalRenderStyleBase64(style)
    )?.appearance.backgroundColor
  ).toBe("#fafafa");
});

test("terminal style maps to surface palette and translucent background", () => {
  const style = {
    backgroundOpacity: 0.5,
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
  };

  expect(normalizeWebTUITerminalStyle(style).palette.foreground).toBe("#ededed");
  expect(normalizeWebTUITerminalStyle(style).palette.background).toBe("#202020");
  expect(webTUITerminalBackgroundColor(style)).toBe("rgba(32, 32, 32, 0.5)");
  expect(resolveWebTUITerminalRenderStyle(style).appearance.palette["0"]).toBe("#20242c");
});

test("shared default transport fixtures stay in sync with WebTUI encoding", () => {
  const fixture = transportFixture("terminal-render-style-default");

  expect(JSON.stringify(resolveWebTUITerminalRenderStyle({}))).toBe(fixture.json);
  expect(encodeWebTUITerminalRenderStyleBase64({})).toBe(fixture.base64);
  expect(
    JSON.stringify(decodeWebTUITerminalRenderStyleBase64(fixture.base64))
  ).toBe(fixture.json);
});

function transportFixture(
  basename: string
): { json: string; base64: string } {
  const json = readTransportFixture(`${basename}.json`);
  const base64 = readTransportFixture(`${basename}.base64.txt`);
  return { json, base64 };
}

function readTransportFixture(
  name: string
): string {
  return readFileSync(
    new URL(`../../../Fixtures/Transport/${name}`, import.meta.url),
    "utf8"
  ).trim();
}
