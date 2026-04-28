import {
  applyWebTUITerminalStyle,
  normalizeWebTUITerminalStyle,
  type ResolvedWebTUITerminalStyle,
  type WebTUITerminalStyle,
  webTUITerminalBackgroundColor,
} from "./WebTUITerminalStyle.ts";
import {
  canRenderBoxDrawing,
  drawBoxDrawing,
} from "./BoxDrawingRenderer.ts";
import {
  encodeKeyInputMessage,
  encodeMouseInputMessage,
  encodePasteInputMessage,
  type WebTUIKeyInput,
  type WebTUISurfaceFrame,
  type WebTUISurfaceImage,
  type WebTUISurfaceImageFormat,
  type WebTUISurfaceStyle,
} from "./WebTUISurfaceTransport.ts";
import type { WebTUISceneDescriptor } from "./WebTUISceneManifest.ts";
import { BrowserWASIBridge } from "./wasi/BrowserWASIBridge.ts";

export interface WebTUISceneRuntimeOptions {
  mount: HTMLElement;
  descriptor: WebTUISceneDescriptor;
  style: WebTUITerminalStyle;
  bridge?: BrowserWASIBridge;
  onInput(chunk: Uint8Array): void;
}

interface CachedWebTUIImage {
  image?: CanvasImageSource;
  promise?: Promise<CanvasImageSource>;
}

export class WebTUISceneRuntime {
  readonly descriptor: WebTUISceneDescriptor;
  readonly element: HTMLElement;
  readonly terminalMount: HTMLElement;

  private readonly bridge?: BrowserWASIBridge;
  private readonly onInput: (chunk: Uint8Array) => void;
  private readonly imageCache = new Map<string, CachedWebTUIImage>();
  private currentStyle: ResolvedWebTUITerminalStyle;
  private canvas?: HTMLCanvasElement;
  private diagnosticText?: HTMLElement;
  private resizeObserver?: ResizeObserver;
  private detachInputHandlers?: () => void;
  private currentFrame?: WebTUISurfaceFrame;
  private columns = 80;
  private rows = 24;
  private cellWidth = 8;
  private cellHeight = 18;
  private activePointerButton: "primary" | "middle" | "secondary" = "primary";
  private lastSentResize?: {
    columns: number;
    rows: number;
    cellWidth: number;
    cellHeight: number;
  };
  private isVisible = false;

  constructor(options: WebTUISceneRuntimeOptions) {
    this.descriptor = options.descriptor;
    this.currentStyle = normalizeWebTUITerminalStyle(options.style);
    this.bridge = options.bridge;
    this.onInput = options.onInput;
    this.element = document.createElement("section");
    this.element.className = "webtuigui-scene";
    this.element.dataset.sceneId = options.descriptor.id;
    this.element.hidden = true;

    const header = document.createElement("div");
    header.className = "webtuigui-scene__header";
    header.textContent = options.descriptor.title ?? options.descriptor.id;

    this.terminalMount = document.createElement("div");
    this.terminalMount.className = "webtuigui-scene__terminal";
    this.terminalMount.tabIndex = 0;

    this.element.append(header, this.terminalMount);
    options.mount.appendChild(this.element);
    this.applyVisibility();
  }

  async mount(): Promise<void> {
    if (this.canvas) {
      return;
    }

    const canvas = document.createElement("canvas");
    canvas.className = "webtuigui-scene__surface";
    this.canvas = canvas;
    this.terminalMount.replaceChildren(canvas);
    this.installInputHandlers();
    this.installResizeObserver();

    this.bridge?.bindOutput({
      presentSurface: (frame) => this.presentSurface(frame),
      writeOutput: (text) => this.writeOutput(text),
      writeError: (text) => this.writeOutput(text),
    });

    this.applyStyle(this.currentStyle);
    this.measureCells();
    this.resizeToMount();
    this.draw();
  }

  setVisible(
    visible: boolean
  ): void {
    this.isVisible = visible;
    this.applyVisibility();
    if (visible) {
      this.resizeToMount();
      this.terminalMount.focus?.();
    }
  }

  setStyle(
    style: WebTUITerminalStyle
  ): void {
    this.currentStyle = normalizeWebTUITerminalStyle(style);
    this.applyStyle(this.currentStyle);
    this.bridge?.updateRenderStyle(this.currentStyle);
    this.measureCells();
    this.resizeToMount();
    this.draw();
  }

