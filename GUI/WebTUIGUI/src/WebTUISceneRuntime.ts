import {
  FitAddon,
  Terminal,
  init,
  type ITerminalOptions,
} from "./vendor/ghostty-web.ts";
import {
  applyWebTUITerminalStyle,
  ghosttyThemeForStyle,
  normalizeWebTUITerminalStyle,
  type WebTUIColorScheme,
  type ResolvedWebTUITerminalStyle,
  type WebTUITerminalStyle,
} from "./WebTUITerminalStyle.ts";
import { BrowserWASIBridge, encodeResizeControlMessage } from "./wasi/BrowserWASIBridge.ts";
import type { WebTUISceneDescriptor } from "./WebTUISceneManifest.ts";

export interface WebTUISceneRuntimeOptions {
  mount: HTMLElement;
  descriptor: WebTUISceneDescriptor;
  style: WebTUITerminalStyle;
  colorScheme: WebTUIColorScheme;
  bridge?: BrowserWASIBridge;
  onInput(chunk: Uint8Array): void;
}

export class WebTUISceneRuntime {
  readonly descriptor: WebTUISceneDescriptor;
  readonly element: HTMLElement;
  readonly terminalMount: HTMLElement;

  private terminal?: Terminal;
  private fitAddon?: FitAddon;
  private readonly bridge?: BrowserWASIBridge;
  private readonly onInput: (chunk: Uint8Array) => void;
  private currentStyle: ResolvedWebTUITerminalStyle;
  private currentColorScheme: WebTUIColorScheme;
  private readonly inputEncoder = new TextEncoder();
  private detachPointerTrackingFallback?: () => void;
  private mouseButtonsPressed = 0;
  private activePointerId?: number;
  private activePointerButton?: number;
  private activePointerLocation?: { col: number; row: number };

  constructor(options: WebTUISceneRuntimeOptions) {
    this.descriptor = options.descriptor;
    this.currentStyle = normalizeWebTUITerminalStyle(options.style);
    this.currentColorScheme = options.colorScheme;
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

    this.element.append(header, this.terminalMount);
    options.mount.appendChild(this.element);
  }

  async mount(): Promise<void> {
    if (this.terminal) {
      return;
    }

    await init();
    const options = this.terminalOptionsForStyle(
      this.currentStyle,
      this.currentColorScheme
    );
    this.terminal = new Terminal(options);
    this.fitAddon = new FitAddon();
    this.terminal.loadAddon(this.fitAddon);

    this.terminal.onData((data) => {
      this.onInput(this.inputEncoder.encode(data));
    });

    this.terminal.onResize((size) => {
      if (this.bridge) {
        this.bridge.resize(size.cols, size.rows);
      } else {
        this.onInput(encodeResizeControlMessage(size.cols, size.rows));
      }
    });

    this.bridge?.bindOutput({
      writeOutput: (text) => this.terminal?.write(text),
      writeError: (text) => this.terminal?.write(text),
      resize: (columns, rows) => {
        this.terminal?.resize(columns, rows);
      },
    });

    this.terminal.open(this.terminalMount);
    this.applyStyle(this.currentStyle, this.currentColorScheme);
    this.fitAddon.fit();
    this.fitAddon.observeResize();
    this.installPointerTrackingFallback();
  }

  setVisible(
    visible: boolean
  ): void {
    this.element.hidden = !visible;
    if (visible) {
      this.fitAddon?.fit();
      this.terminal?.focus();
    }
  }

  setStyle(
    style: WebTUITerminalStyle
  ): void {
    this.setStyleAndScheme(style, this.currentColorScheme);
  }

