// src/wasi/StdIOPipe.ts
class StdIOPipe {
  chunks = [];
  waiters = [];
  listeners = new Set;
  closed = false;
  write(chunk) {
    if (this.closed) {
      return;
    }
    const bytes = typeof chunk === "string" ? new TextEncoder().encode(chunk) : new Uint8Array(chunk);
    const waiter = this.waiters.shift();
    if (waiter) {
      waiter({ done: false, value: bytes });
      return;
    }
    this.chunks.push(bytes);
    for (const listener of this.listeners) {
      listener(bytes);
    }
  }
  close() {
    if (this.closed) {
      return;
    }
    this.closed = true;
    while (this.waiters.length > 0) {
      const waiter = this.waiters.shift();
      waiter?.({ done: true, value: undefined });
    }
  }
  async read() {
    const next = this.chunks.shift();
    if (next) {
      return next;
    }
    if (this.closed) {
      return;
    }
    return await new Promise((resolve) => {
      this.waiters.push((result) => {
        resolve(result.done ? undefined : result.value);
      });
    });
  }
  subscribe(listener) {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }
  async* [Symbol.asyncIterator]() {
    while (true) {
      const next = await this.read();
      if (!next) {
        return;
      }
      yield next;
    }
  }
}

// src/WebHostTerminalStyle.ts
var defaultFontFamily = '"SFMono-Regular", "SF Mono", "Menlo", "Monaco", "Consolas", "Liberation Mono", monospace';
var defaultANSI = {
  black: "#20242c",
  red: "#e05757",
  green: "#61c67b",
  yellow: "#ebb33c",
  blue: "#5ba3ff",
  magenta: "#b46eff",
  cyan: "#56b6c2",
  white: "#eceff4",
  brightBlack: "#8c92ac",
  brightRed: "#ff7b72",
  brightGreen: "#7ee787",
  brightYellow: "#f2cc60",
  brightBlue: "#79c0ff",
  brightMagenta: "#d2a8ff",
  brightCyan: "#7de2d1",
  brightWhite: "#ffffff"
};
var defaultPalette = {
  foreground: "#eceff4",
  background: "#1e222a",
  cursor: "#56b6c2",
  selectionBackground: "#2e3440",
  selectionForeground: "#eceff4",
  ansi: defaultANSI
};
var defaultTheme = {
  foreground: "#eceff4",
  background: "#1e222a",
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
  muted: "#8c92ac"
};
function normalizeWebHostTerminalStyle(style = {}) {
  const palette = normalizePalette(style.palette, defaultPalette);
  const theme = normalizeTheme(style.theme, palette, defaultTheme);
  return {
    fontSize: normalizeFontSize(style.fontSize ?? 14),
    fontFamily: style.fontFamily ?? defaultFontFamily,
    cursorStyle: style.cursorStyle ?? "block",
    cursorBlink: style.cursorBlink ?? false,
    backgroundOpacity: normalizeOpacity(style.backgroundOpacity ?? 1),
    palette,
    theme
  };
}
function mergeWebHostTerminalStyle(base, patch) {
  const resolvedBase = normalizeWebHostTerminalStyle(base);
  return normalizeWebHostTerminalStyle({
    ...resolvedBase,
    ...patch,
    palette: mergePalette(resolvedBase.palette, patch.palette),
    theme: patch.theme ? { ...resolvedBase.theme, ...patch.theme } : resolvedBase.theme
  });
}
function resolveWebHostTerminalRenderStyle(style) {
  const normalized = normalizeWebHostTerminalStyle(style);
  return {
    appearance: {
      foregroundColor: normalized.theme.foreground,
      backgroundColor: normalized.theme.background,
      tintColor: normalized.theme.tint,
      palette: paletteToIndexedMap(normalized.palette.ansi),
      colorSchemeContrast: contrastRatio(normalized.theme.foreground, normalized.theme.background) >= 7 ? "increased" : "standard",
      source: "override"
    },
    theme: { ...normalized.theme }
  };
}
function encodeWebHostTerminalRenderStyleBase64(style) {
  return encodeBase64(JSON.stringify(resolveWebHostTerminalRenderStyle(style)));
}
function webTUITerminalBackgroundColor(style) {
  const normalized = normalizeWebHostTerminalStyle(style);
  return hexToRgba(normalized.theme.background, normalized.backgroundOpacity);
}
function applyWebHostTerminalStyle(element, style) {
  const normalized = normalizeWebHostTerminalStyle(style);
  element.style.fontFamily = normalized.fontFamily;
  element.style.fontSize = `${normalized.fontSize}px`;
  element.style.background = hexToRgba(normalized.theme.background, normalized.backgroundOpacity);
  element.style.color = normalized.theme.foreground;
}
function normalizePalette(input, defaults) {
  return {
    foreground: normalizeHexColor(input?.foreground ?? defaults.foreground),
    background: normalizeHexColor(input?.background ?? defaults.background),
    cursor: normalizeHexColor(input?.cursor ?? defaults.cursor),
    selectionBackground: normalizeHexColor(input?.selectionBackground ?? defaults.selectionBackground),
    selectionForeground: normalizeHexColor(input?.selectionForeground ?? defaults.selectionForeground),
    ansi: normalizeANSI(input?.ansi, defaults.ansi)
  };
}
function mergePalette(base, patch) {
  if (!patch) {
    return base;
  }
  return {
    ...base,
    ...patch,
    ansi: patch.ansi ? { ...base.ansi, ...patch.ansi } : base.ansi
  };
}
function normalizeANSI(input, defaults) {
  return {
    black: normalizeHexColor(input?.black ?? defaults.black),
    red: normalizeHexColor(input?.red ?? defaults.red),
    green: normalizeHexColor(input?.green ?? defaults.green),
    yellow: normalizeHexColor(input?.yellow ?? defaults.yellow),
    blue: normalizeHexColor(input?.blue ?? defaults.blue),
    magenta: normalizeHexColor(input?.magenta ?? defaults.magenta),
    cyan: normalizeHexColor(input?.cyan ?? defaults.cyan),
    white: normalizeHexColor(input?.white ?? defaults.white),
    brightBlack: normalizeHexColor(input?.brightBlack ?? defaults.brightBlack),
    brightRed: normalizeHexColor(input?.brightRed ?? defaults.brightRed),
    brightGreen: normalizeHexColor(input?.brightGreen ?? defaults.brightGreen),
    brightYellow: normalizeHexColor(input?.brightYellow ?? defaults.brightYellow),
    brightBlue: normalizeHexColor(input?.brightBlue ?? defaults.brightBlue),
    brightMagenta: normalizeHexColor(input?.brightMagenta ?? defaults.brightMagenta),
    brightCyan: normalizeHexColor(input?.brightCyan ?? defaults.brightCyan),
    brightWhite: normalizeHexColor(input?.brightWhite ?? defaults.brightWhite)
  };
}
function normalizeTheme(input, palette, defaults) {
  const derived = themeFromPalette(palette, defaults);
  return {
    foreground: normalizeHexColor(input?.foreground ?? derived.foreground),
    background: normalizeHexColor(input?.background ?? derived.background),
    tint: normalizeHexColor(input?.tint ?? derived.tint),
    separator: normalizeHexColor(input?.separator ?? derived.separator),
    selection: normalizeHexColor(input?.selection ?? derived.selection),
    placeholder: normalizeHexColor(input?.placeholder ?? derived.placeholder),
    link: normalizeHexColor(input?.link ?? derived.link),
    fill: normalizeHexColor(input?.fill ?? derived.fill),
    windowBackground: normalizeHexColor(input?.windowBackground ?? derived.windowBackground),
    success: normalizeHexColor(input?.success ?? derived.success),
    warning: normalizeHexColor(input?.warning ?? derived.warning),
    danger: normalizeHexColor(input?.danger ?? derived.danger),
    info: normalizeHexColor(input?.info ?? derived.info),
    muted: normalizeHexColor(input?.muted ?? derived.muted)
  };
}
function themeFromPalette(palette, defaults) {
  return {
    foreground: palette.foreground,
    background: palette.background,
    tint: palette.cursor,
    separator: palette.ansi.brightBlack,
    selection: palette.selectionBackground,
    placeholder: palette.ansi.brightBlack,
    link: palette.ansi.blue,
    fill: defaults.fill,
    windowBackground: palette.background,
    success: palette.ansi.green,
    warning: palette.ansi.yellow,
    danger: palette.ansi.red,
    info: palette.ansi.cyan,
    muted: palette.ansi.brightBlack
  };
}
function paletteToIndexedMap(ansi) {
  return {
    0: ansi.black,
    1: ansi.red,
    2: ansi.green,
    3: ansi.yellow,
    4: ansi.blue,
    5: ansi.magenta,
    6: ansi.cyan,
    7: ansi.white,
    8: ansi.brightBlack,
    9: ansi.brightRed,
    10: ansi.brightGreen,
    11: ansi.brightYellow,
    12: ansi.brightBlue,
    13: ansi.brightMagenta,
    14: ansi.brightCyan,
    15: ansi.brightWhite
  };
}
function normalizeFontSize(fontSize) {
  return Number.isFinite(fontSize) && fontSize > 0 ? fontSize : 14;
}
function normalizeOpacity(opacity) {
  if (!Number.isFinite(opacity)) {
    return 1;
  }
  return Math.min(1, Math.max(0, opacity));
}
function normalizeHexColor(value) {
  const trimmed = value.trim();
  const normalized = trimmed.startsWith("#") ? trimmed : `#${trimmed}`;
  if (!/^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(normalized)) {
    throw new Error(`Invalid hex color: ${value}`);
  }
  return normalized.toLowerCase();
}
function hexToRgba(color, opacity) {
  const normalized = normalizeHexColor(color);
  const alpha = normalizeOpacity(opacity);
  const channels = parseHexColor(normalized);
  if (!channels) {
    return normalized;
  }
  const finalAlpha = Math.round(channels.alpha * alpha * 1000) / 1000;
  return `rgba(${channels.red}, ${channels.green}, ${channels.blue}, ${finalAlpha})`;
}
function parseHexColor(color) {
  const hex = color.startsWith("#") ? color.slice(1) : color;
  const normalized = hex.length === 3 || hex.length === 4 ? hex.split("").map((ch) => ch + ch).join("") : hex;
  if (normalized.length !== 6 && normalized.length !== 8) {
    return;
  }
  const red = Number.parseInt(normalized.slice(0, 2), 16);
  const green = Number.parseInt(normalized.slice(2, 4), 16);
  const blue = Number.parseInt(normalized.slice(4, 6), 16);
  const alpha = normalized.length === 8 ? Number.parseInt(normalized.slice(6, 8), 16) / 255 : 1;
  return { red, green, blue, alpha };
}
function contrastRatio(foreground, background) {
  const fg = relativeLuminance(foreground);
  const bg = relativeLuminance(background);
  const lighter = Math.max(fg, bg);
  const darker = Math.min(fg, bg);
  return (lighter + 0.05) / (darker + 0.05);
}
function relativeLuminance(color) {
  const channels = parseHexColor(normalizeHexColor(color));
  if (!channels) {
    return 0;
  }
  const toLinear = (channel) => {
    const value = channel / 255;
    return value <= 0.03928 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
  };
  return 0.2126 * toLinear(channels.red) + 0.7152 * toLinear(channels.green) + 0.0722 * toLinear(channels.blue);
}
function encodeBase64(value) {
  if (typeof btoa === "function") {
    const bytes = new TextEncoder().encode(value);
    let binary = "";
    for (const byte of bytes) {
      binary += String.fromCharCode(byte);
    }
    return btoa(binary);
  }
  return Buffer.from(value, "utf8").toString("base64");
}