  resize(
    columns: number,
    rows: number
  ): void {
    this.columns = Math.max(1, Math.round(columns));
    this.rows = Math.max(1, Math.round(rows));
    this.resizeCanvas();
    this.draw();
  }

  writeOutput(
    text: string
  ): void {
    if (!this.diagnosticText) {
      const diagnosticText = document.createElement("pre");
      diagnosticText.className = "webtuigui-scene__diagnostic";
      this.diagnosticText = diagnosticText;
      this.terminalMount.appendChild(diagnosticText);
    }
    this.diagnosticText.textContent = `${this.diagnosticText.textContent ?? ""}${text}`;
  }

  sendInput(
    chunk: Uint8Array
  ): void {
    this.onInput(chunk);
  }

  dispose(): void {
    this.detachInputHandlers?.();
    this.resizeObserver?.disconnect();
    this.element.remove();
  }

  private presentSurface(
    frame: WebTUISurfaceFrame
  ): void {
    this.currentFrame = frame;
    this.columns = Math.max(1, Math.round(frame.width));
    this.rows = Math.max(1, Math.round(frame.height));
    this.resizeCanvas();
    this.draw();
  }

  private applyStyle(
    style: WebTUITerminalStyle
  ): void {
    applyWebTUITerminalStyle(this.element, style);
    this.element.style.padding = "0.75rem";
    this.element.style.borderRadius = "16px";
    this.element.style.boxShadow = "0 20px 50px rgba(0, 0, 0, 0.28)";
    this.element.style.overflow = "hidden";
    this.element.style.gap = "0.5rem";
    this.element.style.gridTemplateRows = "auto 1fr";

    this.terminalMount.style.position = "relative";
    this.terminalMount.style.overflow = "hidden";
    this.terminalMount.style.outline = "none";
    this.terminalMount.style.background = webTUITerminalBackgroundColor(this.currentStyle);
    this.terminalMount.style.minHeight = `${this.cellHeight * 8}px`;

    if (this.canvas) {
      this.canvas.style.display = "block";
      this.canvas.style.width = "100%";
      this.canvas.style.height = "100%";
    }
  }

  private applyVisibility(): void {
    this.element.hidden = !this.isVisible;
    this.element.style.setProperty(
      "display",
      this.isVisible ? "grid" : "none",
      "important"
    );
  }

  private installResizeObserver(): void {
    if (typeof ResizeObserver === "undefined") {
      return;
    }

    this.resizeObserver = new ResizeObserver(() => {
      this.resizeToMount();
    });
    this.resizeObserver.observe(this.terminalMount);
  }

  private installInputHandlers(): void {
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.metaKey || event.isComposing) {
        return;
      }
      const key = keyInputFromKeyboardEvent(event);
      if (!key) {
        return;
      }