  setStyleAndScheme(
    style: WebTUITerminalStyle,
    colorScheme: WebTUIColorScheme
  ): void {
    this.currentStyle = normalizeWebTUITerminalStyle(style);
    this.currentColorScheme = colorScheme;
    const terminalOptions = this.terminal?.options;
    if (terminalOptions) {
      terminalOptions.fontSize = this.currentStyle.fontSize;
      terminalOptions.fontFamily = this.currentStyle.fontFamily;
      terminalOptions.cursorBlink = this.currentStyle.cursorBlink;
      terminalOptions.cursorStyle = this.currentStyle.cursorStyle;
      terminalOptions.theme = ghosttyThemeForStyle(
        this.currentStyle,
        this.currentColorScheme
      );
    }
    this.applyStyle(this.currentStyle, this.currentColorScheme);
    this.bridge?.updateRenderStyle(this.currentStyle, this.currentColorScheme);
    this.fitAddon?.fit();
  }

  resize(
    columns: number,
    rows: number
  ): void {
    this.terminal?.resize(columns, rows);
  }

  writeOutput(
    text: string
  ): void {
    this.terminal?.write(text);
  }

  sendInput(
    chunk: Uint8Array
  ): void {
    this.onInput(chunk);
  }

  dispose(): void {
    this.detachPointerTrackingFallback?.();
    this.fitAddon?.dispose();
    this.terminal?.dispose();
    this.element.remove();
  }

  private terminalOptionsForStyle(
    style: WebTUITerminalStyle,
    colorScheme: WebTUIColorScheme
  ): ITerminalOptions {
    const normalized = normalizeWebTUITerminalStyle(style);
    return {
      cursorBlink: normalized.cursorBlink,
      cursorStyle: normalized.cursorStyle,
      fontFamily: normalized.fontFamily,
      fontSize: normalized.fontSize,
      theme: ghosttyThemeForStyle(normalized, colorScheme),
      allowTransparency: normalized.backgroundOpacity < 1,
    };
  }

  private applyStyle(
    style: WebTUITerminalStyle,
    colorScheme: WebTUIColorScheme
  ): void {
    applyWebTUITerminalStyle(this.element, style, colorScheme);
    this.element.style.padding = "0.75rem";
    this.element.style.borderRadius = "16px";
    this.element.style.boxShadow = "0 20px 50px rgba(0, 0, 0, 0.28)";
    this.element.style.overflow = "hidden";
    this.element.style.display = "grid";
    this.element.style.gap = "0.5rem";
    this.element.style.gridTemplateRows = "auto 1fr";
  }