// src/WebHostSurfaceTransport.ts
var recordPrefix = "\x1E";
var textEncoder = new TextEncoder;

class WebHostOutputDecoder {
  textDecoder = new TextDecoder;
  bufferedText = "";
  feed(chunk) {
    this.bufferedText += this.textDecoder.decode(chunk, { stream: true });
    const records = [];
    while (true) {
      const newlineIndex = this.bufferedText.indexOf(`
`);
      if (newlineIndex < 0) {
        break;
      }
      const line = this.bufferedText.slice(0, newlineIndex);
      this.bufferedText = this.bufferedText.slice(newlineIndex + 1);
      records.push(this.decodeLine(line));
    }
    if (this.bufferedText.length > 4096 && !this.bufferedText.startsWith(recordPrefix)) {
      records.push({ type: "text", text: this.bufferedText });
      this.bufferedText = "";
    }
    return records;
  }
  flush() {
    if (!this.bufferedText) {
      return [];
    }
    const text = this.bufferedText;
    this.bufferedText = "";
    return [this.decodeLine(text)];
  }
  decodeLine(line) {
    if (line.startsWith(`${recordPrefix}clipboard:`)) {
      try {
        const record = JSON.parse(line.slice(`${recordPrefix}clipboard:`.length));
        if (isWebHostClipboardRecord(record)) {
          return { type: "clipboard", text: record.text };
        }
      } catch {}
      return { type: "text", text: `${line}
` };
    }
    if (line.startsWith(`${recordPrefix}runtimeIssue:`)) {
      try {
        const record = JSON.parse(line.slice(`${recordPrefix}runtimeIssue:`.length));
        if (isWebHostRuntimeIssue(record)) {
          return { type: "runtimeIssue", issue: record };
        }
      } catch {}
      return { type: "text", text: `${line}
` };
    }
    if (!line.startsWith(`${recordPrefix}surface:`)) {
      return { type: "text", text: `${line}
` };
    }
    try {
      const frame = JSON.parse(line.slice(`${recordPrefix}surface:`.length));
      if (isWebHostSurfaceFrame(frame)) {
        return { type: "surface", frame };
      }
    } catch {}
    return { type: "text", text: `${line}
` };
  }
}
function isWebHostClipboardRecord(value) {
  return !!value && typeof value === "object" && typeof value.text === "string";
}
function isWebHostRuntimeIssue(value) {
  if (!value || typeof value !== "object") {
    return false;
  }
  const record = value;
  return (record.severity === "warning" || record.severity === "error") && typeof record.code === "string" && typeof record.message === "string" && typeof record.description === "string" && (record.identity === undefined || typeof record.identity === "string") && (record.source === undefined || typeof record.source === "string");
}
function encodeResizeControlMessage(columns, rows, cellWidth, cellHeight) {
  const normalizedColumns = Math.max(1, Math.round(columns));
  const normalizedRows = Math.max(1, Math.round(rows));
  if (cellWidth && cellHeight) {
    return textEncoder.encode(`${recordPrefix}resize:${normalizedColumns}:${normalizedRows}:${Math.max(1, Math.round(cellWidth))}:${Math.max(1, Math.round(cellHeight))}
`);
  }
  return textEncoder.encode(`${recordPrefix}resize:${normalizedColumns}:${normalizedRows}
`);
}
function encodeRenderStyleControlMessage(style) {
  const encoded = encodeWebHostTerminalRenderStyleBase64(style);
  return textEncoder.encode(`${recordPrefix}style:${encoded}
`);
}
function encodeKeyInputMessage(input) {
  const modifiers = Math.max(0, Math.round(input.modifiers ?? 0));
  if (input.key === "character") {
    return textEncoder.encode(`${recordPrefix}key:character:${encodeURIComponent(input.character ?? "")}:${modifiers}
`);
  }
  return textEncoder.encode(`${recordPrefix}key:${input.key}:${modifiers}
`);
}
function encodePasteInputMessage(text) {
  return textEncoder.encode(`${recordPrefix}paste:${encodeURIComponent(text)}
`);
}
function encodeMouseInputMessage(input) {
  return textEncoder.encode(recordPrefix + [
    "mouse",
    input.kind,
    formatCellCoordinate(input.x),
    formatCellCoordinate(input.y),
    input.button ?? "none",
    Math.round(input.deltaX ?? 0),
    Math.round(input.deltaY ?? 0),
    Math.max(0, Math.round(input.modifiers ?? 0))
  ].join(":") + `
`);
}
function formatCellCoordinate(value) {
  return Number.isFinite(value) ? String(value) : "0";
}
function isWebHostSurfaceFrame(value) {
  if (!value || typeof value !== "object") {
    return false;
  }
  const frame = value;
  return (frame.version === 1 || frame.version === 2) && (frame.sequence === undefined || Number.isSafeInteger(frame.sequence) && frame.sequence >= 0) && typeof frame.width === "number" && typeof frame.height === "number" && Array.isArray(frame.styles) && Array.isArray(frame.rows) && (frame.images === undefined || isWebHostSurfaceImages(frame.images)) && (frame.damage === undefined || isWebHostSurfaceDamage(frame.damage)) && (frame.accessibilityTree === undefined || isWebHostAccessibilityNodes(frame.accessibilityTree)) && (frame.accessibilityAnnouncements === undefined || isWebHostAccessibilityAnnouncements(frame.accessibilityAnnouncements));
}
function isWebHostAccessibilityNodes(value) {
  return Array.isArray(value) && value.every(isWebHostAccessibilityNode);
}
function isWebHostAccessibilityNode(value) {
  if (!value || typeof value !== "object") {
    return false;
  }
  const node = value;
  return typeof node.id === "string" && (node.parentId === undefined || typeof node.parentId === "string") && isWebHostSurfaceRect(node.rect) && typeof node.role === "string" && (node.label === undefined || typeof node.label === "string") && (node.hint === undefined || typeof node.hint === "string") && (node.liveRegion === undefined || node.liveRegion === "off" || node.liveRegion === "polite" || node.liveRegion === "assertive") && (node.cursorAnchor === undefined || isWebHostAccessibilityPoint(node.cursorAnchor)) && (node.isFocused === undefined || typeof node.isFocused === "boolean");
}
function isWebHostAccessibilityPoint(value) {
  return Array.isArray(value) && value.length === 2 && value.every((entry) => typeof entry === "number");
}
function isWebHostAccessibilityAnnouncements(value) {
  return Array.isArray(value) && value.every(isWebHostAccessibilityAnnouncement);
}
function isWebHostAccessibilityAnnouncement(value) {
  if (!value || typeof value !== "object") {
    return false;
  }
  const announcement = value;
  return typeof announcement.message === "string" && (announcement.politeness === "off" || announcement.politeness === "polite" || announcement.politeness === "assertive");
}
function isWebHostSurfaceImages(value) {
  return Array.isArray(value) && value.every(isWebHostSurfaceImage);
}
function isWebHostSurfaceImage(value) {
  if (!value || typeof value !== "object") {
    return false;
  }
  const image = value;
  return typeof image.id === "string" && isWebHostSurfaceImageFormat(image.format) && isWebHostSurfaceRect(image.bounds) && isWebHostSurfaceRect(image.visibleBounds) && isWebHostSurfaceScalingMode(image.scalingMode) && (image.pixelSize === undefined || isWebHostSurfaceSize(image.pixelSize)) && (image.dataBase64 === undefined || typeof image.dataBase64 === "string");
}
function isWebHostSurfaceDamage(value) {
  if (!value || typeof value !== "object") {
    return false;
  }
  const damage = value;
  return Array.isArray(damage.textRows) && damage.textRows.every(isWebHostSurfaceDamageTextRow) && typeof damage.requiresFullTextRepaint === "boolean" && typeof damage.requiresFullGraphicsReplay === "boolean";
}
function isWebHostSurfaceDamageTextRow(value) {
  return Array.isArray(value) && value.length === 2 && typeof value[0] === "number" && Array.isArray(value[1]) && value[1].every(isWebHostSurfaceDamageRange);
}
function isWebHostSurfaceDamageRange(value) {
  return Array.isArray(value) && value.length === 2 && typeof value[0] === "number" && typeof value[1] === "number";
}
function isWebHostSurfaceImageFormat(value) {
  return value === "png" || value === "jpeg" || value === "gif";
}
function isWebHostSurfaceRect(value) {
  return Array.isArray(value) && value.length === 4 && value.every((entry) => typeof entry === "number");
}
function isWebHostSurfaceSize(value) {
  return Array.isArray(value) && value.length === 2 && value.every((entry) => typeof entry === "number");
}
function isWebHostSurfaceScalingMode(value) {
  return value === "stretch" || value === "fit" || value === "fill";
}

