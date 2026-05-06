import { expect, test } from "bun:test";

import {
  WebHostOutputDecoder,
  encodeMouseInputMessage,
  type WebHostOutputRecord,
  type WebHostSurfaceFrame,
} from "./WebHostSurfaceTransport.ts";
import { transportFixture } from "./WebHostTestFixtures.ts";

const encoder = new TextEncoder();
const decoder = new TextDecoder();

test("decoder reads shared web-surface fixtures across chunk boundaries", () => {
  const decoder = new WebHostOutputDecoder();
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
  const decoder = new WebHostOutputDecoder();
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
  const decoder = new WebHostOutputDecoder();
  const records = decoder.feed(encoder.encode(
    '\u001Esurface:{"version":1,"width":2,"height":1,"styles":[null],"rows":[[]],'
      + '"images":[{"id":"png:test","format":"png","bounds":[0,0,1,1],'
      + '"visibleBounds":[0,0,1,1],"scalingMode":"stretch","pixelSize":[1,1],'
      + '"dataBase64":"iVBORw=="}]}\n'
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
      dataBase64: "iVBORw==",
    },
  ]);
});

test("decoder accepts v2 accessibility trees", () => {
  const decoder = new WebHostOutputDecoder();
  const records = decoder.feed(encoder.encode(
    '\u001Esurface:{"version":2,"width":2,"height":1,"styles":[null],"rows":[[]],'
      + '"accessibilityTree":[{"id":"root/button","parentId":"root","rect":[0,0,2,1],'
      + '"role":"button","label":"Save","hint":"Writes the file",'
      + '"cursorAnchor":[1,0],"isFocused":true},'
      + '{"id":"root/status","rect":[0,1,2,1],"role":"status","label":"Saved",'
      + '"liveRegion":"polite","isFocused":false}]}\n'
  ));

  const frame = surfaceFrame(records[0]);
  expect(frame.version).toBe(2);
  expect(frame.accessibilityTree).toEqual([
    {
      id: "root/button",
      parentId: "root",
      rect: [0, 0, 2, 1],
      role: "button",
      label: "Save",
      hint: "Writes the file",
      cursorAnchor: [1, 0],
      isFocused: true,
    },
    {
      id: "root/status",
      rect: [0, 1, 2, 1],
      role: "status",
      label: "Saved",
      liveRegion: "polite",
      isFocused: false,
    },
  ]);
});

test("decoder accepts imperative accessibility announcements", () => {
  const decoder = new WebHostOutputDecoder();
  const records = decoder.feed(encoder.encode(
    '\u001Esurface:{"version":2,"width":2,"height":1,"styles":[null],"rows":[[]],'
      + '"accessibilityAnnouncements":[{"message":"Saved","politeness":"assertive"},'
      + '{"message":"Queued","politeness":"polite"}]}\n'
  ));

  const frame = surfaceFrame(records[0]);
  expect(frame.accessibilityAnnouncements).toEqual([
    { message: "Saved", politeness: "assertive" },
    { message: "Queued", politeness: "polite" },
  ]);
});

test("decoder rejects malformed accessibility trees as diagnostic text", () => {
  const decoder = new WebHostOutputDecoder();
  const line = '\u001Esurface:{"version":2,"width":2,"height":1,"styles":[null],"rows":[[]],'
    + '"accessibilityTree":[{"id":"missing-rect","role":"button"}]}\n';

  expect(decoder.feed(encoder.encode(line))).toEqual([
    {
      type: "text",
      text: line,
    },
  ]);
});

test("decoder keeps malformed surface output visible as text", () => {
  const decoder = new WebHostOutputDecoder();
  const records = decoder.feed(encoder.encode('\u001Esurface:{"version":1,"width":2}\n'));

  expect(records).toEqual([
    {
      type: "text",
      text: '\u001Esurface:{"version":1,"width":2}\n',
    },
  ]);
});

test("decoder flushes partial buffered text as diagnostic output", () => {
  const decoder = new WebHostOutputDecoder();

  expect(decoder.feed(encoder.encode("partial diagnostic"))).toEqual([]);
  expect(decoder.flush()).toEqual([
    {
      type: "text",
      text: "partial diagnostic\n",
    },
  ]);
});

test("mouse input encoder preserves fractional cell coordinates", () => {
  expect(decoder.decode(encodeMouseInputMessage({
    kind: "dragged",
    x: 2.125,
    y: 1.75,
    button: "primary",
  }))).toBe("\u001Emouse:dragged:2.125:1.75:primary:0:0:0\n");

  expect(decoder.decode(encodeMouseInputMessage({
    kind: "moved",
    x: -0.25,
    y: 99.5,
  }))).toBe("\u001Emouse:moved:-0.25:99.5:none:0:0:0\n");
});

function surfaceFrame(
  record: WebHostOutputRecord | undefined
): WebHostSurfaceFrame {
  if (record?.type !== "surface") {
    throw new Error(`expected surface record, got ${record?.type ?? "undefined"}`);
  }
  return record.frame;
}
