import { expect, test } from "bun:test";

import { BrowserWASIBridge } from "./wasi/BrowserWASIBridge.ts";
import { WebTUISceneRuntime } from "./WebTUISceneRuntime.ts";
import { transportFixture } from "./WebTUITestFixtures.ts";

const encoder = new TextEncoder();
const decoder = new TextDecoder();

test("hidden scenes stay out of layout even after style updates", () => {
  const dom = installFakeDOM();
  try {
    const mount = new FakeElement("div");
    const runtime = new WebTUISceneRuntime({
      mount: mount as unknown as HTMLElement,
      descriptor: { id: "details", title: "Details", isDefault: false },
      style: {},
      onInput: () => {},
    });

    expect(runtime.element.hidden).toBe(true);
    expect(runtime.element.style.getPropertyValue("display")).toBe("none");
    expect(runtime.element.style.getPropertyPriority("display")).toBe("important");

    runtime.setStyle({ fontSize: 18 });
    expect(runtime.element.hidden).toBe(true);
    expect(runtime.element.style.getPropertyValue("display")).toBe("none");

    runtime.setVisible(true);
    expect(runtime.element.hidden).toBe(false);
    expect(runtime.element.style.getPropertyValue("display")).toBe("grid");

    runtime.setVisible(false);
    expect(runtime.element.hidden).toBe(true);
    expect(runtime.element.style.getPropertyValue("display")).toBe("none");
  } finally {
    dom.restore();
  }
});

test("runtime draws decoded surface frames into the canvas", async () => {
  const dom = installFakeDOM({ devicePixelRatio: 2 });
  try {
    const bridge = new BrowserWASIBridge({
      sceneId: "main",
      columns: 4,
      rows: 2,
    });
    const mount = new FakeElement("div");
    const runtime = new WebTUISceneRuntime({
      mount: mount as unknown as HTMLElement,
      descriptor: { id: "main", title: "Main", isDefault: true },
      style: {
        fontSize: 20,
        fontFamily: "Test Mono",
        theme: {
          foreground: "#eeeeee",
          background: "#101820",
        },
      },
      bridge,
      onInput: () => {},
    });

    await runtime.mount();

    expect(dom.canvases).toHaveLength(1);
    const canvas = dom.canvases[0]!;
    const context = canvas.context;

    context.operations = [];
    bridge.stdout.write(encoder.encode(transportFixture("web-surface-styled")));

    expect(canvas.width).toBe(80);
    expect(canvas.height).toBe(108);
    expect(canvas.style.width).toBe("40px");
    expect(canvas.style.height).toBe("54px");

    expect(context.operations).toContainEqual({
      type: "clearRect",
      x: 0,
      y: 0,
      width: 40,
      height: 54,
    });
    expect(context.operations).toContainEqual({
      type: "fillRect",
      x: 0,
      y: 0,
      width: 40,
      height: 54,
      fillStyle: "rgba(16, 24, 32, 1)",
      globalAlpha: 1,
    });

    expect(fillTextOperations(context, "A")).toEqual([
      {
        type: "fillText",
        text: "A",
        x: 0,
        y: 21,
        fillStyle: "#000000FF",
        font: "italic 700 20px Test Mono",
        globalAlpha: 0.75,
      },
    ]);
    expect(fillTextOperations(context, "界")).toHaveLength(1);
    expect(fillRectOperations(context, "#E05757FF")[0]).toMatchObject({
      x: 0,
      y: 0,
      width: 10,
      height: 27,
      globalAlpha: 0.75,
    });
    expect(fillRectOperations(context, "#61C67BFF")[0]).toMatchObject({
      x: 10,
      y: 0,
      width: 20,
      height: 27,
      globalAlpha: 0.5,
    });

    const strokes = context.operations.filter((operation) => operation.type === "stroke");
    expect(strokes).toContainEqual({
      type: "stroke",
      strokeStyle: "#EBB33CFF",
      lineWidth: 1,
      lineDash: [4, 3],
      path: [["moveTo", 0, 25], ["lineTo", 10, 25]],
    });
    expect(strokes).toContainEqual({
      type: "stroke",
      strokeStyle: "#E05757FF",
      lineWidth: 1,
      lineDash: [1, 3],
      path: [["moveTo", 0, 13], ["lineTo", 10, 13]],
    });
    expect(strokes.some((operation) => operation.lineWidth === 2)).toBe(true);
  } finally {
    dom.restore();
  }
});

