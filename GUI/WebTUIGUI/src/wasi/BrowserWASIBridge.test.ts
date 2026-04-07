import { expect, test } from "bun:test";

import {
  BrowserWASIBridge,
  encodeRenderStyleControlMessage,
  encodeResizeControlMessage,
} from "./BrowserWASIBridge.ts";
import {
  decodeWebTUITerminalRenderStyleBase64,
  encodeWebTUITerminalRenderStyleBase64,
} from "../WebTUITerminalStyle.ts";

test("bridge seeds initial render style and emits runtime style updates", async () => {
  const style = {
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
  };

  const bridge = new BrowserWASIBridge({
    sceneId: "main",
    columns: 80,
    rows: 24,
    renderStyle: style,
  });

  expect(
    decodeWebTUITerminalRenderStyleBase64(bridge.environment.TUIGUI_RENDER_STYLE ?? "")
      ?.appearance.backgroundColor
  ).toBe("#111111");
  expect(
    bridge.environment.TUIGUI_RENDER_STYLE
  ).toBe(encodeWebTUITerminalRenderStyleBase64(style));

  bridge.updateRenderStyle(style);
  const input = await bridge.stdin.read();
  expect(Array.from(input ?? [])).toEqual(
    Array.from(encodeRenderStyleControlMessage(style))
  );
});

test("bridge resize updates environment, emits control input, and notifies listeners", async () => {
  const bridge = new BrowserWASIBridge({
    sceneId: "main",
    columns: 80,
    rows: 24,
  });
  const seen: Array<[number, number]> = [];
  const unsubscribe = bridge.subscribeResize((columns, rows) => {
    seen.push([columns, rows]);
  });

  bridge.resize(132, 41);

  expect(bridge.environment.TUIGUI_COLUMNS).toBe("132");
  expect(bridge.environment.TUIGUI_ROWS).toBe("41");
  expect(seen).toEqual([[132, 41]]);

  const input = await bridge.stdin.read();
  expect(Array.from(input ?? [])).toEqual(Array.from(encodeResizeControlMessage(132, 41)));

  unsubscribe();
  bridge.resize(90, 30);
  expect(seen).toEqual([[132, 41]]);
});