// src/wasi/BrowserWASIBridge.ts
class BrowserWASIBridge {
  stdin = new StdIOPipe;
  stdout = new StdIOPipe;
  stderr = new StdIOPipe;
  environment;
  detachStdout;
  detachStderr;
  resizeListeners = new Set;
  latestResize;
  constructor(options) {
    this.environment = {
      TUIGUI_MODE: "browser",
      TUIGUI_TRANSPORT: "surface",
      TUIGUI_SCENE: options.sceneId,
      TUIGUI_COLUMNS: String(Math.max(1, options.columns)),
      TUIGUI_ROWS: String(Math.max(1, options.rows)),
      ...options.environment,
      ...options.renderStyle ? {
        TUIGUI_RENDER_STYLE: encodeWebHostTerminalRenderStyleBase64(options.renderStyle)
      } : {}
    };
    this.latestResize = {
      columns: Math.max(1, options.columns),
      rows: Math.max(1, options.rows)
    };
  }
  bindOutput(sink) {
    this.detachStdout?.();
    this.detachStderr?.();
    const decoder = new WebHostOutputDecoder;
    this.detachStdout = this.stdout.subscribe((chunk) => {
      for (const record of decoder.feed(chunk)) {
        switch (record.type) {
          case "surface":
            sink.presentSurface(record.frame);
            break;
          case "clipboard":
            sink.writeClipboard?.(record.text);
            break;
          case "text":
            sink.writeOutput?.(record.text);
            break;
        }
      }
    });
    this.detachStderr = this.stderr.subscribe((chunk) => {
      sink.writeError?.(new TextDecoder().decode(chunk));
    });
  }
  resize(columns, rows, cellWidth, cellHeight) {
    const normalizedColumns = Math.max(1, columns);
    const normalizedRows = Math.max(1, rows);
    this.environment.TUIGUI_COLUMNS = String(normalizedColumns);
    this.environment.TUIGUI_ROWS = String(normalizedRows);
    this.latestResize = {
      columns: normalizedColumns,
      rows: normalizedRows,
      cellWidth,
      cellHeight
    };
    this.stdin.write(encodeResizeControlMessage(columns, rows, cellWidth, cellHeight));
    for (const listener of this.resizeListeners) {
      listener(normalizedColumns, normalizedRows, cellWidth, cellHeight);
    }
  }
  updateRenderStyle(style) {
    this.environment.TUIGUI_RENDER_STYLE = encodeWebHostTerminalRenderStyleBase64(style);
    this.stdin.write(encodeRenderStyleControlMessage(style));
  }
  sendInput(chunk) {
    this.stdin.write(chunk);
  }
  subscribeResize(listener) {
    this.resizeListeners.add(listener);
    listener(this.latestResize.columns, this.latestResize.rows, this.latestResize.cellWidth, this.latestResize.cellHeight);
    return () => {
      this.resizeListeners.delete(listener);
    };
  }
  dispose() {
    this.detachStdout?.();
    this.detachStderr?.();
    this.resizeListeners.clear();
    this.stdin.close();
    this.stdout.close();
    this.stderr.close();
  }
}

// src/WebSocketSceneBridge.ts
var socketOpenState = 1;
var textEncoder2 = new TextEncoder;

class WebSocketSceneBridge {
  url;
  socket;
  decoder = new WebHostOutputDecoder;
  queuedInput = [];
  queuedOutput = [];
  sink;
  disposed = false;
  handleOpen = () => {
    this.flushQueuedInput();
  };
  handleMessage = (event) => {
    this.receive(event.data);
  };
  handleClose = () => {
    for (const record of this.decoder.flush()) {
      this.deliver(record);
    }
  };
  handleError = () => {};
  constructor(options) {
    this.url = webSocketSceneURL(options);
    this.socket = (options.webSocketFactory ?? defaultWebSocketFactory)(this.url);
    this.socket.binaryType = "arraybuffer";
    this.socket.addEventListener("open", this.handleOpen);
    this.socket.addEventListener("message", this.handleMessage);
    this.socket.addEventListener("close", this.handleClose);
    this.socket.addEventListener("error", this.handleError);
  }
  bindOutput(sink) {
    this.sink = sink;
    while (this.queuedOutput.length > 0) {
      this.deliver(this.queuedOutput.shift());
    }
  }
  resize(columns, rows, cellWidth, cellHeight) {
    this.sendInput(encodeResizeControlMessage(columns, rows, cellWidth, cellHeight));
  }
  updateRenderStyle(style) {
    this.sendInput(encodeRenderStyleControlMessage(style));
  }
  sendInput(chunk) {
    if (this.disposed) {
      return;
    }
    const copy = new Uint8Array(chunk);
    if (this.socket.readyState === socketOpenState) {
      this.socket.send(copy);
    } else {
      this.queuedInput.push(copy);
    }
  }
  dispose() {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    this.socket.removeEventListener("open", this.handleOpen);
    this.socket.removeEventListener("message", this.handleMessage);
    this.socket.removeEventListener("close", this.handleClose);
    this.socket.removeEventListener("error", this.handleError);
    this.queuedInput.length = 0;
    this.queuedOutput.length = 0;
    this.socket.close(1000, "WebHost scene disposed");
  }
  async receive(message) {
    if (this.disposed) {
      return;
    }
    const bytes = await bytesFromWebSocketMessage(message);
    if (!bytes) {
      return;
    }
    for (const record of this.decoder.feed(bytes)) {
      this.deliver(record);
    }
  }
  deliver(record) {
    const sink = this.sink;
    if (!sink) {
      this.queuedOutput.push(record);
      return;
    }
    switch (record.type) {
      case "surface":
        sink.presentSurface(record.frame);
        break;
      case "clipboard":
        sink.writeClipboard?.(record.text);
        break;
      case "runtimeIssue":
        sink.notifyRuntimeIssue?.(record.issue);
        break;
      case "text":
        sink.writeOutput?.(record.text);
        break;
    }
  }
  flushQueuedInput() {
    if (this.disposed || this.socket.readyState !== socketOpenState) {
      return;
    }
    while (this.queuedInput.length > 0) {
      this.socket.send(this.queuedInput.shift());
    }
  }
}
function webSocketSceneURL(options) {
  if (options.webSocketURL) {
    const explicit = new URL(String(options.webSocketURL), currentPageURL());
    explicit.searchParams.set("token", options.token);
    return explicit;
  }
  const url = new URL(String(options.baseURL ?? currentPageURL()), currentPageURL());
  url.protocol = url.protocol === "https:" ? "wss:" : "ws:";
  const basePath = url.pathname.endsWith("/") ? url.pathname.slice(0, -1) : url.pathname;
  url.pathname = `${basePath}/ws/scene/${encodeURIComponent(options.sceneId)}`;
  url.search = "";
  url.searchParams.set("token", options.token);
  return url;
}
async function bytesFromWebSocketMessage(message) {
  if (typeof message === "string") {
    return textEncoder2.encode(message);
  }
  if (message instanceof Uint8Array) {
    return message;
  }
  if (message instanceof ArrayBuffer) {
    return new Uint8Array(message);
  }
  if (ArrayBuffer.isView(message)) {
    return new Uint8Array(message.buffer, message.byteOffset, message.byteLength);
  }
  if (typeof Blob !== "undefined" && message instanceof Blob) {
    return new Uint8Array(await message.arrayBuffer());
  }
  return;
}
function defaultWebSocketFactory(url) {
  if (typeof WebSocket === "undefined") {
    throw new Error("WebSocket is not available");
  }
  return new WebSocket(url);
}
function currentPageURL() {
  return globalThis.location?.href ?? "http://127.0.0.1/";
}