  private installPointerTrackingFallback(): void {
    this.detachPointerTrackingFallback?.();

    const captureOptions = { capture: true } as const;
    const wheelOptions = { capture: true, passive: false } as const;

    const handlePointerDown = (event: PointerEvent) => {
      const button = this.pointerButton(event);
      const tracking = this.mouseTrackingState();
      const cell = tracking && this.mouseCellLocation(event, tracking);
      if (!tracking || !cell || button === undefined) {
        return;
      }

      this.mouseButtonsPressed |= 1 << button;
      this.activePointerId = event.pointerId;
      this.activePointerButton = button;
      this.activePointerLocation = cell;
      this.setPointerCapture(event);
      this.terminal?.focus();
      this.forwardMouseEvent(button, cell, false, event, tracking.useSGR);
      event.preventDefault();
      event.stopImmediatePropagation();
    };

    const handlePointerUp = (event: PointerEvent) => {
      const tracking = this.mouseTrackingState();
      const button =
        this.activePointerId === event.pointerId
          ? this.activePointerButton
          : this.pointerButton(event);
      const cell = tracking && (this.mouseCellLocation(event, tracking) ?? this.activePointerLocation);
      if (button !== undefined) {
        this.mouseButtonsPressed &= ~(1 << button);
      }
      this.releasePointerCapture(event);
      this.clearActivePointer(event.pointerId);
      if (!tracking || !cell || button === undefined) {
        return;
      }

      this.forwardMouseEvent(button, cell, true, event, tracking.useSGR);
      event.preventDefault();
      event.stopImmediatePropagation();
    };

    const handlePointerMove = (event: PointerEvent) => {
      const tracking = this.mouseTrackingState();
      if (!tracking) {
        return;
      }

      this.mouseButtonsPressed = this.pointerButtons(event);

      if (!tracking.buttonMotion && !tracking.anyMotion) {
        return;
      }

      if (tracking.buttonMotion && !tracking.anyMotion && this.mouseButtonsPressed === 0) {
        return;
      }

      const cell = this.mouseCellLocation(event, tracking);
      if (!cell) {
        return;
      }
      if (this.activePointerId === event.pointerId) {
        this.activePointerLocation = cell;
      }

      let button = 32;
      if (this.mouseButtonsPressed & 1) {
        button += 0;
      } else if (this.mouseButtonsPressed & 2) {
        button += 1;
      } else if (this.mouseButtonsPressed & 4) {
        button += 2;
      }

      this.forwardMouseEvent(button, cell, false, event, tracking.useSGR);
      event.preventDefault();
      event.stopImmediatePropagation();
    };

    const handlePointerCancel = (event: PointerEvent) => {
      const tracking = this.mouseTrackingState();
      const button = this.activePointerId === event.pointerId ? this.activePointerButton : undefined;
      const cell = tracking && (this.mouseCellLocation(event, tracking) ?? this.activePointerLocation);
      if (button !== undefined && tracking && cell) {
        this.forwardMouseEvent(button, cell, true, event, tracking.useSGR);
      }
      this.mouseButtonsPressed = 0;
      this.releasePointerCapture(event);
      this.clearActivePointer(event.pointerId);
      event.preventDefault();
      event.stopImmediatePropagation();
    };

    const handleWheel = (event: WheelEvent) => {
      const tracking = this.mouseTrackingState();
      const cell = tracking && this.mouseCellLocation(event, tracking);
      if (!tracking || !cell) {
        return;
      }

      const button = event.deltaY < 0 ? 64 : 65;
      this.forwardMouseEvent(button, cell, false, event, tracking.useSGR);
      event.preventDefault();
      event.stopImmediatePropagation();
    };

    this.terminalMount.addEventListener("pointerdown", handlePointerDown, captureOptions);
    this.terminalMount.addEventListener("pointerup", handlePointerUp, captureOptions);
    this.terminalMount.addEventListener("pointermove", handlePointerMove, captureOptions);
    this.terminalMount.addEventListener("pointercancel", handlePointerCancel, captureOptions);
    this.terminalMount.addEventListener("wheel", handleWheel, wheelOptions);

    this.detachPointerTrackingFallback = () => {
      this.terminalMount.removeEventListener("pointerdown", handlePointerDown, captureOptions);
      this.terminalMount.removeEventListener("pointerup", handlePointerUp, captureOptions);
      this.terminalMount.removeEventListener("pointermove", handlePointerMove, captureOptions);
      this.terminalMount.removeEventListener("pointercancel", handlePointerCancel, captureOptions);
      this.terminalMount.removeEventListener("wheel", handleWheel, wheelOptions);
    };
  }

  private pointerButton(
    event: PointerEvent
  ): number | undefined {
    switch (event.button) {
    case 0:
      return 0
    case 1:
      return 1
    case 2:
      return 2
    default:
      return undefined
    }
  }

  private pointerButtons(
    event: PointerEvent
  ): number {
    let buttons = 0;
    if ((event.buttons & 1) !== 0) {
      buttons |= 1;
    }
    if ((event.buttons & 4) !== 0) {
      buttons |= 2;
    }
    if ((event.buttons & 2) !== 0) {
      buttons |= 4;
    }
    return buttons;
  }

  private setPointerCapture(
    event: PointerEvent
  ): void {
    const target = event.target;
    if (!(target instanceof HTMLElement)) {
      return;
    }
    try {
      target.setPointerCapture(event.pointerId);
    } catch {
      // Ignore pointer-capture failures and continue with best-effort forwarding.
    }
  }