test("runtime draws box and block elements procedurally instead of as font glyphs", async () => {
  const dom = installFakeDOM();
  try {
    const bridge = new BrowserWASIBridge({
      sceneId: "main",
      columns: 4,
      rows: 2,
    });
    const mount = new FakeElement("div");
    const runtime = new WebTUISceneRuntime({
      mount: mount as unknown as HTMLElement,
      descriptor: { id: "main", title: "Main", isDefault: true },
      style: {
        fontSize: 20,
        fontFamily: "Test Mono",
      },
      bridge,
      onInput: () => {},
    });

    await runtime.mount();

    const canvas = dom.canvases[0]!;
    const context = canvas.context;
    context.operations = [];
    bridge.stdout.write(encoder.encode(surfaceRecord({
      version: 1,
      width: 4,
      height: 2,
      styles: [
        null,
        {
          fg: "#EBB33CFF",
        },
      ],
      rows: [
        [
          [0, "┌", 1, 1],
          [1, "─", 1, 1],
          [2, "▄", 1, 1],
          [3, "A", 1, 1],
        ],
      ],
      images: [],
    })));

    expect(fillTextOperations(context, "┌")).toEqual([]);
    expect(fillTextOperations(context, "─")).toEqual([]);
    expect(fillTextOperations(context, "▄")).toEqual([]);
    expect(fillTextOperations(context, "A")).toHaveLength(1);

    const boxFills = fillRectOperations(context, "#EBB33CFF");
    expect(boxFills).toContainEqual({
      type: "fillRect",
      x: 4.5,
      y: 13,
      width: 5.5,
      height: 1,
      fillStyle: "#EBB33CFF",
      globalAlpha: 1,
    });
    expect(boxFills).toContainEqual({
      type: "fillRect",
      x: 4.5,
      y: 13,
      width: 1,
      height: 14,
      fillStyle: "#EBB33CFF",
      globalAlpha: 1,
    });
    expect(boxFills).toContainEqual({
      type: "fillRect",
      x: 10,
      y: 13,
      width: 5.5,
      height: 1,
      fillStyle: "#EBB33CFF",
      globalAlpha: 1,
    });
    expect(boxFills).toContainEqual({
      type: "fillRect",
      x: 14.5,
      y: 13,
      width: 5.5,
      height: 1,
      fillStyle: "#EBB33CFF",
      globalAlpha: 1,
    });
    expect(boxFills).toContainEqual({
      type: "fillRect",
      x: 20,
      y: 13.5,
      width: 10,
      height: 13.5,
      fillStyle: "#EBB33CFF",
      globalAlpha: 1,
    });
  } finally {
    dom.restore();
  }
});

test("runtime keeps diagnostic stdout visible when output is not a surface frame", async () => {
  const dom = installFakeDOM();
  try {
    const bridge = new BrowserWASIBridge({
      sceneId: "main",
      columns: 4,
      rows: 2,
    });
    const mount = new FakeElement("div");
    const runtime = new WebTUISceneRuntime({
      mount: mount as unknown as HTMLElement,
      descriptor: { id: "main", title: "Main", isDefault: true },
      style: {},
      bridge,
      onInput: () => {},
    });

    await runtime.mount();
    bridge.stdout.write(encoder.encode("legacy output\n"));

    const diagnostic = runtime.terminalMount.children.find(
      (child) => child.className === "webtuigui-scene__diagnostic"
    );
    expect(diagnostic?.textContent).toBe("legacy output\n");
  } finally {
    dom.restore();
  }
});