// src/WebHostSceneManifest.ts
function normalizeWebHostSceneManifest(source) {
  const scenes = normalizeSceneDescriptors(source);
  if (scenes.length === 0) {
    throw new Error("scene manifest must contain at least one scene");
  }
  const defaultScene = scenes.find((scene) => scene.isDefault) ?? scenes[0];
  return {
    defaultSceneId: defaultScene.id,
    scenes: scenes.map((scene, index) => ({
      ...scene,
      isDefault: scene.id === defaultScene.id || index === 0 && !scenes.some((entry) => entry.isDefault)
    }))
  };
}
async function loadWebHostSceneManifest(source) {
  if (Array.isArray(source) || isSceneManifest(source)) {
    return normalizeWebHostSceneManifest(source);
  }
  if (source instanceof URL) {
    return loadWebHostSceneManifestFromResponse(await fetch(source));
  }
  if (source instanceof Request) {
    return loadWebHostSceneManifestFromResponse(await fetch(source));
  }
  if (source instanceof Response) {
    return loadWebHostSceneManifestFromResponse(source);
  }
  if (typeof source === "string") {
    const trimmed = source.trim();
    if (trimmed.startsWith("{") || trimmed.startsWith("[")) {
      return normalizeWebHostSceneManifest(JSON.parse(trimmed));
    }
    return loadWebHostSceneManifest(new URL(source, import.meta.url));
  }
  return normalizeWebHostSceneManifest(source);
}
function normalizeSceneDescriptors(source) {
  if (Array.isArray(source)) {
    return source.map(normalizeDescriptor);
  }
  if (isSceneManifest(source)) {
    return source.scenes.map(normalizeDescriptor);
  }
  if (isObject(source) && Array.isArray(source.scenes)) {
    return (source.scenes ?? []).map(normalizeDescriptor);
  }
  throw new Error("scene manifest must be an array or an object with scenes");
}
function normalizeDescriptor(value, index) {
  if (!isObject(value)) {
    throw new Error(`scene descriptor at index ${index ?? 0} must be an object`);
  }
  const id = String(value.id ?? "").trim();
  if (!id) {
    throw new Error(`scene descriptor at index ${index ?? 0} is missing an id`);
  }
  const titleValue = value.title;
  const isDefaultValue = Boolean(value.isDefault);
  return {
    id,
    title: typeof titleValue === "string" && titleValue.trim().length > 0 ? titleValue.trim() : undefined,
    isDefault: isDefaultValue
  };
}
function isSceneManifest(value) {
  return isObject(value) && typeof value.defaultSceneId === "string" && Array.isArray(value.scenes);
}
function isObject(value) {
  return typeof value === "object" && value !== null;
}
async function loadWebHostSceneManifestFromResponse(response) {
  if (!response.ok) {
    throw new Error(`failed to load scene manifest: ${response.status} ${response.statusText}`);
  }
  return normalizeWebHostSceneManifest(await response.json());
}

