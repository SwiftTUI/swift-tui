import { expect, test } from "bun:test";

import {
  WebTUIOutputDecoder,
  type WebTUIOutputRecord,
  type WebTUISurfaceFrame,
} from "./WebTUISurfaceTransport.ts";
import { transportFixture } from "./WebTUITestFixtures.ts";

const encoder = new TextEncoder();

test("decoder reads shared web-surface fixtures across chunk boundaries", () => {
  const decoder = new WebTUIOutputDecoder();
  const fixture = transportFixture("web-surface-basic");
  const split = Math.floor(fixture.length / 2);

  expect(decoder.feed(encoder.encode(fixture.slice(0, split)))).toEqual([]);

  const records = decoder.feed(encoder.encode(fixture.slice(split)));
  expect(records).toHaveLength(1);
  expect(records[0]?.type).toBe("surface");

  const frame = surfaceFrame(records[0]);
  expect(frame.width).toBe(2);
  expect(frame.height).toBe(2);
  expect(frame.styles).toEqual([null]);
  expect(frame.rows[0]).toEqual([[0, "O", 1, 0], [1, "K", 1, 0]]);
});

test("decoder returns multiple records from one stdout chunk", () => {
  const decoder = new WebTUIOutputDecoder();
  const records = decoder.feed(
    encoder.encode(
      transportFixture("web-surface-basic")
        + "legacy text\n"
        + transportFixture("web-surface-styled")
    )
  );

  expect(records.map((record) => record.type)).toEqual(["surface", "text", "surface"]);
  expect(records[1]).toEqual({ type: "text", text: "legacy text\n" });
  expect(surfaceFrame(records[2]).styles).toHaveLength(4);
});

test("decoder preserves typed image records", () => {
  const decoder = new WebTUIOutputDecoder();
  const records = decoder.feed(encoder.encode(
    '\u001Esurface:{"version":1,"width":2,"height":1,"styles":[null],"rows":[[]],'
      + '"images":[{"id":"png:test","format":"png","bounds":[0,0,1,1],'
      + '"visibleBounds":[0,0,1,1],"scalingMode":"stretch","pixelSize":[1,1],'
      + '"pngBase64":"iVBORw=="}]}\n'
  ));

  const frame = surfaceFrame(records[0]);
  expect(frame.images).toEqual([
    {
      id: "png:test",
      format: "png",
      bounds: [0, 0, 1, 1],
      visibleBounds: [0, 0, 1, 1],
      scalingMode: "stretch",
      pixelSize: [1, 1],
      pngBase64: "iVBORw==",
    },
  ]);
});

test("decoder keeps malformed surface output visible as text", () => {
  const decoder = new WebTUIOutputDecoder();
  const records = decoder.feed(encoder.encode('\u001Esurface:{"version":1,"width":2}\n'));

  expect(records).toEqual([
    {
      type: "text",
      text: '\u001Esurface:{"version":1,"width":2}\n',
    },
  ]);
});

test("decoder flushes partial buffered text as diagnostic output", () => {
  const decoder = new WebTUIOutputDecoder();

  expect(decoder.feed(encoder.encode("partial diagnostic"))).toEqual([]);
  expect(decoder.flush()).toEqual([
    {
      type: "text",
      text: "partial diagnostic\n",
    },
  ]);
});

function surfaceFrame(
  record: WebTUIOutputRecord | undefined
): WebTUISurfaceFrame {
  if (record?.type !== "surface") {
    throw new Error(`expected surface record, got ${record?.type ?? "undefined"}`);
  }
  return record.frame;
}