test("runtime maps browser input events to web-surface messages", async () => {
  const dom = installFakeDOM();
  try {
    const inputs: string[] = [];
    const mount = new FakeElement("div");
    const runtime = new WebTUISceneRuntime({
      mount: mount as unknown as HTMLElement,
      descriptor: { id: "main", title: "Main", isDefault: true },
      style: { fontSize: 20 },
      onInput: (chunk) => {
        inputs.push(decoder.decode(chunk));
      },
    });

    await runtime.mount();
    runtime.resize(10, 4);

    runtime.terminalMount.dispatch("keydown", {
      key: "a",
      shiftKey: true,
      altKey: false,
      ctrlKey: true,
      metaKey: false,
      isComposing: false,
      preventDefault() {},
    });
    runtime.terminalMount.dispatch("paste", {
      clipboardData: {
        getData: () => "hello world",
      },
      preventDefault() {},
    });
    runtime.terminalMount.dispatch("pointerdown", pointerEvent({
      button: 0,
      buttons: 1,
      clientX: 25,
      clientY: 10,
      pointerId: 7,
    }));
    runtime.terminalMount.dispatch("pointermove", pointerEvent({
      buttons: 1,
      clientX: 35,
      clientY: 30,
      pointerId: 7,
    }));
    runtime.terminalMount.dispatch("wheel", {
      clientX: 35,
      clientY: 30,
      deltaX: 0,
      deltaY: 20,
      shiftKey: false,
      altKey: true,
      ctrlKey: false,
      preventDefault() {},
    });

    expect(inputs).toEqual([
      "\u001Ekey:character:a:5\n",
      "\u001Epaste:hello%20world\n",
      "\u001Emouse:down:2:0:primary:0:0:0\n",
      "\u001Emouse:dragged:3:1:primary:0:0:0\n",
      "\u001Emouse:scrolled:3:1:none:0:1:2\n",
    ]);
  } finally {
    dom.restore();
  }
});

function pointerEvent(
  overrides: Record<string, unknown>
): Record<string, unknown> {
  return {
    button: 0,
    buttons: 0,
    clientX: 0,
    clientY: 0,
    pointerId: 1,
    shiftKey: false,
    altKey: false,
    ctrlKey: false,
    preventDefault() {},
    ...overrides,
  };
}

function fillTextOperations(
  context: RecordingCanvasContext,
  text: string
): RecordingCanvasOperation[] {
  return context.operations.filter(
    (operation) => operation.type === "fillText" && operation.text === text
  );
}

function fillRectOperations(
  context: RecordingCanvasContext,
  fillStyle: string
): RecordingCanvasOperation[] {
  return context.operations.filter(
    (operation) => operation.type === "fillRect" && operation.fillStyle === fillStyle
  );
}

function surfaceRecord(
  frame: Record<string, unknown>
): string {
  return `\u001Esurface:${JSON.stringify(frame)}\n`;
}

interface FakeDOMOptions {
  devicePixelRatio?: number;
}

function installFakeDOM(
  options: FakeDOMOptions = {}
): {
  canvases: FakeCanvasElement[];
  restore(): void;
} {
  const previousDocument = globalThis.document;
  const previousWindow = globalThis.window;
  const previousResizeObserver = globalThis.ResizeObserver;
  const canvases: FakeCanvasElement[] = [];

  globalThis.document = {
    createElement: (tagName: string) => {
      if (tagName === "canvas") {
        const canvas = new FakeCanvasElement();
        canvases.push(canvas);
        return canvas;
      }
      return new FakeElement(tagName);
    },
  } as unknown as Document;
  globalThis.window = {
    devicePixelRatio: options.devicePixelRatio ?? 1,
  } as unknown as Window & typeof globalThis;
  globalThis.ResizeObserver = FakeResizeObserver as unknown as typeof ResizeObserver;

  return {
    canvases,
    restore: () => {
      globalThis.document = previousDocument;
      globalThis.window = previousWindow;
      globalThis.ResizeObserver = previousResizeObserver;
    },
  };
}

class FakeResizeObserver {
  observe(): void {}
  disconnect(): void {}
}

class FakeStyle {
  [key: string]: unknown;

  private readonly values = new Map<string, string>();
  private readonly priorities = new Map<string, string>();

  setProperty(
    name: string,
    value: string,
    priority?: string
  ): void {
    this.values.set(name, value);
    this.priorities.set(name, priority ?? "");
  }

  getPropertyValue(
    name: string
  ): string {
    return this.values.get(name) ?? "";
  }

  getPropertyPriority(
    name: string
  ): string {
    return this.priorities.get(name) ?? "";
  }
}

class FakeElement {
  readonly tagName: string;
  readonly style = new FakeStyle();
  readonly dataset: Record<string, string> = {};
  readonly children: FakeElement[] = [];
  private readonly eventListeners = new Map<string, Set<(event: Record<string, unknown>) => void>>();