// src/BoxDrawingRenderer.ts
var none = 0;
var light = 1;
var heavy = 2;
var double = 3;
var lineSpecs = {
  9472: [none, light, none, light],
  9473: [none, heavy, none, heavy],
  9474: [light, none, light, none],
  9475: [heavy, none, heavy, none],
  9484: [none, light, light, none],
  9485: [none, heavy, light, none],
  9486: [none, light, heavy, none],
  9487: [none, heavy, heavy, none],
  9488: [none, none, light, light],
  9489: [none, none, light, heavy],
  9490: [none, none, heavy, light],
  9491: [none, none, heavy, heavy],
  9492: [light, light, none, none],
  9493: [light, heavy, none, none],
  9494: [heavy, light, none, none],
  9495: [heavy, heavy, none, none],
  9496: [light, none, none, light],
  9497: [light, none, none, heavy],
  9498: [heavy, none, none, light],
  9499: [heavy, none, none, heavy],
  9500: [light, light, light, none],
  9501: [light, heavy, light, none],
  9502: [heavy, light, light, none],
  9503: [light, light, heavy, none],
  9504: [heavy, light, heavy, none],
  9505: [heavy, heavy, light, none],
  9506: [light, heavy, heavy, none],
  9507: [heavy, heavy, heavy, none],
  9508: [light, none, light, light],
  9509: [light, none, light, heavy],
  9510: [heavy, none, light, light],
  9511: [light, none, heavy, light],
  9512: [heavy, none, heavy, light],
  9513: [heavy, none, light, heavy],
  9514: [light, none, heavy, heavy],
  9515: [heavy, none, heavy, heavy],
  9516: [none, light, light, light],
  9517: [none, light, light, heavy],
  9518: [none, heavy, light, light],
  9519: [none, heavy, light, heavy],
  9520: [none, light, heavy, light],
  9521: [none, light, heavy, heavy],
  9522: [none, heavy, heavy, light],
  9523: [none, heavy, heavy, heavy],
  9524: [light, light, none, light],
  9525: [light, light, none, heavy],
  9526: [light, heavy, none, light],
  9527: [light, heavy, none, heavy],
  9528: [heavy, light, none, light],
  9529: [heavy, light, none, heavy],
  9530: [heavy, heavy, none, light],
  9531: [heavy, heavy, none, heavy],
  9532: [light, light, light, light],
  9533: [light, light, light, heavy],
  9534: [light, heavy, light, light],
  9535: [light, heavy, light, heavy],
  9536: [heavy, light, light, light],
  9537: [light, light, heavy, light],
  9538: [heavy, light, heavy, light],
  9539: [heavy, light, light, heavy],
  9540: [heavy, heavy, light, light],
  9541: [light, light, heavy, heavy],
  9542: [light, heavy, heavy, light],
  9543: [heavy, heavy, light, heavy],
  9544: [light, heavy, heavy, heavy],
  9545: [heavy, light, heavy, heavy],
  9546: [heavy, heavy, heavy, light],
  9547: [heavy, heavy, heavy, heavy],
  9552: [none, double, none, double],
  9553: [double, none, double, none],
  9554: [none, double, light, none],
  9555: [none, light, double, none],
  9556: [none, double, double, none],
  9557: [none, none, light, double],
  9558: [none, none, double, light],
  9559: [none, none, double, double],
  9560: [light, double, none, none],
  9561: [double, light, none, none],
  9562: [double, double, none, none],
  9563: [light, none, none, double],
  9564: [double, none, none, light],
  9565: [double, none, none, double],
  9566: [light, double, light, none],
  9567: [double, light, double, none],
  9568: [double, double, double, none],
  9569: [light, none, light, double],
  9570: [double, none, double, light],
  9571: [double, none, double, double],
  9572: [none, double, light, double],
  9573: [none, light, double, light],
  9574: [none, double, double, double],
  9575: [light, double, none, double],
  9576: [double, light, none, light],
  9577: [double, double, none, double],
  9578: [light, double, light, double],
  9579: [double, light, double, light],
  9580: [double, double, double, double],
  9588: [none, none, none, light],
  9589: [light, none, none, none],
  9590: [none, light, none, none],
  9591: [none, none, light, none],
  9592: [none, none, none, heavy],
  9593: [heavy, none, none, none],
  9594: [none, heavy, none, none],
  9595: [none, none, heavy, none],
  9596: [none, heavy, none, light],
  9597: [light, none, heavy, none],
  9598: [none, light, none, heavy],
  9599: [heavy, none, light, none]
};
function canRenderBoxDrawing(text) {
  const codePoint = singleCodePoint(text);
  if (codePoint === undefined) {
    return false;
  }
  return codePoint >= 9472 && codePoint <= 9631 || codePoint >= 10240 && codePoint <= 10495;
}
function drawBoxDrawing(context, text, rect) {
  const codePoint = singleCodePoint(text);
  if (codePoint === undefined) {
    return false;
  }
  if (codePoint >= 9472 && codePoint <= 9599) {
    return drawBoxDrawingCodePoint(context, codePoint, rect);
  }
  if (codePoint >= 9600 && codePoint <= 9631) {
    return drawBlockElement(context, codePoint, rect);
  }
  if (codePoint >= 10240 && codePoint <= 10495) {
    return drawBraille(context, codePoint, rect);
  }
  return false;
}
function singleCodePoint(text) {
  const characters = Array.from(text);
  if (characters.length !== 1) {
    return;
  }
  return characters[0]?.codePointAt(0);
}
function drawBoxDrawingCodePoint(context, codePoint, rect) {
  const spec = lineSpecs[codePoint];
  if (spec) {
    drawCellLines(context, spec, rect);
    return true;
  }
  switch (codePoint) {
    case 9476:
      drawDashedHorizontal(context, rect, light, 3);
      return true;
    case 9477:
      drawDashedHorizontal(context, rect, heavy, 3);
      return true;
    case 9478:
      drawDashedVertical(context, rect, light, 3);
      return true;
    case 9479:
      drawDashedVertical(context, rect, heavy, 3);
      return true;
    case 9480:
      drawDashedHorizontal(context, rect, light, 4);
      return true;
    case 9481:
      drawDashedHorizontal(context, rect, heavy, 4);
      return true;
    case 9482:
      drawDashedVertical(context, rect, light, 4);
      return true;
    case 9483:
      drawDashedVertical(context, rect, heavy, 4);
      return true;
    case 9548:
      drawDashedHorizontal(context, rect, light, 2);
      return true;
    case 9549:
      drawDashedHorizontal(context, rect, heavy, 2);
      return true;
    case 9550:
      drawDashedVertical(context, rect, light, 2);
      return true;
    case 9551:
      drawDashedVertical(context, rect, heavy, 2);
      return true;
    case 9585:
      drawDiagonal(context, rect, false);
      return true;
    case 9586:
      drawDiagonal(context, rect, true);
      return true;
    case 9587:
      drawDiagonal(context, rect, false);
      drawDiagonal(context, rect, true);
      return true;
    case 9581:
      drawArc(context, rect, "topLeft");
      return true;
    case 9582:
      drawArc(context, rect, "topRight");
      return true;
    case 9583:
      drawArc(context, rect, "bottomRight");
      return true;
    case 9584:
      drawArc(context, rect, "bottomLeft");
      return true;
    default:
      return false;
  }
}
function strokeMetrics(rect) {
  const unit = Math.max(1, Math.round(Math.min(rect.width, rect.height) / 16));
  return {
    light: unit,
    heavy: unit * 2,
    doubleGap: unit
  };
}
function drawCellLines(context, spec, rect) {
  const metrics = strokeMetrics(rect);
  const edges = [
    [spec[0], "north"],
    [spec[1], "east"],
    [spec[2], "south"],
    [spec[3], "west"]
  ];
  for (const [weight, direction] of edges.sort((lhs, rhs) => lhs[0] - rhs[0])) {
    drawHalfStroke(context, weight, direction, rect, metrics);
  }
}
function drawHalfStroke(context, weight, direction, rect, metrics) {
  if (weight === none) {
    return;
  }
  const cx = rect.x + rect.width / 2;
  const cy = rect.y + rect.height / 2;
  const maxX = rect.x + rect.width;
  const maxY = rect.y + rect.height;
  const segment = (thickness, offset) => {
    switch (direction) {
      case "north":
        context.fillRect(cx - thickness / 2 + offset, rect.y, thickness, cy - rect.y + thickness / 2);
        break;
      case "south":
        context.fillRect(cx - thickness / 2 + offset, cy - thickness / 2, thickness, maxY - cy + thickness / 2);
        break;
      case "west":
        context.fillRect(rect.x, cy - thickness / 2 + offset, cx - rect.x + thickness / 2, thickness);
        break;
      case "east":
        context.fillRect(cx - thickness / 2, cy - thickness / 2 + offset, maxX - cx + thickness / 2, thickness);
        break;
    }
  };
  switch (weight) {
    case light:
      segment(metrics.light, 0);
      break;
    case heavy:
      segment(metrics.heavy, 0);
      break;
    case double: {
      const thickness = metrics.light;
      const offset = (thickness + metrics.doubleGap) / 2;
      segment(thickness, -offset);
      segment(thickness, offset);
      break;
    }
  }
}
function drawDashedHorizontal(context, rect, weight, segments) {
  const metrics = strokeMetrics(rect);
  const thickness = weight === heavy ? metrics.heavy : metrics.light;
  const segmentWidth = rect.width / segments;
  const dashWidth = segmentWidth * 0.55;
  const gapWidth = segmentWidth - dashWidth;
  const cy = rect.y + rect.height / 2;
  for (let index = 0;index < segments; index += 1) {
    const x = rect.x + index * segmentWidth + gapWidth / 2;
    context.fillRect(x, cy - thickness / 2, dashWidth, thickness);
  }
}
function drawDashedVertical(context, rect, weight, segments) {
  const metrics = strokeMetrics(rect);
  const thickness = weight === heavy ? metrics.heavy : metrics.light;
  const segmentHeight = rect.height / segments;
  const dashHeight = segmentHeight * 0.55;
  const gapHeight = segmentHeight - dashHeight;
  const cx = rect.x + rect.width / 2;
  for (let index = 0;index < segments; index += 1) {
    const y = rect.y + index * segmentHeight + gapHeight / 2;
    context.fillRect(cx - thickness / 2, y, thickness, dashHeight);
  }
}
function drawDiagonal(context, rect, descending) {
  const metrics = strokeMetrics(rect);
  context.lineWidth = metrics.light;
  context.lineCap = "square";
  context.setLineDash([]);
  context.beginPath();
  if (descending) {
    context.moveTo(rect.x, rect.y);
    context.lineTo(rect.x + rect.width, rect.y + rect.height);
  } else {
    context.moveTo(rect.x + rect.width, rect.y);
    context.lineTo(rect.x, rect.y + rect.height);
  }
  context.stroke();
  context.lineCap = "butt";
}
function drawArc(context, rect, corner) {
  const metrics = strokeMetrics(rect);
  const cx = rect.x + rect.width / 2;
  const cy = rect.y + rect.height / 2;
  const maxX = rect.x + rect.width;
  const maxY = rect.y + rect.height;
  const radius = Math.min(rect.width, rect.height) * 0.4;
  const kappa = radius * 0.5523;
  context.lineWidth = metrics.light;
  context.lineCap = "butt";
  context.setLineDash([]);
  context.beginPath();
  switch (corner) {
    case "topLeft":
      context.moveTo(cx, cy + radius);
      context.lineTo(cx, maxY);
      context.moveTo(cx + radius, cy);
      context.lineTo(maxX, cy);
      context.moveTo(cx, cy + radius);
      context.bezierCurveTo(cx, cy + radius - kappa, cx + radius - kappa, cy, cx + radius, cy);
      break;
    case "topRight":
      context.moveTo(cx, cy + radius);
      context.lineTo(cx, maxY);
      context.moveTo(cx - radius, cy);
      context.lineTo(rect.x, cy);
      context.moveTo(cx - radius, cy);
      context.bezierCurveTo(cx - radius + kappa, cy, cx, cy + radius - kappa, cx, cy + radius);
      break;
    case "bottomRight":
      context.moveTo(cx, cy - radius);
      context.lineTo(cx, rect.y);
      context.moveTo(cx - radius, cy);
      context.lineTo(rect.x, cy);
      context.moveTo(cx, cy - radius);
      context.bezierCurveTo(cx, cy - radius + kappa, cx - radius + kappa, cy, cx - radius, cy);
      break;
    case "bottomLeft":
      context.moveTo(cx, cy - radius);
      context.lineTo(cx, rect.y);
      context.moveTo(cx + radius, cy);
      context.lineTo(maxX, cy);
      context.moveTo(cx + radius, cy);
      context.bezierCurveTo(cx + radius - kappa, cy, cx, cy - radius + kappa, cx, cy - radius);
      break;
  }
  context.stroke();
}
function drawBlockElement(context, codePoint, rect) {
  const maxX = rect.x + rect.width;
  const maxY = rect.y + rect.height;
  const lowerEighths = (count) => {
    const height = rect.height * count / 8;
    context.fillRect(rect.x, maxY - height, rect.width, height);
  };
  const leftEighths = (count) => {
    const width = rect.width * count / 8;
    context.fillRect(rect.x, rect.y, width, rect.height);
  };
  switch (codePoint) {
    case 9600:
      context.fillRect(rect.x, rect.y, rect.width, rect.height / 2);
      return true;
    case 9601:
      lowerEighths(1);
      return true;
    case 9602:
      lowerEighths(2);
      return true;
    case 9603:
      lowerEighths(3);
      return true;
    case 9604:
      lowerEighths(4);
      return true;
    case 9605:
      lowerEighths(5);
      return true;
    case 9606:
      lowerEighths(6);
      return true;
    case 9607:
      lowerEighths(7);
      return true;
    case 9608:
      context.fillRect(rect.x, rect.y, rect.width, rect.height);
      return true;
    case 9609:
      leftEighths(7);
      return true;
    case 9610:
      leftEighths(6);
      return true;
    case 9611:
      leftEighths(5);
      return true;
    case 9612:
      leftEighths(4);
      return true;
    case 9613:
      leftEighths(3);
      return true;
    case 9614:
      leftEighths(2);
      return true;
    case 9615:
      leftEighths(1);
      return true;
    case 9616:
      context.fillRect(rect.x + rect.width / 2, rect.y, rect.width / 2, rect.height);
      return true;
    case 9617:
      drawShade(context, rect, "light");
      return true;
    case 9618:
      drawShade(context, rect, "medium");
      return true;
    case 9619:
      drawShade(context, rect, "dark");
      return true;
    case 9620:
      context.fillRect(rect.x, rect.y, rect.width, rect.height / 8);
      return true;
    case 9621:
      context.fillRect(maxX - rect.width / 8, rect.y, rect.width / 8, rect.height);
      return true;
    case 9622:
      fillQuadrants(context, rect, ["bottomLeft"]);
      return true;
    case 9623:
      fillQuadrants(context, rect, ["bottomRight"]);
      return true;
    case 9624:
      fillQuadrants(context, rect, ["topLeft"]);
      return true;
    case 9625:
      fillQuadrants(context, rect, ["topLeft", "bottomLeft", "bottomRight"]);
      return true;
    case 9626:
      fillQuadrants(context, rect, ["topLeft", "bottomRight"]);
      return true;
    case 9627:
      fillQuadrants(context, rect, ["topLeft", "topRight", "bottomLeft"]);
      return true;
    case 9628:
      fillQuadrants(context, rect, ["topLeft", "topRight", "bottomRight"]);
      return true;
    case 9629:
      fillQuadrants(context, rect, ["topRight"]);
      return true;
    case 9630:
      fillQuadrants(context, rect, ["topRight", "bottomLeft"]);
      return true;
    case 9631:
      fillQuadrants(context, rect, ["topRight", "bottomLeft", "bottomRight"]);
      return true;
    default:
      return false;
  }
}
function fillQuadrants(context, rect, quadrants) {
  const halfWidth = rect.width / 2;
  const halfHeight = rect.height / 2;
  for (const quadrant of quadrants) {
    switch (quadrant) {
      case "topLeft":
        context.fillRect(rect.x, rect.y, halfWidth, halfHeight);
        break;
      case "topRight":
        context.fillRect(rect.x + halfWidth, rect.y, halfWidth, halfHeight);
        break;
      case "bottomLeft":
        context.fillRect(rect.x, rect.y + halfHeight, halfWidth, halfHeight);
        break;
      case "bottomRight":
        context.fillRect(rect.x + halfWidth, rect.y + halfHeight, halfWidth, halfHeight);
        break;
    }
  }
}
function drawShade(context, rect, density) {
  const pixels = density === "light" ? [[0, 0]] : density === "medium" ? [[0, 0], [1, 1]] : [[0, 0], [1, 0], [0, 1]];
  for (let y = rect.y;y < rect.y + rect.height; y += 2) {
    for (let x = rect.x;x < rect.x + rect.width; x += 2) {
      for (const [px, py] of pixels) {
        const dotX = x + (px ?? 0);
        const dotY = y + (py ?? 0);
        if (dotX < rect.x + rect.width && dotY < rect.y + rect.height) {
          context.fillRect(dotX, dotY, 1, 1);
        }
      }
    }
  }
}
var brailleSubpixels = [
  [1, 0, 0],
  [8, 1, 0],
  [2, 0, 1],
  [16, 1, 1],
  [4, 0, 2],
  [32, 1, 2],
  [64, 0, 3],
  [128, 1, 3]
];
function drawBraille(context, codePoint, rect) {
  const mask = codePoint - 10240;
  if (mask === 0) {
    return true;
  }
  const cellWidth = rect.width / 2;
  const rowHeight = rect.height / 4;
  for (const [bit, col, row] of brailleSubpixels) {
    if ((mask & bit) === 0) {
      continue;
    }
    const x = rect.x + col * cellWidth;
    const y = rect.y + row * rowHeight;
    context.fillRect(x, y, cellWidth, rowHeight);
  }
  return true;
}