      this.onInput(encodeKeyInputMessage({
        ...key,
        modifiers: modifierMask(event),
      }));
      event.preventDefault();
    };

    const handlePaste = (event: ClipboardEvent) => {
      const text = event.clipboardData?.getData("text/plain") ?? "";
      if (!text) {
        return;
      }
      this.onInput(encodePasteInputMessage(text));
      event.preventDefault();
    };

    const handlePointerDown = (event: PointerEvent) => {
      const location = this.cellLocation(event);
      if (!location) {
        return;
      }

      const button = pointerButton(event.button);
      this.activePointerButton = button;
      this.terminalMount.focus?.();
      this.terminalMount.setPointerCapture?.(event.pointerId);
      this.onInput(encodeMouseInputMessage({
        kind: "down",
        x: location.x,
        y: location.y,
        button,
        modifiers: modifierMask(event),
      }));
      event.preventDefault();
    };

    const handlePointerUp = (event: PointerEvent) => {
      const location = this.cellLocation(event);
      this.terminalMount.releasePointerCapture?.(event.pointerId);
      if (!location) {
        return;
      }

      this.onInput(encodeMouseInputMessage({
        kind: "up",
        x: location.x,
        y: location.y,
        button: pointerButton(event.button) ?? this.activePointerButton,
        modifiers: modifierMask(event),
      }));
      event.preventDefault();
    };

    const handlePointerMove = (event: PointerEvent) => {
      const location = this.cellLocation(event);
      if (!location) {
        return;
      }

      this.onInput(encodeMouseInputMessage({
        kind: event.buttons ? "dragged" : "moved",
        x: location.x,
        y: location.y,
        button: this.activePointerButton,
        modifiers: modifierMask(event),
      }));
    };

    const handleWheel = (event: WheelEvent) => {
      const location = this.cellLocation(event);
      if (!location) {
        return;
      }

      this.onInput(encodeMouseInputMessage({
        kind: "scrolled",
        x: location.x,
        y: location.y,
        deltaX: normalizedWheelDelta(event.deltaX),
        deltaY: normalizedWheelDelta(event.deltaY),
        modifiers: modifierMask(event),
      }));
      event.preventDefault();
    };

    this.terminalMount.addEventListener("keydown", handleKeyDown);
    this.terminalMount.addEventListener("paste", handlePaste);
    this.terminalMount.addEventListener("pointerdown", handlePointerDown);
    this.terminalMount.addEventListener("pointerup", handlePointerUp);
    this.terminalMount.addEventListener("pointermove", handlePointerMove);
    this.terminalMount.addEventListener("wheel", handleWheel, { passive: false });

    this.detachInputHandlers = () => {
      this.terminalMount.removeEventListener("keydown", handleKeyDown);
      this.terminalMount.removeEventListener("paste", handlePaste);
      this.terminalMount.removeEventListener("pointerdown", handlePointerDown);
      this.terminalMount.removeEventListener("pointerup", handlePointerUp);
      this.terminalMount.removeEventListener("pointermove", handlePointerMove);
      this.terminalMount.removeEventListener("wheel", handleWheel);
    };
  }

  private resizeToMount(): void {
    this.measureCells();
    const rect = this.terminalMount.getBoundingClientRect?.();
    const width = rect?.width && rect.width > 0 ? rect.width : this.columns * this.cellWidth;
    const height = rect?.height && rect.height > 0 ? rect.height : this.rows * this.cellHeight;
    const nextColumns = Math.max(1, Math.floor(width / this.cellWidth));
    const nextRows = Math.max(1, Math.floor(height / this.cellHeight));

    this.columns = nextColumns;
    this.rows = nextRows;
    this.sendResizeIfNeeded();
    this.resizeCanvas();
  }

  private sendResizeIfNeeded(): void {
    const current = {
      columns: this.columns,
      rows: this.rows,
      cellWidth: this.cellWidth,
      cellHeight: this.cellHeight,
    };
    if (this.lastSentResize
      && this.lastSentResize.columns === current.columns
      && this.lastSentResize.rows === current.rows
      && this.lastSentResize.cellWidth === current.cellWidth
      && this.lastSentResize.cellHeight === current.cellHeight
    ) {
      return;
    }

    this.lastSentResize = current;
    this.bridge?.resize(current.columns, current.rows, current.cellWidth, current.cellHeight);
  }

  private resizeCanvas(): void {
    if (!this.canvas) {
      return;
    }

    const cssWidth = Math.max(1, this.columns * this.cellWidth);
    const cssHeight = Math.max(1, this.rows * this.cellHeight);
    const scale = globalThis.window?.devicePixelRatio || 1;
    this.canvas.width = Math.ceil(cssWidth * scale);
    this.canvas.height = Math.ceil(cssHeight * scale);
    this.canvas.style.width = `${cssWidth}px`;
    this.canvas.style.height = `${cssHeight}px`;
  }

  private measureCells(): void {
    const canvas = this.canvas ?? document.createElement("canvas");
    const context = canvas.getContext?.("2d");
    if (!context) {
      this.cellWidth = Math.max(1, Math.round(this.currentStyle.fontSize * 0.62));
      this.cellHeight = Math.max(1, Math.round(this.currentStyle.fontSize * 1.35));
      return;
    }

    context.font = this.fontForStyle();
    this.cellWidth = Math.max(1, Math.ceil(context.measureText("W").width));
    this.cellHeight = Math.max(1, Math.ceil(this.currentStyle.fontSize * 1.35));
  }

  private draw(): void {
    const canvas = this.canvas;
    const context = canvas?.getContext("2d");
    if (!canvas || !context) {
      return;
    }

    const scale = globalThis.window?.devicePixelRatio || 1;
    context.setTransform(scale, 0, 0, scale, 0, 0);
    context.textBaseline = "alphabetic";
    context.clearRect(0, 0, canvas.width / scale, canvas.height / scale);
    context.fillStyle = webTUITerminalBackgroundColor(this.currentStyle);
    context.fillRect(0, 0, this.columns * this.cellWidth, this.rows * this.cellHeight);

    const frame = this.currentFrame;
    if (!frame) {
      return;
    }

    for (let y = 0; y < frame.rows.length; y += 1) {
      const row = frame.rows[y] ?? [];
      for (const cell of row) {
        const [x, text, span, styleIndex] = cell;
        const style = frame.styles[styleIndex] ?? undefined;
        this.drawCell(context, x, y, text, span, style);
      }
    }

    this.drawImages(context, frame.images ?? []);
  }

  private drawImages(
    context: CanvasRenderingContext2D,
    images: WebTUISurfaceImage[]
  ): void {
    for (const image of images) {
      this.drawImage(context, image);
    }
  }

  private drawImage(
    context: CanvasRenderingContext2D,
    image: WebTUISurfaceImage
  ): void {
    const decodedImage = this.cachedImage(image);
    if (!decodedImage) {
      return;
    }

    const [boundsX, boundsY, boundsWidth, boundsHeight] = image.bounds;
    const [clipX, clipY, clipWidth, clipHeight] = image.visibleBounds;
    if (boundsWidth <= 0 || boundsHeight <= 0 || clipWidth <= 0 || clipHeight <= 0) {
      return;
    }

    context.save();
    context.beginPath();
    context.rect(
      clipX * this.cellWidth,
      clipY * this.cellHeight,
      clipWidth * this.cellWidth,
      clipHeight * this.cellHeight
    );
    context.clip();
    context.drawImage(
      decodedImage,
      boundsX * this.cellWidth,
      boundsY * this.cellHeight,
      boundsWidth * this.cellWidth,
      boundsHeight * this.cellHeight
    );
    context.restore();
  }

  private cachedImage(
    image: WebTUISurfaceImage
  ): CanvasImageSource | undefined {
    const cached = this.imageCache.get(image.id);
    if (cached?.image) {
      return cached.image;
    }

    if (!cached?.promise && image.dataBase64) {
      const promise = decodeImage(image.dataBase64, image.format);
      this.imageCache.set(image.id, { promise });
      void promise.then((decodedImage) => {
        const latest = this.imageCache.get(image.id);
        if (latest?.promise !== promise) {
          return;
        }
        this.imageCache.set(image.id, { image: decodedImage });
        this.draw();
      }).catch(() => {
        this.imageCache.delete(image.id);
      });
    }

    return undefined;
  }

  private drawCell(
    context: CanvasRenderingContext2D,
    x: number,
    y: number,
    text: string,
    span: number,
    style?: WebTUISurfaceStyle | null
  ): void {
    const rectX = x * this.cellWidth;
    const rectY = y * this.cellHeight;
    const width = Math.max(1, span) * this.cellWidth;
    const background = resolvedBackground(style, this.currentStyle);
    const foreground = resolvedForeground(style, this.currentStyle);
    const opacity = style?.opacity ?? 1;

    if (background) {
      context.globalAlpha = opacity;
      context.fillStyle = background;
      context.fillRect(rectX, rectY, width, this.cellHeight);
    }

    if (text !== " ") {
      context.globalAlpha = opacity;
      context.fillStyle = foreground;
      context.strokeStyle = foreground;
      if (!canRenderBoxDrawing(text) || !drawBoxDrawing(context, text, {
        x: rectX,
        y: rectY,
        width,
        height: this.cellHeight,
      })) {
        context.font = this.fontForStyle(style);
        context.fillText(
          text,
          rectX,
          rectY + Math.floor((this.cellHeight + this.currentStyle.fontSize) / 2) - 2
        );
      }
    }

    this.drawTextLine(context, rectX, rectY, width, style?.underline, "underline", foreground);
    this.drawTextLine(context, rectX, rectY, width, style?.strikethrough, "strike", foreground);
    context.globalAlpha = 1;
  }

  private drawTextLine(
    context: CanvasRenderingContext2D,
    x: number,
    y: number,
    width: number,
    line: WebTUISurfaceStyle["underline"],
    placement: "underline" | "strike",
    fallbackColor: string
  ): void {
    if (!line) {
      return;
    }
    context.strokeStyle = line.color ?? fallbackColor;
    context.lineWidth = line.pattern === "double" ? 2 : 1;
    if (line.pattern === "dot") {
      context.setLineDash([1, 3]);
    } else if (line.pattern === "dash") {
      context.setLineDash([4, 3]);
    } else {
      context.setLineDash([]);
    }

    const lineY = placement === "underline"
      ? y + this.cellHeight - 2
      : y + Math.floor(this.cellHeight / 2);
    context.beginPath();
    context.moveTo(x, lineY);
    context.lineTo(x + width, lineY);
    context.stroke();
    context.setLineDash([]);
  }

  private fontForStyle(
    style?: WebTUISurfaceStyle | null
  ): string {
    const emphasis = style?.em ?? 0;
    const italic = (emphasis & 2) !== 0 ? "italic " : "";
    const weight = (emphasis & 1) !== 0 ? "700 " : "";
    return `${italic}${weight}${this.currentStyle.fontSize}px ${this.currentStyle.fontFamily}`;
  }

  private cellLocation(
    event: MouseEvent
  ): { x: number; y: number } | undefined {
    const rect = this.canvas?.getBoundingClientRect?.() ?? this.terminalMount.getBoundingClientRect?.();
    if (!rect) {
      return undefined;
    }

    const x = Math.floor((event.clientX - rect.left) / this.cellWidth);
    const y = Math.floor((event.clientY - rect.top) / this.cellHeight);
    if (x < 0 || y < 0 || x >= this.columns || y >= this.rows) {
      return undefined;
    }
    return { x, y };
  }
}