  className = "";
  hidden = false;
  tabIndex = 0;
  textContent = "";
  rect = {
    left: 0,
    top: 0,
    width: 100,
    height: 108,
    right: 100,
    bottom: 108,
  };

  constructor(tagName: string) {
    this.tagName = tagName.toUpperCase();
  }

  append(
    ...children: FakeElement[]
  ): void {
    this.children.push(...children);
  }

  appendChild(
    child: FakeElement
  ): FakeElement {
    this.children.push(child);
    return child;
  }

  replaceChildren(
    ...children: FakeElement[]
  ): void {
    this.children.splice(0, this.children.length, ...children);
  }

  remove(): void {}
  focus(): void {}
  setPointerCapture(): void {}
  releasePointerCapture(): void {}

  getBoundingClientRect(): typeof this.rect {
    return this.rect;
  }

  addEventListener(
    type: string,
    listener: (event: Record<string, unknown>) => void
  ): void {
    let listeners = this.eventListeners.get(type);
    if (!listeners) {
      listeners = new Set();
      this.eventListeners.set(type, listeners);
    }
    listeners.add(listener);
  }

  removeEventListener(
    type: string,
    listener: (event: Record<string, unknown>) => void
  ): void {
    this.eventListeners.get(type)?.delete(listener);
  }

  dispatch(
    type: string,
    event: Record<string, unknown>
  ): void {
    for (const listener of this.eventListeners.get(type) ?? []) {
      listener(event);
    }
  }
}

class FakeCanvasElement extends FakeElement {
  readonly context = new RecordingCanvasContext();
  width = 0;
  height = 0;

  constructor() {
    super("canvas");
    this.rect = {
      left: 0,
      top: 0,
      width: 100,
      height: 108,
      right: 100,
      bottom: 108,
    };
  }

  getContext(
    contextId: string
  ): RecordingCanvasContext | undefined {
    return contextId === "2d" ? this.context : undefined;
  }
}

type RecordingCanvasOperation = Record<string, unknown>;

class RecordingCanvasContext {
  operations: RecordingCanvasOperation[] = [];
  fillStyle = "";
  strokeStyle = "";
  font = "";
  textBaseline = "";
  globalAlpha = 1;
  lineWidth = 1;
  lineCap = "butt";

  private lineDash: number[] = [];
  private path: Array<[string, ...number[]]> = [];

  measureText(
    text: string
  ): { width: number } {
    return { width: Math.max(1, Array.from(text).length) * 10 };
  }

  setTransform(
    a: number,
    b: number,
    c: number,
    d: number,
    e: number,
    f: number
  ): void {
    this.operations.push({ type: "setTransform", a, b, c, d, e, f });
  }

  clearRect(
    x: number,
    y: number,
    width: number,
    height: number
  ): void {
    this.operations.push({ type: "clearRect", x, y, width, height });
  }

  fillRect(
    x: number,
    y: number,
    width: number,
    height: number
  ): void {
    this.operations.push({
      type: "fillRect",
      x,
      y,
      width,
      height,
      fillStyle: this.fillStyle,
      globalAlpha: this.globalAlpha,
    });
  }

  fillText(
    text: string,
    x: number,
    y: number
  ): void {
    this.operations.push({
      type: "fillText",
      text,
      x,
      y,
      fillStyle: this.fillStyle,
      font: this.font,
      globalAlpha: this.globalAlpha,
    });
  }

  beginPath(): void {
    this.path = [];
  }

  moveTo(
    x: number,
    y: number
  ): void {
    this.path.push(["moveTo", x, y]);
  }

  lineTo(
    x: number,
    y: number
  ): void {
    this.path.push(["lineTo", x, y]);
  }

  bezierCurveTo(
    control1X: number,
    control1Y: number,
    control2X: number,
    control2Y: number,
    x: number,
    y: number
  ): void {
    this.path.push(["bezierCurveTo", control1X, control1Y, control2X, control2Y, x, y]);
  }

  stroke(): void {
    this.operations.push({
      type: "stroke",
      strokeStyle: this.strokeStyle,
      lineWidth: this.lineWidth,
      lineDash: [...this.lineDash],
      path: [...this.path],
    });
  }

  setLineDash(
    lineDash: number[]
  ): void {
    this.lineDash = [...lineDash];
  }
}