// src/AccessibilityTree.ts
class AccessibilityTreeMounter {
  element;
  announcerElement;
  nodesById = new Map;
  previousLabelsById = new Map;
  hasLiveRegionBaseline = false;
  constructor() {
    this.element = document.createElement("div");
    this.element.className = "webhost-scene__accessibility-tree";
    applyScreenReaderOnlyStyle(this.element);
    this.announcerElement = document.createElement("div");
    this.announcerElement.className = "webhost-scene__accessibility-announcer";
    this.announcerElement.setAttribute("aria-atomic", "true");
    applyScreenReaderOnlyStyle(this.announcerElement);
  }
  present(nodes, metrics, announcements = [], options = {}) {
    this.element.replaceChildren();
    this.nodesById.clear();
    for (const node of nodes) {
      const element = this.elementForNode(node, metrics);
      this.nodesById.set(node.id, element);
    }
    for (const node of nodes) {
      const element = this.nodesById.get(node.id);
      if (!element) {
        continue;
      }
      const parent = node.parentId ? this.nodesById.get(node.parentId) : undefined;
      (parent ?? this.element).appendChild(element);
    }
    this.announceLiveRegionChanges(nodes, announcements);
    const focused = nodes.find((node) => node.isFocused);
    if ((options.synchronizeFocus ?? true) && focused) {
      this.nodesById.get(focused.id)?.focus?.({ preventScroll: true });
    }
  }
  elementForNode(node, metrics) {
    const element = document.createElement("div");
    element.id = `swifttui-a11y-${stableDOMId(node.id)}`;
    element.dataset.accessibilityId = node.id;
    element.tabIndex = node.isFocused ? 0 : -1;
    const role = roleMapping(node.role);
    if (role.role) {
      element.setAttribute("role", role.role);
    }
    if (role.level !== undefined) {
      element.setAttribute("aria-level", String(role.level));
    }
    if (node.label) {
      element.setAttribute("aria-label", node.label);
    }
    if (node.hint) {
      element.setAttribute("aria-description", node.hint);
    }
    if (node.liveRegion) {
      element.setAttribute("aria-live", node.liveRegion);
    }
    if (node.isFocused) {
      element.dataset.focused = "true";
    }
    const [x, y, width, height] = node.rect;
    element.style.position = "absolute";
    element.style.left = `${x * metrics.cellWidth}px`;
    element.style.top = `${y * metrics.cellHeight}px`;
    element.style.width = `${Math.max(1, width) * metrics.cellWidth}px`;
    element.style.height = `${Math.max(1, height) * metrics.cellHeight}px`;
    return element;
  }
  announceLiveRegionChanges(nodes, announcements) {
    const candidates = nodes.filter((node) => node.liveRegion && node.liveRegion !== "off" && node.label);
    const currentLabelsById = new Map(candidates.map((node) => [node.id, node.label ?? ""]));
    const imperativeAssertive = announcements.filter((announcement) => announcement.politeness === "assertive");
    const imperativePolite = announcements.filter((announcement) => announcement.politeness === "polite");
    if (!this.hasLiveRegionBaseline) {
      this.previousLabelsById = currentLabelsById;
      this.hasLiveRegionBaseline = true;
      this.publishAnnouncements([], imperativeAssertive, [], imperativePolite);
      return;
    }
    const changed = candidates.filter((node) => {
      const previous = this.previousLabelsById.get(node.id);
      return previous !== undefined && previous !== node.label;
    });
    this.previousLabelsById = currentLabelsById;
    const assertive = changed.filter((node) => node.liveRegion === "assertive");
    const polite = changed.filter((node) => node.liveRegion === "polite");
    this.publishAnnouncements(assertive, imperativeAssertive, polite, imperativePolite);
  }
  publishAnnouncements(assertive, imperativeAssertive, polite, imperativePolite) {
    const ordered = [...assertive, ...imperativeAssertive, ...polite, ...imperativePolite];
    if (ordered.length === 0) {
      return;
    }
    const politeness = assertive.length > 0 || imperativeAssertive.length > 0 ? "assertive" : "polite";
    this.announcerElement.setAttribute("aria-live", politeness);
    this.announcerElement.textContent = ordered.map((entry) => {
      if ("message" in entry) {
        return entry.message;
      }
      return entry.label ?? "";
    }).join(`
`);
  }
}
function applyScreenReaderOnlyStyle(element) {
  element.style.position = "absolute";
  element.style.left = "0";
  element.style.top = "0";
  element.style.width = "1px";
  element.style.height = "1px";
  element.style.overflow = "hidden";
  element.style.clipPath = "inset(50%)";
  element.style.whiteSpace = "nowrap";
}
function roleMapping(role) {
  const heading = /^heading\(level: ([0-9]+)\)$/.exec(role);
  if (heading) {
    return {
      role: "heading",
      level: Math.max(1, Math.min(6, Number(heading[1])))
    };
  }
  const custom = /^custom\((.+)\)$/.exec(role);
  if (custom) {
    return { role: custom[1] };
  }
  switch (role) {
    case "alert":
    case "button":
    case "cell":
    case "checkbox":
    case "grid":
    case "group":
    case "link":
    case "list":
    case "menu":
    case "region":
    case "separator":
    case "slider":
    case "status":
    case "tab":
    case "table":
    case "timer":
      return { role };
    case "columnHeader":
      return { role: "columnheader" };
    case "confirmationDialog":
    case "sheet":
      return { role: "dialog" };
    case "disclosureGroup":
    case "scrollView":
    case "scrollViewWithIndicators":
    case "section":
      return { role: "region" };
    case "image":
      return { role: "img" };
    case "menuItem":
      return { role: "menuitem" };
    case "picker":
      return { role: "combobox" };
    case "progressBar":
      return { role: "progressbar" };
    case "rowHeader":
      return { role: "rowheader" };
    case "secureField":
    case "textEditor":
    case "textField":
      return { role: "textbox" };
    case "stepper":
      return { role: "spinbutton" };
    case "tabPanel":
      return { role: "tabpanel" };
    case "tableRow":
      return { role: "row" };
    case "tabView":
      return { role: "tablist" };
    case "toggle":
      return { role: "checkbox" };
    default:
      return { role: "group" };
  }
}
function stableDOMId(id) {
  return Array.from(id).map((character) => {
    if (/^[a-zA-Z0-9_-]$/.test(character)) {
      return character;
    }
    return `-${character.codePointAt(0)?.toString(16) ?? "0"}-`;
  }).join("");
}