async function decodeImage(
  dataBase64: string,
  format: WebTUISurfaceImageFormat
): Promise<CanvasImageSource> {
  const bytes = decodeBase64Bytes(dataBase64);
  const blob = new Blob([bytes], { type: `image/${format}` });

  if (typeof createImageBitmap === "function") {
    // Animated GIFs collapse to their first frame in createImageBitmap
    // — that matches the Kitty path's first-frame composite. Phase 7
    // will replace this with a frame ticker.
    return createImageBitmap(blob);
  }

  return new Promise((resolve, reject) => {
    const image = new Image();
    const url = URL.createObjectURL(blob);
    image.onload = () => {
      URL.revokeObjectURL(url);
      resolve(image);
    };
    image.onerror = () => {
      URL.revokeObjectURL(url);
      reject(new Error(`Failed to decode ${format} image`));
    };
    image.src = url;
  });
}

function decodeBase64Bytes(
  value: string
): Uint8Array {
  if (typeof atob === "function") {
    const binary = atob(value);
    const bytes = new Uint8Array(binary.length);
    for (let index = 0; index < binary.length; index += 1) {
      bytes[index] = binary.charCodeAt(index);
    }
    return bytes;
  }

  return new Uint8Array(Buffer.from(value, "base64"));
}

function keyInputFromKeyboardEvent(
  event: KeyboardEvent
): Pick<WebTUIKeyInput, "key" | "character"> | undefined {
  switch (event.key) {
  case "Enter":
    return { key: "return" };
  case " ":
    return { key: "space" };
  case "Tab":
    return { key: "tab" };
  case "ArrowLeft":
    return { key: "arrowLeft" };
  case "ArrowRight":
    return { key: "arrowRight" };
  case "ArrowUp":
    return { key: "arrowUp" };
  case "ArrowDown":
    return { key: "arrowDown" };
  case "Backspace":
    return { key: "backspace" };
  case "Escape":
    return { key: "escape" };
  case "Home":
    return { key: "home" };
  case "End":
    return { key: "end" };
  default:
    {
      const characters = Array.from(event.key);
      if (characters.length !== 1) {
        return undefined;
      }
      return {
        key: "character",
        character: characters[0],
      };
    }
  }
}