  private releasePointerCapture(
    event: PointerEvent
  ): void {
    const target = event.target;
    if (!(target instanceof HTMLElement)) {
      return;
    }
    if (!target.hasPointerCapture(event.pointerId)) {
      return;
    }
    try {
      target.releasePointerCapture(event.pointerId);
    } catch {
      // Ignore pointer-capture failures and continue cleaning up local state.
    }
  }

  private clearActivePointer(
    pointerId: number
  ): void {
    if (this.activePointerId !== pointerId) {
      return;
    }
    this.activePointerId = undefined;
    this.activePointerButton = undefined;
    this.activePointerLocation = undefined;
  }

  private mouseTrackingState():
    | {
        useSGR: boolean;
        buttonMotion: boolean;
        anyMotion: boolean;
        canvasRect: DOMRect;
        charWidth: number;
        charHeight: number;
      }
    | undefined {
    const terminal = this.terminal as
      | {
          getMode?(mode: number, ansiMode?: boolean): boolean;
          renderer?: {
            charWidth?: number;
            charHeight?: number;
          };
        }
      | undefined;
    const canvas = this.terminalMount.querySelector("canvas");

    if (!(canvas instanceof HTMLCanvasElement)) {
      return undefined;
    }

    const normalTracking = terminal?.getMode?.(1000, false) ?? false;
    const buttonMotion = terminal?.getMode?.(1002, false) ?? false;
    const anyMotion = terminal?.getMode?.(1003, false) ?? false;
    const useSGR = terminal?.getMode?.(1006, false) ?? true;
    const charWidth = terminal?.renderer?.charWidth ?? 0;
    const charHeight = terminal?.renderer?.charHeight ?? 0;

    if (!(normalTracking || buttonMotion || anyMotion)) {
      return undefined;
    }

    if (!(charWidth > 0) || !(charHeight > 0)) {
      return undefined;
    }

    return {
      useSGR,
      buttonMotion,
      anyMotion,
      canvasRect: canvas.getBoundingClientRect(),
      charWidth,
      charHeight,
    };
  }

  private mouseCellLocation(
    event: MouseEvent,
    tracking: {
      canvasRect: DOMRect;
      charWidth: number;
      charHeight: number;
    }
  ): {
    col: number;
    row: number;
  } | undefined {
    const x = event.clientX - tracking.canvasRect.left;
    const y = event.clientY - tracking.canvasRect.top;

    if (!Number.isFinite(x) || !Number.isFinite(y)) {
      return undefined;
    }

    return {
      col: Math.max(1, Math.floor(x / tracking.charWidth) + 1),
      row: Math.max(1, Math.floor(y / tracking.charHeight) + 1),
    };
  }

  private forwardMouseEvent(
    button: number,
    location: {
      col: number;
      row: number;
    },
    isRelease: boolean,
    event: MouseEvent,
    useSGR: boolean
  ): void {
    const modifiers = this.mouseModifierBits(event);
    const sequence = useSGR
      ? `\u001B[<${button + modifiers};${location.col};${location.row}${isRelease ? "m" : "M"}`
      : this.encodeX10MouseSequence(button, location, isRelease, modifiers);

    this.onInput(this.inputEncoder.encode(sequence));
  }

  private encodeX10MouseSequence(
    button: number,
    location: {
      col: number;
      row: number;
    },
    isRelease: boolean,
    modifiers: number
  ): string {
    const encodedButton = (isRelease ? 3 : button) + modifiers + 32;
    const column = String.fromCharCode(Math.min(location.col + 32, 255));
    const row = String.fromCharCode(Math.min(location.row + 32, 255));
    return `\u001B[M${String.fromCharCode(encodedButton)}${column}${row}`;
  }

  private mouseModifierBits(
    event: MouseEvent
  ): number {
    let modifiers = 0;
    if (event.shiftKey) {
      modifiers |= 4;
    }
    if (event.metaKey) {
      modifiers |= 8;
    }
    if (event.ctrlKey) {
      modifiers |= 16;
    }
    return modifiers;
  }
}
