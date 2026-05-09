import { expect, test } from "bun:test";

import {
  BrowserWASIBridge,
  encodeRenderStyleControlMessage,
  encodeResizeControlMessage,
} from "./BrowserWASIBridge.ts";
import {
  decodeWebHostTerminalRenderStyleBase64,
  encodeWebHostTerminalRenderStyleBase64,
} from "../WebHostTerminalStyle.ts";

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
    decodeWebHostTerminalRenderStyleBase64(bridge.environment.TUIGUI_RENDER_STYLE ?? "")
      ?.appearance.backgroundColor
  ).toBe("#111111");
  expect(
    bridge.environment.TUIGUI_RENDER_STYLE
  ).toBe(encodeWebHostTerminalRenderStyleBase64(style));
  expect(bridge.environment.TUIGUI_TRANSPORT).toBe("surface");

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
  const seen: Array<[number, number, number | undefined, number | undefined]> = [];
  const unsubscribe = bridge.subscribeResize((columns, rows, cellWidth, cellHeight) => {
    seen.push([columns, rows, cellWidth, cellHeight]);
  });

  expect(seen).toEqual([[80, 24, undefined, undefined]]);

  bridge.resize(132, 41, 9, 18);

  expect(bridge.environment.TUIGUI_COLUMNS).toBe("132");
  expect(bridge.environment.TUIGUI_ROWS).toBe("41");
  expect(seen).toEqual([
    [80, 24, undefined, undefined],
    [132, 41, 9, 18],
  ]);

  const input = await bridge.stdin.read();
  expect(Array.from(input ?? [])).toEqual(Array.from(encodeResizeControlMessage(132, 41, 9, 18)));

  unsubscribe();
  bridge.resize(90, 30);
  expect(seen).toEqual([
    [80, 24, undefined, undefined],
    [132, 41, 9, 18],
  ]);

  const replayed: Array<[number, number, number | undefined, number | undefined]> = [];
  bridge.subscribeResize((columns, rows, cellWidth, cellHeight) => {
    replayed.push([columns, rows, cellWidth, cellHeight]);
  })();
  expect(replayed).toEqual([[90, 30, undefined, undefined]]);
});

test("bridge delivers typed clipboard output to sinks", () => {
  const bridge = new BrowserWASIBridge({
    sceneId: "main",
    columns: 80,
    rows: 24,
  });
  const clipboard: string[] = [];

  bridge.bindOutput({
    presentSurface: () => {},
    writeClipboard: (text) => clipboard.push(text),
  });

  bridge.stdout.write(new TextEncoder().encode('\u001Eclipboard:{"text":"copied text"}\n'));

  expect(clipboard).toEqual(["copied text"]);
});