function pointerButton(
  button: number
): "primary" | "middle" | "secondary" {
  switch (button) {
  case 1:
    return "middle";
  case 2:
    return "secondary";
  default:
    return "primary";
  }
}

function modifierMask(
  event: MouseEvent | KeyboardEvent
): number {
  let mask = 0;
  if (event.shiftKey) {
    mask |= 1;
  }
  if (event.altKey) {
    mask |= 2;
  }
  if (event.ctrlKey) {
    mask |= 4;
  }
  return mask;
}

function normalizedWheelDelta(
  delta: number
): number {
  if (delta > 0) {
    return 1;
  }
  if (delta < 0) {
    return -1;
  }
  return 0;
}

function resolvedForeground(
  style: WebTUISurfaceStyle | null | undefined,
  terminalStyle: ResolvedWebTUITerminalStyle
): string {
  if ((style?.em ?? 0) & 16) {
    return style?.bg ?? terminalStyle.theme.background;
  }
  return style?.fg ?? terminalStyle.theme.foreground;
}

function resolvedBackground(
  style: WebTUISurfaceStyle | null | undefined,
  terminalStyle: ResolvedWebTUITerminalStyle
): string | undefined {
  if ((style?.em ?? 0) & 16) {
    return style?.fg ?? terminalStyle.theme.foreground;
  }
  return style?.bg;
}