// src/WebHostSceneRuntime.ts
class WebHostSceneRuntime {
  descriptor;
  element;
  terminalMount;
  bridge;
  onInput;
  synchronizeAccessibilityFocus;
  captureWheelInput;
  imageCache = new Map;
  currentStyle;
  canvas;
  accessibilityTree;
  diagnosticText;
  resizeObserver;
  detachInputHandlers;
  currentFrame;
  columns = 80;
  rows = 24;
  cellWidth = 8;
  cellHeight = 18;
  activePointerButton = "primary";
  lastSentResize;
  isVisible = false;
  constructor(options) {
    this.descriptor = options.descriptor;
    this.currentStyle = normalizeWebHostTerminalStyle(options.style);
    this.bridge = options.bridge;
    this.onInput = options.onInput;
    this.synchronizeAccessibilityFocus = options.synchronizeAccessibilityFocus ?? true;
    this.captureWheelInput = options.captureWheelInput ?? true;
    this.element = document.createElement("section");
    this.element.className = "webhost-scene";
    this.element.dataset.sceneId = options.descriptor.id;
    this.element.hidden = true;
    const header = document.createElement("div");
    header.className = "webhost-scene__header";
    header.textContent = options.descriptor.title ?? options.descriptor.id;
    this.terminalMount = document.createElement("div");
    this.terminalMount.className = "webhost-scene__terminal";
    this.terminalMount.tabIndex = 0;
    this.element.append(header, this.terminalMount);
    options.mount.appendChild(this.element);
    this.applyVisibility();
  }
  async mount() {
    if (this.canvas) {
      return;
    }
    const canvas = document.createElement("canvas");
    canvas.className = "webhost-scene__surface";
    canvas.setAttribute("aria-hidden", "true");
    this.canvas = canvas;
    this.accessibilityTree = new AccessibilityTreeMounter;
    this.terminalMount.replaceChildren(canvas, this.accessibilityTree.element, this.accessibilityTree.announcerElement);
    this.installInputHandlers();
    this.installResizeObserver();
    this.bridge?.bindOutput({
      presentSurface: (frame) => this.presentSurface(frame),
      writeClipboard: (text) => this.writeClipboard(text),
      notifyRuntimeIssue: (issue) => this.notifyRuntimeIssue(issue),
      writeOutput: (text) => this.writeOutput(text),
      writeError: (text) => this.writeOutput(text)
    });
    this.applyStyle(this.currentStyle);
    this.measureCells();
    this.resizeToMount();
    this.draw();
    this.syncAccessibilityTree();
  }
  setVisible(visible) {
    this.isVisible = visible;
    this.applyVisibility();
    if (visible) {
      this.resizeToMount();
      if (this.synchronizeAccessibilityFocus) {
        this.terminalMount.focus?.({ preventScroll: true });
      }
    }
  }
  setStyle(style) {
    this.currentStyle = normalizeWebHostTerminalStyle(style);
    this.applyStyle(this.currentStyle);
    this.bridge?.updateRenderStyle(this.currentStyle);
    this.measureCells();
    this.resizeToMount();
    this.draw();
    this.syncAccessibilityTree();
  }
  resize(columns, rows) {
    this.columns = Math.max(1, Math.round(columns));
    this.rows = Math.max(1, Math.round(rows));
    this.resizeCanvas();
    this.draw();
    this.syncAccessibilityTree();
  }
  writeOutput(text) {
    if (!this.diagnosticText) {
      const diagnosticText = document.createElement("pre");
      diagnosticText.className = "webhost-scene__diagnostic";
      this.diagnosticText = diagnosticText;
      this.terminalMount.appendChild(diagnosticText);
    }
    this.diagnosticText.textContent = `${this.diagnosticText.textContent ?? ""}${text}`;
  }
  notifyRuntimeIssue(issue) {
    console.log(issue.description);
  }
  async writeClipboard(text) {
    const clipboard = globalThis.navigator?.clipboard;
    if (!clipboard?.writeText) {
      return;
    }
    try {
      await clipboard.writeText(text);
    } catch {}
  }
  sendInput(chunk) {
    this.onInput(chunk);
  }
  dispose() {
    this.detachInputHandlers?.();
    this.resizeObserver?.disconnect();
    this.element.remove();
  }
  presentSurface(frame) {
    const previousFrame = this.currentFrame;
    this.currentFrame = frame;
    this.columns = Math.max(1, Math.round(frame.width));
    this.rows = Math.max(1, Math.round(frame.height));
    const resized = this.resizeCanvas();
    this.draw(previousFrame && !resized ? frame.damage : undefined);
    this.syncAccessibilityTree();
  }
  applyStyle(style) {
    applyWebHostTerminalStyle(this.element, style);
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
  applyVisibility() {
    this.element.hidden = !this.isVisible;
    this.element.style.setProperty("display", this.isVisible ? "grid" : "none", "important");
  }
  installResizeObserver() {
    if (typeof ResizeObserver === "undefined") {
      return;
    }
    this.resizeObserver = new ResizeObserver(() => {
      this.resizeToMount();
    });
    this.resizeObserver.observe(this.terminalMount);
  }
  installInputHandlers() {
    const handleKeyDown = (event) => {
      if (event.metaKey || event.isComposing) {
        return;
      }
      const key = keyInputFromKeyboardEvent(event);
      if (!key) {
        return;
      }
      this.onInput(encodeKeyInputMessage({
        ...key,
        modifiers: modifierMask(event)
      }));
      event.preventDefault();
    };
    const handlePaste = (event) => {
      const text = event.clipboardData?.getData("text/plain") ?? "";
      if (!text) {
        return;
      }
      this.onInput(encodePasteInputMessage(text));
      event.preventDefault();
    };
    const handlePointerDown = (event) => {
      const location = this.cellLocation(event);
      if (!location) {
        return;
      }
      const button = pointerButton(event.button);
      this.activePointerButton = button;
      this.terminalMount.focus?.({ preventScroll: true });
      this.terminalMount.setPointerCapture?.(event.pointerId);
      this.onInput(encodeMouseInputMessage({
        kind: "down",
        x: location.x,
        y: location.y,
        button,
        modifiers: modifierMask(event)
      }));
      event.preventDefault();
    };
    const handlePointerUp = (event) => {
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
        modifiers: modifierMask(event)
      }));
      event.preventDefault();
    };
    const handlePointerMove = (event) => {
      const location = this.cellLocation(event);
      if (!location) {
        return;
      }
      this.onInput(encodeMouseInputMessage({
        kind: event.buttons ? "dragged" : "moved",
        x: location.x,
        y: location.y,
        button: this.activePointerButton,
        modifiers: modifierMask(event)
      }));
    };
    const handleWheel = (event) => {
      if (!this.captureWheelInput) {
        return;
      }
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
        modifiers: modifierMask(event)
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
  resizeToMount() {
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
  sendResizeIfNeeded() {
    const current = {
      columns: this.columns,
      rows: this.rows,
      cellWidth: this.cellWidth,
      cellHeight: this.cellHeight
    };
    if (this.lastSentResize && this.lastSentResize.columns === current.columns && this.lastSentResize.rows === current.rows && this.lastSentResize.cellWidth === current.cellWidth && this.lastSentResize.cellHeight === current.cellHeight) {
      return;
    }
    this.lastSentResize = current;
    this.bridge?.resize(current.columns, current.rows, current.cellWidth, current.cellHeight);
  }
  resizeCanvas() {
    if (!this.canvas) {
      return false;
    }
    const cssWidth = Math.max(1, this.columns * this.cellWidth);
    const cssHeight = Math.max(1, this.rows * this.cellHeight);
    const scale = globalThis.window?.devicePixelRatio || 1;
    const width = Math.ceil(cssWidth * scale);
    const height = Math.ceil(cssHeight * scale);
    const styleWidth = `${cssWidth}px`;
    const styleHeight = `${cssHeight}px`;
    if (this.canvas.width === width && this.canvas.height === height && this.canvas.style.width === styleWidth && this.canvas.style.height === styleHeight) {
      return false;
    }
    this.canvas.width = width;
    this.canvas.height = height;
    this.canvas.style.width = styleWidth;
    this.canvas.style.height = styleHeight;
    return true;
  }
  measureCells() {
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
  draw(damage) {
    const canvas = this.canvas;
    const context = canvas?.getContext("2d");
    if (!canvas || !context) {
      return;
    }
    const scale = globalThis.window?.devicePixelRatio || 1;
    context.setTransform(scale, 0, 0, scale, 0, 0);
    context.textBaseline = "alphabetic";
    const frame = this.currentFrame;
    const dirtyRects = frame ? this.dirtyRectsForDamage(damage, frame) : undefined;
    if (dirtyRects?.length === 0) {
      return;
    }
    context.fillStyle = webTUITerminalBackgroundColor(this.currentStyle);
    if (dirtyRects) {
      for (const rect of dirtyRects) {
        context.clearRect(rect.x, rect.y, rect.width, rect.height);
        context.fillRect(rect.x, rect.y, rect.width, rect.height);
      }
    } else {
      context.clearRect(0, 0, canvas.width / scale, canvas.height / scale);
      context.fillRect(0, 0, this.columns * this.cellWidth, this.rows * this.cellHeight);
    }
    if (!frame) {
      return;
    }
    this.drawRows(context, frame, dirtyRects);
    this.drawImages(context, frame.images ?? [], dirtyRects);
  }
  drawRows(context, frame, dirtyRects) {
    for (let y = 0;y < frame.rows.length; y += 1) {
      const row = frame.rows[y] ?? [];
      for (const cell of row) {
        const [x, text, span, styleIndex] = cell;
        const cellRect = this.cellRect(x, y, span);
        if (dirtyRects && !dirtyRects.some((rect) => rectsIntersect(rect, cellRect))) {
          continue;
        }
        const style = frame.styles[styleIndex] ?? undefined;
        this.drawCell(context, x, y, text, span, style);
      }
    }
  }
  syncAccessibilityTree() {
    const tree = this.accessibilityTree;
    if (!tree || !this.currentFrame) {
      return;
    }
    tree.present(this.currentFrame.accessibilityTree ?? [], {
      cellWidth: this.cellWidth,
      cellHeight: this.cellHeight
    }, this.currentFrame.accessibilityAnnouncements ?? [], {
      synchronizeFocus: this.synchronizeAccessibilityFocus
    });
  }
  drawImages(context, images, dirtyRects) {
    for (const image of images) {
      this.drawImage(context, image, dirtyRects);
    }
  }
  drawImage(context, image, dirtyRects) {
    const decodedImage = this.cachedImage(image);
    if (!decodedImage) {
      return;
    }
    const [boundsX, boundsY, boundsWidth, boundsHeight] = image.bounds;
    const [clipX, clipY, clipWidth, clipHeight] = image.visibleBounds;
    if (boundsWidth <= 0 || boundsHeight <= 0 || clipWidth <= 0 || clipHeight <= 0) {
      return;
    }
    const imageRect = {
      x: clipX * this.cellWidth,
      y: clipY * this.cellHeight,
      width: clipWidth * this.cellWidth,
      height: clipHeight * this.cellHeight
    };
    if (dirtyRects && !dirtyRects.some((rect) => rectsIntersect(rect, imageRect))) {
      return;
    }
    context.save();
    context.beginPath();
    context.rect(clipX * this.cellWidth, clipY * this.cellHeight, clipWidth * this.cellWidth, clipHeight * this.cellHeight);
    context.clip();
    context.drawImage(decodedImage, boundsX * this.cellWidth, boundsY * this.cellHeight, boundsWidth * this.cellWidth, boundsHeight * this.cellHeight);
    context.restore();
  }
  cachedImage(image) {
    const cached = this.imageCache.get(image.id);
    if (cached?.image) {
      return cached.image;
    }
    if (!cached?.promise && image.dataBase64) {
      const promise = decodeImage(image.dataBase64, image.format);
      this.imageCache.set(image.id, { promise });
      promise.then((decodedImage) => {
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
    return;
  }
  drawCell(context, x, y, text, span, style) {
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
        height: this.cellHeight
      })) {
        context.font = this.fontForStyle(style);
        context.fillText(text, rectX, rectY + Math.floor((this.cellHeight + this.currentStyle.fontSize) / 2) - 2);
      }
    }
    this.drawTextLine(context, rectX, rectY, width, style?.underline, "underline", foreground);
    this.drawTextLine(context, rectX, rectY, width, style?.strikethrough, "strike", foreground);
    context.globalAlpha = 1;
  }
  dirtyRectsForDamage(damage, frame) {
    if (!damage || damage.requiresFullTextRepaint || damage.requiresFullGraphicsReplay) {
      return;
    }
    const rects = [];
    for (const [row, ranges] of damage.textRows) {
      if (row < 0 || row >= frame.height) {
        continue;
      }
      if (ranges.length === 0) {
        rects.push(this.cellRect(0, row, frame.width));
        continue;
      }
      for (const [start, end] of ranges) {
        const lowerBound = Math.max(0, Math.min(frame.width, Math.floor(start)));
        const upperBound = Math.max(lowerBound, Math.min(frame.width, Math.ceil(end)));
        if (lowerBound >= upperBound) {
          continue;
        }
        rects.push(this.cellRect(lowerBound, row, upperBound - lowerBound));
      }
    }
    return rects;
  }
  cellRect(x, y, span) {
    return {
      x: x * this.cellWidth,
      y: y * this.cellHeight,
      width: Math.max(1, span) * this.cellWidth,
      height: this.cellHeight
    };
  }
  drawTextLine(context, x, y, width, line, placement, fallbackColor) {
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
    const lineY = placement === "underline" ? y + this.cellHeight - 2 : y + Math.floor(this.cellHeight / 2);
    context.beginPath();
    context.moveTo(x, lineY);
    context.lineTo(x + width, lineY);
    context.stroke();
    context.setLineDash([]);
  }
  fontForStyle(style) {
    const emphasis = style?.em ?? 0;
    const italic = (emphasis & 2) !== 0 ? "italic " : "";
    const weight = (emphasis & 1) !== 0 ? "700 " : "";
    return `${italic}${weight}${this.currentStyle.fontSize}px ${this.currentStyle.fontFamily}`;
  }
  cellLocation(event) {
    const rect = this.canvas?.getBoundingClientRect?.() ?? this.terminalMount.getBoundingClientRect?.();
    if (!rect) {
      return;
    }
    const x = (event.clientX - rect.left) / this.cellWidth;
    const y = (event.clientY - rect.top) / this.cellHeight;
    const cellX = Math.floor(x);
    const cellY = Math.floor(y);
    if (cellX < 0 || cellY < 0 || cellX >= this.columns || cellY >= this.rows) {
      return;
    }
    return { x, y };
  }
}
async function decodeImage(dataBase64, format) {
  const bytes = decodeBase64Bytes(dataBase64);
  const blob = new Blob([bytes], { type: `image/${format}` });
  if (typeof createImageBitmap === "function") {
    return createImageBitmap(blob);
  }
  return new Promise((resolve, reject) => {
    const image = new Image;
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
function decodeBase64Bytes(value) {
  if (typeof atob === "function") {
    const binary = atob(value);
    const bytes = new Uint8Array(binary.length);
    for (let index = 0;index < binary.length; index += 1) {
      bytes[index] = binary.charCodeAt(index);
    }
    return bytes;
  }
  return new Uint8Array(Buffer.from(value, "base64"));
}
function keyInputFromKeyboardEvent(event) {
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
    default: {
      const characters = Array.from(event.key);
      if (characters.length !== 1) {
        return;
      }
      return {
        key: "character",
        character: characters[0]
      };
    }
  }
}
function pointerButton(button) {
  switch (button) {
    case 1:
      return "middle";
    case 2:
      return "secondary";
    default:
      return "primary";
  }
}
function modifierMask(event) {
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
function normalizedWheelDelta(delta) {
  if (delta > 0) {
    return 1;
  }
  if (delta < 0) {
    return -1;
  }
  return 0;
}
function rectsIntersect(lhs, rhs) {
  return lhs.x < rhs.x + rhs.width && lhs.x + lhs.width > rhs.x && lhs.y < rhs.y + rhs.height && lhs.y + lhs.height > rhs.y;
}
function resolvedForeground(style, terminalStyle) {
  if ((style?.em ?? 0) & 16) {
    return style?.bg ?? terminalStyle.theme.background;
  }
  return style?.fg ?? terminalStyle.theme.foreground;
}
function resolvedBackground(style, terminalStyle) {
  if ((style?.em ?? 0) & 16) {
    return style?.fg ?? terminalStyle.theme.foreground;
  }
  return style?.bg;
}

// src/WebHostApp.ts
async function createWebHostApp(options) {
  const manifest = await resolveManifest(options);
  const controller = new InternalWebHostAppController({
    mount: options.mount,
    manifest,
    style: options.style,
    environment: options.environment,
    embeddedHost: options.embeddedHost,
    bridgeFactory: options.bridgeFactory,
    initialSceneId: options.initialSceneId,
    createElement: options.createElement,
    sceneRuntimeFactory: options.sceneRuntimeFactory ?? ((runtimeOptions) => new WebHostSceneRuntime(runtimeOptions))
  });
  await controller.initialize();
  return controller;
}

class InternalWebHostAppController {
  scenes;
  selectedSceneId;
  mount;
  sceneRoot;
  style;
  environment;
  embeddedHost;
  bridgeFactory;
  sceneRuntimeFactory;
  runtimes = new Map;
  bridges = new Map;
  constructor(options) {
    this.mount = options.mount;
    this.style = normalizeWebHostTerminalStyle(options.style ?? {});
    this.environment = options.environment;
    this.embeddedHost = options.embeddedHost;
    this.bridgeFactory = options.bridgeFactory;
    this.sceneRuntimeFactory = options.sceneRuntimeFactory;
    this.scenes = options.manifest.scenes;
    this.selectedSceneId = options.initialSceneId && options.manifest.scenes.some((scene) => scene.id === options.initialSceneId) ? options.initialSceneId : options.manifest.scenes.find((scene) => scene.id === options.manifest.defaultSceneId)?.id ?? options.manifest.defaultSceneId;
    this.sceneRoot = (options.createElement ?? defaultCreateElement)("div");
    this.sceneRoot.className = "webhost-scene-root";
    this.mount.replaceChildren(this.sceneRoot);
    this.applyHostFrameStyle();
  }
  async initialize() {
    await this.ensureRuntime(this.selectedSceneId);
    await this.switchScene(this.selectedSceneId);
  }
  async switchScene(id) {
    const descriptor = this.scenes.find((scene) => scene.id === id);
    if (!descriptor) {
      throw new Error(`Unknown scene: ${id}`);
    }
    for (const [sceneId, runtime2] of this.runtimes) {
      runtime2.setVisible(sceneId === id);
    }
    const runtime = await this.ensureRuntime(id);
    runtime.setVisible(true);
    this.selectedSceneId = id;
  }
  setStyle(style) {
    const merged = mergeWebHostTerminalStyle(this.style, style);
    this.style = merged;
    for (const runtime of this.runtimes.values()) {
      runtime.setStyle(this.style);
    }
    this.applyHostFrameStyle();
  }
  async dispose() {
    for (const runtime of this.runtimes.values()) {
      runtime.dispose();
    }
    for (const bridge of this.bridges.values()) {
      bridge.dispose();
    }
    this.runtimes.clear();
    this.bridges.clear();
    this.mount.replaceChildren();
  }
  async ensureRuntime(id) {
    const existing = this.runtimes.get(id);
    if (existing) {
      return existing;
    }
    const descriptor = this.scenes.find((scene) => scene.id === id);
    if (!descriptor) {
      throw new Error(`Unknown scene: ${id}`);
    }
    const bridge = this.makeBridge(id, descriptor);
    const runtime = this.sceneRuntimeFactory({
      mount: this.sceneRoot,
      descriptor,
      style: this.style,
      bridge,
      onInput: (chunk) => bridge.sendInput(chunk)
    });
    this.bridges.set(id, bridge);
    this.runtimes.set(id, runtime);
    await runtime.mount();
    runtime.setVisible(id === this.selectedSceneId);
    return runtime;
  }
  makeBridge(sceneId, descriptor) {
    if (this.bridgeFactory) {
      return this.bridgeFactory({
        sceneId,
        descriptor,
        style: this.style,
        environment: this.environment
      });
    }
    if (this.embeddedHost) {
      return new WebSocketSceneBridge({
        sceneId,
        token: this.embeddedHost.token,
        baseURL: this.embeddedHost.webSocketBaseURL,
        webSocketFactory: this.embeddedHost.webSocketFactory
      });
    }
    return new BrowserWASIBridge({
      sceneId,
      columns: 80,
      rows: 24,
      environment: this.environment,
      renderStyle: this.style
    });
  }
  applyHostFrameStyle() {
    this.mount.style.background = "linear-gradient(180deg, #0f172a 0%, #111827 100%)";
    this.mount.style.minHeight = "100%";
    this.mount.style.display = "block";
    this.mount.style.padding = "1rem";
  }
}
function defaultCreateElement(tagName) {
  if (typeof document === "undefined") {
    throw new Error("document is not available");
  }
  return document.createElement(tagName);
}
async function resolveManifest(options) {
  if (options.manifest) {
    return loadWebHostSceneManifest(options.manifest);
  }
  if (options.manifestUrl) {
    return loadWebHostSceneManifest(options.manifestUrl);
  }
  return normalizeWebHostSceneManifest([
    {
      id: "main",
      title: "Main",
      isDefault: true
    }
  ]);
}

// src/browser.ts
async function bootstrap() {
  const mount = document.getElementById("webhost-root");
  if (!mount) {
    throw new Error("webhost root element not found");
  }
  const config = window.__WEBTUI__ ?? {};
  const pageURL = new URL(globalThis.location?.href ?? import.meta.url);
  const embeddedToken = config.embeddedHost?.token ?? pageURL.searchParams.get("token") ?? undefined;
  const manifestUrl = tokenizedURL(config.manifestUrl ?? new URL("./scene-manifest.json", pageURL), embeddedToken);
  const controller = await createWebHostApp({
    mount,
    manifestUrl,
    initialSceneId: config.initialSceneId,
    style: config.style,
    embeddedHost: embeddedToken ? {
      token: embeddedToken,
      webSocketBaseURL: config.embeddedHost?.webSocketBaseURL ?? new URL("./", pageURL).href
    } : undefined
  });
  window.__WEBTUI_APP__ = controller;
}
bootstrap();
function tokenizedURL(value, token) {
  if (!token) {
    return value;
  }
  const url = new URL(String(value), globalThis.location?.href ?? import.meta.url);
  url.searchParams.set("token", token);
  return url;
}
