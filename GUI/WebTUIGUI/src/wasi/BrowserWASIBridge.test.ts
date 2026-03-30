import { expect, test } from "bun:test";
import { BrowserWASIBridge, encodeResizeControlMessage } from "./BrowserWASIBridge.ts";

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
