// dist/src/SurfaceRenderer.js
function resolveSurfaceRenderer(renderer) {
  let selected = renderer ?? "canvas";
  if (selected === "dom" && !0 || selected === "canvas" && !1)
    throw Error(`The ${selected} renderer is not included in this browser build. Rebuild with --renderer ${selected}.`);
  return selected;
}
function resolvedSurfaceForeground(style, terminalStyle) {
  if ((style?.em ?? 0) & 16)
    return style?.bg ?? terminalStyle.theme.background;
  return style?.fg ?? terminalStyle.theme.foreground;
}
function resolvedSurfaceBackground(style, terminalStyle) {
  if ((style?.em ?? 0) & 16)
    return style?.fg ?? terminalStyle.theme.foreground;
  return style?.bg;
}

// dist/src/WebHostTerminalStyle.js
var defaultPalette = {
  foreground: "#eceff4",
  background: "#1e222a",
  cursor: "#56b6c2",
  selectionBackground: "#2e3440",
  selectionForeground: "#eceff4",
  ansi: {
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
  }
}, defaultTheme = {
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
  let palette = normalizePalette(style.palette, defaultPalette), theme = normalizeTheme(style.theme, palette, defaultTheme);
  return {
    fontSize: normalizeFontSize(style.fontSize ?? 14),
    fontFamily: style.fontFamily ?? '"SFMono-Regular", "SF Mono", "Menlo", "Monaco", "Consolas", "Liberation Mono", monospace',
    cursorStyle: style.cursorStyle ?? "block",
    cursorBlink: style.cursorBlink ?? !1,
    backgroundOpacity: normalizeOpacity(style.backgroundOpacity ?? 1),
    ...style.reduceMotion === void 0 ? {} : { reduceMotion: style.reduceMotion },
    ...style.contrast === void 0 ? {} : { contrast: style.contrast },
    ...style.differentiateWithoutColor === void 0 ? {} : { differentiateWithoutColor: style.differentiateWithoutColor },
    ...style.reduceTransparency === void 0 ? {} : { reduceTransparency: style.reduceTransparency },
    ...style.colorProfile === void 0 ? {} : { colorProfile: style.colorProfile },
    palette,
    theme
  };
}
function mergeWebHostTerminalStyle(base, patch) {
  let resolvedBase = normalizeWebHostTerminalStyle(base);
  return normalizeWebHostTerminalStyle({
    ...resolvedBase,
    ...patch,
    palette: mergePalette(resolvedBase.palette, patch.palette),
    theme: patch.theme ? {
      ...resolvedBase.theme,
      ...patch.theme
    } : resolvedBase.theme
  });
}
function resolveWebHostAccessibilityPreferences(style) {
  let media = (query) => globalThis.matchMedia?.(query).matches, forced = media("(forced-colors: active)"), contrast = media("(prefers-contrast: more)") || forced ? "increased" : media("(prefers-contrast: less)") ? "standard" : void 0;
  return {
    reduceMotion: style.reduceMotion ?? media("(prefers-reduced-motion: reduce)"),
    contrast: style.contrast ?? contrast,
    differentiateWithoutColor: style.differentiateWithoutColor ?? (forced ? !0 : void 0),
    reduceTransparency: style.reduceTransparency ?? media("(prefers-reduced-transparency: reduce)"),
    colorProfile: style.colorProfile
  };
}
function resolveWebHostTerminalRenderStyle(style) {
  let normalized = normalizeWebHostTerminalStyle(style), preferences = resolveWebHostAccessibilityPreferences(normalized), reduceMotion = preferences.reduceMotion;
  return {
    ...reduceMotion === void 0 ? {} : { reduceMotion: reduceMotion ? "true" : "false" },
    ...preferences.contrast === void 0 ? {} : { contrast: preferences.contrast },
    ...preferences.differentiateWithoutColor === void 0 ? {} : { differentiateWithoutColor: preferences.differentiateWithoutColor ? "true" : "false" },
    ...preferences.reduceTransparency === void 0 ? {} : { reduceTransparency: preferences.reduceTransparency ? "true" : "false" },
    ...preferences.colorProfile === void 0 ? {} : { colorProfile: preferences.colorProfile },
    appearance: {
      foregroundColor: normalized.theme.foreground,
      backgroundColor: normalized.theme.background,
      tintColor: normalized.theme.tint,
      palette: paletteToIndexedMap(normalized.palette.ansi),
      colorSchemeContrast: preferences.contrast ?? (contrastRatio(normalized.theme.foreground, normalized.theme.background) >= 7 ? "increased" : "standard"),
      source: "override"
    },
    theme: { ...normalized.theme }
  };
}
function encodeWebHostTerminalRenderStyleBase64(style) {
  return encodeBase64(JSON.stringify(resolveWebHostTerminalRenderStyle(style)));
}
function webTUITerminalBackgroundColor(style) {
  let normalized = normalizeWebHostTerminalStyle(style);
  return hexToRgba(normalized.theme.background, resolveWebHostAccessibilityPreferences(normalized).reduceTransparency ? 1 : normalized.backgroundOpacity);
}
function applyWebHostTerminalStyle(element, style) {
  let normalized = normalizeWebHostTerminalStyle(style);
  element.style.fontFamily = normalized.fontFamily, element.style.fontSize = `${normalized.fontSize}px`, element.style.background = webTUITerminalBackgroundColor(normalized), element.style.color = normalized.theme.foreground;
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
  if (!patch)
    return base;
  return {
    ...base,
    ...patch,
    ansi: patch.ansi ? {
      ...base.ansi,
      ...patch.ansi
    } : base.ansi
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
  let derived = themeFromPalette(palette, defaults);
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
  if (!Number.isFinite(opacity))
    return 1;
  return Math.min(1, Math.max(0, opacity));
}
function normalizeHexColor(value) {
  let trimmed = value.trim(), normalized = trimmed.startsWith("#") ? trimmed : `#${trimmed}`;
  if (!/^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(normalized))
    throw Error(`Invalid hex color: ${value}`);
  return normalized.toLowerCase();
}
function hexToRgba(color, opacity) {
  let normalized = normalizeHexColor(color), alpha = normalizeOpacity(opacity), channels = parseHexColor(normalized);
  if (!channels)
    return normalized;
  let finalAlpha = Math.round(channels.alpha * alpha * 1000) / 1000;
  return `rgba(${channels.red}, ${channels.green}, ${channels.blue}, ${finalAlpha})`;
}
function parseHexColor(color) {
  let hex = color.startsWith("#") ? color.slice(1) : color, normalized = hex.length === 3 || hex.length === 4 ? hex.split("").map((ch) => ch + ch).join("") : hex;
  if (normalized.length !== 6 && normalized.length !== 8)
    return;
  return {
    red: Number.parseInt(normalized.slice(0, 2), 16),
    green: Number.parseInt(normalized.slice(2, 4), 16),
    blue: Number.parseInt(normalized.slice(4, 6), 16),
    alpha: normalized.length === 8 ? Number.parseInt(normalized.slice(6, 8), 16) / 255 : 1
  };
}
function contrastRatio(foreground, background) {
  let fg = relativeLuminance(foreground), bg = relativeLuminance(background), lighter = Math.max(fg, bg), darker = Math.min(fg, bg);
  return (lighter + 0.05) / (darker + 0.05);
}
function relativeLuminance(color) {
  let channels = parseHexColor(normalizeHexColor(color));
  if (!channels)
    return 0;
  let toLinear = (channel) => {
    let value = channel / 255;
    return value <= 0.03928 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
  };
  return 0.2126 * toLinear(channels.red) + 0.7152 * toLinear(channels.green) + 0.0722 * toLinear(channels.blue);
}
function encodeBase64(value) {
  if (typeof btoa === "function") {
    let bytes = (/* @__PURE__ */ new TextEncoder()).encode(value), binary = "";
    for (let byte of bytes)
      binary += String.fromCharCode(byte);
    return btoa(binary);
  }
  return Buffer.from(value, "utf8").toString("base64");
}

// dist/src/WebHostAccessibilitySettings.js
var profiles = [
  "standard",
  "monochrome",
  "protanopia",
  "deuteranopia",
  "tritanopia"
], booleanKeys = [
  "reduceMotion",
  "differentiateWithoutColor",
  "reduceTransparency"
];
function readWebHostAccessibilityPreferences() {
  try {
    let value = JSON.parse(globalThis.sessionStorage?.getItem("swifttui.accessibility.preferences.v1") ?? "{}");
    if (!value || typeof value !== "object")
      return {};
    let result = {};
    for (let key of booleanKeys) {
      let candidate = value[key];
      if (typeof candidate === "boolean")
        result[key] = candidate;
    }
    let contrast = value.contrast;
    if (contrast === "standard" || contrast === "increased")
      result.contrast = contrast;
    let profile = value.colorProfile;
    if (profiles.some((candidate) => candidate === profile))
      result.colorProfile = profile;
    return result;
  } catch {
    return {};
  }
}
function createWebHostAccessibilitySettings(document2, initial, changed) {
  let details = document2.createElement("details");
  details.className = "webhost-accessibility-settings", Object.assign(details.style, {
    flex: "0 0 auto",
    color: "CanvasText",
    background: "Canvas",
    font: "14px system-ui",
    padding: "4px 8px",
    boxSizing: "border-box"
  });
  let summary = document2.createElement("summary");
  summary.textContent = "Accessibility settings", details.append(summary);
  let fields = document2.createElement("div");
  Object.assign(fields.style, {
    display: "flex",
    flexWrap: "wrap",
    gap: "8px",
    padding: "8px 0"
  }), details.append(fields);
  let selectors = /* @__PURE__ */ new Map, definitions = [
    [
      "reduceMotion",
      "Reduce motion",
      [
        "auto",
        "on",
        "off"
      ]
    ],
    [
      "contrast",
      "Contrast",
      [
        "auto",
        "increased",
        "standard"
      ]
    ],
    [
      "differentiateWithoutColor",
      "Differentiate without color",
      [
        "auto",
        "on",
        "off"
      ]
    ],
    [
      "reduceTransparency",
      "Reduce transparency",
      [
        "auto",
        "on",
        "off"
      ]
    ],
    [
      "colorProfile",
      "Color profile",
      ["auto", ...profiles]
    ]
  ], read = () => {
    let result = {};
    for (let key of booleanKeys) {
      let value = selectors.get(key)?.value ?? "auto";
      result[key] = value === "auto" ? void 0 : value === "on";
    }
    let contrast = selectors.get("contrast")?.value ?? "auto";
    result.contrast = contrast === "auto" ? void 0 : contrast;
    let profile = selectors.get("colorProfile")?.value ?? "auto";
    return result.colorProfile = profile === "auto" ? void 0 : profile, result;
  }, commit = () => {
    let preferences = read();
    try {
      globalThis.sessionStorage?.setItem("swifttui.accessibility.preferences.v1", JSON.stringify(preferences));
    } catch {}
    changed(preferences);
  };
  for (let [key, title, values] of definitions) {
    let label = document2.createElement("label");
    label.append(document2.createTextNode(`${title} `));
    let select = document2.createElement("select");
    for (let value of values) {
      let option = document2.createElement("option");
      option.value = value, option.textContent = value === "auto" ? "Use system setting" : value.charAt(0).toUpperCase() + value.slice(1), select.append(option);
    }
    select.addEventListener("change", commit), selectors.set(key, select), label.append(select), fields.append(label);
  }
  let reset = document2.createElement("button");
  reset.type = "button", reset.textContent = "Use system settings", reset.addEventListener("click", () => {
    for (let select of selectors.values())
      select.value = "auto";
    commit();
  }), fields.append(reset);
  let update = (preferences) => {
    for (let [key, select] of selectors) {
      let value = preferences[key];
      select.value = value === void 0 ? "auto" : typeof value === "boolean" ? value ? "on" : "off" : value;
    }
  };
  return update(initial), {
    element: details,
    update
  };
}

// dist/src/WebHostSceneManifest.js
function normalizeWebHostSceneManifest(source) {
  let scenes = normalizeSceneDescriptors(source);
  if (scenes.length === 0)
    throw Error("scene manifest must contain at least one scene");
  let defaultScene = scenes.find((scene) => scene.isDefault) ?? scenes[0];
  return {
    defaultSceneId: defaultScene.id,
    scenes: scenes.map((scene, index) => ({
      ...scene,
      isDefault: scene.id === defaultScene.id || index === 0 && !scenes.some((entry) => entry.isDefault)
    }))
  };
}
async function loadWebHostSceneManifest(source) {
  if (Array.isArray(source) || isSceneManifest(source))
    return normalizeWebHostSceneManifest(source);
  if (source instanceof URL)
    return loadWebHostSceneManifestFromResponse(await fetch(source));
  if (source instanceof Request)
    return loadWebHostSceneManifestFromResponse(await fetch(source));
  if (source instanceof Response)
    return loadWebHostSceneManifestFromResponse(source);
  if (typeof source === "string") {
    let trimmed = source.trim();
    if (trimmed.startsWith("{") || trimmed.startsWith("["))
      return normalizeWebHostSceneManifest(JSON.parse(trimmed));
    return loadWebHostSceneManifest(new URL(source, import.meta.url));
  }
  return normalizeWebHostSceneManifest(source);
}
function normalizeSceneDescriptors(source) {
  if (Array.isArray(source))
    return source.map(normalizeDescriptor);
  if (isSceneManifest(source))
    return source.scenes.map(normalizeDescriptor);
  if (isObject(source) && Array.isArray(source.scenes))
    return (source.scenes ?? []).map(normalizeDescriptor);
  throw Error("scene manifest must be an array or an object with scenes");
}
function normalizeDescriptor(value, index) {
  if (!isObject(value))
    throw Error(`scene descriptor at index ${index ?? 0} must be an object`);
  let id = String(value.id ?? "").trim();
  if (!id)
    throw Error(`scene descriptor at index ${index ?? 0} is missing an id`);
  let titleValue = value.title, isDefaultValue = Boolean(value.isDefault);
  return {
    id,
    title: typeof titleValue === "string" && titleValue.trim().length > 0 ? titleValue.trim() : void 0,
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
  if (!response.ok)
    throw Error(`failed to load scene manifest: ${response.status} ${response.statusText}`);
  return normalizeWebHostSceneManifest(await response.json());
}

// dist/src/SurfaceTypography.js
function fontForStyle(terminalStyle, style) {
  let emphasis = style?.em ?? 0;
  return `${(emphasis & 2) !== 0 ? "italic " : ""}${(emphasis & 1) !== 0 ? "700 " : ""}${terminalStyle.fontSize}px ${terminalStyle.fontFamily}`;
}

// dist/src/RasterAllocationBudget.js
function boundedCanvasSize(cssWidth, cssHeight, scale) {
  if (![
    cssWidth,
    cssHeight,
    scale
  ].every((value) => Number.isFinite(value) && value > 0))
    return {
      width: 1,
      height: 1,
      scale: 1
    };
  let requestedWidth = Math.ceil(cssWidth * scale), requestedHeight = Math.ceil(cssHeight * scale);
  if (requestedWidth <= 8192 && requestedHeight <= 8192 && requestedWidth * requestedHeight <= 16777216)
    return {
      width: requestedWidth,
      height: requestedHeight,
      scale
    };
  let boundedScale = Math.min(scale, 8192 / cssWidth, 8192 / cssHeight, Math.sqrt(16777216 / cssWidth / cssHeight));
  return {
    width: Math.max(1, Math.floor(cssWidth * boundedScale)),
    height: Math.max(1, Math.floor(cssHeight * boundedScale)),
    scale: boundedScale
  };
}

// dist/src/normalizeWireTokens.js
function normalizeSemantics(value) {
  switch (value) {
    case "none":
    case "automatic":
    case "activate":
    case "edit":
      return value;
    default:
      return "automatic";
  }
}
function normalizePoliteness(value) {
  switch (value) {
    case "off":
    case "polite":
    case "assertive":
      return value;
    default:
      return "polite";
  }
}
function normalizeLiveRegion(value) {
  switch (value) {
    case "off":
    case "polite":
    case "assertive":
      return value;
    default:
      return;
  }
}
function isSupportedImageFormat(value) {
  return value === "png" || value === "jpeg" || value === "gif";
}

// dist/src/HostWireBudget.js
var HOST_WIRE_MAX_RECORD_BYTES = 4194304, HOST_WIRE_MAX_GRID_DIMENSION = 1024, HOST_WIRE_MAX_GRID_CELLS = 65536;
function fitsUTF8(text, limit) {
  let bytes = 0;
  for (let scalar of text) {
    let code = scalar.codePointAt(0);
    if (bytes += code <= 127 ? 1 : code <= 2047 ? 2 : code <= 65535 ? 3 : 4, bytes > limit)
      return !1;
  }
  return !0;
}
function fitsWireGrid(width, height) {
  return Number.isInteger(width) && Number.isInteger(height) && width >= 0 && height >= 0 && width <= 1024 && height <= 1024 && width * height <= 65536;
}
function wireStyleLimit(width, height) {
  return Math.max(1024, width * height + 1);
}
function fitsStyleContent(style) {
  let remaining = 1024, chargeString = (text) => {
    for (let scalar of text) {
      let code = scalar.codePointAt(0);
      if (remaining -= code <= 127 ? 1 : code <= 2047 ? 2 : code <= 65535 ? 3 : 4, remaining < 0)
        return !1;
    }
    return !0;
  }, visit = (value) => {
    if (remaining -= 8, remaining < 0)
      return !1;
    if (typeof value === "string")
      return chargeString(value);
    if (Array.isArray(value))
      return value.every(visit);
    if (value !== null && typeof value === "object")
      return Object.entries(value).every(([key, item]) => chargeString(key) && visit(item));
    return !0;
  };
  return visit(style);
}
function fitsJSONDepth(text) {
  let depth = 0, quoted = !1, escaped = !1;
  for (let character of text)
    if (quoted) {
      if (escaped)
        escaped = !1;
      else if (character === "\\")
        escaped = !0;
      else if (character === '"')
        quoted = !1;
    } else if (character === '"')
      quoted = !0;
    else if (character === "[" || character === "{") {
      if (++depth > 32)
        return !1;
    } else if (character === "]" || character === "}")
      depth--;
  return !0;
}
function fitsSurfaceBudget(frame) {
  let { width, height } = frame;
  if (!fitsWireGrid(width, height))
    return !1;
  if (frame.styles.length + (frame.stylesBase ?? 0) > wireStyleLimit(width, height))
    return !1;
  if (!frame.styles.every(fitsStyleContent))
    return !1;
  if ((frame.rows?.length ?? 0) > height || (frame.deltaRows?.length ?? 0) > height)
    return !1;
  let validCells = (cells) => {
    if (cells.length > width)
      return !1;
    let end = 0;
    for (let [x, text, span, style] of cells) {
      if (!Number.isInteger(x) || !Number.isInteger(span) || x < end || span < 1 || x > width - span || !fitsUTF8(text, 256) || !Number.isInteger(style) || style < 0 || style >= frame.styles.length + (frame.stylesBase ?? 0))
        return !1;
      end = x + span;
    }
    return !0;
  };
  if (frame.rows && !frame.rows.every(validCells))
    return !1;
  let seen = /* @__PURE__ */ new Set;
  for (let [y, cells] of frame.deltaRows ?? []) {
    if (y < 0 || y >= height || seen.has(y) || !validCells(cells))
      return !1;
    seen.add(y);
  }
  if ((frame.images?.length ?? 0) > 1024)
    return !1;
  for (let image of frame.images ?? []) {
    if (!fitsUTF8(image.id, 1024))
      return !1;
    if (image.pixelSize) {
      let [w, h] = image.pixelSize;
      if (!Number.isInteger(w) || !Number.isInteger(h) || w < 0 || h < 0 || w > 8192 || h > 8192 || w * h > 16777216)
        return !1;
    }
  }
  let occupied = new Uint8Array(frame.paragraphs?.length ? width * height : 0);
  if ((frame.paragraphs?.length ?? 0) > width * height)
    return !1;
  for (let paragraph of frame.paragraphs ?? []) {
    if (!fitsUTF8(paragraph.id, 1024))
      return !1;
    let [x, y, w, h] = paragraph.rect;
    if (![
      x,
      y,
      w,
      h
    ].every(Number.isInteger) || x < 0 || y < 0 || w <= 0 || h <= 0 || x + w > width || y + h > height)
      return !1;
    for (let row = y;row < y + h; row++)
      for (let col = x;col < x + w; col++) {
        let index = row * width + col;
        if (occupied[index])
          return !1;
        occupied[index] = 1;
      }
  }
  for (let entries of [
    frame.accessibilityTree,
    frame.accessibilityAnnouncements,
    frame.scrollRegions,
    frame.linkTargets
  ])
    if ((entries?.length ?? 0) > 65536)
      return !1;
  for (let dimension of [frame.preferredGridWidth, frame.preferredGridHeight])
    if (dimension !== void 0 && dimension > 1024)
      return !1;
  if (!fitsWireGrid(frame.preferredGridWidth ?? 0, frame.preferredGridHeight ?? 0))
    return !1;
  if ((frame.links?.length ?? 0) > height || (frame.damage?.textRows.length ?? 0) > height)
    return !1;
  for (let rows of [frame.links, frame.damage?.textRows]) {
    let seenRows = /* @__PURE__ */ new Set;
    for (let [y, ranges] of rows ?? []) {
      if (!Number.isInteger(y) || y < 0 || y >= height || seenRows.has(y) || ranges.length > width)
        return !1;
      seenRows.add(y);
      let end = 0;
      for (let range of ranges) {
        let [start, lengthOrEnd] = range, stop = range.length === 3 ? start + lengthOrEnd : lengthOrEnd;
        if (!Number.isInteger(start) || !Number.isInteger(stop) || start < 0 || range.length === 3 && start < end || stop < start || stop > width)
          return !1;
        end = stop;
      }
    }
  }
  return !0;
}

// dist/src/HostGeometryProtocol.js
function isGeometryRevision(value, allowAcknowledgement = !1) {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= (allowAcknowledgement ? 0 : 1);
}
function isHostGeometryRequest(request) {
  return isGeometryRevision(request.revision) && (request.paragraphSpacing === void 0 || Number.isInteger(request.paragraphSpacing) && request.paragraphSpacing >= 0 && request.paragraphSpacing <= 8192) && request.columns > 0 && request.rows > 0 && fitsWireGrid(request.columns, request.rows) && [request.cellWidth, request.cellHeight].every((value) => Number.isInteger(value) && value > 0 && value <= 8192);
}
function encodeGeometryControlMessage(request) {
  if (!isHostGeometryRequest(request))
    throw RangeError("Invalid host geometry request");
  return (/* @__PURE__ */ new TextEncoder()).encode(`\x1Egeometry:${request.revision}:${request.columns}:${request.rows}:${request.cellWidth}:${request.cellHeight}${request.paragraphSpacing === void 0 ? "" : `:${request.paragraphSpacing}`}
`);
}

// dist/src/WebHostSurfaceTransport.js
function encodeAccessibilityActionMessage(target, request, requestID) {
  let value = request.action === "editText" || request.action === "selectText" ? `:text:${encodeURIComponent(request.text)}:${request.anchor}:${request.head}` : request.action === "setValue" ? `:${request.value.type}:${encodeURIComponent(String(request.value.value))}` : request.action === "custom" ? `:name:${encodeURIComponent(request.name)}` : "";
  return (/* @__PURE__ */ new TextEncoder()).encode(`\x1Eaccessibility:${requestID === void 0 ? "" : `${requestID}:`}${encodeURIComponent(target)}:${request.action}${value}
`);
}
var recordPrefix = "\x1E", textEncoder = /* @__PURE__ */ new TextEncoder;
function isWebHostImageRecoveryId(id) {
  return id.length > 0 && id.length <= 1024 && textEncoder.encode(id).byteLength <= 1024;
}
var WebHostOutputDecoder = class {
  textDecoder = /* @__PURE__ */ new TextDecoder;
  bufferedText = "";
  bufferedBytes = 0;
  discardingLine = !1;
  lastSurfaceFrame;
  lastEpoch;
  lastGen;
  lastPresentedEpoch;
  keyframeResyncOutstanding = !1;
  keyframeResyncPending = !1;
  imageResyncOutstandingIds = /* @__PURE__ */ new Set;
  imageResyncPendingIds = /* @__PURE__ */ new Set;
  feed(chunk) {
    let records = [], offset = 0;
    while (offset < chunk.length) {
      let newline = chunk.indexOf(10, offset), end = newline < 0 ? chunk.length : newline;
      if (!this.discardingLine)
        if (end - offset > 4194304 - this.bufferedBytes)
          this.bufferedText = "", this.bufferedBytes = 0, this.textDecoder.decode(), this.discardingLine = !0, records.push(this.refuseBudget());
        else
          this.bufferedBytes += end - offset, this.bufferedText += this.textDecoder.decode(chunk.subarray(offset, end), { stream: !0 });
      if (newline >= 0) {
        if (!this.discardingLine)
          this.bufferedText += this.textDecoder.decode(), records.push(this.decodeLine(this.bufferedText));
        this.bufferedText = "", this.bufferedBytes = 0, this.discardingLine = !1;
      }
      offset = end + 1;
    }
    if (this.bufferedText.length > 4096 && !this.bufferedText.startsWith(recordPrefix))
      records.push({
        type: "text",
        text: this.bufferedText
      }), this.bufferedText = "", this.bufferedBytes = 0;
    return records;
  }
  flush() {
    if (this.bufferedText += this.textDecoder.decode(), this.bufferedBytes = 0, this.discardingLine = !1, !this.bufferedText)
      return [];
    let text = this.bufferedText;
    return this.bufferedText = "", [this.decodeLine(text)];
  }
  rejectOversizedMessage() {
    return this.bufferedText = "", this.bufferedBytes = 0, this.discardingLine = !1, this.textDecoder.decode(), this.refuseBudget();
  }
  takeResyncRequest(maximumEncodedBytes) {
    if (this.keyframeResyncPending)
      return this.keyframeResyncPending = !1, { scope: "keyframe" };
    if (this.imageResyncPendingIds.size === 0)
      return;
    let { ids, rejectedIds } = boundedImageResyncIds([...this.imageResyncPendingIds].sort(), maximumEncodedBytes);
    for (let id of rejectedIds)
      this.imageResyncPendingIds.delete(id), this.imageResyncOutstandingIds.delete(id);
    for (let id of ids)
      this.imageResyncPendingIds.delete(id);
    if (ids.length === 0)
      return;
    return {
      scope: "images",
      ids
    };
  }
  requestImagePayloads(ids) {
    let acceptedIds = /* @__PURE__ */ new Set;
    for (let id of ids) {
      if (!isWebHostImageRecoveryId(id))
        continue;
      if (this.imageResyncOutstandingIds.has(id)) {
        acceptedIds.add(id);
        continue;
      }
      if (this.imageResyncOutstandingIds.size >= 1024)
        continue;
      this.imageResyncOutstandingIds.add(id), this.imageResyncPendingIds.add(id), acceptedIds.add(id);
    }
    return [...acceptedIds];
  }
  prepareToPresentSurface(frame) {
    let recoveredImagePayloadIds = this.recoveredImagePayloadIds(frame.images);
    if (this.resetImageResyncForEpoch(frame.epoch), this.sweepImageResyncForPresentedImages(frame.images), this.clearArrivedImagePayloads(frame.images), frame.epoch !== void 0)
      this.lastPresentedEpoch = frame.epoch;
    return recoveredImagePayloadIds;
  }
  resyncRequestDeliveryFailed(request) {
    if (request.scope === "keyframe") {
      if (this.keyframeResyncOutstanding)
        this.keyframeResyncPending = !0;
      return;
    }
    for (let id of request.ids ?? [])
      if (this.imageResyncOutstandingIds.has(id))
        this.imageResyncPendingIds.add(id);
  }
  decodeLine(line) {
    if (line.startsWith(recordPrefix) && !fitsJSONDepth(line))
      return this.refuseBudget();
    if (line.startsWith(`${recordPrefix}clipboard:`)) {
      try {
        let record = JSON.parse(line.slice(`${recordPrefix}clipboard:`.length));
        if (isWebHostClipboardRecord(record))
          return {
            type: "clipboard",
            text: record.text
          };
      } catch {}
      return {
        type: "text",
        text: `${line}
`
      };
    }
    if (line.startsWith(`${recordPrefix}runtimeIssue:`)) {
      try {
        let record = JSON.parse(line.slice(`${recordPrefix}runtimeIssue:`.length));
        if (isWebHostRuntimeIssue(record))
          return {
            type: "runtimeIssue",
            issue: record
          };
      } catch {}
      return {
        type: "text",
        text: `${line}
`
      };
    }
    if (line.startsWith(`${recordPrefix}frameDiagnostic:`)) {
      try {
        let record = JSON.parse(line.slice(`${recordPrefix}frameDiagnostic:`.length));
        if (isWebHostFrameDiagnosticRecord(record))
          return {
            type: "frameDiagnostic",
            diagnostic: record
          };
      } catch {}
      return {
        type: "text",
        text: `${line}
`
      };
    }
    if (!line.startsWith(`${recordPrefix}surface:`))
      return {
        type: "text",
        text: `${line}
`
      };
    try {
      let frame = JSON.parse(line.slice(`${recordPrefix}surface:`.length));
      if (declaresNewerSurfaceVersion(frame))
        return {
          type: "runtimeIssue",
          issue: {
            severity: "error",
            code: "surface.unsupportedVersion",
            message: `SwiftTUI surface version ${frame.version} is newer than the supported 3`,
            description: `The app emitted a surface record with version ${frame.version}, but this @swifttui/web runtime understands versions up to 3. Update @swifttui/web to render it.`
          }
        };
      if (isWebHostSurfaceFrame(frame)) {
        if (!fitsSurfaceBudget(frame))
          return this.refuseBudget();
        return this.lastSurfaceFrame = frame, this.lastEpoch = frame.epoch, this.lastGen = frame.gen, this.keyframeResyncOutstanding = !1, this.keyframeResyncPending = !1, {
          type: "surface",
          frame
        };
      }
      if (isWebHostSurfaceDeltaFrame(frame)) {
        if (!fitsSurfaceBudget(frame))
          return this.refuseBudget();
        let carriesDeliveryStamps = frame.epoch !== void 0 || frame.gen !== void 0 || frame.baselineGen !== void 0;
        if (!this.lastSurfaceFrame || this.lastSurfaceFrame.width !== frame.width || this.lastSurfaceFrame.height !== frame.height) {
          if (carriesDeliveryStamps)
            this.requestKeyframeResync();
          return {
            type: "surfaceDropped",
            reason: "noBaseline"
          };
        }
        if (carriesDeliveryStamps && (frame.epoch === void 0 || frame.gen === void 0 || frame.baselineGen === void 0 || frame.epoch !== this.lastEpoch || frame.baselineGen !== this.lastGen))
          return this.requestKeyframeResync(), {
            type: "surfaceDropped",
            reason: "staleBaseline"
          };
        let materialized = this.materializeDeltaFrame(frame);
        if (materialized)
          return this.lastSurfaceFrame = materialized, this.lastEpoch = frame.epoch, this.lastGen = frame.gen, {
            type: "surface",
            frame: materialized
          };
        this.requestKeyframeResync();
      }
    } catch {}
    return {
      type: "text",
      text: `${line}
`
    };
  }
  requestKeyframeResync() {
    if (this.keyframeResyncOutstanding)
      return;
    this.keyframeResyncOutstanding = !0, this.keyframeResyncPending = !0;
  }
  refuseBudget() {
    return this.requestKeyframeResync(), {
      type: "surfaceDropped",
      reason: "budgetExceeded"
    };
  }
  resetImageResyncForEpoch(epoch) {
    if (epoch === void 0 || epoch === this.lastPresentedEpoch)
      return;
    this.imageResyncOutstandingIds.clear(), this.imageResyncPendingIds.clear();
  }
  clearArrivedImagePayloads(images) {
    for (let image of images ?? []) {
      if (image.dataBase64 === void 0)
        continue;
      this.imageResyncOutstandingIds.delete(image.id), this.imageResyncPendingIds.delete(image.id);
    }
  }
  recoveredImagePayloadIds(images) {
    let recoveredIds = /* @__PURE__ */ new Set;
    for (let image of images ?? [])
      if (image.dataBase64 !== void 0 && this.imageResyncOutstandingIds.has(image.id))
        recoveredIds.add(image.id);
    return [...recoveredIds].sort();
  }
  sweepImageResyncForPresentedImages(images) {
    let presentedIds = /* @__PURE__ */ new Set;
    for (let image of images ?? [])
      if (this.imageResyncOutstandingIds.has(image.id))
        presentedIds.add(image.id);
    for (let id of this.imageResyncOutstandingIds) {
      if (presentedIds.has(id))
        continue;
      this.imageResyncOutstandingIds.delete(id), this.imageResyncPendingIds.delete(id);
    }
  }
  materializeDeltaFrame(frame) {
    let baseline = this.lastSurfaceFrame;
    if (!baseline)
      return;
    let styles = this.materializeDeltaStyles(frame, baseline);
    if (!styles)
      return;
    let rows = baseline.rows.slice();
    for (let [row, cells] of frame.deltaRows) {
      if (!Number.isSafeInteger(row) || row < 0 || row >= frame.height)
        return;
      rows[row] = cells;
    }
    return {
      version: baseline.version,
      epoch: frame.epoch,
      gen: frame.gen,
      sequence: frame.sequence,
      geometryRevision: frame.geometryRevision,
      viewportRevision: frame.viewportRevision,
      width: frame.width,
      height: frame.height,
      styles,
      rows,
      images: frame.images,
      damage: frame.damage,
      accessibilityTree: frame.accessibilityTree,
      accessibilityActionResponse: frame.accessibilityActionResponse,
      accessibilityFocusRequest: frame.accessibilityFocusRequest,
      accessibilityAnnouncements: frame.accessibilityAnnouncements,
      scrollRegions: frame.scrollRegions,
      paragraphs: frame.paragraphs,
      links: frame.links,
      linkTargets: frame.linkTargets,
      focusPresentation: frame.focusPresentation,
      preferredGridWidth: frame.preferredGridWidth,
      preferredGridHeight: frame.preferredGridHeight
    };
  }
  materializeDeltaStyles(frame, baseline) {
    if (frame.stylesBase === void 0)
      return frame.styles;
    if (frame.stylesBase !== baseline.styles.length)
      return;
    return baseline.styles.concat(frame.styles);
  }
};
function boundedImageResyncIds(sortedIds, maximumEncodedBytes) {
  if (maximumEncodedBytes === void 0 || !Number.isFinite(maximumEncodedBytes))
    return {
      ids: sortedIds,
      rejectedIds: []
    };
  let emptyRequestBytes = encodeResyncControlMessage({
    scope: "images",
    ids: []
  }).byteLength, normalizedMaximum = Math.max(0, Math.floor(maximumEncodedBytes)), ids = [], rejectedIds = [], encodedBytes = emptyRequestBytes;
  for (let id of sortedIds) {
    let separatorBytes = ids.length === 0 ? 0 : 1, idBytes = textEncoder.encode(JSON.stringify(id)).byteLength;
    if (encodedBytes + separatorBytes + idBytes > normalizedMaximum) {
      if (ids.length === 0) {
        rejectedIds.push(id);
        continue;
      }
      break;
    }
    if (ids.push(id), encodedBytes += separatorBytes + idBytes, encodedBytes >= normalizedMaximum)
      break;
  }
  return {
    ids,
    rejectedIds
  };
}
function declaresNewerSurfaceVersion(value) {
  if (!value || typeof value !== "object")
    return !1;
  let version = value.version;
  return typeof version === "number" && Number.isSafeInteger(version) && version > 3;
}
function isWebHostClipboardRecord(value) {
  return !!value && typeof value === "object" && typeof value.text === "string";
}
function isWebHostRuntimeIssue(value) {
  if (!value || typeof value !== "object")
    return !1;
  let record = value;
  return (record.severity === "warning" || record.severity === "error") && typeof record.code === "string" && typeof record.message === "string" && typeof record.description === "string" && (record.identity === void 0 || typeof record.identity === "string") && (record.source === void 0 || typeof record.source === "string");
}
function isWebHostFrameDiagnosticRecord(value) {
  if (!value || typeof value !== "object")
    return !1;
  let record = value;
  return record.format === "swift-tui-frame-diagnostics-v1" && Array.isArray(record.header) && record.header.every((field) => typeof field === "string") && Array.isArray(record.fields) && record.fields.every((field) => typeof field === "string");
}
function encodeResizeControlMessage(columns, rows, cellWidth, cellHeight) {
  let normalizedColumns = Math.max(1, Math.round(columns)), normalizedRows = Math.max(1, Math.round(rows));
  if (cellWidth && cellHeight)
    return textEncoder.encode(`${recordPrefix}resize:${normalizedColumns}:${normalizedRows}:${Math.max(1, Math.round(cellWidth))}:${Math.max(1, Math.round(cellHeight))}
`);
  return textEncoder.encode(`${recordPrefix}resize:${normalizedColumns}:${normalizedRows}
`);
}
function encodeRenderStyleControlMessage(style) {
  let encoded = encodeWebHostTerminalRenderStyleBase64(style);
  return textEncoder.encode(`${recordPrefix}style:${encoded}
`);
}
function encodeCapabilitiesControlMessage() {
  return textEncoder.encode(`${recordPrefix}caps:{"acceptsDeltaFrames":true,"styleAppend":true,"geometryRevisions":true,"sharedViewport":true}
`);
}
function encodePointerCapabilitiesControlMessage(supportsScrollPanning) {
  return textEncoder.encode(`${recordPrefix}pointer:panning=${supportsScrollPanning ? 1 : 0}
`);
}
function encodeResyncControlMessage(request) {
  let payload = request.scope === "keyframe" ? { scope: "keyframe" } : {
    scope: "images",
    ...request.ids === void 0 ? {} : { ids: request.ids }
  };
  return textEncoder.encode(`${recordPrefix}resync:${JSON.stringify(payload)}
`);
}
function encodeKeyInputMessage(input) {
  let modifiers = Math.max(0, Math.round(input.modifiers ?? 0));
  if (input.key === "character")
    return textEncoder.encode(`${recordPrefix}key:character:${encodeURIComponent(input.character ?? "")}:${modifiers}
`);
  return textEncoder.encode(`${recordPrefix}key:${input.key}:${modifiers}
`);
}
function encodePasteInputMessage(text) {
  return textEncoder.encode(`${recordPrefix}paste:${encodeURIComponent(text)}
`);
}
function encodeMouseInputMessage(input, geometryRevision, viewportRevision) {
  if (viewportRevision !== void 0 && (!isGeometryRevision(viewportRevision) || geometryRevision === void 0 || !isGeometryRevision(geometryRevision, !0)))
    throw RangeError("Invalid shared viewport pointer revision");
  if (viewportRevision === void 0 && geometryRevision !== void 0 && !isGeometryRevision(geometryRevision))
    throw RangeError("Invalid pointer geometry revision");
  return textEncoder.encode(recordPrefix + [
    ...viewportRevision !== void 0 ? [
      "mouseViewport",
      geometryRevision,
      viewportRevision
    ] : geometryRevision === void 0 ? ["mouse"] : ["mouseGeometry", geometryRevision],
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
  if (!value || typeof value !== "object")
    return !1;
  let frame = value;
  return (frame.version === 1 || frame.version === 2) && (frame.sequence === void 0 || Number.isSafeInteger(frame.sequence) && frame.sequence >= 0) && isSurfaceGridDimension(frame.width) && isSurfaceGridDimension(frame.height) && Array.isArray(frame.styles) && Array.isArray(frame.rows) && frame.rows.every(isWebHostSurfaceRow) && (frame.images === void 0 || isWebHostSurfaceImages(frame.images)) && (frame.damage === void 0 || isWebHostSurfaceDamage(frame.damage)) && (frame.accessibilityActionResponse === void 0 || isAccessibilityActionResponse(frame.accessibilityActionResponse)) && (frame.accessibilityTree === void 0 || isWebHostAccessibilityNodes(frame.accessibilityTree)) && (frame.accessibilityAnnouncements === void 0 || isWebHostAccessibilityAnnouncements(frame.accessibilityAnnouncements)) && (frame.scrollRegions === void 0 || isWebHostScrollRegions(frame.scrollRegions)) && (frame.paragraphs === void 0 || isWebHostParagraphs(frame.paragraphs)) && hasValidAdditiveFrameFields(frame);
}
function isWebHostSurfaceDeltaFrame(value) {
  if (!value || typeof value !== "object")
    return !1;
  let frame = value;
  return frame.version === 3 && frame.encoding === "delta" && (frame.sequence === void 0 || Number.isSafeInteger(frame.sequence) && frame.sequence >= 0) && isSurfaceGridDimension(frame.width) && isSurfaceGridDimension(frame.height) && Array.isArray(frame.styles) && Array.isArray(frame.deltaRows) && frame.deltaRows.every(isWebHostSurfaceDeltaRow) && isOptionalSafeInteger(frame.baselineGen) && isOptionalSafeInteger(frame.stylesBase) && (frame.images === void 0 || isWebHostSurfaceImages(frame.images)) && (frame.damage === void 0 || isWebHostSurfaceDamage(frame.damage)) && (frame.accessibilityActionResponse === void 0 || isAccessibilityActionResponse(frame.accessibilityActionResponse)) && (frame.accessibilityTree === void 0 || isWebHostAccessibilityNodes(frame.accessibilityTree)) && (frame.accessibilityAnnouncements === void 0 || isWebHostAccessibilityAnnouncements(frame.accessibilityAnnouncements)) && (frame.scrollRegions === void 0 || isWebHostScrollRegions(frame.scrollRegions)) && (frame.paragraphs === void 0 || isWebHostParagraphs(frame.paragraphs)) && hasValidAdditiveFrameFields(frame);
}
function isSurfaceGridDimension(value) {
  return typeof value === "number" && Number.isInteger(value) && value >= 0 && value <= 2147483647;
}
function hasValidAdditiveFrameFields(frame) {
  return (frame.accessibilityFocusRequest === void 0 || isAccessibilityFocusPresentation(frame.accessibilityFocusRequest)) && isOptionalSafeInteger(frame.epoch) && isOptionalSafeInteger(frame.gen) && (frame.geometryRevision === void 0 || isGeometryRevision(frame.geometryRevision, !0)) && (frame.viewportRevision === void 0 || isGeometryRevision(frame.viewportRevision) && frame.geometryRevision !== void 0) && (frame.links === void 0 || isWebHostSurfaceLinks(frame.links)) && (frame.linkTargets === void 0 || isWebHostSurfaceLinkTargets(frame.linkTargets)) && (frame.focusPresentation === void 0 || isWebHostFocusPresentation(frame.focusPresentation)) && (frame.preferredGridWidth === void 0 || Number.isSafeInteger(frame.preferredGridWidth) && frame.preferredGridWidth >= 0) && (frame.preferredGridHeight === void 0 || Number.isSafeInteger(frame.preferredGridHeight) && frame.preferredGridHeight >= 0);
}
function isAccessibilityFocusPresentation(value) {
  if (!value || typeof value !== "object" || Array.isArray(value))
    return !1;
  let request = value;
  return typeof request.generation === "string" && /^(0|[1-9][0-9]{0,19})$/.test(request.generation) && BigInt(request.generation) <= 18446744073709551615n && (request.target === void 0 || typeof request.target === "string");
}
function isOptionalSafeInteger(value) {
  return value === void 0 || Number.isSafeInteger(value);
}
function isWebHostSurfaceLinks(value) {
  return Array.isArray(value) && value.every(isWebHostSurfaceLinkRow);
}
function isWebHostSurfaceLinkRow(value) {
  return Array.isArray(value) && value.length === 2 && Number.isSafeInteger(value[0]) && value[0] >= 0 && Array.isArray(value[1]) && value[1].every(isWebHostSurfaceLinkRun);
}
function isWebHostSurfaceLinkRun(value) {
  if (!Array.isArray(value) || value.length !== 3)
    return !1;
  let [x, span, targetIndex] = value;
  return Number.isSafeInteger(x) && x >= 0 && Number.isSafeInteger(span) && span >= 1 && Number.isSafeInteger(targetIndex) && targetIndex >= 0;
}
function isWebHostSurfaceLinkTargets(value) {
  return Array.isArray(value) && value.every((entry) => typeof entry === "string");
}
function isWebHostFocusPresentation(value) {
  if (!value || typeof value !== "object")
    return !1;
  let presentation = value;
  return (presentation.focusedIdentity === void 0 || typeof presentation.focusedIdentity === "string") && typeof presentation.semantics === "string" && typeof presentation.prefersTextInput === "boolean" && typeof presentation.hasFocusedRegion === "boolean";
}
function isWebHostSurfaceDeltaRow(value) {
  return Array.isArray(value) && value.length === 2 && Number.isSafeInteger(value[0]) && value[0] >= 0 && isWebHostSurfaceRow(value[1]);
}
function isWebHostSurfaceRow(value) {
  return Array.isArray(value) && value.every(isWebHostSurfaceCell);
}
function isWebHostSurfaceCell(value) {
  return Array.isArray(value) && value.length === 4 && Number.isSafeInteger(value[0]) && value[0] >= 0 && typeof value[1] === "string" && Number.isSafeInteger(value[2]) && value[2] >= 1 && Number.isSafeInteger(value[3]) && value[3] >= 0;
}
function isWebHostAccessibilityNodes(value) {
  return Array.isArray(value) && value.every(isWebHostAccessibilityNode);
}
function isWebHostAccessibilityNode(value) {
  if (!value || typeof value !== "object")
    return !1;
  let node = value;
  return (node.opensLink === void 0 || typeof node.opensLink === "boolean") && (node.customActions === void 0 || Array.isArray(node.customActions) && node.customActions.length <= 65536 && node.customActions.every((name) => typeof name === "string" && name.trim().length > 0) && new Set(node.customActions).size === node.customActions.length) && (node.selection === void 0 || isAccessibilitySelection(node.selection)) && (node.textSelection === void 0 || Array.isArray(node.textSelection) && node.textSelection.length === 2 && node.textSelection.every((offset) => Number.isSafeInteger(offset) && offset >= 0)) && (node.properties === void 0 || isAccessibilityProperties(node.properties)) && typeof node.id === "string" && (node.parentId === void 0 || typeof node.parentId === "string") && isWebHostSurfaceRect(node.rect) && typeof node.role === "string" && (node.label === void 0 || typeof node.label === "string") && (node.hint === void 0 || typeof node.hint === "string") && (node.hidden === void 0 || typeof node.hidden === "boolean") && (node.liveRegion === void 0 || typeof node.liveRegion === "string") && (node.cursorAnchor === void 0 || isWebHostAccessibilityPoint(node.cursorAnchor)) && (node.isFocused === void 0 || typeof node.isFocused === "boolean") && (node.isAccessibilityFocused === void 0 || typeof node.isAccessibilityFocused === "boolean") && (node.navigationCategories === void 0 || Array.isArray(node.navigationCategories) && node.navigationCategories.length <= 65536 && node.navigationCategories.every((name) => typeof name === "string" && name.trim().length > 0) && new Set(node.navigationCategories).size === node.navigationCategories.length) && (node.actionTarget === void 0 || typeof node.actionTarget === "string") && (node.actions === void 0 || Array.isArray(node.actions) && node.actions.every((action) => typeof action === "string")) && (node.isEnabled === void 0 || typeof node.isEnabled === "boolean") && (node.value === void 0 || isAccessibilityValue(node.value)) && [
    node.valueMin,
    node.valueMax,
    node.valueStep
  ].every((value2) => value2 === void 0 || typeof value2 === "number" && Number.isFinite(value2));
}
function isAccessibilitySelection(value) {
  if (!value || typeof value !== "object" || Array.isArray(value))
    return !1;
  let selection = value;
  if (![
    "menu",
    "list",
    "radioGroup",
    "segmented"
  ].includes(selection.presentation) || !Array.isArray(selection.options) || selection.options.length > 65536)
    return !1;
  let ids = /* @__PURE__ */ new Set;
  return selection.options.every((option) => {
    if (!option || typeof option !== "object" || typeof option.id !== "string" || option.id === "" || ids.has(option.id) || typeof option.label !== "string" || typeof option.isEnabled !== "boolean" || option.rect !== void 0 && (!isWebHostSurfaceRect(option.rect) || !option.rect.every(Number.isFinite) || option.rect[2] <= 0 || option.rect[3] <= 0))
      return !1;
    return ids.add(option.id), !0;
  });
}
function isAccessibilityProperties(value) {
  if (!value || typeof value !== "object" || Array.isArray(value))
    return !1;
  let properties = value;
  return (properties.selected === void 0 || typeof properties.selected === "boolean") && (properties.expanded === void 0 || typeof properties.expanded === "boolean") && (properties.popup === void 0 || [
    "menu",
    "listbox",
    "tree",
    "grid",
    "dialog"
  ].includes(properties.popup)) && (properties.modal === void 0 || typeof properties.modal === "boolean") && (properties.required === void 0 || typeof properties.required === "boolean") && (properties.invalid === void 0 || typeof properties.invalid === "boolean") && (properties.busy === void 0 || typeof properties.busy === "boolean") && (properties.readOnly === void 0 || typeof properties.readOnly === "boolean") && (properties.description === void 0 || typeof properties.description === "string") && (properties.valueDescription === void 0 || typeof properties.valueDescription === "string") && (properties.language === void 0 || typeof properties.language === "string") && (properties.headingLevel === void 0 || Number.isSafeInteger(properties.headingLevel) && properties.headingLevel > 0) && (properties.level === void 0 || Number.isSafeInteger(properties.level) && properties.level > 0) && (properties.positionInSet === void 0 || Number.isSafeInteger(properties.positionInSet) && properties.positionInSet > 0) && (properties.setSize === void 0 || Number.isSafeInteger(properties.setSize) && (properties.setSize === -1 || properties.setSize >= 0)) && (properties.rowIndex === void 0 || Number.isSafeInteger(properties.rowIndex) && properties.rowIndex > 0) && (properties.columnIndex === void 0 || Number.isSafeInteger(properties.columnIndex) && properties.columnIndex > 0) && (properties.rowCount === void 0 || Number.isSafeInteger(properties.rowCount) && (properties.rowCount === -1 || properties.rowCount >= 0)) && (properties.columnCount === void 0 || Number.isSafeInteger(properties.columnCount) && (properties.columnCount === -1 || properties.columnCount >= 0)) && (properties.rowSpan === void 0 || Number.isSafeInteger(properties.rowSpan) && properties.rowSpan > 0) && (properties.columnSpan === void 0 || Number.isSafeInteger(properties.columnSpan) && properties.columnSpan > 0) && (properties.textKind === void 0 || [
    "plain",
    "paragraph",
    "code",
    "quotation"
  ].includes(properties.textKind)) && (properties.sort === void 0 || [
    "none",
    "ascending",
    "descending",
    "other"
  ].includes(properties.sort)) && (properties.labelledBy === void 0 || Array.isArray(properties.labelledBy) && properties.labelledBy.every((id) => typeof id === "string")) && (properties.describedBy === void 0 || Array.isArray(properties.describedBy) && properties.describedBy.every((id) => typeof id === "string")) && (properties.errorMessage === void 0 || Array.isArray(properties.errorMessage) && properties.errorMessage.every((id) => typeof id === "string")) && (properties.controls === void 0 || Array.isArray(properties.controls) && properties.controls.every((id) => typeof id === "string")) && (properties.owns === void 0 || Array.isArray(properties.owns) && properties.owns.every((id) => typeof id === "string")) && (properties.flowTo === void 0 || Array.isArray(properties.flowTo) && properties.flowTo.every((id) => typeof id === "string")) && (properties.activeDescendant === void 0 || typeof properties.activeDescendant === "string");
}
function isAccessibilityActionResponse(value) {
  if (!value || typeof value !== "object")
    return !1;
  let response = value;
  return typeof response.requestID === "string" && /^[0-9]{1,20}$/.test(response.requestID) && typeof response.target === "string" && typeof response.result === "string" && [
    "accepted",
    "staleTarget",
    "disabled",
    "outOfScope",
    "unsupported",
    "invalidValue"
  ].includes(response.result);
}
function isAccessibilityValue(value) {
  if (!value || typeof value !== "object")
    return !1;
  let candidate = value;
  switch (candidate.type) {
    case "text":
      return typeof candidate.value === "string";
    case "boolean":
      return typeof candidate.value === "boolean";
    case "number":
      return typeof candidate.value === "number" && Number.isFinite(candidate.value);
    default:
      return !1;
  }
}
function isWebHostAccessibilityPoint(value) {
  return Array.isArray(value) && value.length === 2 && value.every((entry) => typeof entry === "number");
}
function isWebHostAccessibilityAnnouncements(value) {
  return Array.isArray(value) && value.every(isWebHostAccessibilityAnnouncement);
}
function isWebHostAccessibilityAnnouncement(value) {
  if (!value || typeof value !== "object")
    return !1;
  let announcement = value;
  return typeof announcement.message === "string" && typeof announcement.politeness === "string";
}
function isWebHostSurfaceImages(value) {
  return Array.isArray(value) && value.every(isWebHostSurfaceImage);
}
function isWebHostSurfaceImage(value) {
  if (!value || typeof value !== "object")
    return !1;
  let image = value;
  return typeof image.id === "string" && isWebHostSurfaceImageFormat(image.format) && isWebHostSurfaceRect(image.bounds) && isWebHostSurfaceRect(image.visibleBounds) && isWebHostSurfaceScalingMode(image.scalingMode) && (image.opacity === void 0 || typeof image.opacity === "number" && Number.isFinite(image.opacity)) && (image.pixelSize === void 0 || isWebHostSurfaceSize(image.pixelSize)) && (image.dataBase64 === void 0 || typeof image.dataBase64 === "string");
}
function isWebHostSurfaceDamage(value) {
  if (!value || typeof value !== "object")
    return !1;
  let damage = value;
  return Array.isArray(damage.textRows) && damage.textRows.every(isWebHostSurfaceDamageTextRow) && typeof damage.requiresFullTextRepaint === "boolean" && typeof damage.requiresFullGraphicsReplay === "boolean";
}
function isWebHostSurfaceDamageTextRow(value) {
  return Array.isArray(value) && value.length === 2 && typeof value[0] === "number" && Array.isArray(value[1]) && value[1].every(isWebHostSurfaceDamageRange);
}
function isWebHostSurfaceDamageRange(value) {
  return Array.isArray(value) && value.length === 2 && typeof value[0] === "number" && typeof value[1] === "number";
}
function isWebHostSurfaceImageFormat(value) {
  return typeof value === "string";
}
function isWebHostParagraphs(value) {
  if (!Array.isArray(value))
    return !1;
  let ids = /* @__PURE__ */ new Set;
  return value.every((item) => {
    if (!item || typeof item !== "object" || typeof item.id !== "string" || ids.has(item.id) || !isWebHostSurfaceRect(item.rect))
      return !1;
    return ids.add(item.id), !0;
  });
}
function isWebHostScrollRegions(value) {
  return Array.isArray(value) && value.every(isWebHostScrollRegion);
}
function isWebHostScrollRegion(value) {
  if (!value || typeof value !== "object")
    return !1;
  let region = value;
  return typeof region.id === "string" && isWebHostSurfaceRect(region.rect) && isWebHostSurfaceSize(region.offset) && isWebHostSurfaceSize(region.content);
}
function isWebHostSurfaceRect(value) {
  return Array.isArray(value) && value.length === 4 && value.every((entry) => typeof entry === "number");
}
function isWebHostSurfaceSize(value) {
  return Array.isArray(value) && value.length === 2 && value.every((entry) => typeof entry === "number");
}
function isWebHostSurfaceScalingMode(value) {
  return typeof value === "string";
}

// dist/src/GlyphGeometry.js
var lineSpecs = {
  9472: [
    0,
    1,
    0,
    1
  ],
  9473: [
    0,
    2,
    0,
    2
  ],
  9474: [
    1,
    0,
    1,
    0
  ],
  9475: [
    2,
    0,
    2,
    0
  ],
  9484: [
    0,
    1,
    1,
    0
  ],
  9485: [
    0,
    2,
    1,
    0
  ],
  9486: [
    0,
    1,
    2,
    0
  ],
  9487: [
    0,
    2,
    2,
    0
  ],
  9488: [
    0,
    0,
    1,
    1
  ],
  9489: [
    0,
    0,
    1,
    2
  ],
  9490: [
    0,
    0,
    2,
    1
  ],
  9491: [
    0,
    0,
    2,
    2
  ],
  9492: [
    1,
    1,
    0,
    0
  ],
  9493: [
    1,
    2,
    0,
    0
  ],
  9494: [
    2,
    1,
    0,
    0
  ],
  9495: [
    2,
    2,
    0,
    0
  ],
  9496: [
    1,
    0,
    0,
    1
  ],
  9497: [
    1,
    0,
    0,
    2
  ],
  9498: [
    2,
    0,
    0,
    1
  ],
  9499: [
    2,
    0,
    0,
    2
  ],
  9500: [
    1,
    1,
    1,
    0
  ],
  9501: [
    1,
    2,
    1,
    0
  ],
  9502: [
    2,
    1,
    1,
    0
  ],
  9503: [
    1,
    1,
    2,
    0
  ],
  9504: [
    2,
    1,
    2,
    0
  ],
  9505: [
    2,
    2,
    1,
    0
  ],
  9506: [
    1,
    2,
    2,
    0
  ],
  9507: [
    2,
    2,
    2,
    0
  ],
  9508: [
    1,
    0,
    1,
    1
  ],
  9509: [
    1,
    0,
    1,
    2
  ],
  9510: [
    2,
    0,
    1,
    1
  ],
  9511: [
    1,
    0,
    2,
    1
  ],
  9512: [
    2,
    0,
    2,
    1
  ],
  9513: [
    2,
    0,
    1,
    2
  ],
  9514: [
    1,
    0,
    2,
    2
  ],
  9515: [
    2,
    0,
    2,
    2
  ],
  9516: [
    0,
    1,
    1,
    1
  ],
  9517: [
    0,
    1,
    1,
    2
  ],
  9518: [
    0,
    2,
    1,
    1
  ],
  9519: [
    0,
    2,
    1,
    2
  ],
  9520: [
    0,
    1,
    2,
    1
  ],
  9521: [
    0,
    1,
    2,
    2
  ],
  9522: [
    0,
    2,
    2,
    1
  ],
  9523: [
    0,
    2,
    2,
    2
  ],
  9524: [
    1,
    1,
    0,
    1
  ],
  9525: [
    1,
    1,
    0,
    2
  ],
  9526: [
    1,
    2,
    0,
    1
  ],
  9527: [
    1,
    2,
    0,
    2
  ],
  9528: [
    2,
    1,
    0,
    1
  ],
  9529: [
    2,
    1,
    0,
    2
  ],
  9530: [
    2,
    2,
    0,
    1
  ],
  9531: [
    2,
    2,
    0,
    2
  ],
  9532: [
    1,
    1,
    1,
    1
  ],
  9533: [
    1,
    1,
    1,
    2
  ],
  9534: [
    1,
    2,
    1,
    1
  ],
  9535: [
    1,
    2,
    1,
    2
  ],
  9536: [
    2,
    1,
    1,
    1
  ],
  9537: [
    1,
    1,
    2,
    1
  ],
  9538: [
    2,
    1,
    2,
    1
  ],
  9539: [
    2,
    1,
    1,
    2
  ],
  9540: [
    2,
    2,
    1,
    1
  ],
  9541: [
    1,
    1,
    2,
    2
  ],
  9542: [
    1,
    2,
    2,
    1
  ],
  9543: [
    2,
    2,
    1,
    2
  ],
  9544: [
    1,
    2,
    2,
    2
  ],
  9545: [
    2,
    1,
    2,
    2
  ],
  9546: [
    2,
    2,
    2,
    1
  ],
  9547: [
    2,
    2,
    2,
    2
  ],
  9552: [
    0,
    3,
    0,
    3
  ],
  9553: [
    3,
    0,
    3,
    0
  ],
  9554: [
    0,
    3,
    1,
    0
  ],
  9555: [
    0,
    1,
    3,
    0
  ],
  9556: [
    0,
    3,
    3,
    0
  ],
  9557: [
    0,
    0,
    1,
    3
  ],
  9558: [
    0,
    0,
    3,
    1
  ],
  9559: [
    0,
    0,
    3,
    3
  ],
  9560: [
    1,
    3,
    0,
    0
  ],
  9561: [
    3,
    1,
    0,
    0
  ],
  9562: [
    3,
    3,
    0,
    0
  ],
  9563: [
    1,
    0,
    0,
    3
  ],
  9564: [
    3,
    0,
    0,
    1
  ],
  9565: [
    3,
    0,
    0,
    3
  ],
  9566: [
    1,
    3,
    1,
    0
  ],
  9567: [
    3,
    1,
    3,
    0
  ],
  9568: [
    3,
    3,
    3,
    0
  ],
  9569: [
    1,
    0,
    1,
    3
  ],
  9570: [
    3,
    0,
    3,
    1
  ],
  9571: [
    3,
    0,
    3,
    3
  ],
  9572: [
    0,
    3,
    1,
    3
  ],
  9573: [
    0,
    1,
    3,
    1
  ],
  9574: [
    0,
    3,
    3,
    3
  ],
  9575: [
    1,
    3,
    0,
    3
  ],
  9576: [
    3,
    1,
    0,
    1
  ],
  9577: [
    3,
    3,
    0,
    3
  ],
  9578: [
    1,
    3,
    1,
    3
  ],
  9579: [
    3,
    1,
    3,
    1
  ],
  9580: [
    3,
    3,
    3,
    3
  ],
  9588: [
    0,
    0,
    0,
    1
  ],
  9589: [
    1,
    0,
    0,
    0
  ],
  9590: [
    0,
    1,
    0,
    0
  ],
  9591: [
    0,
    0,
    1,
    0
  ],
  9592: [
    0,
    0,
    0,
    2
  ],
  9593: [
    2,
    0,
    0,
    0
  ],
  9594: [
    0,
    2,
    0,
    0
  ],
  9595: [
    0,
    0,
    2,
    0
  ],
  9596: [
    0,
    2,
    0,
    1
  ],
  9597: [
    1,
    0,
    2,
    0
  ],
  9598: [
    0,
    1,
    0,
    2
  ],
  9599: [
    2,
    0,
    1,
    0
  ]
};
function canRenderGeometricGlyph(text) {
  let codePoint = singleCodePoint(text);
  if (codePoint === void 0)
    return !1;
  return codePoint >= 9472 && codePoint <= 9631 || codePoint >= 10240 && codePoint <= 10495;
}
function emitGlyphGeometry(context, text, rect) {
  let codePoint = singleCodePoint(text);
  if (codePoint === void 0)
    return !1;
  if (codePoint >= 9472 && codePoint <= 9599)
    return drawBoxDrawingCodePoint(context, codePoint, rect);
  if (codePoint >= 9600 && codePoint <= 9631)
    return drawBlockElement(context, codePoint, rect);
  if (codePoint >= 10240 && codePoint <= 10495)
    return drawBraille(context, codePoint, rect);
  return !1;
}
function singleCodePoint(text) {
  let characters = Array.from(text);
  if (characters.length !== 1)
    return;
  return characters[0]?.codePointAt(0);
}
function drawBoxDrawingCodePoint(context, codePoint, rect) {
  let spec = lineSpecs[codePoint];
  if (spec)
    return drawCellLines(context, spec, rect), !0;
  switch (codePoint) {
    case 9476:
      return drawDashedHorizontal(context, rect, 1, 3), !0;
    case 9477:
      return drawDashedHorizontal(context, rect, 2, 3), !0;
    case 9478:
      return drawDashedVertical(context, rect, 1, 3), !0;
    case 9479:
      return drawDashedVertical(context, rect, 2, 3), !0;
    case 9480:
      return drawDashedHorizontal(context, rect, 1, 4), !0;
    case 9481:
      return drawDashedHorizontal(context, rect, 2, 4), !0;
    case 9482:
      return drawDashedVertical(context, rect, 1, 4), !0;
    case 9483:
      return drawDashedVertical(context, rect, 2, 4), !0;
    case 9548:
      return drawDashedHorizontal(context, rect, 1, 2), !0;
    case 9549:
      return drawDashedHorizontal(context, rect, 2, 2), !0;
    case 9550:
      return drawDashedVertical(context, rect, 1, 2), !0;
    case 9551:
      return drawDashedVertical(context, rect, 2, 2), !0;
    case 9585:
      return drawDiagonal(context, rect, !1), !0;
    case 9586:
      return drawDiagonal(context, rect, !0), !0;
    case 9587:
      return drawDiagonal(context, rect, !1), drawDiagonal(context, rect, !0), !0;
    case 9581:
      return drawArc(context, rect, "topLeft"), !0;
    case 9582:
      return drawArc(context, rect, "topRight"), !0;
    case 9583:
      return drawArc(context, rect, "bottomRight"), !0;
    case 9584:
      return drawArc(context, rect, "bottomLeft"), !0;
    default:
      return !1;
  }
}
function strokeMetrics(rect) {
  let unit = Math.max(1, Math.round(Math.min(rect.width, rect.height) / 16));
  return {
    light: unit,
    heavy: unit * 2,
    doubleGap: unit
  };
}
function drawCellLines(context, spec, rect) {
  let metrics = strokeMetrics(rect), edges = [
    [spec[0], "north"],
    [spec[1], "east"],
    [spec[2], "south"],
    [spec[3], "west"]
  ];
  for (let [weight, direction] of edges.sort((lhs, rhs) => lhs[0] - rhs[0]))
    drawHalfStroke(context, weight, direction, rect, metrics);
}
function drawHalfStroke(context, weight, direction, rect, metrics) {
  if (weight === 0)
    return;
  let cx = rect.x + rect.width / 2, cy = rect.y + rect.height / 2, maxX = rect.x + rect.width, maxY = rect.y + rect.height, segment = (thickness, offset) => {
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
    case 1:
      segment(metrics.light, 0);
      break;
    case 2:
      segment(metrics.heavy, 0);
      break;
    case 3: {
      let thickness = metrics.light, offset = (thickness + metrics.doubleGap) / 2;
      segment(thickness, -offset), segment(thickness, offset);
      break;
    }
  }
}
function drawDashedHorizontal(context, rect, weight, segments) {
  let metrics = strokeMetrics(rect), thickness = weight === 2 ? metrics.heavy : metrics.light, segmentWidth = rect.width / segments, dashWidth = segmentWidth * 0.55, gapWidth = segmentWidth - dashWidth, cy = rect.y + rect.height / 2;
  for (let index = 0;index < segments; index += 1) {
    let x = rect.x + index * segmentWidth + gapWidth / 2;
    context.fillRect(x, cy - thickness / 2, dashWidth, thickness);
  }
}
function drawDashedVertical(context, rect, weight, segments) {
  let metrics = strokeMetrics(rect), thickness = weight === 2 ? metrics.heavy : metrics.light, segmentHeight = rect.height / segments, dashHeight = segmentHeight * 0.55, gapHeight = segmentHeight - dashHeight, cx = rect.x + rect.width / 2;
  for (let index = 0;index < segments; index += 1) {
    let y = rect.y + index * segmentHeight + gapHeight / 2;
    context.fillRect(cx - thickness / 2, y, thickness, dashHeight);
  }
}
function drawDiagonal(context, rect, descending) {
  if (context.lineWidth = strokeMetrics(rect).light, context.lineCap = "square", context.setLineDash([]), context.beginPath(), descending)
    context.moveTo(rect.x, rect.y), context.lineTo(rect.x + rect.width, rect.y + rect.height);
  else
    context.moveTo(rect.x + rect.width, rect.y), context.lineTo(rect.x, rect.y + rect.height);
  context.stroke(), context.lineCap = "butt";
}
function drawArc(context, rect, corner) {
  let metrics = strokeMetrics(rect), cx = rect.x + rect.width / 2, cy = rect.y + rect.height / 2, maxX = rect.x + rect.width, maxY = rect.y + rect.height, radius = Math.min(rect.width, rect.height) * 0.4, kappa = radius * 0.5523;
  switch (context.lineWidth = metrics.light, context.lineCap = "butt", context.setLineDash([]), context.beginPath(), corner) {
    case "topLeft":
      context.moveTo(cx, cy + radius), context.lineTo(cx, maxY), context.moveTo(cx + radius, cy), context.lineTo(maxX, cy), context.moveTo(cx, cy + radius), context.bezierCurveTo(cx, cy + radius - kappa, cx + radius - kappa, cy, cx + radius, cy);
      break;
    case "topRight":
      context.moveTo(cx, cy + radius), context.lineTo(cx, maxY), context.moveTo(cx - radius, cy), context.lineTo(rect.x, cy), context.moveTo(cx - radius, cy), context.bezierCurveTo(cx - radius + kappa, cy, cx, cy + radius - kappa, cx, cy + radius);
      break;
    case "bottomRight":
      context.moveTo(cx, cy - radius), context.lineTo(cx, rect.y), context.moveTo(cx - radius, cy), context.lineTo(rect.x, cy), context.moveTo(cx, cy - radius), context.bezierCurveTo(cx, cy - radius + kappa, cx - radius + kappa, cy, cx - radius, cy);
      break;
    case "bottomLeft":
      context.moveTo(cx, cy - radius), context.lineTo(cx, rect.y), context.moveTo(cx + radius, cy), context.lineTo(maxX, cy), context.moveTo(cx + radius, cy), context.bezierCurveTo(cx + radius - kappa, cy, cx, cy - radius + kappa, cx, cy - radius);
      break;
  }
  context.stroke();
}
function drawBlockElement(context, codePoint, rect) {
  let maxX = rect.x + rect.width, maxY = rect.y + rect.height, lowerEighths = (count) => {
    let height = rect.height * count / 8;
    context.fillRect(rect.x, maxY - height, rect.width, height);
  }, leftEighths = (count) => {
    let width = rect.width * count / 8;
    context.fillRect(rect.x, rect.y, width, rect.height);
  };
  switch (codePoint) {
    case 9600:
      return context.fillRect(rect.x, rect.y, rect.width, rect.height / 2), !0;
    case 9601:
      return lowerEighths(1), !0;
    case 9602:
      return lowerEighths(2), !0;
    case 9603:
      return lowerEighths(3), !0;
    case 9604:
      return lowerEighths(4), !0;
    case 9605:
      return lowerEighths(5), !0;
    case 9606:
      return lowerEighths(6), !0;
    case 9607:
      return lowerEighths(7), !0;
    case 9608:
      return context.fillRect(rect.x, rect.y, rect.width, rect.height), !0;
    case 9609:
      return leftEighths(7), !0;
    case 9610:
      return leftEighths(6), !0;
    case 9611:
      return leftEighths(5), !0;
    case 9612:
      return leftEighths(4), !0;
    case 9613:
      return leftEighths(3), !0;
    case 9614:
      return leftEighths(2), !0;
    case 9615:
      return leftEighths(1), !0;
    case 9616:
      return context.fillRect(rect.x + rect.width / 2, rect.y, rect.width / 2, rect.height), !0;
    case 9617:
      return drawShade(context, rect, "light"), !0;
    case 9618:
      return drawShade(context, rect, "medium"), !0;
    case 9619:
      return drawShade(context, rect, "dark"), !0;
    case 9620:
      return context.fillRect(rect.x, rect.y, rect.width, rect.height / 8), !0;
    case 9621:
      return context.fillRect(maxX - rect.width / 8, rect.y, rect.width / 8, rect.height), !0;
    case 9622:
      return fillQuadrants(context, rect, ["bottomLeft"]), !0;
    case 9623:
      return fillQuadrants(context, rect, ["bottomRight"]), !0;
    case 9624:
      return fillQuadrants(context, rect, ["topLeft"]), !0;
    case 9625:
      return fillQuadrants(context, rect, [
        "topLeft",
        "bottomLeft",
        "bottomRight"
      ]), !0;
    case 9626:
      return fillQuadrants(context, rect, ["topLeft", "bottomRight"]), !0;
    case 9627:
      return fillQuadrants(context, rect, [
        "topLeft",
        "topRight",
        "bottomLeft"
      ]), !0;
    case 9628:
      return fillQuadrants(context, rect, [
        "topLeft",
        "topRight",
        "bottomRight"
      ]), !0;
    case 9629:
      return fillQuadrants(context, rect, ["topRight"]), !0;
    case 9630:
      return fillQuadrants(context, rect, ["topRight", "bottomLeft"]), !0;
    case 9631:
      return fillQuadrants(context, rect, [
        "topRight",
        "bottomLeft",
        "bottomRight"
      ]), !0;
    default:
      return !1;
  }
}
function fillQuadrants(context, rect, quadrants) {
  let halfWidth = rect.width / 2, halfHeight = rect.height / 2;
  for (let quadrant of quadrants)
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
function drawShade(context, rect, density) {
  let pixels = density === "light" ? [[0, 0]] : density === "medium" ? [[0, 0], [1, 1]] : [
    [0, 0],
    [1, 0],
    [0, 1]
  ];
  for (let y = rect.y;y < rect.y + rect.height; y += 2)
    for (let x = rect.x;x < rect.x + rect.width; x += 2)
      for (let [px, py] of pixels) {
        let dotX = x + (px ?? 0), dotY = y + (py ?? 0);
        if (dotX < rect.x + rect.width && dotY < rect.y + rect.height)
          context.fillRect(dotX, dotY, 1, 1);
      }
}
var brailleSubpixels = [
  [
    1,
    0,
    0
  ],
  [
    8,
    1,
    0
  ],
  [
    2,
    0,
    1
  ],
  [
    16,
    1,
    1
  ],
  [
    4,
    0,
    2
  ],
  [
    32,
    1,
    2
  ],
  [
    64,
    0,
    3
  ],
  [
    128,
    1,
    3
  ]
];
function drawBraille(context, codePoint, rect) {
  let mask = codePoint - 10240;
  if (mask === 0)
    return !0;
  let cellWidth = rect.width / 2, rowHeight = rect.height / 4;
  for (let [bit, col, row] of brailleSubpixels) {
    if ((mask & bit) === 0)
      continue;
    let x = rect.x + col * cellWidth, y = rect.y + row * rowHeight;
    context.fillRect(x, y, cellWidth, rowHeight);
  }
  return !0;
}

// dist/src/TextDecorationGeometry.js
function emitTextDecoration(sink, pattern, x, y, width, phaseX = x) {
  if (pattern === "double") {
    sink.fillRect(x, y - 1.5, width, 1), sink.fillRect(x, y + 0.5, width, 1);
    return;
  }
  if (pattern === "curly") {
    let start = x - positiveRemainder(phaseX, 6);
    sink.lineWidth = 1, sink.lineCap = "butt", sink.setLineDash([]), sink.beginPath(), sink.moveTo(start, y);
    for (let p2 = start;p2 < x + width; p2 += 6)
      sink.bezierCurveTo(p2 + 1, y - 2, p2 + 2, y - 2, p2 + 3, y), sink.bezierCurveTo(p2 + 4, y + 2, p2 + 5, y + 2, p2 + 6, y);
    sink.stroke();
    return;
  }
  let patternLengths = {
    solid: [width],
    dot: [1, 3],
    dash: [4, 3],
    dashDot: [
      4,
      3,
      1,
      3
    ],
    dashDotDot: [
      4,
      3,
      1,
      3,
      1,
      3
    ]
  }[pattern] ?? [width];
  if (pattern === "solid") {
    sink.fillRect(x, y - 0.5, width, 1);
    return;
  }
  let p = x - positiveRemainder(phaseX, patternLengths.reduce((sum, value) => sum + value, 0));
  while (p < x + width)
    for (let [index, length] of patternLengths.entries()) {
      let left = Math.max(x, p), right = Math.min(x + width, p + length);
      if (index % 2 === 0 && right > left)
        sink.fillRect(left, y - 0.5, right - left, 1);
      p += length;
    }
}
function positiveRemainder(value, divisor) {
  return (value % divisor + divisor) % divisor;
}

// dist/src/DomTextSpacing.js
function readDomTextSpacing(mount) {
  let view = mount.ownerDocument?.defaultView;
  if (!view)
    return {};
  let text = mount.querySelector(".webhost-scene__surface-row [data-column]"), root = mount.querySelector(".webhost-scene__surface--dom") ?? (mount.matches?.(".webhost-scene__surface--dom") ? mount : null);
  if (!text || !root) {
    let canvas = mount.querySelector("canvas.webhost-scene__surface");
    if (!canvas)
      return {};
    let computed2 = view.getComputedStyle(canvas), spacing = {};
    for (let key of [
      "letterSpacing",
      "wordSpacing",
      "lineHeight"
    ]) {
      let value = Number.parseFloat(computed2[key]);
      if (Number.isFinite(value) && value > 0)
        spacing[key] = value;
    }
    return spacing;
  }
  let computed = view.getComputedStyle(text), result = {};
  for (let key of [
    "letterSpacing",
    "wordSpacing",
    "lineHeight"
  ]) {
    let authored = key === "lineHeight" ? Number.parseFloat(computed.fontSize) * 1.5 : Number.parseFloat(text.style[key]) || 0, actual = Number.parseFloat(computed[key]) || 0;
    if (Number.isFinite(actual) && Math.abs(actual - authored) > 0.015625)
      result[key] = actual;
  }
  return result;
}

// dist/src/ImageAllocationBudget.js
function admitsImageBytes(bytes) {
  let size = imageSize(bytes);
  return size !== void 0 && admitsImageSize(...size);
}
function admitsImageSize(width, height) {
  return Number.isInteger(width) && Number.isInteger(height) && width > 0 && height > 0 && width <= 8192 && height <= 8192 && width * height <= 16777216;
}
function imageSize(bytes) {
  let view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  if (bytes.length >= 24 && view.getUint32(0) === 2303741511 && view.getUint32(4) === 218765834 && view.getUint32(12) === 1229472850)
    return [view.getUint32(16), view.getUint32(20)];
  if (bytes.length >= 10 && view.getUint32(0) === 1195984440 && (bytes[4] === 55 || bytes[4] === 57) && bytes[5] === 97)
    return [view.getUint16(6, !0), view.getUint16(8, !0)];
  if (bytes.length < 4 || view.getUint16(0) !== 65496)
    return;
  let offset = 2;
  while (offset < bytes.length) {
    if (bytes[offset++] !== 255)
      return;
    while (bytes[offset] === 255)
      offset++;
    let marker = bytes[offset++];
    if (marker === void 0 || marker === 218 || marker === 217)
      return;
    if (marker === 1 || marker >= 208 && marker <= 215)
      continue;
    if (offset + 2 > bytes.length)
      return;
    let length = view.getUint16(offset);
    if (length < 2 || offset + length > bytes.length)
      return;
    if (marker >= 192 && marker <= 207 && marker !== 196 && marker !== 200 && marker !== 204) {
      if (length < 8)
        return;
      return [view.getUint16(offset + 5), view.getUint16(offset + 3)];
    }
    offset += length;
  }
}

// dist/src/StaticGif.js
function firstGifFrame(bytes) {
  let fail = () => {
    throw Error("Invalid GIF container");
  };
  if (bytes.length < 13 || String.fromCharCode(...bytes.subarray(0, 6)) !== "GIF89a" && String.fromCharCode(...bytes.subarray(0, 6)) !== "GIF87a")
    return fail();
  let offset = 13 + (bytes[10] & 128 ? 3 * 2 ** ((bytes[10] & 7) + 1) : 0);
  if (offset > bytes.length)
    return fail();
  let header = bytes.slice(0, offset), control = /* @__PURE__ */ new Uint8Array(0), subBlocks = () => {
    while (offset < bytes.length) {
      let size = bytes[offset++];
      if (!size)
        return;
      if (offset += size, offset > bytes.length)
        return fail();
    }
    return fail();
  };
  while (offset < bytes.length) {
    let start = offset, marker = bytes[offset++];
    if (marker === 33) {
      let label = bytes[offset++];
      if (label === 249 && bytes[offset] !== 4)
        return fail();
      if (subBlocks(), label === 249)
        control = bytes.slice(start, offset);
    } else if (marker === 44) {
      if (offset + 9 > bytes.length)
        return fail();
      let word = (at) => bytes[at] | bytes[at + 1] << 8, width = word(offset + 4), height = word(offset + 6);
      if (!width || !height || word(offset) + width > word(6) || word(offset + 2) + height > word(8))
        return fail();
      let packed = bytes[offset + 8];
      if (offset += 9 + (packed & 128 ? 3 * 2 ** ((packed & 7) + 1) : 0), offset >= bytes.length)
        return fail();
      if (bytes[offset] < 2 || bytes[offset] > 8)
        return fail();
      offset++, subBlocks();
      let frame = bytes.subarray(start, offset), result = new Uint8Array(header.length + control.length + frame.length + 1);
      return result.set(header), result.set(control, header.length), result.set(frame, header.length + control.length), result[result.length - 1] = 59, result;
    } else
      return fail();
  }
  return fail();
}

// dist/src/SurfacePainterConformanceControl.js
var canvasControls = /* @__PURE__ */ new WeakMap;
function registerCanvasSurfacePainterConformanceControl(painter, control) {
  canvasControls.set(painter, control);
}

// dist/src/AccessibilitySelection.js
function presentSelection(element, node, synchronizeValue, interactive) {
  let selection = node.selection, selected = node.value?.type === "text" ? node.value.value : "", enabled = interactive && node.isEnabled !== !1 && node.properties?.readOnly !== !0, active = document.activeElement, ownedFocus = active instanceof HTMLElement && active !== element && element.contains(active), previous = new Map(Array.from(element.children, (child) => [child.dataset.optionId, child])), nativeSelect = element instanceof HTMLSelectElement;
  if (nativeSelect)
    element.size = selection.presentation === "menu" ? 1 : Math.max(2, Math.min(8, selection.options.length)), element.disabled = !enabled, element.tabIndex = enabled ? 0 : -1, element.required = node.properties?.required === !0, element.style.pointerEvents = "auto", element.removeAttribute("role");
  else
    element.setAttribute("role", "radiogroup"), element.setAttribute("aria-orientation", selection.presentation === "segmented" ? "horizontal" : "vertical"), element.tabIndex = -1;
  selection.options.forEach((option, index) => {
    let child = previous.get(option.id) ?? document.createElement(nativeSelect ? "option" : "input");
    if (previous.delete(option.id), child.dataset.optionId = option.id, nativeSelect) {
      let nativeOption = child;
      nativeOption.value = option.id, nativeOption.textContent = option.label, nativeOption.disabled = !enabled || !option.isEnabled;
    } else {
      let radio = child;
      if (radio.type = "radio", radio.name = element.id, radio.value = option.id, radio.id = `${element.id}-option-${Array.from(option.id, (c) => c.codePointAt(0).toString(16)).join("-")}`, radio.setAttribute("aria-label", option.label), radio.setAttribute("aria-posinset", String(index + 1)), radio.setAttribute("aria-setsize", String(selection.options.length)), radio.disabled = !enabled || !option.isEnabled, synchronizeValue)
        radio.checked = selected === option.id;
      radio.style.position = "absolute";
      let horizontal = selection.presentation === "segmented";
      if (radio.style.left = horizontal ? `${index * 100 / selection.options.length}%` : "0", radio.style.top = horizontal ? "0" : `${index * 100 / selection.options.length}%`, radio.style.width = horizontal ? `${100 / selection.options.length}%` : "100%", radio.style.height = horizontal ? "100%" : `${100 / selection.options.length}%`, option.rect) {
        let [x, y, width, height] = option.rect, [ownerX, ownerY, ownerWidth, ownerHeight] = node.rect;
        radio.style.left = `${(x - ownerX) * 100 / Math.max(1, ownerWidth)}%`, radio.style.top = `${(y - ownerY) * 100 / Math.max(1, ownerHeight)}%`, radio.style.width = `${width * 100 / Math.max(1, ownerWidth)}%`, radio.style.height = `${height * 100 / Math.max(1, ownerHeight)}%`;
      }
      radio.style.pointerEvents = option.rect ? "auto" : "none", radio.style.boxSizing = "border-box", radio.style.margin = "0";
    }
    if (element.children[index] !== child)
      element.insertBefore(child, element.children[index] ?? null);
  });
  for (let child of previous.values())
    child.remove();
  if (nativeSelect) {
    if (synchronizeValue)
      element.value = selected;
  } else {
    let radios = Array.from(element.querySelectorAll("input")), tabStop = radios.find((radio) => radio.checked && !radio.disabled) ?? radios.find((radio) => !radio.disabled);
    for (let radio of radios)
      radio.tabIndex = radio === tabStop ? 0 : -1;
    if (ownedFocus)
      (active instanceof HTMLInputElement && element.contains(active) && !active.disabled ? active : tabStop)?.focus({ preventScroll: !0 });
  }
}
function selectionFocusElement(element) {
  if (element.getAttribute("role") !== "radiogroup")
    return element;
  let active = document.activeElement;
  if (active instanceof HTMLElement && element.contains(active))
    return active;
  return element.querySelector("input[tabindex='0']") ?? element;
}

// dist/src/AccessibilityTree.js
var AccessibilityTreeMounter = class {
  sendAction;
  openLink;
  element;
  announcerElement;
  navigationElement;
  categorySelect;
  targetSelect;
  navigationGo;
  navigationGroups = /* @__PURE__ */ new Map;
  domIdentity = Array.from(crypto.getRandomValues(/* @__PURE__ */ new Uint32Array(4)), (part) => part.toString(16)).join("-");
  nodesById = /* @__PURE__ */ new Map;
  actionGroupsById = /* @__PURE__ */ new Map;
  previousLabelsById = /* @__PURE__ */ new Map;
  hasLiveRegionBaseline = !1;
  readingText = /* @__PURE__ */ new WeakMap;
  modelsById = /* @__PURE__ */ new Map;
  keysByElement = /* @__PURE__ */ new WeakMap;
  presenting = !1;
  nextRequestID = 0n;
  acknowledgedRequestID = 0n;
  pendingValues = /* @__PURE__ */ new Map;
  pendingFocus;
  runtimeFocusedElement;
  pendingMenu;
  pendingMenuReturn;
  appliedAssistiveFocusGeneration = -1n;
  composing = /* @__PURE__ */ new WeakSet;
  textSelections = /* @__PURE__ */ new WeakMap;
  compositionCommits = /* @__PURE__ */ new WeakMap;
  get hasInteractiveControls() {
    return [...this.modelsById.values()].some((node) => this.isTabStop(node));
  }
  advanceFocus(backward) {
    let controls = [...this.element.querySelectorAll("[tabindex='0']")], current = controls.indexOf(document.activeElement);
    if (current < 0)
      return !1;
    let next = controls[current + (backward ? -1 : 1)];
    if (!next)
      return !1;
    return next.focus(), !0;
  }
  isTabStop(node) {
    return !!this.sendAction && !!node.actionTarget && node.isEnabled !== !1 && (!!node.actions?.includes("focus") || node.role === "tab" && !!node.actions?.includes("accessibilityFocus"));
  }
  enclosingMenu(node, models = this.modelsById) {
    let seen = /* @__PURE__ */ new Set, parent = node.parentId;
    while (parent && !seen.has(parent)) {
      seen.add(parent);
      let model = models.get(parent);
      if (model?.role === "menu")
        return model;
      parent = model?.parentId;
    }
  }
  menuItems(menu) {
    return [...this.modelsById.values()].filter((node) => this.enclosingMenu(node)?.id === menu.id && this.isTabStop(node));
  }
  focusControl(node) {
    let element = this.nodesById.get(node.id);
    if (!element || !node.actionTarget)
      return;
    if (element.focus({ preventScroll: !0 }), this.presenting && node.actions?.includes("focus")) {
      let requestID = ++this.nextRequestID;
      this.pendingFocus = {
        id: node.id,
        requestID
      }, this.sendAction?.(node.actionTarget, { action: "focus" }, String(requestID));
    }
  }
  setMenuExpanded(trigger, expanded) {
    if (!trigger?.actionTarget || trigger.isEnabled === !1 || !trigger.actions?.includes("setValue"))
      return !1;
    return this.sendAction?.(trigger.actionTarget, {
      action: "setValue",
      value: {
        type: "boolean",
        value: expanded
      }
    }, String(++this.nextRequestID)), !0;
  }
  constructor(sendAction, openLink) {
    this.sendAction = sendAction, this.openLink = openLink, this.navigationElement = document.createElement("details"), this.navigationElement.hidden = !0, this.navigationElement.className = "webhost-scene__content-navigation";
    let summary = document.createElement("summary");
    summary.textContent = "Navigate content";
    let categoryLabel = document.createElement("label");
    categoryLabel.textContent = "Content group ", this.categorySelect = document.createElement("select"), categoryLabel.append(this.categorySelect);
    let targetLabel = document.createElement("label");
    targetLabel.textContent = "Destination ", this.targetSelect = document.createElement("select"), targetLabel.append(this.targetSelect), this.navigationGo = document.createElement("button"), this.navigationGo.type = "button", this.navigationGo.textContent = "Go to content", this.navigationElement.append(summary, categoryLabel, targetLabel, this.navigationGo), this.categorySelect.addEventListener("change", () => this.refreshNavigationTargets()), this.navigationGo.addEventListener("click", () => {
      let node = this.modelsById.get(this.targetSelect.value), target = node ? this.nodesById.get(node.id) : void 0;
      if (!node?.actionTarget || !target || !node.actions?.includes("accessibilityFocus"))
        return;
      this.presenting = !0;
      try {
        target.focus();
      } finally {
        this.presenting = !1;
      }
      this.sendAction?.(node.actionTarget, { action: "accessibilityFocus" }, String(++this.nextRequestID));
    }), this.element = document.createElement("div"), this.element.className = "webhost-scene__accessibility-tree", this.element.style.position = "absolute", this.element.style.inset = "0", this.element.style.opacity = "0", this.element.style.pointerEvents = "none", this.element.style.zIndex = "3", this.announcerElement = document.createElement("div"), this.announcerElement.className = "webhost-scene__accessibility-announcer", this.announcerElement.setAttribute("aria-atomic", "true"), this.announcerElement.setAttribute("aria-live", "polite"), applyScreenReaderOnlyStyle(this.announcerElement);
  }
  present(nodes, metrics, announcements = [], options = {}) {
    this.presenting = !0;
    try {
      this.presentFrame(nodes, metrics, announcements, options);
    } finally {
      this.presenting = !1;
    }
  }
  presentFrame(nodes, metrics, announcements, options) {
    let activeBeforePresentation = document.activeElement, reviewedID = activeBeforePresentation ? this.keysByElement.get(activeBeforePresentation) : void 0, reviewedModel = reviewedID ? this.modelsById.get(reviewedID) : void 0, reviewedMenu = reviewedModel ? this.enclosingMenu(reviewedModel) : void 0, menuReturn = this.pendingMenuReturn ?? reviewedMenu?.properties?.labelledBy?.[0], visibleNodes = presentationNodes(nodes.filter((node) => !node.hidden)).map((node) => ({
      ...node,
      liveRegion: normalizeLiveRegion(node.liveRegion)
    })), normalizedAnnouncements = announcements.map((announcement) => ({
      ...announcement,
      politeness: normalizePoliteness(announcement.politeness)
    }));
    if (options.actionResponse) {
      let acknowledged = BigInt(options.actionResponse.requestID);
      if (acknowledged > this.acknowledgedRequestID)
        this.acknowledgedRequestID = acknowledged;
    }
    let previousById = this.nodesById, nextById = /* @__PURE__ */ new Map, modelsById = new Map(visibleNodes.map((node) => [node.id, node]));
    for (let node of visibleNodes) {
      let existing = previousById.get(node.id), tag = this.elementTag(node), previousModel = this.modelsById.get(node.id), reusable = existing?.tagName.toLowerCase() === tag && previousModel?.actionTarget === node.actionTarget && previousModel?.selection?.presentation === node.selection?.presentation, element2 = reusable ? existing : this.createElement(node, tag);
      if (!reusable) {
        if (existing)
          this.clearEditable(existing);
        if (existing?.remove(), this.pendingValues.delete(node.id), this.pendingFocus?.id === node.id)
          this.pendingFocus = void 0;
      }
      this.applyNodeAttributes(element2, node, metrics, node.parentId ? modelsById.get(node.parentId) : void 0), nextById.set(node.id, element2);
    }
    for (let id of previousById.keys())
      if (!nextById.has(id)) {
        let removed = previousById.get(id);
        if (removed)
          this.clearEditable(removed), removed.remove();
        if (this.pendingValues.delete(id), this.actionGroupsById.get(id)?.remove(), this.actionGroupsById.delete(id), this.pendingFocus?.id === id)
          this.pendingFocus = void 0;
      }
    this.nodesById = nextById, this.modelsById = modelsById;
    for (let node of visibleNodes) {
      let element2 = nextById.get(node.id);
      if (element2)
        this.applyRelationships(element2, node, nextById);
    }
    let childOffsets = /* @__PURE__ */ new Map;
    for (let node of visibleNodes) {
      let element2 = nextById.get(node.id);
      if (!element2)
        continue;
      let container = (node.parentId ? nextById.get(node.parentId) : void 0) ?? this.element, offset = childOffsets.get(container) ?? 0;
      if (container.children[offset] !== element2)
        container.insertBefore(element2, container.children[offset] ?? null);
      let group = this.presentCustomActions(node, element2);
      if (group && container.children[offset + 1] !== group)
        container.insertBefore(group, container.children[offset + 1] ?? null);
      childOffsets.set(container, offset + (group ? 2 : 1));
    }
    let tabGroups = /* @__PURE__ */ new Map;
    for (let node of visibleNodes)
      if (node.role === "tab") {
        let group = tabGroups.get(node.parentId) ?? [];
        group.push(node), tabGroups.set(node.parentId, group);
      }
    for (let group of tabGroups.values()) {
      let enabled = group.filter((node) => this.isTabStop(node)), chosen = enabled.find((node) => this.nodesById.get(node.id) === activeBeforePresentation) ?? enabled.find((node) => node.properties?.selected) ?? enabled[0];
      for (let node of group) {
        let element2 = this.nodesById.get(node.id);
        if (element2)
          element2.tabIndex = node === chosen ? 0 : -1;
      }
      if ((options.synchronizeFocus ?? !0) && reviewedModel?.role === "tab" && reviewedModel.parentId === group[0]?.parentId && !enabled.some((node) => this.nodesById.get(node.id) === activeBeforePresentation) && chosen?.actionTarget && (!options.focusRequest || BigInt(options.focusRequest.generation) <= this.appliedAssistiveFocusGeneration))
        this.nodesById.get(chosen.id)?.focus({ preventScroll: !0 }), this.sendAction?.(chosen.actionTarget, { action: "accessibilityFocus" }, String(++this.nextRequestID));
    }
    for (let menu of visibleNodes.filter((node) => node.role === "menu")) {
      let items = this.menuItems(menu), selected = items.find((node) => this.nodesById.get(node.id) === activeBeforePresentation) ?? items[0];
      for (let item of items) {
        let element2 = this.nodesById.get(item.id);
        if (element2)
          element2.tabIndex = item === selected ? 0 : -1;
      }
    }
    let newAppFocus = options.focusRequest && BigInt(options.focusRequest.generation) > this.appliedAssistiveFocusGeneration;
    if ((options.synchronizeFocus ?? !0) && !newAppFocus) {
      if (this.pendingMenu) {
        let trigger = this.modelsById.get(this.pendingMenu.trigger), menu = trigger?.properties?.controls?.map((id) => this.modelsById.get(id)).find((node) => node?.role === "menu");
        if (menu) {
          let items = this.menuItems(menu), destination = this.pendingMenu.last ? items.at(-1) : items[0];
          if (destination)
            this.focusControl(destination);
          this.pendingMenu = void 0;
        } else if (!trigger)
          this.pendingMenu = void 0;
      }
      if (menuReturn && (!reviewedID || !this.modelsById.has(reviewedID) || this.pendingMenuReturn)) {
        let trigger = this.modelsById.get(menuReturn);
        if (trigger?.properties?.expanded === !1 && this.isTabStop(trigger))
          this.focusControl(trigger), this.pendingMenuReturn = void 0;
      }
    }
    this.refreshNavigation(visibleNodes), this.announceLiveRegionChanges(visibleNodes, normalizedAnnouncements);
    let assistiveRequest = options.focusRequest, requestGeneration = assistiveRequest ? BigInt(assistiveRequest.generation) : void 0, applyAssistiveRequest = (options.synchronizeFocus ?? !0) && requestGeneration !== void 0 && requestGeneration > this.appliedAssistiveFocusGeneration;
    if (applyAssistiveRequest && assistiveRequest) {
      this.appliedAssistiveFocusGeneration = requestGeneration;
      let target = visibleNodes.find((node) => node.actionTarget === assistiveRequest.target);
      if (assistiveRequest.target !== void 0 && target)
        this.nodesById.get(target.id)?.focus({ preventScroll: !0 });
      else if (assistiveRequest.target === void 0 && this.element.contains(document.activeElement))
        document.activeElement?.blur();
    }
    let focused = visibleNodes.find((node) => node.isFocused), element = focused ? this.nodesById.get(focused.id) : void 0, pending = this.pendingFocus, focusAcknowledged = pending !== void 0 && pending.requestID <= this.acknowledgedRequestID, synchronize = focusAcknowledged ? this.nodesById.get(pending.id)?.contains(activeBeforePresentation) ?? !1 : element !== this.runtimeFocusedElement || element === activeBeforePresentation;
    if (this.runtimeFocusedElement = element, focusAcknowledged)
      this.pendingFocus = void 0;
    if ((options.synchronizeFocus ?? !0) && !applyAssistiveRequest && synchronize && element && this.pendingFocus === void 0) {
      let focusElement = selectionFocusElement(element);
      if (document.activeElement !== focusElement)
        focusElement.focus?.({ preventScroll: !0 });
    }
  }
  dispose() {
    for (let element of this.nodesById.values())
      this.clearEditable(element);
    this.nodesById.clear(), this.actionGroupsById.clear(), this.modelsById.clear(), this.previousLabelsById.clear(), this.pendingValues.clear(), this.pendingFocus = void 0, this.runtimeFocusedElement = void 0, this.appliedAssistiveFocusGeneration = -1n, this.element.replaceChildren(), this.announcerElement.replaceChildren(), this.navigationElement.remove();
  }
  refreshNavigation(nodes) {
    this.navigationGroups = /* @__PURE__ */ new Map;
    for (let node of nodes) {
      if (!node.label?.trim() || !node.actionTarget || !node.actions?.includes("accessibilityFocus"))
        continue;
      for (let category of node.navigationCategories ?? []) {
        let entries = this.navigationGroups.get(category) ?? [];
        entries.push(node), this.navigationGroups.set(category, entries);
      }
    }
    this.navigationElement.hidden = this.navigationGroups.size === 0, this.setNavigationOptions(this.categorySelect, [...this.navigationGroups.keys()].map((name) => [name, name])), this.refreshNavigationTargets();
  }
  refreshNavigationTargets() {
    let entries = this.navigationGroups.get(this.categorySelect.value) ?? [];
    this.setNavigationOptions(this.targetSelect, entries.map((node) => [node.id, node.label ?? ""])), this.navigationGo.disabled = entries.length === 0;
  }
  setNavigationOptions(select, entries) {
    if (select.options.length === entries.length && entries.every(([value, label], index) => select.options[index]?.value === value && select.options[index]?.textContent === label))
      return;
    let selected = select.value;
    if (select.replaceChildren(...entries.map(([value, label]) => {
      let option = document.createElement("option");
      return option.value = value, option.textContent = label, option;
    })), entries.some(([value]) => value === selected))
      select.value = selected;
  }
  clearEditable(element) {
    if (element.tagName === "INPUT" || element.tagName === "TEXTAREA")
      element.value = "";
    this.compositionCommits.delete(element), this.composing.delete(element), this.textSelections.delete(element);
  }
  elementTag(node) {
    if (node.role === "link")
      return "a";
    if (node.selection && ["menu", "list"].includes(node.selection.presentation))
      return "select";
    if (!node.actionTarget || !this.sendAction)
      return "div";
    if (node.role === "stepper" && !node.actions?.includes("setValue"))
      return "div";
    if (node.role === "textEditor")
      return "textarea";
    if ([
      "textField",
      "secureField",
      "slider",
      "stepper"
    ].includes(node.role))
      return "input";
    return "div";
  }
  presentCustomActions(node, owner) {
    let names = node.actionTarget && this.sendAction && node.actions?.includes("custom") ? node.customActions ?? [] : [], group = this.actionGroupsById.get(node.id);
    if (!names.length) {
      group?.remove(), this.actionGroupsById.delete(node.id);
      return;
    }
    if (!group) {
      group = document.createElement("div"), group.setAttribute("role", "group"), this.actionGroupsById.set(node.id, group);
      for (let type of [
        "click",
        "pointerdown",
        "pointerup",
        "pointermove"
      ])
        group.addEventListener(type, (event) => event.stopPropagation());
      group.addEventListener("keydown", (event) => {
        if (event.key !== "Tab" && event.key !== "Escape")
          event.stopPropagation();
      });
    }
    group.setAttribute("aria-label", `${node.label ?? "Control"} actions`), group.style.cssText = owner.style.cssText;
    let previous = new Map(Array.from(group.children, (child) => [child.textContent, child]));
    for (let [index, name] of names.entries()) {
      let button = previous.get(name);
      if (!button)
        button = document.createElement("button"), button.type = "button", button.textContent = name, button.addEventListener("click", () => {
          let current = this.modelsById.get(node.id);
          if (this.actionGroupsById.get(node.id) !== group || !current?.actionTarget || current.isEnabled === !1 || current.properties?.readOnly === !0 || !current.customActions?.includes(name))
            return;
          this.sendAction?.(current.actionTarget, {
            action: "custom",
            name
          }, String(++this.nextRequestID));
        });
      if (previous.delete(name), button.disabled = node.isEnabled === !1 || node.properties?.readOnly === !0, button.tabIndex = button.disabled ? -1 : 0, group.children[index] !== button)
        group.insertBefore(button, group.children[index] ?? null);
    }
    for (let button of previous.values())
      button.remove();
    return group;
  }
  createElement(node, tag) {
    let element = document.createElement(tag);
    if (!node.actionTarget || !this.sendAction)
      return element;
    let current = () => this.nodesById.get(node.id) === element ? this.modelsById.get(node.id) : void 0, send = (request) => {
      let model = current(), semanticFocus = request.action === "accessibilityFocus" || request.action === "accessibilityBlur";
      if (this.presenting || !model?.actionTarget || model.isEnabled === !1 && !semanticFocus || model.properties?.readOnly === !0 && request.action !== "focus" && request.action !== "selectText" && !semanticFocus || !model.actions?.includes(request.action))
        return;
      let requestID = ++this.nextRequestID;
      if ([
        "setValue",
        "editText",
        "selectText"
      ].includes(request.action))
        this.pendingValues.set(node.id, requestID);
      if (request.action === "focus")
        this.pendingFocus = {
          id: node.id,
          requestID
        };
      this.sendAction?.(model.actionTarget, request, String(requestID));
    };
    if (element.addEventListener(node.selection ? "focusin" : "focus", () => {
      send({ action: "focus" }), send({ action: "accessibilityFocus" });
    }), element.addEventListener(node.selection ? "focusout" : "blur", (event) => {
      if (node.selection && element.contains(event.relatedTarget))
        return;
      send({ action: "accessibilityBlur" });
    }), node.selection) {
      for (let type of [
        "pointerdown",
        "pointerup",
        "pointermove"
      ])
        element.addEventListener(type, (event) => event.stopPropagation());
      return element.addEventListener("change", (event) => {
        event.stopPropagation();
        let input = event.target, option = current()?.selection?.options.find((option2) => option2.id === input.value);
        if (!option?.isEnabled || input instanceof HTMLInputElement && !input.checked)
          return;
        send({
          action: "setValue",
          value: {
            type: "text",
            value: option.id
          }
        });
      }), element.addEventListener("keydown", (event) => {
        if (event.key !== "Tab")
          event.stopPropagation();
      }), element.addEventListener("click", (event) => event.stopPropagation()), element;
    }
    if (element.addEventListener("click", (event) => {
      event.stopPropagation();
      let model = current();
      if (tag === "a") {
        if (model?.opensLink && model.isEnabled !== !1 && model.properties?.readOnly !== !0) {
          if (this.openLink && model.value?.type === "text") {
            event.preventDefault(), this.openLink(model.value.value);
            return;
          }
          if (element.hasAttribute("href"))
            return;
        }
        event.preventDefault();
      }
      send({ action: "activate" });
    }), tag === "a")
      for (let type of [
        "pointerdown",
        "pointerup",
        "pointermove"
      ])
        element.addEventListener(type, (event) => event.stopPropagation());
    if (element.addEventListener("keydown", (event) => {
      let model = current();
      if (!model || event.key === "Tab")
        return;
      let menu = this.enclosingMenu(model);
      if (menu && ["Escape", "ArrowLeft"].includes(event.key)) {
        let triggerID = menu.properties?.labelledBy?.[0];
        if (triggerID && this.setMenuExpanded(this.modelsById.get(triggerID), !1)) {
          event.preventDefault(), event.stopPropagation(), this.pendingMenuReturn = triggerID;
          return;
        }
      }
      if (event.key === "Escape")
        return;
      if (model.properties?.popup === "menu" && [
        "ArrowDown",
        "ArrowUp",
        "ArrowRight"
      ].includes(event.key)) {
        let opened = model.properties.expanded === !0;
        if (opened || this.setMenuExpanded(model, !0)) {
          event.preventDefault(), event.stopPropagation();
          let last = event.key === "ArrowUp", controlled = model.properties.controls?.map((id) => this.modelsById.get(id)).find((node2) => node2?.role === "menu");
          if (opened && controlled) {
            let items = this.menuItems(controlled), destination = last ? items.at(-1) : items[0];
            if (destination)
              this.focusControl(destination);
          } else
            this.pendingMenu = {
              trigger: model.id,
              last
            };
          return;
        }
      }
      if (menu && [
        "ArrowDown",
        "ArrowUp",
        "Home",
        "End"
      ].includes(event.key)) {
        event.preventDefault(), event.stopPropagation();
        let peers = this.menuItems(menu), index = peers.findIndex((node2) => node2.id === model.id), destination = peers[event.key === "Home" ? 0 : event.key === "End" ? peers.length - 1 : (index + (event.key === "ArrowUp" ? -1 : 1) + peers.length) % peers.length];
        if (destination) {
          for (let peer of peers) {
            let target = this.nodesById.get(peer.id);
            if (target)
              target.tabIndex = peer === destination ? 0 : -1;
          }
          this.focusControl(destination);
        }
        return;
      }
      if (tag === "a" && event.key === "Enter") {
        if (event.stopPropagation(), !element.hasAttribute("href"))
          event.preventDefault(), element.click();
        return;
      }
      if (model.role === "tab" && [
        "ArrowLeft",
        "ArrowRight",
        "Home",
        "End"
      ].includes(event.key)) {
        event.preventDefault(), event.stopPropagation();
        let peers = [...this.modelsById.values()].filter((node2) => node2.role === "tab" && node2.parentId === model.parentId && this.isTabStop(node2)), index = peers.findIndex((node2) => node2.id === model.id), destination = peers[event.key === "Home" ? 0 : event.key === "End" ? peers.length - 1 : (index + (event.key === "ArrowLeft" ? -1 : 1) + peers.length) % peers.length];
        if (destination) {
          for (let peer of peers) {
            let target = this.nodesById.get(peer.id);
            if (target)
              target.tabIndex = peer === destination ? 0 : -1;
          }
          this.nodesById.get(destination.id)?.focus();
        }
        return;
      }
      if (model.properties?.readOnly === !0 && (event.key === "Backspace" || event.key === "Delete")) {
        event.preventDefault(), event.stopPropagation();
        return;
      }
      if (tag !== "div" && event.key === "Enter" && model.role !== "textEditor")
        return;
      event.stopPropagation();
      let request;
      if (model.actions?.includes("increment") && ["ArrowRight", "ArrowUp"].includes(event.key))
        request = { action: "increment" };
      else if (model.actions?.includes("decrement") && ["ArrowLeft", "ArrowDown"].includes(event.key))
        request = { action: "decrement" };
      else if ((model.role === "slider" || model.role === "stepper") && (event.key === "Home" || event.key === "End")) {
        let value = event.key === "Home" ? model.valueMin : model.valueMax;
        if (value !== void 0)
          request = {
            action: "setValue",
            value: {
              type: "number",
              value
            }
          };
      } else if (tag === "div" && (event.key === "Enter" || event.key === " "))
        request = { action: "activate" };
      if (request)
        event.preventDefault(), send(request);
    }), tag !== "div") {
      element.addEventListener("blur", () => {
        if (this.composing.delete(element), this.textSelections.delete(element), this.compositionCommits.delete(element), current()?.role === "secureField")
          element.value = "";
      }), element.addEventListener("paste", (event) => event.stopPropagation());
      let commit = () => {
        let model = current();
        if (!model)
          return;
        let value = element.value;
        if (model.role === "slider" || model.role === "stepper") {
          let number = Number(value);
          if (value !== "" && Number.isFinite(number))
            send({
              action: "setValue",
              value: {
                type: "number",
                value: number
              }
            });
        } else if (model.actions?.includes("editText")) {
          let selection = nativeTextSelection(element);
          this.textSelections.set(element, selection), send({
            action: "editText",
            ...selection
          });
        } else
          send({
            action: "setValue",
            value: {
              type: "text",
              value
            }
          });
      };
      element.addEventListener("selectionchange", () => {
        let model = current();
        if (this.presenting || this.composing.has(element) || document.activeElement !== element || !model?.actions?.includes("selectText"))
          return;
        let selection = nativeTextSelection(element), previous = this.textSelections.get(element);
        if (previous?.text === selection.text && previous.anchor === selection.anchor && previous.head === selection.head)
          return;
        this.textSelections.set(element, selection), send({
          action: "selectText",
          ...selection
        });
      }), element.addEventListener("compositionstart", () => {
        this.composing.add(element), this.compositionCommits.delete(element);
      }), element.addEventListener("compositionend", () => {
        if (!this.composing.delete(element))
          return;
        if (!current())
          return;
        commit(), this.compositionCommits.set(element, element.value);
      }), element.addEventListener("input", (event) => {
        if (this.composing.has(element) || event.isComposing)
          return;
        let previous = this.compositionCommits.get(element);
        if (this.compositionCommits.delete(element), previous !== void 0 && previous === element.value)
          return;
        commit();
      });
    }
    return element;
  }
  applyNodeAttributes(element, node, metrics, parent) {
    if (element.id = `swifttui-a11y-${this.domIdentity}-${stableDOMId(node.id)}`, element.dataset.accessibilityId = node.wireId, this.keysByElement.set(element, node.id), element.tabIndex = this.isTabStop(node) ? 0 : -1, element.tagName === "A") {
      element.setAttribute("target", "_blank"), element.setAttribute("rel", "noopener noreferrer");
      let destination = node.value?.type === "text" ? node.value.value : void 0;
      setOrRemoveAttribute(element, "href", node.isEnabled !== !1 ? safeLinkDestination(destination) : void 0), element.style.pointerEvents = "auto";
    }
    if (node.isAccessibilityFocused)
      element.dataset.accessibilityFocused = "true";
    else
      delete element.dataset.accessibilityFocused;
    let properties = node.properties, role = node.role === "alert" && properties?.modal ? { role: "alertdialog" } : roleMapping(node.role);
    if (properties?.headingLevel !== void 0)
      role.role = "heading", role.level = properties.headingLevel;
    else if (role.role !== "heading" && properties?.textKind !== void 0)
      role.role = properties.textKind === "plain" ? "generic" : properties.textKind === "quotation" ? "blockquote" : properties.textKind;
    setOrRemoveAttribute(element, "role", node.role === "secureField" && element.tagName === "INPUT" ? void 0 : role.role), setOrRemoveAttribute(element, "aria-level", role.level !== void 0 ? String(role.level) : properties?.level?.toString());
    let structuredText = properties?.textKind !== void 0 || role.role === "heading";
    setOrRemoveAttribute(element, "aria-label", structuredText ? void 0 : node.label || void 0);
    let text = this.readingText.get(element);
    if (element.style.userSelect = structuredText ? "text" : "", element.style.setProperty("-webkit-user-select", structuredText ? "text" : ""), structuredText)
      if (text) {
        if (text.data !== (node.label ?? ""))
          text.data = node.label ?? "";
      } else {
        let content = document.createTextNode(node.label ?? "");
        this.readingText.set(element, content), element.prepend(content);
      }
    else if (text)
      text.remove(), this.readingText.delete(element);
    if (setOrRemoveAttribute(element, "aria-description", [!supportsValueText(node.role) && node.role !== "secureField" ? properties?.valueDescription : void 0, properties?.description ?? node.hint].filter(Boolean).join("; ") || void 0), setOrRemoveAttribute(element, "lang", properties?.language), setOrRemoveAttribute(element, "aria-haspopup", properties?.popup), setOrRemoveAttribute(element, "aria-modal", properties?.modal?.toString()), setOrRemoveAttribute(element, "aria-live", node.liveRegion || void 0), node.isFocused)
      element.dataset.focused = "true";
    else
      delete element.dataset.focused;
    if (setOrRemoveAttribute(element, "aria-disabled", node.isEnabled === !1 ? "true" : void 0), setOrRemoveAttribute(element, "aria-pressed", node.role === "button" && properties?.expanded === void 0 && node.value?.type === "boolean" ? String(node.value.value) : void 0), setOrRemoveAttribute(element, "aria-checked", ["toggle", "custom(menuitemcheckbox)"].includes(node.role) && node.value?.type === "boolean" ? String(node.value.value) : void 0), setOrRemoveAttribute(element, "aria-expanded", properties?.expanded !== void 0 ? String(properties.expanded) : node.role === "disclosureGroup" && node.value?.type === "boolean" ? String(node.value.value) : void 0), setOrRemoveAttribute(element, "aria-valuenow", node.value?.type === "number" ? String(node.value.value) : void 0), setOrRemoveAttribute(element, "aria-valuemin", node.valueMin === void 0 ? void 0 : String(node.valueMin)), setOrRemoveAttribute(element, "aria-valuemax", node.valueMax === void 0 ? void 0 : String(node.valueMax)), setOrRemoveAttribute(element, "aria-selected", properties?.selected?.toString()), setOrRemoveAttribute(element, "aria-required", properties?.required?.toString()), setOrRemoveAttribute(element, "aria-invalid", properties?.invalid?.toString()), setOrRemoveAttribute(element, "aria-busy", properties?.busy?.toString()), setOrRemoveAttribute(element, "aria-readonly", properties?.readOnly?.toString()), setOrRemoveAttribute(element, "aria-valuetext", !supportsValueText(node.role) || node.selection ? void 0 : properties?.valueDescription?.toString()), setOrRemoveAttribute(element, "aria-posinset", properties?.positionInSet?.toString()), setOrRemoveAttribute(element, "aria-setsize", properties?.setSize?.toString()), setOrRemoveAttribute(element, "aria-rowindex", properties?.rowIndex?.toString()), setOrRemoveAttribute(element, "aria-colindex", properties?.columnIndex?.toString()), setOrRemoveAttribute(element, "aria-rowcount", properties?.rowCount?.toString()), setOrRemoveAttribute(element, "aria-colcount", properties?.columnCount?.toString()), setOrRemoveAttribute(element, "aria-rowspan", properties?.rowSpan?.toString()), setOrRemoveAttribute(element, "aria-colspan", properties?.columnSpan?.toString()), setOrRemoveAttribute(element, "aria-sort", properties?.sort?.toString()), element.tagName === "INPUT" || element.tagName === "TEXTAREA") {
      let input = element;
      if (element.tagName === "INPUT")
        input.type = node.role === "secureField" ? "password" : node.role === "slider" ? "range" : node.role === "stepper" ? "number" : "text";
      input.disabled = node.isEnabled === !1, input.readOnly = properties?.readOnly === !0, input.required = properties?.required === !0, setOrRemoveAttribute(element, "min", node.valueMin === void 0 ? void 0 : String(node.valueMin)), setOrRemoveAttribute(element, "max", node.valueMax === void 0 ? void 0 : String(node.valueMax)), setOrRemoveAttribute(element, "step", node.valueStep === void 0 ? void 0 : String(node.valueStep));
      let value = node.value ? String(node.value.value) : "", pending = this.pendingValues.get(node.id);
      if (!this.composing.has(element) && (pending === void 0 || pending <= this.acknowledgedRequestID)) {
        this.pendingValues.delete(node.id);
        let previous = nativeTextSelection(input);
        if (node.role !== "secureField" && input.value !== value)
          this.compositionCommits.delete(element), input.value = value;
        if (input.selectionStart !== null) {
          let [anchor, head] = node.textSelection ?? [previous.anchor, previous.head], boundedAnchor = Math.min(anchor, input.value.length), boundedHead = Math.min(head, input.value.length);
          if (input.selectionStart !== Math.min(boundedAnchor, boundedHead) || input.selectionEnd !== Math.max(boundedAnchor, boundedHead) || boundedAnchor !== boundedHead && input.selectionDirection !== (boundedHead < boundedAnchor ? "backward" : "forward"))
            input.setSelectionRange(Math.min(boundedAnchor, boundedHead), Math.max(boundedAnchor, boundedHead), boundedHead < boundedAnchor ? "backward" : "forward");
          this.textSelections.set(element, nativeTextSelection(input));
        }
      }
    }
    if (node.selection) {
      let pending = this.pendingValues.get(node.id), synchronizeValue = pending === void 0 || pending <= this.acknowledgedRequestID;
      if (synchronizeValue)
        this.pendingValues.delete(node.id);
      presentSelection(element, node, synchronizeValue, this.isTabStop(node) && !!node.actions?.includes("setValue"));
    }
    let [x, y, width, height] = node.rect, [parentX, parentY] = parent?.rect ?? [0, 0];
    element.style.position = "absolute", element.style.left = `${(x - parentX) * metrics.cellWidth}px`, element.style.top = `${(y - parentY) * metrics.cellHeight}px`, element.style.width = `${Math.max(1, width) * metrics.cellWidth}px`, element.style.height = `${Math.max(1, height) * metrics.cellHeight}px`, element.style.boxSizing = "border-box", element.style.margin = "0", element.style.padding = "0", element.style.border = "0", element.style.minWidth = "0", element.style.minHeight = "0";
  }
  applyRelationships(element, node, elements) {
    let properties = node.properties, references = (ids) => {
      let resolved = [...new Set(ids ?? [])].filter((id) => id !== node.id && elements.has(id)).map((id) => elements.get(id).id);
      return resolved.length ? resolved.join(" ") : void 0;
    };
    setOrRemoveAttribute(element, "aria-labelledby", references(properties?.labelledBy)), setOrRemoveAttribute(element, "aria-describedby", references(properties?.describedBy)), setOrRemoveAttribute(element, "aria-errormessage", references(properties?.errorMessage)), setOrRemoveAttribute(element, "aria-controls", references(properties?.controls)), setOrRemoveAttribute(element, "aria-owns", references(properties?.owns)), setOrRemoveAttribute(element, "aria-flowto", references(properties?.flowTo)), setOrRemoveAttribute(element, "aria-activedescendant", references(properties?.activeDescendant === void 0 ? void 0 : [properties.activeDescendant]));
  }
  announceLiveRegionChanges(nodes, announcements) {
    let candidates = nodes.filter((node) => node.liveRegion && node.liveRegion !== "off" && node.label), currentLabelsById = new Map(candidates.map((node) => [node.id, node.label ?? ""])), imperativeAssertive = announcements.filter((announcement) => announcement.politeness === "assertive"), imperativePolite = announcements.filter((announcement) => announcement.politeness === "polite");
    if (!this.hasLiveRegionBaseline) {
      this.previousLabelsById = currentLabelsById, this.hasLiveRegionBaseline = !0, this.publishAnnouncements([], imperativeAssertive, [], imperativePolite);
      return;
    }
    let changed = candidates.filter((node) => {
      let previous = this.previousLabelsById.get(node.id);
      return previous !== void 0 && previous !== node.label;
    });
    this.previousLabelsById = currentLabelsById;
    let assertive = changed.filter((node) => node.liveRegion === "assertive"), polite = changed.filter((node) => node.liveRegion === "polite");
    this.publishAnnouncements(assertive, imperativeAssertive, polite, imperativePolite);
  }
  publishAnnouncements(assertive, imperativeAssertive, polite, imperativePolite) {
    let ordered = [
      ...assertive,
      ...imperativeAssertive,
      ...polite,
      ...imperativePolite
    ];
    if (ordered.length === 0)
      return;
    let politeness = assertive.length > 0 || imperativeAssertive.length > 0 ? "assertive" : "polite";
    this.announcerElement.setAttribute("aria-live", politeness);
    let message = ordered.map((entry) => {
      if ("message" in entry)
        return entry.message;
      return entry.label ?? "";
    }).join(`
`);
    if (!message.trim()) {
      this.announcerElement.replaceChildren();
      return;
    }
    let content = document.createElement("span");
    content.setAttribute("role", "img"), content.setAttribute("aria-label", message), this.announcerElement.replaceChildren(content);
  }
};
function supportsValueText(role) {
  return [
    "slider",
    "stepper",
    "progressBar",
    "scrollBar",
    "meter"
  ].includes(role);
}
function safeLinkDestination(destination) {
  if (!destination)
    return;
  try {
    let url = new URL(destination);
    return [
      "http:",
      "https:",
      "mailto:",
      "tel:"
    ].includes(url.protocol) ? url.href : void 0;
  } catch {
    return;
  }
}
function setOrRemoveAttribute(element, name, value) {
  if (value === void 0) {
    element.removeAttribute(name);
    return;
  }
  element.setAttribute(name, value);
}
function applyScreenReaderOnlyStyle(element) {
  element.style.position = "absolute", element.style.left = "0", element.style.top = "0", element.style.width = "1px", element.style.height = "1px", element.style.overflow = "hidden", element.style.clipPath = "inset(50%)", element.style.whiteSpace = "nowrap";
}
function roleMapping(role) {
  let heading = /^heading\(level: ([0-9]+)\)$/.exec(role);
  if (heading)
    return {
      role: "heading",
      level: Math.max(1, Math.min(6, Number(heading[1])))
    };
  let custom = /^custom\((.+)\)$/.exec(role);
  if (custom)
    return { role: custom[1] };
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
    case "popover":
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
var presentationKeySeparator = "\x1F";
function presentationNodes(nodes) {
  let used = /* @__PURE__ */ new Set, keysByWireId = /* @__PURE__ */ new Map, keys = nodes.map((node) => {
    let base = node.actionTarget === void 0 ? node.id : `${node.id}${presentationKeySeparator}${node.actionTarget}`, key = base;
    for (let occurrence = 1;used.has(key); occurrence++)
      key = `${base}${presentationKeySeparator}#${occurrence}`;
    used.add(key);
    let group = keysByWireId.get(node.id);
    if (group)
      group.push(key);
    else
      keysByWireId.set(node.id, [key]);
    return key;
  }), unique = (id) => {
    let group = keysByWireId.get(id);
    return group?.length === 1 ? group[0] : group ? void 0 : id;
  }, references = (ids) => ids?.flatMap((id) => unique(id) ?? []), preceding = /* @__PURE__ */ new Map;
  return nodes.map((node, index) => {
    let key = keys[index] ?? node.id, parentId = node.parentId === void 0 ? void 0 : preceding.get(node.parentId) ?? keysByWireId.get(node.parentId)?.[0] ?? node.parentId;
    preceding.set(node.id, key);
    let properties = node.properties && {
      ...node.properties,
      labelledBy: references(node.properties.labelledBy),
      describedBy: references(node.properties.describedBy),
      errorMessage: references(node.properties.errorMessage),
      controls: references(node.properties.controls),
      owns: references(node.properties.owns),
      flowTo: references(node.properties.flowTo),
      activeDescendant: node.properties.activeDescendant === void 0 ? void 0 : unique(node.properties.activeDescendant)
    };
    return {
      ...node,
      id: key,
      parentId,
      properties,
      wireId: node.id
    };
  });
}
function stableDOMId(id) {
  return Array.from(id, (character) => character.codePointAt(0).toString(16)).join("-");
}
function nativeTextSelection(input) {
  let start = input.selectionStart ?? input.value.length, end = input.selectionEnd ?? input.value.length;
  return {
    text: input.value,
    anchor: input.selectionDirection === "backward" ? end : start,
    head: input.selectionDirection === "backward" ? start : end
  };
}

// dist/src/CanvasSurfacePainter.js
var MAX_DECODED_IMAGE_CACHE_BYTES = 67108864, CanvasSurfacePainter = class {
  imageCache = /* @__PURE__ */ new Map;
  unresolvedImageIds = /* @__PURE__ */ new Set;
  unresolvedImagePayloadCharacters = 0;
  imageDecoder;
  onImagePayloadMiss;
  maxDecodedImageCacheEntries;
  maxDecodedImageCacheBytes;
  decodedImageCount = 0;
  decodedImageBytes = 0;
  visibleImageIds = /* @__PURE__ */ new Set;
  inactiveDecodedImageIds = /* @__PURE__ */ new Set;
  disposed = !1;
  canvas;
  requestRedraw = () => {};
  lastEpoch;
  forcedColors = !1;
  pendingImagePayloadMissIds = /* @__PURE__ */ new Set;
  imagePayloadMissScheduled = !1;
  constructor(options = {}) {
    this.imageDecoder = options.decodeImage ?? decodeImage, this.onImagePayloadMiss = options.onImagePayloadMiss ?? (() => {}), this.maxDecodedImageCacheEntries = cacheLimit(options.maxDecodedImageCacheEntries, 256), this.maxDecodedImageCacheBytes = cacheLimit(options.maxDecodedImageCacheBytes, MAX_DECODED_IMAGE_CACHE_BYTES), registerCanvasSurfacePainterConformanceControl(this, {
      evictImages: (ids) => {
        for (let id of ids)
          this.removeCachedImage(id);
      },
      visibleImageIDs: (images) => [...new Set(images.filter(isPaintableSurfaceImage).filter((image) => this.imageCache.get(image.id)?.image !== void 0).map((image) => image.id))].sort()
    });
  }
  attach(canvas, requestRedraw) {
    if (this.disposed)
      return;
    this.canvas = canvas, this.requestRedraw = requestRedraw;
  }
  paint(metrics, frame, damage, recoveredImagePayloadIds = []) {
    if (this.disposed)
      return;
    let canvas = this.canvas, context = canvas?.getContext("2d");
    if (!canvas || !context)
      return;
    if (frame?.epoch !== void 0 && frame.epoch !== this.lastEpoch) {
      this.lastEpoch = frame.epoch;
      for (let cached of this.imageCache.values())
        if (!cached.image)
          cached.missReported = !1;
    }
    this.sweepUnresolvedImages(frame?.images), this.visibleImageIds = new Set((frame?.images ?? []).filter(isPaintableSurfaceImage).map((image) => image.id)), this.inactiveDecodedImageIds.clear();
    for (let [id, cached] of this.imageCache)
      if (cached.image && !this.visibleImageIds.has(id) && isWebHostImageRecoveryId(id))
        this.inactiveDecodedImageIds.add(id);
    this.trimDecodedImages();
    let forcedColors = globalThis.matchMedia?.("(forced-colors: active)").matches ?? !1, colorsChanged = forcedColors !== this.forcedColors;
    this.forcedColors = forcedColors;
    let dirtyRegion = frame && !colorsChanged ? this.dirtyRegionForDamage(damage, frame, metrics) : void 0, recoveredPayloadIds = new Set(recoveredImagePayloadIds);
    if (dirtyRegion?.rects.length === 0) {
      this.prepareImages(frame?.images ?? [], recoveredPayloadIds);
      return;
    }
    let scale = metrics.pixelScale ?? (globalThis.window?.devicePixelRatio || 1);
    if (context.setTransform(scale, 0, 0, scale, 0, 0), context.textBaseline = "alphabetic", context.fillStyle = forcedColors ? "Canvas" : webTUITerminalBackgroundColor(metrics.style), dirtyRegion)
      for (let rect of dirtyRegion.rects)
        context.clearRect(rect.x, rect.y, rect.width, rect.height), context.fillRect(rect.x, rect.y, rect.width, rect.height);
    else
      context.clearRect(0, 0, canvas.width / scale, canvas.height / scale), context.fillRect(0, 0, canvas.width / scale, canvas.height / scale);
    if (!frame)
      return;
    if (dirtyRegion) {
      context.save(), context.beginPath();
      for (let rect of dirtyRegion.rects)
        context.rect(rect.x, rect.y, rect.width, rect.height);
      context.clip();
    }
    try {
      this.drawRows(context, frame, metrics, dirtyRegion), this.drawImages(context, frame.images ?? [], metrics, dirtyRegion, recoveredPayloadIds);
    } finally {
      if (dirtyRegion)
        context.restore();
    }
  }
  dispose() {
    if (this.disposed)
      return;
    this.disposed = !0, this.canvas = void 0, this.requestRedraw = () => {};
    for (let id of this.imageCache.keys())
      this.removeCachedImage(id);
    this.visibleImageIds.clear(), this.inactiveDecodedImageIds.clear(), this.pendingImagePayloadMissIds.clear();
  }
  drawRows(context, frame, metrics, dirtyRegion) {
    if (dirtyRegion) {
      for (let [y, ranges] of dirtyRegion.rows) {
        let row = frame.rows[y] ?? [];
        this.drawRow(context, frame, metrics, row, y, ranges);
      }
      return;
    }
    for (let y = 0;y < frame.rows.length; y += 1) {
      let row = frame.rows[y] ?? [];
      this.drawRow(context, frame, metrics, row, y);
    }
  }
  drawRow(context, frame, metrics, row, y, ranges) {
    for (let cell of row) {
      let [x, text, span, styleIndex] = cell;
      if (ranges !== void 0 && !cellIntersectsRanges(x, span, ranges))
        continue;
      let style = frame.styles[styleIndex] ?? void 0;
      this.drawCell(context, metrics, x, y, text, span, style);
    }
  }
  drawImages(context, images, metrics, dirtyRegion, recoveredPayloadIds) {
    let missingPayloadIds = /* @__PURE__ */ new Set;
    for (let image of images) {
      if (!isPaintableSurfaceImage(image))
        continue;
      this.drawImage(context, image, metrics, dirtyRegion, missingPayloadIds, recoveredPayloadIds);
    }
    this.reportImagePayloadMisses(missingPayloadIds);
  }
  prepareImages(images, recoveredPayloadIds) {
    let missingPayloadIds = /* @__PURE__ */ new Set;
    for (let image of images) {
      if (!isPaintableSurfaceImage(image))
        continue;
      this.cachedImage(image, missingPayloadIds, recoveredPayloadIds);
    }
    this.reportImagePayloadMisses(missingPayloadIds);
  }
  drawImage(context, image, metrics, dirtyRegion, missingPayloadIds, recoveredPayloadIds) {
    let [boundsX, boundsY, boundsWidth, boundsHeight] = image.bounds, [clipX, clipY, clipWidth, clipHeight] = image.visibleBounds;
    if (boundsWidth <= 0 || boundsHeight <= 0 || clipWidth <= 0 || clipHeight <= 0)
      return;
    let decodedImage = this.cachedImage(image, missingPayloadIds, recoveredPayloadIds);
    if (!decodedImage)
      return;
    if (dirtyRegion && !dirtyRegionIntersectsCellRect(dirtyRegion, clipX, clipY, clipWidth, clipHeight))
      return;
    context.save(), context.beginPath(), context.rect(clipX * metrics.cellWidth, clipY * metrics.cellHeight, clipWidth * metrics.cellWidth, clipHeight * metrics.cellHeight), context.clip(), context.globalAlpha = normalizedImageOpacity(image.opacity), context.drawImage(decodedImage, boundsX * metrics.cellWidth, boundsY * metrics.cellHeight, boundsWidth * metrics.cellWidth, boundsHeight * metrics.cellHeight), context.restore();
  }
  cachedImage(image, missingPayloadIds, recoveredPayloadIds) {
    if (!isSupportedImageFormat(image.format))
      return;
    let cached = this.imageCache.get(image.id);
    if (cached?.image)
      return this.imageCache.delete(image.id), this.imageCache.set(image.id, cached), cached.image;
    let beginsRecoveredGeneration = image.dataBase64 !== void 0 && recoveredPayloadIds.delete(image.id);
    if (image.dataBase64 !== void 0 && (cached?.payload === void 0 || beginsRecoveredGeneration)) {
      if (!this.canTrackUnresolvedImage(image.id, image.dataBase64))
        return;
      cached = {
        payload: image.dataBase64,
        retries: 0
      }, this.setUnresolvedImage(image.id, cached);
    } else if (!cached) {
      if (!isWebHostImageRecoveryId(image.id))
        return;
      if (!this.canTrackUnresolvedImage(image.id))
        return;
      cached = { missReported: !1 }, this.setUnresolvedImage(image.id, cached), missingPayloadIds.add(image.id);
      return;
    }
    let attempts = cached.retries ?? 0;
    if (cached.payload === void 0) {
      if (!cached.missReported)
        cached.missReported = !0, missingPayloadIds.add(image.id);
      return;
    }
    if (attempts >= 3) {
      if (!cached.missReported)
        cached.missReported = !0, missingPayloadIds.add(image.id);
      return;
    }
    if (!cached.promise) {
      let nextAttempts = attempts + 1, promise = this.imageDecoder(cached.payload, image.format, image.id);
      cached.promise = promise, cached.retries = nextAttempts, promise.then((decodedImage) => {
        if (this.imageCache.get(image.id)?.promise !== promise) {
          closeDecodedImage(decodedImage);
          return;
        }
        this.removeUnresolvedImage(image.id);
        let decodedBytes = estimatedDecodedImageBytes(decodedImage);
        this.imageCache.delete(image.id), this.imageCache.set(image.id, {
          image: decodedImage,
          decodedBytes
        }), this.decodedImageCount += 1, this.decodedImageBytes += decodedBytes, this.trimDecodedImages(), this.requestRedraw();
      }).catch(() => {
        let latest = this.imageCache.get(image.id);
        if (latest?.promise !== promise)
          return;
        if (latest.promise = void 0, (latest.retries ?? 0) >= 3 && !latest.missReported) {
          if (latest.missReported = !0, isWebHostImageRecoveryId(image.id))
            this.scheduleImagePayloadMiss(image.id);
        }
        this.requestRedraw();
      });
    }
  }
  canTrackUnresolvedImage(id, payload) {
    let existing = this.imageCache.get(id), existingPayloadCharacters = existing?.image ? 0 : existing?.payload?.length ?? 0, nextPayloadCharacters = this.unresolvedImagePayloadCharacters - existingPayloadCharacters + (payload?.length ?? 0);
    return (this.unresolvedImageIds.has(id) || this.unresolvedImageIds.size < 256) && nextPayloadCharacters <= 67108864;
  }
  removeCachedImage(id) {
    let cached = this.imageCache.get(id);
    if (cached?.image)
      this.decodedImageCount -= 1, this.decodedImageBytes -= cached.decodedBytes ?? 0, closeDecodedImage(cached.image);
    this.removeUnresolvedImage(id), this.imageCache.delete(id), this.inactiveDecodedImageIds.delete(id), this.pendingImagePayloadMissIds.delete(id);
  }
  trimDecodedImages() {
    for (let id of this.inactiveDecodedImageIds) {
      if (this.decodedImageCount <= this.maxDecodedImageCacheEntries && this.decodedImageBytes <= this.maxDecodedImageCacheBytes)
        break;
      this.removeCachedImage(id);
    }
  }
  setUnresolvedImage(id, cached) {
    let existing = this.imageCache.get(id);
    if (this.unresolvedImageIds.has(id))
      this.unresolvedImagePayloadCharacters -= existing?.payload?.length ?? 0;
    this.imageCache.set(id, cached), this.unresolvedImageIds.add(id), this.unresolvedImagePayloadCharacters += cached.payload?.length ?? 0, this.pendingImagePayloadMissIds.delete(id);
  }
  removeUnresolvedImage(id) {
    if (!this.unresolvedImageIds.delete(id))
      return;
    this.unresolvedImagePayloadCharacters -= this.imageCache.get(id)?.payload?.length ?? 0, this.pendingImagePayloadMissIds.delete(id);
  }
  sweepUnresolvedImages(images) {
    let presentedIds = /* @__PURE__ */ new Set;
    for (let image of images ?? []) {
      if (!this.unresolvedImageIds.has(image.id))
        continue;
      if (isPaintableSurfaceImage(image))
        presentedIds.add(image.id);
    }
    for (let id of this.unresolvedImageIds) {
      if (presentedIds.has(id))
        continue;
      this.removeUnresolvedImage(id), this.imageCache.delete(id);
    }
  }
  reportImagePayloadMisses(ids) {
    if (ids.size === 0)
      return;
    let candidateIds = [...ids].sort();
    this.applyImagePayloadMissAdmission(candidateIds, this.onImagePayloadMiss(candidateIds));
  }
  scheduleImagePayloadMiss(id) {
    if (this.pendingImagePayloadMissIds.add(id), this.imagePayloadMissScheduled)
      return;
    this.imagePayloadMissScheduled = !0, queueMicrotask(() => {
      if (this.imagePayloadMissScheduled = !1, this.disposed)
        return;
      let ids = [...this.pendingImagePayloadMissIds].sort();
      if (this.pendingImagePayloadMissIds.clear(), ids.length > 0)
        this.applyImagePayloadMissAdmission(ids, this.onImagePayloadMiss(ids));
    });
  }
  applyImagePayloadMissAdmission(candidateIds, admittedIds) {
    let acceptedIds = new Set(Array.isArray(admittedIds) ? admittedIds : candidateIds);
    for (let id of candidateIds) {
      let cached = this.imageCache.get(id);
      if (cached && !cached.image)
        cached.missReported = acceptedIds.has(id);
    }
  }
  drawCell(context, metrics, x, y, text, span, style) {
    let rectX = x * metrics.cellWidth, rectY = y * metrics.cellHeight, width = Math.max(1, span) * metrics.cellWidth, reversed = !!((style?.em ?? 0) & 16), background = this.forcedColors ? reversed ? "CanvasText" : "Canvas" : resolvedSurfaceBackground(style, metrics.style), foreground = this.forcedColors ? reversed ? "Canvas" : "CanvasText" : resolvedSurfaceForeground(style, metrics.style), opacity = style?.opacity ?? 1;
    if (background)
      context.globalAlpha = opacity, context.fillStyle = background, context.fillRect(rectX, rectY, width, metrics.cellHeight);
    if (text !== " " || style?.underline || style?.strikethrough) {
      context.save(), context.beginPath(), context.rect(rectX, rectY, width, metrics.cellHeight), context.clip();
      try {
        if (context.globalAlpha = opacity, text !== " ") {
          if (context.fillStyle = foreground, context.strokeStyle = foreground, !canRenderGeometricGlyph(text) || !emitGlyphGeometry(context, text, {
            x: rectX,
            y: rectY,
            width,
            height: metrics.cellHeight
          }))
            context.font = fontForStyle(metrics.style, style), context.fillText(text, rectX, rectY + Math.floor((metrics.cellHeight + metrics.style.fontSize) / 2) - 2);
        }
        this.drawTextLine(context, metrics, rectX, rectY, width, style?.underline, "underline", foreground), this.drawTextLine(context, metrics, rectX, rectY, width, style?.strikethrough, "strike", foreground);
      } finally {
        context.restore();
      }
    }
    context.globalAlpha = 1;
  }
  dirtyRegionForDamage(damage, frame, metrics) {
    if (!damage || damage.requiresFullTextRepaint || damage.requiresFullGraphicsReplay)
      return;
    let rects = [], rows = /* @__PURE__ */ new Map;
    for (let [row, ranges] of damage.textRows) {
      if (row < 0 || row >= frame.height)
        continue;
      if (ranges.length === 0) {
        rects.push(cellRect(metrics, 0, row, frame.width)), rows.set(row, "full");
        continue;
      }
      let rowRanges = rows.get(row) === "full" ? [] : [...rows.get(row) ?? []];
      for (let [start, end] of ranges) {
        let lowerBound = Math.max(0, Math.min(frame.width, Math.floor(start))), upperBound = Math.max(lowerBound, Math.min(frame.width, Math.ceil(end)));
        if (lowerBound >= upperBound)
          continue;
        rects.push(cellRect(metrics, lowerBound, row, upperBound - lowerBound)), rowRanges.push({
          start: lowerBound,
          end: upperBound
        });
      }
      if (rows.get(row) !== "full" && rowRanges.length > 0)
        rows.set(row, normalizeCellRanges(rowRanges));
    }
    return {
      rects,
      rows
    };
  }
  drawTextLine(context, metrics, x, y, width, line, placement, fallbackColor) {
    if (!line)
      return;
    context.strokeStyle = this.forcedColors ? fallbackColor : line.color ?? fallbackColor, context.fillStyle = this.forcedColors ? fallbackColor : line.color ?? fallbackColor;
    let lineY = placement === "underline" ? y + metrics.cellHeight - 2 : y + Math.floor(metrics.cellHeight / 2);
    emitTextDecoration(context, line.pattern, x, lineY, width);
  }
};
function cacheLimit(value, fallback) {
  return value !== void 0 && Number.isFinite(value) ? Math.max(0, Math.floor(value)) : fallback;
}
function estimatedDecodedImageBytes(image) {
  let dimensions = image, width = dimensions.naturalWidth ?? dimensions.width, height = dimensions.naturalHeight ?? dimensions.height;
  if (typeof width !== "number" || typeof height !== "number" || !Number.isFinite(width) || !Number.isFinite(height) || width < 0 || height < 0)
    return 0;
  return Math.min(Number.MAX_SAFE_INTEGER, Math.ceil(width) * Math.ceil(height) * 4);
}
function closeDecodedImage(image) {
  image.close?.();
}
function normalizedImageOpacity(opacity) {
  if (opacity === void 0 || !Number.isFinite(opacity))
    return 1;
  return Math.max(0, Math.min(1, opacity));
}
function isPaintableSurfaceImage(image) {
  let [, , boundsWidth, boundsHeight] = image.bounds, [, , clipWidth, clipHeight] = image.visibleBounds;
  return isSupportedImageFormat(image.format) && boundsWidth > 0 && boundsHeight > 0 && clipWidth > 0 && clipHeight > 0;
}
function cellRect(metrics, x, y, span) {
  return {
    x: x * metrics.cellWidth,
    y: y * metrics.cellHeight,
    width: Math.max(1, span) * metrics.cellWidth,
    height: metrics.cellHeight
  };
}
async function decodeImage(dataBase64, format) {
  let bytes = decodeBase64Bytes(dataBase64);
  if (!admitsImageBytes(bytes))
    throw Error("Image exceeds the raster budget or has an unsupported container");
  if (format === "gif")
    bytes = firstGifFrame(bytes);
  let blob = new Blob([bytes], { type: `image/${format}` });
  if (typeof createImageBitmap === "function")
    return createImageBitmap(blob);
  return new Promise((resolve, reject) => {
    let image = new Image, url = URL.createObjectURL(blob);
    image.onload = () => {
      URL.revokeObjectURL(url), resolve(image);
    }, image.onerror = () => {
      URL.revokeObjectURL(url), reject(/* @__PURE__ */ Error(`Failed to decode ${format} image`));
    }, image.src = url;
  });
}
function decodeBase64Bytes(value) {
  if (typeof atob === "function") {
    let binary = atob(value), bytes = new Uint8Array(binary.length);
    for (let index = 0;index < binary.length; index += 1)
      bytes[index] = binary.charCodeAt(index);
    return bytes;
  }
  return new Uint8Array(Buffer.from(value, "base64"));
}
function normalizeCellRanges(ranges) {
  let sorted = ranges.filter((range) => range.end > range.start).sort((lhs, rhs) => lhs.start - rhs.start || lhs.end - rhs.end), normalized = [];
  for (let range of sorted) {
    let previous = normalized[normalized.length - 1];
    if (previous && range.start <= previous.end) {
      previous.end = Math.max(previous.end, range.end);
      continue;
    }
    normalized.push({ ...range });
  }
  return normalized;
}
function cellIntersectsRanges(x, span, ranges) {
  if (ranges === "full")
    return !0;
  let start = Math.floor(x), end = start + Math.max(1, Math.ceil(span));
  return ranges.some((range) => start < range.end && end > range.start);
}
function dirtyRegionIntersectsCellRect(region, x, y, width, height) {
  let startRow = Math.max(0, Math.floor(y)), endRow = Math.max(startRow, Math.ceil(y + height)), rectRange = {
    start: Math.floor(x),
    end: Math.floor(x) + Math.max(1, Math.ceil(width))
  };
  for (let row = startRow;row < endRow; row += 1) {
    let ranges = region.rows.get(row);
    if (!ranges)
      continue;
    if (cellIntersectsRanges(rectRange.start, rectRange.end - rectRange.start, ranges))
      return !0;
  }
  return !1;
}

// dist/src/DomFocusPresentation.js
var DomFocusPresentation = class {
  terminal;
  selecting;
  element = document.createElement("div");
  ring = document.createElement("div");
  caret = document.createElement("div");
  hasFocus = !1;
  presentation;
  constructor(terminal, selecting) {
    this.terminal = terminal, this.selecting = selecting, this.element.className = "webhost-scene__focus-layer", this.element.setAttribute("aria-hidden", "true"), Object.assign(this.element.style, {
      position: "absolute",
      pointerEvents: "none",
      userSelect: "none",
      zIndex: "3",
      boxSizing: "border-box",
      margin: "0",
      padding: "0",
      border: "0"
    }), this.ring.className = "webhost-scene__focus-ring", this.caret.className = "webhost-scene__caret";
    for (let item of [this.ring, this.caret])
      Object.assign(item.style, {
        position: "absolute",
        boxSizing: "border-box",
        margin: "0",
        padding: "0",
        border: "0",
        minWidth: "0",
        maxWidth: "none",
        minHeight: "0",
        maxHeight: "none",
        pointerEvents: "none"
      });
    this.element.append(this.ring, this.caret), this.element.hidden = !0, terminal.appendChild(this.element), terminal.addEventListener("focusin", this.refresh), terminal.addEventListener("focusout", this.refresh);
  }
  refresh = () => {
    if (this.presentation)
      this.paintFocus();
    this.element.hidden = !this.hasFocus || this.selecting() || !this.terminal.contains?.(document.activeElement), this.element.style.display = this.element.hidden ? "none" : "block";
  };
  present(frame, metrics, offsetX = 0, offsetY = 0) {
    this.presentation = {
      frame,
      metrics,
      offsetX,
      offsetY
    }, this.refresh();
  }
  paintFocus() {
    let { frame, metrics, offsetX, offsetY } = this.presentation, active = document.activeElement?.closest("[data-accessibility-id]"), activeID = active && this.terminal.contains(active) ? active.dataset.accessibilityId : void 0, focused = frame?.accessibilityTree?.find((node) => !node.hidden && (activeID ? node.id === activeID : node.isFocused));
    if (this.hasFocus = focused !== void 0, this.element.style.left = `${offsetX}px`, this.element.style.top = `${offsetY}px`, this.element.style.width = `${metrics.columns * metrics.cellWidth}px`, this.element.style.height = `${metrics.rows * metrics.cellHeight}px`, this.element.style.overflow = "hidden", focused) {
      let [x, y, width, height] = focused.rect, forced = globalThis.matchMedia?.("(forced-colors: active)").matches, color = forced ? "CanvasText" : focusColor(metrics.style.theme.background), companionColor = forced ? "Canvas" : color === "#000000" ? "#ffffff" : "#000000";
      Object.assign(this.ring.style, {
        left: `${x * metrics.cellWidth}px`,
        top: `${y * metrics.cellHeight}px`,
        width: `${Math.max(1, width) * metrics.cellWidth}px`,
        height: `${Math.max(1, height) * metrics.cellHeight}px`,
        outline: `2px solid ${color}`,
        outlineOffset: "-2px",
        boxShadow: `inset 0 0 0 4px ${companionColor}`,
        forcedColorAdjust: "none"
      });
      let anchor = focused.cursorAnchor;
      if (this.caret.hidden = !anchor || !focused.isFocused || focused.isEnabled === !1 || ![
        "textField",
        "textEditor",
        "secureField"
      ].includes(focused.role), this.caret.style.display = this.caret.hidden ? "none" : "block", anchor)
        Object.assign(this.caret.style, {
          left: `${anchor[0] * metrics.cellWidth}px`,
          top: `${anchor[1] * metrics.cellHeight}px`,
          width: "2px",
          height: `${metrics.cellHeight}px`,
          background: color,
          boxShadow: `1px 0 0 ${companionColor}`,
          forcedColorAdjust: "none"
        });
    }
  }
  dispose() {
    this.terminal.removeEventListener("focusin", this.refresh), this.terminal.removeEventListener("focusout", this.refresh), this.hasFocus = !1, this.presentation = void 0, this.element.remove();
  }
};
function focusColor(background) {
  let hex = background.match(/^#([\da-f]{6})/i)?.[1];
  if (!hex)
    return "#ffffff";
  let channels = [
    0,
    2,
    4
  ].map((offset) => parseInt(hex.slice(offset, offset + 2), 16) / 255).map((value) => value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4), luminance = channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722;
  return (luminance + 0.05) / 0.05 >= 1.05 / (luminance + 0.05) ? "#000000" : "#ffffff";
}

// dist/src/DomCellMetrics.js
var DomCellProbe = class {
  mount;
  element;
  faces;
  styleKey;
  canvas;
  constructor(mount) {
    this.mount = mount;
    let doc = mount.ownerDocument ?? document;
    this.canvas = mount.querySelector?.("canvas.webhost-scene__surface") ?? void 0, this.element = doc.createElement("div"), this.element.setAttribute("aria-hidden", "true"), Object.assign(this.element.style, {
      position: "absolute",
      visibility: "hidden",
      pointerEvents: "none",
      userSelect: "none",
      width: "max-content",
      height: "auto",
      left: "0",
      top: "0",
      overflow: "hidden",
      contain: "layout style",
      margin: "0",
      padding: "0",
      border: "0"
    }), this.faces = [
      0,
      1,
      2,
      3
    ].map(() => {
      let line = doc.createElement("div"), text = doc.createElement("span"), baseline = doc.createElement("span");
      return Object.assign(baseline.style, {
        display: "inline-block",
        width: "0",
        height: "0",
        padding: "0",
        margin: "0",
        border: "0",
        verticalAlign: "baseline"
      }), line.append(text, baseline), this.element.appendChild(line), {
        line,
        text,
        baseline
      };
    }), mount.appendChild(this.element);
  }
  configure(style) {
    let key = fontForStyle(style);
    if (key === this.styleKey)
      return;
    this.styleKey = key, this.faces.forEach(({ line, text }, em) => {
      Object.assign(line.style, {
        display: "block",
        width: "max-content",
        height: "auto",
        padding: "0",
        margin: "0",
        border: "0",
        font: fontForStyle(style, { em }),
        lineHeight: this.canvas ? "1.35" : "1.5",
        whiteSpace: "pre"
      }), Object.assign(text.style, {
        display: "inline",
        font: "inherit",
        lineHeight: this.canvas ? "1.35" : "1.5",
        padding: "0",
        margin: "0",
        border: "0",
        fontVariantLigatures: "none",
        fontKerning: "none",
        fontSynthesis: "none",
        letterSpacing: "0px",
        wordSpacing: "0px",
        whiteSpace: "pre",
        direction: "ltr",
        unicodeBidi: "isolate"
      }), text.textContent = "W".repeat(64);
    });
  }
  measure(style, scaleX = 1, scaleY = scaleX) {
    let canvasCSS = this.canvas && this.mount.ownerDocument?.defaultView?.getComputedStyle(this.canvas);
    if (canvasCSS)
      style = {
        ...style,
        fontSize: Number.parseFloat(canvasCSS.fontSize) || style.fontSize,
        fontFamily: canvasCSS.fontFamily || style.fontFamily
      };
    this.configure(style);
    let spacing = readDomTextSpacing(this.mount);
    for (let { line, text } of this.faces)
      line.style.lineHeight = text.style.lineHeight = spacing.lineHeight === void 0 ? this.canvas ? "1.35" : "1.5" : `${spacing.lineHeight}px`, text.style.letterSpacing = `${spacing.letterSpacing ?? 0}px`, text.style.wordSpacing = `${spacing.wordSpacing ?? 0}px`;
    let width = 0, height = 0, baseline = 0;
    for (let face2 of this.faces) {
      let rect = face2.text.getBoundingClientRect(), line = face2.line.getBoundingClientRect();
      if (!(rect.width > 0 && line.height > 0))
        return;
      width = Math.max(width, rect.width / scaleX / 64), height = Math.max(height, line.height / scaleY), baseline = Math.max(baseline, (face2.baseline.getBoundingClientRect().top - line.top) / scaleY);
    }
    let baseAdvance = width, face = this.faces[0];
    for (let [sample, span] of [
      [" ", 1],
      ["é", 1],
      ["漢", 2],
      ["\uD83D\uDE42", 2],
      ["\uD83D\uDC69‍\uD83D\uDCBB", 2]
    ]) {
      face.text.textContent = sample;
      let rect = face.text.getBoundingClientRect();
      width = Math.max(width, rect.width / scaleX / span), height = Math.max(height, face.line.getBoundingClientRect().height / scaleY);
    }
    if (face.text.textContent = "W".repeat(64), ![
      width,
      height,
      baseline
    ].every(Number.isFinite) || width <= 0 || height <= 0)
      return;
    let computed = this.mount.ownerDocument?.defaultView?.getComputedStyle(face.text);
    return {
      width: Math.ceil(width - 0.03125),
      height: Math.ceil(height - 0.03125),
      advance: baseAdvance,
      baseline,
      fontSize: Number.parseFloat(computed?.fontSize ?? "") || style.fontSize,
      fontFamily: computed?.fontFamily || style.fontFamily,
      spacingKey: JSON.stringify(spacing)
    };
  }
  dispose() {
    this.element.remove();
  }
};

// dist/src/DomGeometry.js
function makeDomGeometry(revision, fontIdentity, cells, content) {
  let numbers = [
    revision,
    cells.width,
    cells.height,
    cells.baseline,
    cells.fontSize,
    ...Object.values(content)
  ];
  if (!Number.isSafeInteger(revision) || revision < 1 || !numbers.every(Number.isFinite) || content.width <= 0 || content.height <= 0 || cells.width <= 0 || cells.height <= 0 || content.scaleX <= 0 || content.scaleY <= 0)
    return;
  let cellWidth = Math.ceil(cells.width), cellHeight = Math.ceil(cells.height), requestedColumns = Math.floor(content.width / cellWidth), requestedRows = Math.floor(content.height / cellHeight);
  if (requestedColumns < 1 || requestedRows < 1)
    return;
  let columns = Math.min(HOST_WIRE_MAX_GRID_DIMENSION, requestedColumns), rows = Math.min(HOST_WIRE_MAX_GRID_DIMENSION, requestedRows, Math.floor(HOST_WIRE_MAX_GRID_CELLS / columns));
  return Object.freeze({
    revision,
    fontIdentity,
    fontSize: cells.fontSize,
    cellWidth,
    cellHeight,
    baseline: cells.baseline,
    columns,
    rows,
    content: Object.freeze({ ...content }),
    bounded: columns !== requestedColumns || rows !== requestedRows
  });
}
function validateTransforms(mount) {
  let view = mount.ownerDocument?.defaultView;
  if (!view)
    return;
  for (let node = mount;node; node = node.parentElement) {
    let css = view.getComputedStyle(node);
    if (css.perspective !== "none" || css.rotate && css.rotate !== "none" && css.rotate !== "0deg")
      throw Error("DOM host supports positive axis-aligned scale and translation; rotation, skew and perspective require a different embedding.");
    if (css.scale && css.scale !== "none" && css.scale.split(/\s+/).some((v) => Number(v) <= 0))
      throw Error("DOM host requires a positive embedding scale.");
    if (css.transform !== "none") {
      let matrix = new DOMMatrixReadOnly(css.transform);
      if (!matrix.is2D || Math.abs(matrix.b) > 0.00000001 || Math.abs(matrix.c) > 0.00000001 || matrix.a <= 0 || matrix.d <= 0)
        throw Error("DOM host supports positive axis-aligned scale and translation; rotation, skew and perspective require a different embedding.");
    }
  }
}
function measureDomContentBox(mount) {
  let rect = mount.getBoundingClientRect();
  if (!(rect.width > 0 && rect.height > 0))
    return;
  validateTransforms(mount);
  let css = mount.ownerDocument?.defaultView?.getComputedStyle(mount), number = (value) => Number.parseFloat(value ?? "") || 0, pl = number(css?.paddingLeft), pr = number(css?.paddingRight), pt = number(css?.paddingTop), pb = number(css?.paddingBottom), bl = number(css?.borderLeftWidth), br = number(css?.borderRightWidth), bt = number(css?.borderTopWidth), bb = number(css?.borderBottomWidth), borderBox = css?.boxSizing === "border-box", width = css ? number(css.width) - (borderBox ? pl + pr + bl + br : 0) : rect.width, height = css ? number(css.height) - (borderBox ? pt + pb + bt + bb : 0) : rect.height, scaleX = rect.width / (width + pl + pr + bl + br), scaleY = rect.height / (height + pt + pb + bt + bb);
  if (!(width > 0 && height > 0 && scaleX > 0 && scaleY > 0))
    return;
  return {
    width,
    height,
    scaleX,
    scaleY,
    left: rect.left + (bl + pl) * scaleX,
    top: rect.top + (bt + pt) * scaleY,
    offsetX: pl,
    offsetY: pt
  };
}
var DomGeometryController = class {
  mount;
  probe;
  pending;
  presented;
  paragraphProbe;
  paragraphSupport = !1;
  typography;
  constructor(mount) {
    this.mount = mount, this.probe = new DomCellProbe(mount);
  }
  resetParagraphs() {
    this.paragraphSupport = !1, this.paragraphProbe?.remove(), this.paragraphProbe = void 0;
  }
  enableParagraphs() {
    if (this.paragraphSupport)
      return !1;
    return this.paragraphSupport = !0, !0;
  }
  paragraphSpacing(style, cellHeight) {
    if (!this.paragraphSupport)
      return;
    let view = this.mount.ownerDocument?.defaultView;
    if (!view)
      return 0;
    if (!this.paragraphProbe?.isConnected) {
      let probe = this.mount.ownerDocument.createElement("p");
      probe.className = "webhost-scene__paragraph", probe.setAttribute("data-paragraph-probe", ""), probe.setAttribute("aria-hidden", "true"), Object.assign(probe.style, {
        position: "absolute",
        visibility: "hidden",
        pointerEvents: "none",
        width: "0",
        height: "0",
        margin: "0",
        padding: "0",
        overflow: "hidden"
      }), (this.mount.querySelector(".webhost-scene__surface-rows") ?? this.mount).appendChild(probe), this.paragraphProbe = probe;
    }
    this.paragraphProbe.style.font = fontForStyle(style);
    let pixels = 0;
    for (let paragraph of this.mount.querySelectorAll("p.webhost-scene__paragraph")) {
      let margin = Number.parseFloat(view.getComputedStyle(paragraph).marginBottom);
      if (Number.isFinite(margin))
        pixels = Math.max(pixels, margin);
    }
    return Math.min(8192, Math.ceil(pixels / cellHeight));
  }
  measure(style) {
    let content = measureDomContentBox(this.mount);
    if (!content)
      return;
    let cells = this.probe.measure(style, content.scaleX, content.scaleY);
    if (!cells)
      return;
    let prior = this.typography;
    if (prior?.identity === (cells.fontFamily ?? style.fontFamily) && prior.cells.fontSize === cells.fontSize && prior.cells.spacingKey === cells.spacingKey && Math.abs(prior.cells.advance - cells.advance) <= 0.03125 && prior.cells.height === cells.height)
      cells = prior.cells;
    else
      this.typography = {
        identity: cells.fontFamily ?? style.fontFamily,
        cells
      };
    let previous = this.pending, measured = makeDomGeometry(previous?.revision ?? 1, cells.fontFamily ?? style.fontFamily, cells, content);
    if (!measured)
      return;
    let next = {
      ...measured,
      paragraphSpacing: this.paragraphSpacing({
        ...style,
        fontSize: cells.fontSize,
        fontFamily: cells.fontFamily ?? style.fontFamily
      }, measured.cellHeight)
    }, layoutChanged = previous && [
      "fontIdentity",
      "fontSize",
      "cellWidth",
      "cellHeight",
      "paragraphSpacing",
      "columns",
      "rows"
    ].some((key) => previous[key] !== next[key]);
    if (layoutChanged && previous.revision >= Number.MAX_SAFE_INTEGER)
      throw Error("DOM geometry revision exhausted; remount the scene.");
    return this.pending = Object.freeze({
      ...next,
      revision: next.revision + (layoutChanged ? 1 : 0)
    }), this.pending;
  }
  present(snapshot) {
    this.presented = snapshot;
  }
  dispose() {
    this.probe.dispose(), this.paragraphProbe?.remove(), this.paragraphProbe = void 0, this.pending = void 0, this.presented = void 0;
  }
};

// dist/src/HostGeometrySession.js
var HostGeometrySession = class {
  acknowledged = !1;
  sentRevision;
  latest;
  presentedRevision;
  presentedViewportRevision;
  hasPresentedFrame = !1;
  get negotiated() {
    return this.acknowledged;
  }
  get allowsPointer() {
    return this.hasPresentedFrame;
  }
  get pointerRevision() {
    return this.acknowledged ? this.presentedRevision : void 0;
  }
  get pointerViewportRevision() {
    return this.presentedViewportRevision;
  }
  request(geometry) {
    if (!isHostGeometryRequest(geometry))
      throw RangeError("Invalid host geometry request");
    if (this.latest && geometry.revision < this.latest.revision)
      throw RangeError("Geometry revision cannot regress");
    if (this.latest && geometry.revision === this.latest.revision && [
      "columns",
      "rows",
      "cellWidth",
      "cellHeight",
      "paragraphSpacing"
    ].some((key) => this.latest[key] !== geometry[key]))
      throw RangeError("A geometry revision cannot name different metrics");
    this.latest = Object.freeze({ ...geometry });
  }
  observe(frame) {
    if (frame.geometryRevision === 0)
      this.acknowledged = !0;
  }
  takeRequest() {
    if (!this.acknowledged || !this.latest || this.sentRevision === this.latest.revision)
      return;
    return this.sentRevision = this.latest.revision, this.latest;
  }
  canPresent(frame) {
    if (!this.acknowledged)
      return frame?.geometryRevision === void 0;
    return !!frame && !!this.latest && frame.geometryRevision === this.latest.revision && (frame.viewportRevision === void 0 ? frame.width === this.latest.columns && frame.height === this.latest.rows : frame.width <= this.latest.columns && frame.height <= this.latest.rows);
  }
  didPresent(frame) {
    if (!this.canPresent(frame))
      throw Error("Presentation does not match requested geometry");
    this.presentedRevision = frame?.geometryRevision, this.presentedViewportRevision = frame?.viewportRevision, this.hasPresentedFrame = frame !== void 0;
  }
  resetConnection() {
    if (this.latest?.paragraphSpacing !== void 0)
      this.latest = void 0;
    this.acknowledged = !1, this.sentRevision = void 0, this.presentedRevision = void 0, this.presentedViewportRevision = void 0, this.hasPresentedFrame = !1;
  }
};

// dist/src/InputEventEncoder.js
var DOM_DELTA_LINE = 1, DOM_DELTA_PAGE = 2, noWheelTravel = {
  travel: 0,
  unitsPerCell: 1
}, InputEventEncoder = class {
  wheelCarryX = noWheelTravel;
  wheelCarryY = noWheelTravel;
  encodeKey(event) {
    let key = keyInputFromKeyboardEvent(event);
    if (!key)
      return;
    return encodeKeyInputMessage({
      ...key,
      modifiers: modifierMask(event)
    });
  }
  encodePaste(text) {
    return encodePasteInputMessage(text);
  }
  encodePointerDown(location, button, event, geometryRevision, viewportRevision) {
    return encodeMouseInputMessage({
      kind: "down",
      x: location.x,
      y: location.y,
      button,
      modifiers: modifierMask(event)
    }, geometryRevision, viewportRevision);
  }
  encodePointerUp(location, button, event, geometryRevision, viewportRevision) {
    return encodeMouseInputMessage({
      kind: "up",
      x: location.x,
      y: location.y,
      button,
      modifiers: modifierMask(event)
    }, geometryRevision, viewportRevision);
  }
  encodePointerCancel(location, geometryRevision, viewportRevision) {
    return encodeMouseInputMessage({
      kind: "cancelled",
      x: location.x,
      y: location.y
    }, geometryRevision, viewportRevision);
  }
  encodePointerMove(location, button, event, geometryRevision, viewportRevision) {
    return encodeMouseInputMessage({
      kind: event.buttons ? "dragged" : "moved",
      x: location.x,
      y: location.y,
      button,
      modifiers: modifierMask(event)
    }, geometryRevision, viewportRevision);
  }
  encodeWheel(location, event, metrics, geometryRevision, viewportRevision) {
    let mode = event.deltaMode, [deltaX, carryX] = wholeWheelCells(this.wheelCarryX, wheelTravel(event.deltaX, mode, metrics.cellWidth, metrics.columns)), [deltaY, carryY] = wholeWheelCells(this.wheelCarryY, wheelTravel(event.deltaY, mode, metrics.cellHeight, metrics.rows));
    if (this.wheelCarryX = carryX, this.wheelCarryY = carryY, deltaX === 0 && deltaY === 0)
      return;
    return encodeMouseInputMessage({
      kind: "scrolled",
      x: location.x,
      y: location.y,
      deltaX,
      deltaY,
      modifiers: modifierMask(event)
    }, geometryRevision, viewportRevision);
  }
  observeUnforwardedWheel(event) {
    this.wheelCarryX = droppingReversedCarry(this.wheelCarryX, event.deltaX), this.wheelCarryY = droppingReversedCarry(this.wheelCarryY, event.deltaY);
  }
  pointerButton(button) {
    return pointerButton(button);
  }
};
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
      let characters = Array.from(event.key);
      if (characters.length !== 1)
        return;
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
  if (event.shiftKey)
    mask |= 1;
  if (event.altKey)
    mask |= 2;
  if (event.ctrlKey)
    mask |= 4;
  return mask;
}
function wheelTravel(delta, mode, pitch, extent) {
  if (!Number.isFinite(delta) || delta === 0)
    return;
  switch (mode) {
    case DOM_DELTA_LINE:
      return {
        travel: delta,
        unitsPerCell: 1
      };
    case DOM_DELTA_PAGE:
      return {
        travel: delta * (Number.isFinite(extent) && extent >= 1 ? extent : 1),
        unitsPerCell: 1
      };
    default:
      return Number.isFinite(pitch) && pitch > 0 ? {
        travel: delta,
        unitsPerCell: pitch
      } : {
        travel: Math.sign(delta),
        unitsPerCell: 1
      };
  }
}
function wholeWheelCells(carry, next) {
  if (!next)
    return [0, carry];
  let unit = next.unitsPerCell, kept = droppingReversedCarry(carry, next.travel), total = (kept.unitsPerCell === unit ? kept.travel : kept.travel / kept.unitsPerCell * unit) + next.travel;
  if (Math.abs(total) > 16 * unit)
    return [Math.sign(total) * 16, {
      travel: 0,
      unitsPerCell: unit
    }];
  let remainder = total % unit;
  return [Math.round((total - remainder) / unit) || 0, {
    travel: remainder,
    unitsPerCell: unit
  }];
}
function droppingReversedCarry(carry, delta) {
  return Number.isFinite(delta) && delta !== 0 && Math.sign(delta) !== Math.sign(carry.travel) ? {
    travel: 0,
    unitsPerCell: carry.unitsPerCell
  } : carry;
}

// dist/src/PointerGeometry.js
function cellLocationForEvent(event, metrics) {
  let location = rawCellLocationForEvent(event, metrics);
  if (!location)
    return;
  let cellX = Math.floor(location.x), cellY = Math.floor(location.y);
  if (cellX < 0 || cellY < 0 || cellX >= metrics.columns || cellY >= metrics.rows)
    return;
  return location;
}
function rawCellLocationForEvent(event, metrics) {
  let rect = metrics.rect;
  if (!rect)
    return;
  return {
    x: (event.clientX - rect.left) / metrics.cellWidth,
    y: (event.clientY - rect.top) / metrics.cellHeight
  };
}
function linkTargetAt(links, linkTargets, location) {
  if (!links || !linkTargets || linkTargets.length === 0)
    return;
  let cellX = Math.floor(location.x), cellY = Math.floor(location.y);
  for (let [row, runs] of links) {
    if (row !== cellY)
      continue;
    for (let [x, span, targetIndex] of runs)
      if (cellX >= x && cellX < x + span)
        return linkTargets[targetIndex];
  }
}
function wheelTargetCanScroll(regions, location, deltaX, deltaY) {
  if (!regions || regions.length === 0)
    return !1;
  let cellX = Math.floor(location.x), cellY = Math.floor(location.y);
  for (let region of regions) {
    let [rx, ry, rw, rh] = region.rect;
    if (cellX < rx || cellY < ry || cellX >= rx + rw || cellY >= ry + rh)
      continue;
    if (regionCanScrollInDirection(region, deltaX, deltaY))
      return !0;
  }
  return !1;
}
function regionCanScrollInDirection(region, deltaX, deltaY) {
  let [, , viewportWidth, viewportHeight] = region.rect, [offsetX, offsetY] = region.offset, [contentWidth, contentHeight] = region.content, maxX = Math.max(0, contentWidth - viewportWidth), maxY = Math.max(0, contentHeight - viewportHeight), clampedX = Math.min(Math.max(0, offsetX), maxX), clampedY = Math.min(Math.max(0, offsetY), maxY);
  if (deltaY > 0 && clampedY < maxY)
    return !0;
  if (deltaY < 0 && clampedY > 0)
    return !0;
  if (deltaX > 0 && clampedX < maxX)
    return !0;
  if (deltaX < 0 && clampedX > 0)
    return !0;
  return !1;
}

// dist/src/SurfacePaintScheduler.js
function defaultAnimationFrameScheduler() {
  let { requestAnimationFrame: request, cancelAnimationFrame: cancel } = globalThis;
  if (typeof request !== "function" || typeof cancel !== "function")
    return;
  return {
    requestAnimationFrame: (callback) => request.call(globalThis, callback),
    cancelAnimationFrame: (handle) => cancel.call(globalThis, handle)
  };
}
var SurfacePaintScheduler = class {
  animationFrames;
  paint;
  canPresent;
  onResourceLimit;
  pending;
  lastPaintedFrame;
  handle;
  disposed = !1;
  held = !1;
  presentedFrames = 0;
  paints = 0;
  coalescedFrames = 0;
  resourceLimitExceeded = !1;
  constructor(animationFrames, paint, canPresent = () => !0, onResourceLimit = () => {}) {
    this.animationFrames = animationFrames, this.paint = paint, this.canPresent = canPresent, this.onResourceLimit = onResourceLimit;
  }
  get statistics() {
    return {
      presentedFrames: this.presentedFrames,
      paints: this.paints,
      coalescedFrames: this.coalescedFrames,
      pending: this.pending !== void 0,
      carriedImagePayloadBytes: [...this.pending?.carriedImagePayloads.values() ?? []].reduce((total, value) => total + value.length * 2, 0),
      queuedAnnouncements: this.pending?.accessibilityAnnouncements.length ?? 0,
      queuedAnnouncementBytes: this.pending?.announcementBytes ?? 0,
      resourceLimitExceeded: this.resourceLimitExceeded
    };
  }
  get batchesPaints() {
    return this.animationFrames !== void 0;
  }
  present(frame, recoveredImagePayloadIds = []) {
    if (this.disposed)
      return;
    this.presentedFrames += 1;
    let pending = this.pending, keepEligibleCandidate = !this.canPresent(frame) && pending?.frame !== void 0 && this.canPresent(pending.frame), damage = promotesToFullRepaint(pending ? pending.frame : this.lastPaintedFrame, frame) ? void 0 : pending ? unionSurfaceDamage(pending.damage, frame.damage) : frame.damage, next = pending ?? {
      frame: void 0,
      damage: void 0,
      carriedImagePayloads: /* @__PURE__ */ new Map,
      recoveredImagePayloadIds: /* @__PURE__ */ new Set,
      accessibilityAnnouncements: [],
      coalescedFrameCount: 0,
      announcementBytes: 0
    };
    if (pending?.frame && pending.frame !== this.lastPaintedFrame) {
      for (let image of pending.frame.images ?? [])
        if (image.dataBase64 !== void 0)
          next.carriedImagePayloads.set(image.id, image.dataBase64);
      next.coalescedFrameCount += 1, this.coalescedFrames += 1;
    }
    if (keepEligibleCandidate) {
      for (let image of frame.images ?? [])
        if (image.dataBase64 !== void 0)
          next.carriedImagePayloads.set(image.id, image.dataBase64);
      next.damage = void 0;
    } else
      next.frame = frame, next.damage = damage;
    let visibleIDs = new Set(next.frame?.images?.map((image) => image.id)), carriedBytes = 0;
    for (let [id, payload] of next.carriedImagePayloads) {
      let bytes2 = payload.length * 2;
      if (!visibleIDs.has(id) || carriedBytes + bytes2 > 67108864)
        next.carriedImagePayloads.delete(id);
      else
        carriedBytes += bytes2;
    }
    for (let id of next.recoveredImagePayloadIds)
      if (!visibleIDs.has(id))
        next.recoveredImagePayloadIds.delete(id);
    for (let id of recoveredImagePayloadIds) {
      if (next.recoveredImagePayloadIds.size >= 1024)
        next.recoveredImagePayloadIds.delete(next.recoveredImagePayloadIds.values().next().value);
      next.recoveredImagePayloadIds.add(id);
    }
    let announcements = frame.accessibilityAnnouncements ?? [], bytes = announcements.reduce((total, item) => total + item.message.length * 2, 0);
    if (next.accessibilityAnnouncements.length + announcements.length > 1024 || next.announcementBytes + bytes > 262144) {
      this.resourceLimitExceeded = !0, this.dispose(), this.onResourceLimit("WebHost stopped: the pending announcement queue exceeded 1,024 messages or 256 KiB. Reload the scene to restart.");
      return;
    }
    next.announcementBytes += bytes, next.accessibilityAnnouncements.push(...announcements), this.pending = next, this.schedule();
  }
  requestRepaint() {
    if (this.disposed)
      return;
    this.promoteToFullRepaint(), this.schedule();
  }
  repaintNow() {
    if (this.disposed)
      return;
    this.promoteToFullRepaint(), this.flush();
  }
  flush() {
    if (this.disposed || this.held)
      return;
    this.cancelScheduled();
    let pending = this.pending;
    if (!pending)
      return;
    if (!this.canPresent(pending.frame))
      return;
    this.pending = void 0;
    let frame = pending.frame ? spliceCarriedImagePayloads(pending.frame, pending.carriedImagePayloads) : void 0;
    this.lastPaintedFrame = frame, this.paints += 1, this.paint({
      frame,
      damage: pending.damage,
      recoveredImagePayloadIds: [...pending.recoveredImagePayloadIds].sort(),
      accessibilityAnnouncements: pending.accessibilityAnnouncements,
      coalescedFrameCount: pending.coalescedFrameCount
    });
  }
  reprojectVisible() {
    if (this.disposed || !this.lastPaintedFrame)
      return;
    this.paints++, this.paint({
      frame: this.lastPaintedFrame,
      damage: void 0,
      recoveredImagePayloadIds: [],
      accessibilityAnnouncements: [],
      coalescedFrameCount: 0
    });
  }
  resetSession() {
    this.cancelScheduled(), this.pending = void 0, this.lastPaintedFrame = void 0;
  }
  dispose() {
    if (this.disposed)
      return;
    this.cancelScheduled(), this.pending = void 0, this.lastPaintedFrame = void 0, this.disposed = !0;
  }
  promoteToFullRepaint() {
    if (this.pending) {
      this.pending.damage = void 0;
      return;
    }
    this.pending = {
      frame: this.lastPaintedFrame,
      damage: void 0,
      carriedImagePayloads: /* @__PURE__ */ new Map,
      recoveredImagePayloadIds: /* @__PURE__ */ new Set,
      accessibilityAnnouncements: [],
      coalescedFrameCount: 0,
      announcementBytes: 0
    };
  }
  schedule() {
    if (this.held)
      return;
    if (this.pending && !this.canPresent(this.pending.frame))
      return;
    if (!this.animationFrames) {
      this.flush();
      return;
    }
    if (this.handle !== void 0)
      return;
    this.handle = this.animationFrames.requestAnimationFrame(() => {
      this.handle = void 0, this.flush();
    });
  }
  cancelScheduled() {
    if (this.handle === void 0)
      return;
    this.animationFrames?.cancelAnimationFrame(this.handle), this.handle = void 0;
  }
  setHeld(held) {
    if (this.disposed || held === this.held)
      return;
    if (this.held = held, held)
      this.cancelScheduled();
    else if (this.pending)
      this.schedule();
  }
};
function promotesToFullRepaint(previous, frame) {
  return previous === void 0 || previous.width !== frame.width || previous.height !== frame.height || previous.epoch !== frame.epoch || previous.geometryRevision !== frame.geometryRevision || frame.damage === void 0;
}
function spliceCarriedImagePayloads(frame, carried) {
  if (carried.size === 0 || !frame.images?.length)
    return frame;
  let spliced = !1, images = frame.images.map((image) => {
    if (image.dataBase64 !== void 0)
      return image;
    let payload = carried.get(image.id);
    if (payload === void 0)
      return image;
    return spliced = !0, {
      ...image,
      dataBase64: payload
    };
  });
  return spliced ? {
    ...frame,
    images
  } : frame;
}
function unionSurfaceDamage(a, b) {
  if (!a || !b)
    return;
  let rows = /* @__PURE__ */ new Map;
  for (let [row, ranges] of [...a.textRows, ...b.textRows]) {
    let existing = rows.get(row);
    if (existing === "full")
      continue;
    if (ranges.length === 0) {
      rows.set(row, "full");
      continue;
    }
    rows.set(row, existing ? [...existing, ...ranges] : [...ranges]);
  }
  return {
    textRows: [...rows.entries()].sort(([left], [right]) => left - right).map(([row, ranges]) => [row, ranges === "full" ? [] : mergeDamageRanges(ranges)]),
    requiresFullTextRepaint: a.requiresFullTextRepaint || b.requiresFullTextRepaint,
    requiresFullGraphicsReplay: a.requiresFullGraphicsReplay || b.requiresFullGraphicsReplay
  };
}
function mergeDamageRanges(ranges) {
  let sorted = [...ranges].sort(([left], [right]) => left - right), merged = [];
  for (let [start, end] of sorted) {
    let last = merged[merged.length - 1];
    if (last && start <= last[1])
      merged[merged.length - 1] = [last[0], Math.max(last[1], end)];
    else
      merged.push([start, end]);
  }
  return merged;
}

// dist/src/WebHostSceneRuntime.js
function legacyWheelMode(captureWheelInput) {
  if (captureWheelInput === void 0)
    return "chain";
  return captureWheelInput ? "capture" : "passive";
}
function coarsePointerQuery() {
  if (typeof globalThis.matchMedia !== "function")
    return;
  try {
    return globalThis.matchMedia("(pointer: coarse)");
  } catch {
    return;
  }
}
function coarsePrimaryPointer() {
  return coarsePointerQuery()?.matches ?? !1;
}
var WebHostSceneRuntime = class {
  descriptor;
  element;
  terminalMount;
  bridge;
  onInput;
  onFrameDiagnostic;
  onSurfacePainted;
  synchronizeAccessibilityFocus;
  wheelMode;
  rendererKind;
  sceneFrame;
  painter;
  domPainter;
  canvasPainter;
  paintScheduler;
  inputEncoder = new InputEventEncoder;
  awaitingConnectionFrame = !1;
  currentStyle;
  canvas;
  canvasScale = 1;
  domSurfaceRoot;
  textInputPress;
  domFocus;
  lastDomSurfaceSize;
  domGeometry;
  geometrySession = new HostGeometrySession;
  embeddingMount;
  geometryRefreshHandle;
  geometryDiagnostic;
  geometryMeasurable = !1;
  capturedPointerId;
  canceledPointerId;
  capturedPointerLocation;
  capturedPointerRevision;
  capturedViewportRevision;
  paintedGeometryRevision;
  paintedViewportRevision;
  get pointerRevision() {
    return this.domGeometry ? this.geometrySession.pointerRevision : this.paintedViewportRevision !== void 0 ? this.paintedGeometryRevision : void 0;
  }
  get pointerViewportRevision() {
    return this.domGeometry ? this.geometrySession.pointerViewportRevision : this.paintedViewportRevision;
  }
  disposed = !1;
  stagedFontChange = !1;
  reprojecting = !1;
  geometryWaitTimer;
  domFontOptions;
  fontResources;
  activeFontResources;
  fontPending = !1;
  fontResult;
  loadingFont;
  accessibilityTree;
  chrome;
  diagnosticText;
  resizeObserver;
  detachMetricObservers;
  nativePointerGesture = !1;
  detachInputHandlers;
  currentFrame;
  columns = 80;
  rows = 24;
  cellWidth = 8;
  cellHeight = 18;
  surfaceCSSWidth;
  surfaceCSSHeight;
  activePointerButton = "primary";
  hasCapturedPointer = !1;
  onOpenHyperlink;
  pointerDownLinkTarget;
  lastSentResize;
  isVisible = !1;
  documentVisible = !0;
  runtimeSuspended = !1;
  suspendWhenHidden;
  lastSentPointerCapabilities = !1;
  detachPointerParadigmObserver;
  constructor(options) {
    this.rendererKind = resolveSurfaceRenderer(options.renderer), this.descriptor = options.descriptor, this.embeddingMount = options.mount, this.currentStyle = normalizeWebHostTerminalStyle(options.style), this.domFontOptions = options.domFont, this.bridge = options.bridge, this.onInput = (chunk) => {
      if (!this.awaitingConnectionFrame)
        options.onInput(chunk);
    }, this.onFrameDiagnostic = options.onFrameDiagnostic, this.onSurfacePainted = options.onSurfacePainted, this.synchronizeAccessibilityFocus = options.synchronizeAccessibilityFocus ?? !0, this.wheelMode = options.wheelMode ?? legacyWheelMode(options.captureWheelInput), this.sceneFrame = options.sceneFrame ?? "fill";
    let onImagePayloadMiss = (ids) => {
      return this.bridge?.requestImagePayloads?.(ids);
    };
    if (this.rendererKind === "canvas")
      this.canvasPainter = new CanvasSurfacePainter({ onImagePayloadMiss });
    let painter = this.domPainter ?? this.canvasPainter;
    if (!painter)
      throw Error(`Unsupported surface renderer: ${this.rendererKind}`);
    this.painter = painter;
    let paintScheduling = options.paintScheduling ?? defaultAnimationFrameScheduler();
    this.paintScheduler = new SurfacePaintScheduler(paintScheduling === "synchronous" ? void 0 : paintScheduling, (request) => this.paint(request), (frame) => !this.domGeometry || this.geometrySession.canPresent(frame), (message) => {
      this.writeOutput(`${message}
`), this.bridge?.dispose();
    }), this.onOpenHyperlink = options.onOpenHyperlink, this.suspendWhenHidden = options.suspendWhenHidden ?? !0, this.element = document.createElement("section"), this.element.className = "webhost-scene", this.element.dataset.sceneId = options.descriptor.id, this.element.hidden = !0;
    let header = document.createElement("div");
    this.chrome = document.createElement("div"), this.chrome.className = "webhost-scene__chrome", this.chrome.append(header), header.className = "webhost-scene__header", header.textContent = options.descriptor.title ?? options.descriptor.id, this.terminalMount = document.createElement("div"), this.terminalMount.className = "webhost-scene__terminal", this.terminalMount.tabIndex = 0, this.element.append(this.chrome, this.terminalMount), options.mount.appendChild(this.element), this.applyVisibility();
  }
  async mount() {
    if (this.disposed)
      return;
    if (this.surfaceElement)
      return;
    let surfaceElement;
    if (this.domPainter) {
      let surfaceRoot = document.createElement("div");
      surfaceRoot.className = "webhost-scene__surface webhost-scene__surface--dom", surfaceRoot.setAttribute("aria-hidden", "true"), this.domSurfaceRoot = surfaceRoot, surfaceElement = surfaceRoot, this.domPainter.attach(surfaceRoot);
    } else if (this.canvasPainter) {
      let canvas = document.createElement("canvas");
      canvas.className = "webhost-scene__surface", canvas.setAttribute("aria-hidden", "true"), this.canvas = canvas, surfaceElement = canvas, this.canvasPainter.attach(canvas, () => this.paintScheduler.requestRepaint());
    } else
      throw Error(`Unsupported surface renderer: ${this.rendererKind}`);
    if (this.accessibilityTree = new AccessibilityTreeMounter((target, request, requestID) => {
      this.onInput(encodeAccessibilityActionMessage(target, request, requestID));
    }, this.onOpenHyperlink), this.chrome.append(this.accessibilityTree.navigationElement), this.terminalMount.replaceChildren(surfaceElement, this.accessibilityTree.element, this.accessibilityTree.announcerElement), this.domFocus = new DomFocusPresentation(this.terminalMount, () => this.nativePointerGesture || this.hasSurfaceSelection()), this.domSurfaceRoot || this.terminalMount.ownerDocument?.defaultView?.getComputedStyle)
      this.domGeometry = new DomGeometryController(this.terminalMount), this.paintScheduler.setHeld(!0);
    if (this.installInputHandlers(), this.installResizeObserver(), this.bridge?.bindOutput({
      resetSurfaceSession: () => {
        this.awaitingConnectionFrame = !0, this.currentFrame = void 0, this.paintedGeometryRevision = void 0, this.paintedViewportRevision = void 0, this.finishGeometryWait(), this.domGeometry?.resetParagraphs(), this.geometrySession.resetConnection(), this.paintScheduler.resetSession(), this.terminalMount.setAttribute("aria-busy", "true"), this.lastSentResize = void 0, this.cancelGeometryPointer(), this.refreshGeometry();
      },
      presentSurface: (frame, recoveredImagePayloadIds) => this.presentSurface(frame, recoveredImagePayloadIds),
      writeClipboard: (text) => this.writeClipboard(text),
      notifyRuntimeIssue: (issue) => this.notifyRuntimeIssue(issue),
      recordFrameDiagnostic: (diagnostic) => this.recordFrameDiagnostic(diagnostic),
      writeOutput: (text) => this.writeOutput(text),
      writeError: (text) => this.writeOutput(text)
    }), this.applyStyle(this.currentStyle), this.domSurfaceRoot)
      this.loadDomFont(this.currentStyle);
    else
      this.bridge?.updateRenderStyle(this.currentStyle);
    this.installPointerParadigmObserver(), this.sendPointerCapabilitiesIfChanged(coarsePrimaryPointer()), this.measureCells(), this.resizeToMount();
  }
  setVisible(visible) {
    if (this.disposed)
      return;
    if (!visible)
      this.cancelGeometryPointer();
    if (this.isVisible = visible, this.applyVisibility(), visible) {
      if (this.resizeToMount(), this.synchronizeAccessibilityFocus)
        this.terminalMount.focus?.({ preventScroll: !0 });
    }
    this.updateRuntimeSuspension();
  }
  setDocumentVisible(visible) {
    if (this.disposed)
      return;
    if (!visible)
      this.cancelGeometryPointer();
    let becameVisible = visible && !this.documentVisible;
    if (this.documentVisible = visible, this.updateRuntimeSuspension(), becameVisible && this.paintScheduler.statistics.pending)
      this.paintScheduler.repaintNow();
  }
  get paintStatistics() {
    return this.paintScheduler.statistics;
  }
  get resourceStatistics() {
    return {
      dom: this.domPainter?.statistics,
      semanticNodes: this.terminalMount.querySelectorAll(".webhost-scene__accessibility-tree *").length,
      fontFaceLeases: (this.fontResources?.ownedFaceLeases ?? 0) + (this.activeFontResources !== this.fontResources ? this.activeFontResources?.ownedFaceLeases ?? 0 : 0),
      paintQueue: this.paintScheduler.statistics
    };
  }
  updateRuntimeSuspension() {
    let suspended = this.suspendWhenHidden && (!this.isVisible || !this.documentVisible);
    if (suspended === this.runtimeSuspended)
      return;
    this.runtimeSuspended = suspended, this.onRuntimeSuspensionChange(suspended);
  }
  onRuntimeSuspensionChange(_suspended) {}
  setStyle(style) {
    if (this.disposed)
      return;
    let next = normalizeWebHostTerminalStyle(style);
    if (this.domSurfaceRoot) {
      this.stagedFontChange = !0, this.loadDomFont(next);
      return;
    }
    this.currentStyle = next, this.applyStyle(this.currentStyle), this.bridge?.updateRenderStyle(this.currentStyle), this.measureCells(), this.resizeToMount();
  }
  resize(columns, rows) {
    this.columns = Math.max(1, Math.round(columns)), this.rows = Math.max(1, Math.round(rows)), this.paintScheduler.repaintNow();
  }
  writeOutput(text) {
    if (this.disposed)
      return;
    if (!this.diagnosticText) {
      let diagnosticText = document.createElement("pre");
      if (diagnosticText.className = "webhost-scene__diagnostic", this.rendererKind === "dom")
        diagnosticText.setAttribute("role", "status"), Object.assign(diagnosticText.style, {
          position: "absolute",
          inset: "auto 0 0",
          zIndex: "5",
          boxSizing: "border-box",
          margin: "0",
          padding: "8px",
          maxHeight: "50%",
          overflow: "auto",
          whiteSpace: "pre-wrap",
          font: "12px/1.4 system-ui, sans-serif",
          color: "#fff",
          background: "#402020"
        });
      this.diagnosticText = diagnosticText, this.terminalMount.appendChild(diagnosticText);
    }
    this.diagnosticText.textContent = `${this.diagnosticText.textContent ?? ""}${text}`.slice(-16384);
  }
  notifyRuntimeIssue(issue) {
    if (this.disposed)
      return;
    if (issue.severity === "error")
      console.error(issue.description);
    else
      console.warn(issue.description);
    this.writeOutput(`${issue.description}
`);
  }
  recordFrameDiagnostic(diagnostic) {
    this.onFrameDiagnostic?.(diagnostic);
  }
  async writeClipboard(text) {
    let clipboard = globalThis.navigator?.clipboard;
    if (!clipboard?.writeText)
      return;
    try {
      await clipboard.writeText(text);
    } catch {}
  }
  sendInput(chunk) {
    this.onInput(chunk);
  }
  dispose() {
    if (this.cancelGeometryPointer(), this.disposed = !0, this.finishGeometryWait(), this.fontResources?.dispose(), this.activeFontResources !== this.fontResources)
      this.activeFontResources?.dispose();
    if (this.geometryRefreshHandle !== void 0)
      globalThis.cancelAnimationFrame?.(this.geometryRefreshHandle);
    this.domGeometry?.dispose(), this.paintScheduler.dispose(), this.painter.dispose(), this.domFocus?.dispose(), this.accessibilityTree?.dispose(), this.accessibilityTree = void 0, this.detachInputHandlers?.(), this.detachPointerParadigmObserver?.(), this.resizeObserver?.disconnect(), this.detachMetricObservers?.(), this.element.remove();
  }
  sendPointerCapabilitiesIfChanged(supportsScrollPanning) {
    if (this.lastSentPointerCapabilities === supportsScrollPanning)
      return;
    this.lastSentPointerCapabilities = supportsScrollPanning, this.bridge?.updatePointerCapabilities?.(supportsScrollPanning);
  }
  installPointerParadigmObserver() {
    let query = coarsePointerQuery();
    if (!query?.addEventListener)
      return;
    let handleChange = (event) => {
      this.sendPointerCapabilitiesIfChanged(event.matches);
    };
    query.addEventListener("change", handleChange), this.detachPointerParadigmObserver = () => {
      query.removeEventListener?.("change", handleChange);
    };
  }
  presentSurface(frame, recoveredImagePayloadIds) {
    if (this.disposed)
      return;
    if (this.domGeometry) {
      if (this.geometrySession.observe(frame), this.sendGeometryIfNeeded(), !this.geometrySession.negotiated && frame.viewportRevision === void 0)
        this.currentFrame = frame;
    } else if (frame.viewportRevision === void 0)
      this.currentFrame = frame, this.columns = Math.max(1, Math.round(frame.width)), this.rows = Math.max(1, Math.round(frame.height));
    this.paintScheduler.present(frame, recoveredImagePayloadIds);
  }
  get preferredGridSize() {
    let frame = this.currentFrame;
    if (frame?.preferredGridWidth === void 0 || frame.preferredGridHeight === void 0)
      return;
    return {
      width: frame.preferredGridWidth,
      height: frame.preferredGridHeight
    };
  }
  get focusPresentation() {
    let presentation = this.currentFrame?.focusPresentation;
    if (!presentation)
      return;
    return {
      ...presentation,
      semantics: normalizeSemantics(presentation.semantics)
    };
  }
  linkTarget(location) {
    return linkTargetAt(this.currentFrame?.links, this.currentFrame?.linkTargets, location);
  }
  openHyperlink(url) {
    if (this.onOpenHyperlink) {
      this.onOpenHyperlink(url);
      return;
    }
    if (!/^https?:/i.test(url))
      return;
    window.open(url, "_blank", "noopener,noreferrer");
  }
  applyStyle(style) {
    if (applyWebHostTerminalStyle(this.element, style), this.element.style.boxSizing = "border-box", this.sceneFrame === "resizable")
      this.element.style.width = "80%", this.element.style.height = "80%", this.element.style.maxWidth = "100%", this.element.style.maxHeight = "100%", this.element.style.resize = "both", this.element.style.flex = "0 0 auto";
    else
      this.element.style.width = "100%", this.element.style.height = "100%";
    if (this.element.style.minWidth = "0", this.element.style.minHeight = "0", this.element.style.padding = "0.75rem", this.element.style.borderRadius = "16px", this.element.style.boxShadow = "0 20px 50px rgba(0, 0, 0, 0.28)", this.element.style.overflow = "hidden", this.element.style.gap = "0.5rem", this.element.style.gridTemplateRows = "auto minmax(0, 1fr)", this.terminalMount.style.position = "relative", this.terminalMount.style.gridRow = "2", this.terminalMount.style.boxSizing = "border-box", this.terminalMount.style.width = "100%", this.sceneFrame === "resizable")
      this.terminalMount.style.height = "auto", this.terminalMount.style.alignSelf = "stretch";
    else
      this.terminalMount.style.height = "100%";
    if (this.terminalMount.style.minWidth = "0", this.terminalMount.style.minHeight = "0", this.terminalMount.style.overflow = "hidden", this.terminalMount.style.overscrollBehavior = this.wheelMode === "capture" ? "contain" : "auto", this.terminalMount.style.outline = "none", this.terminalMount.style.background = webTUITerminalBackgroundColor(this.currentStyle), this.canvas)
      this.canvas.style.display = "block", this.canvas.style.width = "100%", this.canvas.style.height = "100%";
    if (this.domSurfaceRoot)
      this.domSurfaceRoot.style.display = "block", this.domSurfaceRoot.style.position = "relative";
  }
  get surfaceElement() {
    return this.canvas ?? this.domSurfaceRoot;
  }
  applyVisibility() {
    this.element.hidden = !this.isVisible, this.element.style.setProperty("display", this.isVisible ? "grid" : "none", "important");
  }
  installResizeObserver() {
    let refresh = () => {
      if (this.domGeometry) {
        this.refreshGeometry();
        return;
      }
      this.domPainter?.invalidateFontMetrics(), this.resizeToMount();
    };
    if (typeof ResizeObserver < "u") {
      if (this.resizeObserver = new ResizeObserver(refresh), this.resizeObserver.observe(this.terminalMount), this.domGeometry)
        this.resizeObserver.observe(this.embeddingMount);
      if (this.domGeometry)
        this.resizeObserver.observe(this.domGeometry.probe.element);
    }
    let fonts = document.fonts, userStyleObserver = this.domGeometry && typeof MutationObserver < "u" ? new MutationObserver(() => {
      this.domPainter?.invalidateFontMetrics(), refresh();
    }) : void 0;
    if (userStyleObserver) {
      userStyleObserver.observe(document.head, {
        childList: !0,
        subtree: !0,
        characterData: !0,
        attributes: !0
      });
      for (let node = this.embeddingMount;node; node = node.parentElement)
        userStyleObserver.observe(node, {
          attributes: !0,
          attributeFilter: ["style", "class"]
        });
    }
    let refreshFonts = () => {
      this.domPainter?.invalidateFontMetrics(), refresh();
    };
    fonts?.addEventListener?.("loadingdone", refreshFonts), fonts?.addEventListener?.("loadingerror", refreshFonts), globalThis.window?.addEventListener?.("resize", refresh), globalThis.window?.visualViewport?.addEventListener("resize", refresh);
    let dpr, watchDpr = () => {
      dpr?.removeEventListener?.("change", changedDpr), dpr = globalThis.matchMedia?.(`(resolution: ${globalThis.devicePixelRatio || 1}dppx)`), dpr?.addEventListener?.("change", changedDpr);
    }, changedDpr = () => {
      watchDpr(), refresh();
    };
    watchDpr();
    let preferences = [
      "(forced-colors: active)",
      "(prefers-color-scheme: dark)",
      "(prefers-reduced-motion: reduce)",
      "(prefers-reduced-transparency: reduce)",
      "(prefers-contrast: more)",
      "(prefers-contrast: less)"
    ].map((query) => globalThis.matchMedia?.(query)).filter((query) => query !== void 0), preferenceChanged = () => {
      this.applyStyle(this.currentStyle), this.bridge?.updateRenderStyle?.(this.currentStyle), refresh(), this.paintScheduler.requestRepaint();
    };
    for (let query of preferences)
      query.addEventListener?.("change", preferenceChanged);
    this.detachMetricObservers = () => {
      userStyleObserver?.disconnect();
      for (let query of preferences)
        query.removeEventListener?.("change", preferenceChanged);
      fonts?.removeEventListener?.("loadingdone", refreshFonts), fonts?.removeEventListener?.("loadingerror", refreshFonts), globalThis.window?.removeEventListener?.("resize", refresh), globalThis.window?.visualViewport?.removeEventListener("resize", refresh), dpr?.removeEventListener?.("change", changedDpr);
    };
  }
  installInputHandlers() {
    let handleKeyDown = (event) => {
      if (event.metaKey || event.isComposing || this.rendererKind === "dom" && event.ctrlKey && ([
        "f",
        "+",
        "=",
        "-",
        "0",
        "l",
        "r",
        "t",
        "w",
        "n",
        "tab",
        "pageup",
        "pagedown"
      ].includes(event.key.toLowerCase()) || event.key.toLowerCase() === "c" && document.getSelection?.()?.isCollapsed === !1))
        return;
      if (event.key === "Tab" && this.accessibilityTree?.hasInteractiveControls) {
        if (this.accessibilityTree.advanceFocus(event.shiftKey))
          event.preventDefault(), event.stopPropagation();
        return;
      }
      if (this.rendererKind === "dom" && event.altKey && ["ArrowLeft", "ArrowRight"].includes(event.key))
        return;
      let message = this.inputEncoder.encodeKey(event);
      if (!message)
        return;
      this.onInput(message), event.preventDefault();
    }, handlePaste = (event) => {
      let text = event.clipboardData?.getData("text/plain") ?? "";
      if (!text)
        return;
      this.onInput(this.inputEncoder.encodePaste(text)), event.preventDefault();
    }, handlePointerDown = (event) => {
      if (event.pointerType === "touch" || event.pointerType === "mouse")
        this.sendPointerCapabilitiesIfChanged(event.pointerType === "touch");
      if (this.allowsNativeTextSelection(event) || this.isNativeLink(event)) {
        this.nativePointerGesture = !0;
        let location2 = this.cellLocation(event);
        if (this.textInputPress = location2 && this.domPainter?.isTextInput(location2.x, location2.y) ? {
          location: location2,
          event,
          moved: !1,
          revision: this.pointerRevision,
          viewportRevision: this.pointerViewportRevision
        } : void 0, this.allowsNativeTextSelection(event))
          this.terminalMount.focus?.({ preventScroll: !0 });
        this.domFocus?.refresh();
        return;
      }
      let location = this.cellLocation(event);
      if (!location)
        return;
      if (this.nativePointerGesture = !1, this.textInputPress = void 0, this.hasSurfaceSelection())
        document.getSelection()?.removeAllRanges();
      this.canceledPointerId = void 0;
      let button = this.inputEncoder.pointerButton(event.button);
      this.activePointerButton = button, this.hasCapturedPointer = !0, this.capturedPointerId = event.pointerId, this.capturedPointerLocation = location, this.capturedPointerRevision = this.pointerRevision, this.capturedViewportRevision = this.pointerViewportRevision, this.pointerDownLinkTarget = button === "primary" ? this.linkTarget(location) : void 0, this.terminalMount.focus?.({ preventScroll: !0 }), this.terminalMount.setPointerCapture?.(event.pointerId), this.onInput(this.inputEncoder.encodePointerDown(location, button, event, this.pointerRevision, this.pointerViewportRevision)), event.preventDefault();
    }, handlePointerUp = (event) => {
      if (event.pointerId === this.canceledPointerId) {
        this.canceledPointerId = void 0;
        return;
      }
      if (!this.hasCapturedPointer && (this.nativePointerGesture || this.allowsNativeTextSelection(event) || this.isNativeLink(event))) {
        let press = this.textInputPress;
        if (this.textInputPress = void 0, this.nativePointerGesture = !1, press && !press.moved && press.revision === this.pointerRevision && press.viewportRevision === this.pointerViewportRevision) {
          if (this.hasSurfaceSelection())
            document.getSelection()?.removeAllRanges();
          this.onInput(this.inputEncoder.encodePointerDown(press.location, "primary", press.event, this.pointerRevision, this.pointerViewportRevision)), this.onInput(this.inputEncoder.encodePointerUp(press.location, "primary", event, this.pointerRevision, this.pointerViewportRevision));
        }
        this.domFocus?.refresh();
        return;
      }
      let location = this.hasCapturedPointer ? this.rawCellLocation(event) : this.cellLocation(event);
      this.hasCapturedPointer = !1, this.capturedPointerId = void 0, this.capturedPointerLocation = void 0, this.capturedPointerRevision = void 0, this.capturedViewportRevision = void 0, this.terminalMount.releasePointerCapture?.(event.pointerId);
      let downLinkTarget = this.pointerDownLinkTarget;
      if (this.pointerDownLinkTarget = void 0, !location)
        return;
      let button = this.inputEncoder.pointerButton(event.button) ?? this.activePointerButton;
      if (this.onInput(this.inputEncoder.encodePointerUp(location, button, event, this.pointerRevision, this.pointerViewportRevision)), downLinkTarget !== void 0 && this.linkTarget(location) === downLinkTarget)
        this.openHyperlink(downLinkTarget);
      event.preventDefault();
    }, handlePointerMove = (event) => {
      if (event.pointerId === this.canceledPointerId) {
        if (event.buttons)
          return;
        this.canceledPointerId = void 0;
      }
      let press = this.textInputPress;
      if (press && Math.hypot(event.clientX - press.event.clientX, event.clientY - press.event.clientY) > 3)
        press.moved = !0;
      if (!this.hasCapturedPointer && (this.nativePointerGesture || this.allowsNativeTextSelection(event) || this.isNativeLink(event)))
        return;
      let location = event.buttons && this.hasCapturedPointer ? this.rawCellLocation(event) : this.cellLocation(event);
      if (!location)
        return;
      if (!this.hasCapturedPointer)
        this.terminalMount.style.cursor = this.linkTarget(location) !== void 0 ? "pointer" : "";
      this.onInput(this.inputEncoder.encodePointerMove(location, this.activePointerButton, event, this.pointerRevision, this.pointerViewportRevision));
    }, forwardWheel = (event) => {
      if (this.wheelMode === "passive" || event.ctrlKey || event.metaKey)
        return !1;
      let location = this.cellLocation(event);
      if (!location)
        return !1;
      if (this.wheelMode === "chain" && !wheelTargetCanScroll(this.currentFrame?.scrollRegions, location, event.deltaX, event.deltaY))
        return !1;
      let record = this.inputEncoder.encodeWheel(location, event, this.pointerMetrics(), this.pointerRevision, this.pointerViewportRevision);
      if (record)
        this.onInput(record);
      return event.preventDefault(), !0;
    }, handleWheel = (event) => {
      if (!forwardWheel(event))
        this.inputEncoder.observeUnforwardedWheel(event);
    }, cancelPointer = (event) => {
      if (event.pointerId === this.capturedPointerId)
        this.cancelGeometryPointer();
    }, blurPointer = () => {
      this.cancelGeometryPointer(), endNativeDrag();
    }, endNativeDrag = () => {
      this.nativePointerGesture = !1, this.textInputPress = void 0, this.domFocus?.refresh();
    }, selectionChanged = () => this.domFocus?.refresh();
    document.addEventListener?.("selectionchange", selectionChanged), document.addEventListener?.("pointerup", endNativeDrag), document.addEventListener?.("pointercancel", endNativeDrag), globalThis.window?.addEventListener?.("blur", blurPointer), this.terminalMount.addEventListener("pointercancel", cancelPointer), this.terminalMount.addEventListener("lostpointercapture", cancelPointer), this.terminalMount.addEventListener("keydown", handleKeyDown), this.terminalMount.addEventListener("paste", handlePaste), this.terminalMount.addEventListener("pointerdown", handlePointerDown), this.terminalMount.addEventListener("pointerup", handlePointerUp), this.terminalMount.addEventListener("pointermove", handlePointerMove), this.terminalMount.addEventListener("wheel", handleWheel, { passive: !1 }), this.detachInputHandlers = () => {
      document.removeEventListener?.("selectionchange", selectionChanged), document.removeEventListener?.("pointerup", endNativeDrag), document.removeEventListener?.("pointercancel", endNativeDrag), globalThis.window?.removeEventListener?.("blur", blurPointer), this.terminalMount.removeEventListener("pointercancel", cancelPointer), this.terminalMount.removeEventListener("lostpointercapture", cancelPointer), this.terminalMount.removeEventListener("keydown", handleKeyDown), this.terminalMount.removeEventListener("paste", handlePaste), this.terminalMount.removeEventListener("pointerdown", handlePointerDown), this.terminalMount.removeEventListener("pointerup", handlePointerUp), this.terminalMount.removeEventListener("pointermove", handlePointerMove), this.terminalMount.removeEventListener("wheel", handleWheel);
    };
  }
  resizeToMount() {
    if (this.disposed)
      return;
    if (this.fontPending)
      return;
    if (this.domGeometry) {
      let snapshot;
      this.geometryMeasurable = !1;
      try {
        snapshot = this.domGeometry.measure(this.currentStyle);
      } catch (error) {
        let message = error instanceof Error ? error.message : String(error);
        if (message !== this.geometryDiagnostic)
          this.writeOutput(`${message}
`);
        this.geometryDiagnostic = message;
      }
      if (!snapshot) {
        this.cancelGeometryPointer(), this.paintScheduler.setHeld(!0);
        return;
      }
      let previous = this.domGeometry.presented, userTypographyChanged = !this.stagedFontChange && previous && this.currentFrame && (previous.cellWidth !== snapshot.cellWidth || previous.cellHeight !== snapshot.cellHeight || previous.baseline !== snapshot.baseline || previous.fontSize !== snapshot.fontSize);
      this.cellWidth = snapshot.cellWidth, this.cellHeight = snapshot.cellHeight, this.columns = snapshot.columns, this.rows = snapshot.rows, this.surfaceCSSWidth = snapshot.content.width, this.surfaceCSSHeight = snapshot.content.height;
      try {
        if (this.domGeometry.presented?.revision !== snapshot.revision)
          this.cancelGeometryPointer();
        this.geometrySession.request(snapshot);
      } catch (error) {
        this.writeOutput(`${String(error)}
`), this.paintScheduler.setHeld(!0);
        return;
      }
      if (this.geometryMeasurable = !0, snapshot.bounded && this.geometryDiagnostic !== "bounded")
        this.writeOutput(`Viewport exceeds the supported grid; showing a bounded viewport.
`), this.geometryDiagnostic = "bounded";
      else if (!snapshot.bounded)
        this.geometryDiagnostic = void 0;
      if (this.geometrySession.negotiated)
        this.sendGeometryIfNeeded();
      else
        this.sendResizeIfNeeded();
      if (this.paintScheduler.setHeld(!1), userTypographyChanged && this.geometrySession.negotiated && !this.geometrySession.canPresent(this.currentFrame)) {
        this.reprojecting = !0;
        try {
          this.paintScheduler.reprojectVisible();
        } finally {
          this.reprojecting = !1;
        }
      }
      this.paintScheduler.repaintNow();
      return;
    }
    this.measureCells();
    let rect = this.terminalMount.getBoundingClientRect?.(), width = this.terminalMount.clientWidth || (rect?.width && rect.width > 0 ? rect.width : this.columns * this.cellWidth), height = this.terminalMount.clientHeight || (rect?.height && rect.height > 0 ? rect.height : this.rows * this.cellHeight);
    this.surfaceCSSWidth = width, this.surfaceCSSHeight = height;
    let nextColumns = Math.max(1, Math.floor(width / this.cellWidth)), nextRows = Math.max(1, Math.floor(height / this.cellHeight));
    this.columns = nextColumns, this.rows = nextRows, this.sendResizeIfNeeded(), this.paintScheduler.repaintNow();
  }
  sendResizeIfNeeded() {
    let current = {
      columns: this.columns,
      rows: this.rows,
      cellWidth: this.cellWidth,
      cellHeight: this.cellHeight
    };
    if (this.lastSentResize && this.lastSentResize.columns === current.columns && this.lastSentResize.rows === current.rows && this.lastSentResize.cellWidth === current.cellWidth && this.lastSentResize.cellHeight === current.cellHeight)
      return;
    this.lastSentResize = current, this.bridge?.resize(current.columns, current.rows, current.cellWidth, current.cellHeight);
  }
  cancelGeometryPointer() {
    this.textInputPress = void 0;
    let id = this.capturedPointerId, location = this.capturedPointerLocation, revision = this.capturedPointerRevision, viewportRevision = this.capturedViewportRevision;
    if (this.capturedPointerId = void 0, this.capturedPointerLocation = void 0, this.capturedPointerRevision = void 0, this.capturedViewportRevision = void 0, this.hasCapturedPointer = !1, this.pointerDownLinkTarget = void 0, id !== void 0) {
      if (this.canceledPointerId = id, location)
        this.onInput(this.inputEncoder.encodePointerCancel(location, revision, viewportRevision));
      if (this.terminalMount.hasPointerCapture?.(id))
        this.terminalMount.releasePointerCapture?.(id);
    }
  }
  finishGeometryWait() {
    if (this.geometryWaitTimer !== void 0)
      clearTimeout(this.geometryWaitTimer);
    this.geometryWaitTimer = void 0, this.terminalMount.removeAttribute("data-geometry-pending");
  }
  sendGeometryIfNeeded() {
    let request = this.geometrySession.takeRequest();
    if (!request)
      return;
    if (this.terminalMount.setAttribute("aria-busy", "true"), this.terminalMount.setAttribute("data-geometry-pending", String(request.revision)), this.geometryWaitTimer === void 0)
      this.geometryWaitTimer = setTimeout(() => {
        if (this.geometryWaitTimer = void 0, !this.disposed && this.terminalMount.getAttribute("data-geometry-pending"))
          this.writeOutput(`Waiting for the app to finish layout for the requested display geometry.
`);
      }, 1000);
    this.onInput(encodeGeometryControlMessage(request));
  }
  resizeSurface() {
    let gridCSSWidth = Math.max(1, this.columns * this.cellWidth), gridCSSHeight = Math.max(1, this.rows * this.cellHeight);
    if (this.domSurfaceRoot) {
      let last = this.lastDomSurfaceSize;
      if (last && last.width === gridCSSWidth && last.height === gridCSSHeight)
        return !1;
      return this.lastDomSurfaceSize = {
        width: gridCSSWidth,
        height: gridCSSHeight
      }, this.domSurfaceRoot.style.width = `${gridCSSWidth}px`, this.domSurfaceRoot.style.height = `${gridCSSHeight}px`, !0;
    }
    if (!this.canvas)
      return !1;
    let scale = globalThis.window?.devicePixelRatio || 1, bounded = boundedCanvasSize(Math.max(1, this.surfaceCSSWidth ?? gridCSSWidth), Math.max(1, this.surfaceCSSHeight ?? gridCSSHeight), scale), { width, height } = bounded, scaleChanged = this.canvasScale !== bounded.scale;
    this.canvasScale = bounded.scale;
    let styleWidth = "100%", styleHeight = "100%";
    if (this.canvas.width === width && this.canvas.height === height && this.canvas.style.width === styleWidth && this.canvas.style.height === styleHeight && !scaleChanged)
      return !1;
    return this.canvas.width = width, this.canvas.height = height, this.canvas.style.width = styleWidth, this.canvas.style.height = styleHeight, !0;
  }
  measureCells() {
    if (this.domGeometry)
      return;
    let context = (this.canvas ?? document.createElement("canvas")).getContext?.("2d");
    if (!context) {
      this.cellWidth = Math.max(1, Math.round(this.currentStyle.fontSize * 0.62)), this.cellHeight = Math.max(1, Math.round(this.currentStyle.fontSize * 1.35));
      return;
    }
    context.font = fontForStyle(this.currentStyle), this.cellWidth = Math.max(1, Math.ceil(context.measureText("W").width)), this.cellHeight = Math.max(1, Math.ceil(this.currentStyle.fontSize * 1.35));
  }
  paint(request) {
    if (request.frame)
      this.awaitingConnectionFrame = !1;
    if (this.paintedViewportRevision !== request.frame?.viewportRevision)
      this.cancelGeometryPointer();
    if (this.paintedViewportRevision = request.frame?.viewportRevision, this.paintedGeometryRevision = request.frame?.geometryRevision, !this.domGeometry && request.frame)
      this.currentFrame = request.frame, this.columns = Math.max(1, Math.round(request.frame.width)), this.rows = Math.max(1, Math.round(request.frame.height));
    if (this.domGeometry?.pending) {
      let pending = this.domGeometry.pending;
      if (!this.reprojecting)
        this.geometrySession.didPresent(request.frame);
      this.currentFrame = request.frame;
      let snapshot = Object.freeze({
        ...pending,
        sourceRevision: request.frame?.geometryRevision,
        projected: this.reprojecting || void 0,
        columns: request.frame?.width ?? pending.columns,
        rows: request.frame?.height ?? pending.rows
      });
      if (this.domGeometry.present(snapshot), this.cellWidth = snapshot.cellWidth, this.cellHeight = snapshot.cellHeight, this.columns = Math.max(1, snapshot.columns), this.rows = Math.max(1, snapshot.rows), this.accessibilityTree)
        Object.assign(this.accessibilityTree.element.style, {
          inset: "auto",
          left: `${snapshot.content.offsetX}px`,
          top: `${snapshot.content.offsetY}px`,
          width: `${this.canvas ? snapshot.content.width : this.columns * snapshot.cellWidth}px`,
          height: `${this.canvas ? snapshot.content.height : this.rows * snapshot.cellHeight}px`
        });
    }
    let resized = this.resizeSurface();
    if (this.painter.paint(this.surfaceMetrics(), request.frame, resized ? void 0 : request.damage, request.recoveredImagePayloadIds), request.frame?.paragraphs?.length && this.domGeometry?.enableParagraphs())
      this.refreshGeometry();
    if (this.onSurfacePainted?.({
      frame: request.frame,
      paintedAt: performance.now(),
      coalescedFrameCount: request.coalescedFrameCount
    }), this.syncAccessibilityTree(request.frame, request.accessibilityAnnouncements), this.domFocus?.present(request.frame, this.surfaceMetrics(), this.domGeometry?.presented?.content.offsetX, this.domGeometry?.presented?.content.offsetY), this.domGeometry && !this.fontPending && !this.reprojecting) {
      this.stagedFontChange = !1, this.finishGeometryWait();
      let previous = this.activeFontResources;
      if (this.activeFontResources = this.fontResources, previous !== this.activeFontResources)
        previous?.dispose();
      this.terminalMount.removeAttribute("aria-busy");
    }
  }
  syncAccessibilityTree(frame, announcements) {
    let tree = this.accessibilityTree;
    if (!tree || !frame)
      return;
    tree.present(frame.accessibilityTree ?? [], {
      cellWidth: this.cellWidth,
      cellHeight: this.cellHeight
    }, [...announcements], {
      synchronizeFocus: this.synchronizeAccessibilityFocus && !this.nativePointerGesture && !this.hasSurfaceSelection(),
      actionResponse: frame.accessibilityActionResponse,
      focusRequest: frame.accessibilityFocusRequest
    });
  }
  surfaceMetrics() {
    return {
      columns: this.columns,
      rows: this.rows,
      cellWidth: this.cellWidth,
      cellHeight: this.cellHeight,
      pixelScale: this.canvasScale,
      style: this.canvas && this.domGeometry?.presented ? {
        ...this.currentStyle,
        fontSize: this.domGeometry.presented.fontSize,
        fontFamily: this.domGeometry.presented.fontIdentity
      } : this.currentStyle
    };
  }
  pointerMetrics() {
    let domRect = this.domSurfaceRoot?.getBoundingClientRect?.(), presented = this.domGeometry?.presented, columns = presented?.columns ?? this.columns, rows = presented?.rows ?? this.rows;
    return {
      rect: this.surfaceElement?.getBoundingClientRect?.() ?? this.terminalMount.getBoundingClientRect?.(),
      cellWidth: domRect?.width ? domRect.width / columns : this.cellWidth,
      cellHeight: domRect?.height ? domRect.height / rows : this.cellHeight,
      columns,
      rows
    };
  }
  refreshGeometry() {
    if (this.disposed || this.geometryRefreshHandle !== void 0)
      return;
    if (!globalThis.requestAnimationFrame) {
      this.resizeToMount();
      return;
    }
    this.geometryRefreshHandle = requestAnimationFrame(() => {
      this.geometryRefreshHandle = void 0, this.resizeToMount();
    });
  }
  get geometrySnapshot() {
    return this.domGeometry?.presented;
  }
  get fontStatus() {
    return this.fontResult;
  }
  get fontReady() {
    return this.fontResources?.ready;
  }
  loadDomFont(style) {}
  isNativeLink(event) {
    return this.rendererKind === "dom" && !!event.target?.closest?.("a[data-surface-link]");
  }
  hasSurfaceSelection() {
    let selection = document.getSelection?.();
    return selection?.isCollapsed === !1 && !!this.domSurfaceRoot?.contains(selection.anchorNode) && !!this.domSurfaceRoot?.contains(selection.focusNode);
  }
  allowsNativeTextSelection(event) {
    if (!this.domPainter || event.button > 0)
      return !1;
    let location = this.cellLocation(event);
    return !!location && this.domPainter.allowsTextSelection(location.x, location.y);
  }
  cellLocation(event) {
    if (this.awaitingConnectionFrame)
      return;
    if (this.domGeometry && (!this.geometryMeasurable || !this.geometrySession.allowsPointer))
      return;
    return cellLocationForEvent(event, this.pointerMetrics());
  }
  rawCellLocation(event) {
    if (this.awaitingConnectionFrame)
      return;
    if (this.domGeometry && (!this.geometryMeasurable || !this.geometrySession.allowsPointer))
      return;
    return rawCellLocationForEvent(event, this.pointerMetrics());
  }
};

// dist/src/WebSocketSceneBridge.js
var socketOpenState = 1, normalClosureCode = 1000, textEncoder2 = /* @__PURE__ */ new TextEncoder;
function defaultReconnectDelayMilliseconds(attempt) {
  return Math.min(250 * 2 ** (attempt - 1), 8000);
}
var WebSocketSceneBridge = class {
  url;
  socket;
  createSocket;
  reconnectDelayMilliseconds;
  decoder = new WebHostOutputDecoder;
  receiveGeneration = 0;
  receiveTail = Promise.resolve();
  pendingReceives = 0;
  pendingReceiveBytes = 0;
  queuedInput = [];
  queuedOutput = [];
  sink;
  disposed = !1;
  resourceFailure;
  queuedOutputBytes = 0;
  reconnectAttempts = 0;
  reconnectTimer;
  lastRenderStyleMessage;
  lastResizeMessage;
  lastPointerCapabilitiesMessage;
  handleOpen = () => {
    this.reconnectAttempts = 0, this.flushQueuedInput();
  };
  handleMessage = (event) => {
    let generation = this.receiveGeneration, message = event.data, bytes = typeof message === "string" ? message.length * 3 : message instanceof Blob ? message.size : message instanceof ArrayBuffer || ArrayBuffer.isView(message) ? message.byteLength : 0, retainedBytes = Math.min(bytes, HOST_WIRE_MAX_RECORD_BYTES * 2);
    if (this.pendingReceives >= 32 || this.pendingReceiveBytes + retainedBytes > 16777216) {
      this.socket.close(1009, "WebHost receive backlog exceeded"), this.resetReceiveSession();
      return;
    }
    this.pendingReceives++, this.pendingReceiveBytes += retainedBytes, this.receiveTail = this.receiveTail.then(() => this.receive(message, generation)).catch(() => {
      if (!this.disposed && generation === this.receiveGeneration)
        this.deliver(this.decoder.rejectOversizedMessage()), this.sendPendingResyncRequests();
    }).finally(() => {
      if (generation === this.receiveGeneration)
        this.pendingReceives--, this.pendingReceiveBytes -= retainedBytes;
    });
  };
  handleClose = (event) => {
    if (this.resetReceiveSession(), this.disposed || event.code === normalClosureCode)
      return;
    this.queuedInput.length = 0, this.scheduleReconnect();
  };
  handleError = () => {};
  constructor(options) {
    this.url = webSocketSceneURL(options), this.createSocket = options.webSocketFactory ?? defaultWebSocketFactory, this.reconnectDelayMilliseconds = options.reconnectDelayMilliseconds ?? defaultReconnectDelayMilliseconds, this.socket = this.createSocket(this.url), this.attachSocket(this.socket), this.sendInput(encodeCapabilitiesControlMessage());
  }
  bindOutput(sink) {
    if (this.sink = sink, this.resourceFailure)
      sink.writeError?.(this.resourceFailure);
    this.queuedOutputBytes = 0;
    while (this.queuedOutput.length > 0)
      this.deliver(this.queuedOutput.shift());
  }
  resize(columns, rows, cellWidth, cellHeight) {
    let message = encodeResizeControlMessage(columns, rows, cellWidth, cellHeight);
    this.lastResizeMessage = message, this.sendInput(message);
  }
  updateRenderStyle(style) {
    let message = encodeRenderStyleControlMessage(style);
    this.lastRenderStyleMessage = message, this.sendInput(message);
  }
  updatePointerCapabilities(supportsScrollPanning) {
    let message = encodePointerCapabilitiesControlMessage(supportsScrollPanning);
    this.lastPointerCapabilitiesMessage = message, this.sendInput(message);
  }
  sendInput(chunk) {
    if (this.disposed)
      return;
    if (!this.admitsQueuedInput([chunk]))
      return;
    let copy = new Uint8Array(chunk);
    if (this.queuedInput.push(copy), this.socket.readyState === socketOpenState)
      this.flushQueuedInput();
  }
  requestImagePayloads(ids) {
    if (this.disposed)
      return [];
    let acceptedIds = this.decoder.requestImagePayloads(ids);
    return this.sendPendingResyncRequests(), acceptedIds;
  }
  dispose() {
    if (this.disposed)
      return;
    if (this.disposed = !0, this.resetReceiveSession(), this.reconnectTimer !== void 0)
      clearTimeout(this.reconnectTimer), this.reconnectTimer = void 0;
    this.detachSocket(this.socket), this.queuedInput.length = 0, this.queuedOutput.length = 0, this.queuedOutputBytes = 0, this.socket.close(1000, "WebHost scene disposed");
  }
  attachSocket(socket) {
    socket.binaryType = "arraybuffer", socket.addEventListener("open", this.handleOpen), socket.addEventListener("message", this.handleMessage), socket.addEventListener("close", this.handleClose), socket.addEventListener("error", this.handleError);
  }
  detachSocket(socket) {
    socket.removeEventListener("open", this.handleOpen), socket.removeEventListener("message", this.handleMessage), socket.removeEventListener("close", this.handleClose), socket.removeEventListener("error", this.handleError);
  }
  scheduleReconnect() {
    if (this.reconnectTimer !== void 0)
      return;
    this.reconnectAttempts += 1;
    let delay = Math.max(0, this.reconnectDelayMilliseconds(this.reconnectAttempts));
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = void 0, this.reconnect();
    }, delay);
  }
  reconnect() {
    if (this.disposed)
      return;
    this.detachSocket(this.socket);
    let socket;
    try {
      socket = this.createSocket(this.url);
    } catch {
      this.scheduleReconnect();
      return;
    }
    this.socket = socket, this.attachSocket(socket);
    let handshake = [encodeCapabilitiesControlMessage()];
    if (this.lastRenderStyleMessage)
      handshake.push(this.lastRenderStyleMessage);
    if (this.lastResizeMessage)
      handshake.push(this.lastResizeMessage);
    if (this.lastPointerCapabilitiesMessage)
      handshake.push(this.lastPointerCapabilitiesMessage);
    if (!this.admitsQueuedInput(handshake))
      return;
    if (this.queuedInput.unshift(...handshake.map((chunk) => new Uint8Array(chunk))), this.socket.readyState === socketOpenState)
      this.flushQueuedInput();
  }
  resetReceiveSession() {
    this.receiveGeneration++, this.receiveTail = Promise.resolve(), this.pendingReceives = 0, this.pendingReceiveBytes = 0, this.decoder = new WebHostOutputDecoder, this.queuedOutput.length = 0, this.queuedOutputBytes = 0, this.sink?.resetSurfaceSession?.();
  }
  async receive(message, generation) {
    if (this.disposed || generation !== this.receiveGeneration)
      return;
    let limit = HOST_WIRE_MAX_RECORD_BYTES * 2, oversized = typeof message === "string" ? !fitsUTF8(message, limit) : message instanceof ArrayBuffer || ArrayBuffer.isView(message) ? message.byteLength > limit : typeof Blob < "u" && message instanceof Blob ? message.size > limit : !1, bytes = await (oversized ? void 0 : bytesFromWebSocketMessage(message));
    if (this.disposed || generation !== this.receiveGeneration)
      return;
    if (oversized) {
      this.deliver(this.decoder.rejectOversizedMessage()), this.sendPendingResyncRequests();
      return;
    }
    if (!bytes)
      return;
    for (let record of this.decoder.feed(bytes))
      this.deliver(record);
    this.sendPendingResyncRequests();
  }
  deliver(record) {
    if (this.disposed)
      return;
    let sink = this.sink;
    if (!sink) {
      let bytes = JSON.stringify(record).length * 2;
      if (this.queuedOutput.length >= 256 || this.queuedOutputBytes + bytes > 16777216) {
        this.failResourceLimit(`WebHost stopped: unbound output exceeded 256 records or 16 MiB. Reload the scene to restart.
`);
        return;
      }
      this.queuedOutputBytes += bytes, this.queuedOutput.push(record);
      return;
    }
    switch (record.type) {
      case "surface":
        sink.presentSurface(record.frame, this.decoder.prepareToPresentSurface(record.frame));
        break;
      case "clipboard":
        sink.writeClipboard?.(record.text);
        break;
      case "runtimeIssue":
        sink.notifyRuntimeIssue?.(record.issue);
        break;
      case "frameDiagnostic":
        sink.recordFrameDiagnostic?.(record.diagnostic);
        break;
      case "surfaceDropped":
        break;
      case "text":
        sink.writeOutput?.(record.text);
        break;
    }
  }
  flushQueuedInput() {
    if (this.disposed || this.socket.readyState !== socketOpenState)
      return;
    while (this.queuedInput.length > 0)
      try {
        this.socket.send(this.queuedInput[0]), this.queuedInput.shift();
      } catch {
        return;
      }
  }
  failResourceLimit(message) {
    if (this.disposed)
      return;
    this.resourceFailure = message, this.sink?.writeError?.(message), this.dispose();
  }
  admitsQueuedInput(chunks) {
    let bytes = [...this.queuedInput, ...chunks].reduce((total, item) => total + item.byteLength, 0);
    if (this.queuedInput.length + chunks.length <= 1024 && bytes <= 1048576)
      return !0;
    return this.failResourceLimit(`WebHost stopped: disconnected input exceeded 1,024 records or 1 MiB. Reload the scene to restart.
`), !1;
  }
  sendPendingResyncRequests() {
    while (!0) {
      let request = this.decoder.takeResyncRequest();
      if (!request)
        return;
      try {
        this.sendInput(encodeResyncControlMessage(request));
      } catch {
        this.decoder.resyncRequestDeliveryFailed(request);
        return;
      }
    }
  }
};
function webSocketSceneURL(options) {
  if (options.webSocketURL) {
    let explicit = new URL(String(options.webSocketURL), currentPageURL());
    return explicit.searchParams.set("token", options.token), explicit;
  }
  let url = new URL(String(options.baseURL ?? currentPageURL()), currentPageURL());
  return url.protocol = url.protocol === "https:" ? "wss:" : "ws:", url.pathname = `${url.pathname.endsWith("/") ? url.pathname.slice(0, -1) : url.pathname}/ws/scene/${encodeURIComponent(options.sceneId)}`, url.search = "", url.searchParams.set("token", options.token), url;
}
async function bytesFromWebSocketMessage(message) {
  if (typeof message === "string")
    return textEncoder2.encode(message);
  if (message instanceof Uint8Array)
    return message;
  if (message instanceof ArrayBuffer)
    return new Uint8Array(message);
  if (ArrayBuffer.isView(message))
    return new Uint8Array(message.buffer, message.byteOffset, message.byteLength);
  if (typeof Blob < "u" && message instanceof Blob)
    return new Uint8Array(await message.arrayBuffer());
}
function defaultWebSocketFactory(url) {
  if (typeof WebSocket > "u")
    throw Error("WebSocket is not available");
  return new WebSocket(url);
}
function currentPageURL() {
  return globalThis.location?.href ?? "http://127.0.0.1/";
}

// dist/src/wasi/SharedInputQueue.js
var sharedInputQueueDefaultCapacity = 65536;
function hydrateSharedInputQueue(buffers) {
  return {
    control: new Int32Array(buffers.controlBuffer),
    data: new Uint8Array(buffers.dataBuffer)
  };
}
var SharedInputQueueWriter = class {
  queue;
  writeChain = Promise.resolve();
  pendingWrites = 0;
  constructor(buffers) {
    this.queue = hydrateSharedInputQueue(buffers);
  }
  writeAsync(chunk, options = {}) {
    let bytes = normalizeChunk(chunk);
    if (bytes.length === 0)
      return Promise.resolve({ status: "written" });
    if (Atomics.load(this.queue.control, 2) !== 0)
      return Promise.resolve({
        status: "closed",
        bytesWritten: 0
      });
    if (this.pendingWrites === 0 && bytes.length <= this.availableCapacity())
      return this.writeSegment(bytes), Promise.resolve({ status: "written" });
    this.pendingWrites += 1;
    let attempt = this.writeChain.then(() => this.performChunkedWrite(bytes, options), () => this.performChunkedWrite(bytes, options));
    return this.writeChain = attempt, attempt.finally(() => {
      this.pendingWrites -= 1;
    });
  }
  async performChunkedWrite(bytes, options) {
    let now = options.now ?? (() => Date.now()), deadline = now() + Math.max(0, options.deadlineMilliseconds ?? 500), written = 0;
    while (written < bytes.length) {
      if (Atomics.load(this.queue.control, 2) !== 0)
        return {
          status: "closed",
          bytesWritten: written
        };
      let free = this.availableCapacity();
      if (free > 0) {
        let segment = Math.min(free, bytes.length - written);
        this.writeSegment(bytes.subarray(written, written + segment)), written += segment;
        continue;
      }
      let remainingBudget = deadline - now();
      if (remainingBudget <= 0)
        return {
          status: "partial",
          bytesWritten: written,
          bytesRemaining: bytes.length - written
        };
      await this.waitForCapacity(1, {
        timeoutMilliseconds: Math.min(50, remainingBudget),
        singleWait: !0
      });
    }
    return { status: "written" };
  }
  writeSegment(segment) {
    let length = this.queue.data.length, writeIndex = Atomics.load(this.queue.control, 1);
    writeToRingBuffer(this.queue.data, segment, writeIndex), Atomics.store(this.queue.control, 1, ringAdvance(writeIndex, segment.length, length)), Atomics.notify(this.queue.control, 1);
  }
  write(chunk) {
    if (Atomics.load(this.queue.control, 2) !== 0)
      return;
    let bytes = normalizeChunk(chunk);
    if (bytes.length === 0)
      return;
    let length = this.queue.data.length, readIndex = Atomics.load(this.queue.control, 0), writeIndex = Atomics.load(this.queue.control, 1), availableCapacity = length - ringUsed(readIndex, writeIndex, length);
    if (bytes.length > availableCapacity)
      throw Error(`Shared input queue overflow: cannot enqueue ${bytes.length} byte(s) into ${availableCapacity} byte(s) of free space.`);
    writeToRingBuffer(this.queue.data, bytes, writeIndex), Atomics.store(this.queue.control, 1, ringAdvance(writeIndex, bytes.length, length)), Atomics.notify(this.queue.control, 1);
  }
  availableCapacity() {
    let length = this.queue.data.length;
    return length - ringUsed(Atomics.load(this.queue.control, 0), Atomics.load(this.queue.control, 1), length);
  }
  async waitForCapacity(minimumBytes, options = {}) {
    let required = Math.max(0, Math.ceil(minimumBytes));
    if (required > this.queue.data.length)
      return !1;
    let timeout = options.timeoutMilliseconds ?? 50;
    while (!0) {
      let readIndex = Atomics.load(this.queue.control, 0);
      if (Atomics.load(this.queue.control, 2) !== 0)
        return !1;
      if (this.availableCapacity() >= required)
        return !0;
      if (typeof Atomics.waitAsync === "function") {
        let waiting = Atomics.waitAsync(this.queue.control, 0, readIndex, timeout);
        if (waiting.async)
          await waiting.value;
      } else
        await new Promise((resolve) => {
          setTimeout(resolve, 1);
        });
      if (options.singleWait)
        return this.availableCapacity() >= required;
    }
  }
  close() {
    Atomics.store(this.queue.control, 2, 1), Atomics.notify(this.queue.control, 1), Atomics.notify(this.queue.control, 0);
  }
};
function normalizeChunk(chunk) {
  return typeof chunk === "string" ? (/* @__PURE__ */ new TextEncoder()).encode(chunk) : new Uint8Array(chunk);
}
function ringUsed(readIndex, writeIndex, length) {
  let span = 2 * length;
  return ((writeIndex - readIndex) % span + span) % span;
}
function ringAdvance(index, delta, length) {
  return (index + delta) % (2 * length);
}
function writeToRingBuffer(buffer, chunk, startIndex) {
  let offset = startIndex % buffer.length, firstSegmentLength = Math.min(chunk.length, buffer.length - offset);
  if (buffer.set(chunk.subarray(0, firstSegmentLength), offset), firstSegmentLength < chunk.length)
    buffer.set(chunk.subarray(firstSegmentLength), 0);
}

// dist/src/wasi/StdIOPipeDelivery.js
var deliverChunk;
function provideStdIOPipeDelivery(deliver) {
  deliverChunk = deliver;
}
function deliverToStdIOPipe(pipe, chunk) {
  if (!deliverChunk)
    throw Error("StdIOPipe is not loaded");
  return deliverChunk(pipe, chunk);
}

// dist/src/wasi/StdIOPipe.js
var StdIOPipe = class {
  static {
    provideStdIOPipeDelivery((pipe, chunk) => pipe.writeChunk(chunk).delivered);
  }
  chunks = [];
  waiters = [];
  listeners = /* @__PURE__ */ new Set;
  consumer;
  closed = !1;
  get bufferedBytes() {
    return this.chunks.reduce((total, chunk) => total + chunk.byteLength, 0);
  }
  write(chunk) {
    let { delivered, observed } = this.writeChunk(chunk);
    return delivered && observed;
  }
  writeChunk(chunk) {
    if (this.closed)
      return {
        delivered: !1,
        observed: !0
      };
    let bytes = typeof chunk === "string" ? (/* @__PURE__ */ new TextEncoder()).encode(chunk) : new Uint8Array(chunk), delivered = !0, waiter = this.waiters.shift();
    if (waiter)
      waiter({
        done: !1,
        value: bytes
      });
    else {
      if (this.consumer && this.chunks.length > 0)
        this.offerQueued();
      if (!this.consumer)
        this.chunks.push(bytes);
      else if (this.chunks.length > 0)
        delivered = !1;
      else
        delivered = this.consumer(bytes) !== !1;
    }
    let observed = !0;
    for (let listener of this.listeners)
      if (listener(bytes) === !1)
        observed = !1;
    return {
      delivered,
      observed
    };
  }
  close() {
    if (this.closed)
      return;
    this.closed = !0;
    while (this.waiters.length > 0)
      this.waiters.shift()?.({
        done: !0,
        value: void 0
      });
  }
  async read() {
    if (this.consumer)
      throw Error("The pipe already has an exclusive consumer");
    let next = this.chunks.shift();
    if (next)
      return next;
    if (this.closed)
      return;
    return await new Promise((resolve) => {
      this.waiters.push((result) => resolve(result.done ? void 0 : result.value));
    });
  }
  subscribe(listener) {
    return this.listeners.add(listener), () => {
      this.listeners.delete(listener);
    };
  }
  consume(listener) {
    if (this.consumer || this.waiters.length > 0)
      throw Error("The pipe already has an exclusive consumer or pending read");
    return this.consumer = listener, this.offerQueued(), () => {
      if (this.consumer === listener)
        this.consumer = void 0;
    };
  }
  offerQueued() {
    let consumer = this.consumer;
    while (consumer && this.consumer === consumer) {
      let chunk = this.chunks.shift();
      if (!chunk)
        return;
      if (consumer(chunk) === !1) {
        this.chunks.unshift(chunk);
        return;
      }
    }
  }
  async* [Symbol.asyncIterator]() {
    while (!0) {
      let next = await this.read();
      if (!next)
        return;
      yield next;
    }
  }
};

// dist/src/wasi/WasmEngineCapabilities.js
function collectWasmEngineProbeSignals() {
  let probe = /* @__PURE__ */ Error("wasm-engine-probe"), wasm = globalThis.WebAssembly;
  return {
    errorStack: readProbe(() => typeof probe.stack === "string" ? probe.stack : "", ""),
    errorHasGeckoFileName: readProbe(() => ("fileName" in probe), !1),
    errorHasJSCSourceURL: readProbe(() => ("sourceURL" in probe), !1),
    wasmSuspendingType: readProbe(() => typeof wasm?.Suspending, "undefined"),
    wasmPromisingType: readProbe(() => typeof wasm?.promising, "undefined")
  };
}
function classifyWasmEngineFamily(signals) {
  let v8 = /^\s*at /m.test(signals.errorStack), atFrames = /^[^\n]*@/m.test(signals.errorStack), gecko = signals.errorHasGeckoFileName, jsc = signals.errorHasJSCSourceURL;
  if (Number(v8) + Number(gecko) + Number(jsc) > 1 || v8 && atFrames)
    return "unknown";
  if (v8)
    return "v8";
  if (gecko)
    return "gecko";
  if (jsc)
    return "jsc";
  return "unknown";
}
function resolveWasmEngineCapabilities(signals = collectWasmEngineProbeSignals()) {
  let engine = classifyWasmEngineFamily(signals);
  return {
    engine,
    supportsJSPI: signals.wasmSuspendingType === "function" && signals.wasmPromisingType === "function",
    stackLeanRecommended: engine !== "v8"
  };
}
function stackProfileEnvironmentDefaults(capabilities) {
  if (capabilities.engine === "v8")
    return { SWIFTTUI_STACK_LEAN_PROFILE: "0" };
  return { SWIFTTUI_LEAN_RETAINED_REUSE: "1" };
}
function readProbe(read, fallback) {
  try {
    return read();
  } catch {
    return fallback;
  }
}

// dist/src/wasi/BrowserWASIBridge.js
var maximumWASIResyncControlBytes = sharedInputQueueDefaultCapacity - 1, BrowserWASIBridge = class {
  stdin = new StdIOPipe;
  stdout = new StdIOPipe;
  stderr = new StdIOPipe;
  environment;
  detachStdout;
  detachStderr;
  decoder = new WebHostOutputDecoder;
  resizeListeners = /* @__PURE__ */ new Set;
  latestResize;
  constructor(options) {
    this.environment = {
      SWIFTTUI_MODE: "browser",
      SWIFTTUI_TRANSPORT: "surface",
      SWIFTTUI_SURFACE_DELTA: "1",
      SWIFTTUI_GEOMETRY_REVISIONS: "1",
      SWIFTTUI_SCENE: options.sceneId,
      SWIFTTUI_COLUMNS: String(Math.max(1, options.columns)),
      SWIFTTUI_ROWS: String(Math.max(1, options.rows)),
      SWIFTTUI_RENDER_MODE: "async-no-cancel",
      ...stackProfileEnvironmentDefaults(options.engineCapabilities ?? resolveWasmEngineCapabilities()),
      ...options.environment,
      ...options.renderStyle ? { SWIFTTUI_RENDER_STYLE: encodeWebHostTerminalRenderStyleBase64(options.renderStyle) } : {}
    }, this.latestResize = {
      columns: Math.max(1, options.columns),
      rows: Math.max(1, options.rows)
    };
  }
  bindOutput(sink) {
    this.detachStdout?.(), this.detachStderr?.(), this.decoder = new WebHostOutputDecoder, this.detachStdout = this.stdout.consume((chunk) => {
      for (let record of this.decoder.feed(chunk))
        switch (record.type) {
          case "surface":
            sink.presentSurface(record.frame, this.decoder.prepareToPresentSurface(record.frame));
            break;
          case "clipboard":
            sink.writeClipboard?.(record.text);
            break;
          case "runtimeIssue":
            sink.notifyRuntimeIssue?.(record.issue);
            break;
          case "frameDiagnostic":
            sink.recordFrameDiagnostic?.(record.diagnostic);
            break;
          case "surfaceDropped":
            break;
          case "text":
            sink.writeOutput?.(record.text);
            break;
        }
      this.sendPendingResyncRequests();
    }), this.detachStderr = this.stderr.consume((chunk) => {
      sink.writeError?.((/* @__PURE__ */ new TextDecoder()).decode(chunk));
    });
  }
  resize(columns, rows, cellWidth, cellHeight) {
    let normalizedColumns = Math.max(1, columns), normalizedRows = Math.max(1, rows);
    this.environment.SWIFTTUI_COLUMNS = String(normalizedColumns), this.environment.SWIFTTUI_ROWS = String(normalizedRows), this.latestResize = {
      columns: normalizedColumns,
      rows: normalizedRows,
      cellWidth,
      cellHeight
    }, this.stdin.write(encodeResizeControlMessage(columns, rows, cellWidth, cellHeight));
    for (let listener of this.resizeListeners)
      listener(normalizedColumns, normalizedRows, cellWidth, cellHeight);
  }
  updateRenderStyle(style) {
    this.environment.SWIFTTUI_RENDER_STYLE = encodeWebHostTerminalRenderStyleBase64(style), this.stdin.write(encodeRenderStyleControlMessage(style));
  }
  updatePointerCapabilities(supportsScrollPanning) {
    this.stdin.write(encodePointerCapabilitiesControlMessage(supportsScrollPanning));
  }
  sendInput(chunk) {
    this.stdin.write(chunk);
  }
  requestImagePayloads(ids) {
    let acceptedIds = this.decoder.requestImagePayloads(ids);
    return this.sendPendingResyncRequests(), acceptedIds;
  }
  notifyInputCapacityAvailable() {
    this.sendPendingResyncRequests();
  }
  subscribeResize(listener) {
    return this.resizeListeners.add(listener), listener(this.latestResize.columns, this.latestResize.rows, this.latestResize.cellWidth, this.latestResize.cellHeight), () => {
      this.resizeListeners.delete(listener);
    };
  }
  sendPendingResyncRequests() {
    while (!0) {
      let request = this.decoder.takeResyncRequest(maximumWASIResyncControlBytes);
      if (!request)
        return;
      if (!deliverToStdIOPipe(this.stdin, encodeResyncControlMessage(request))) {
        this.decoder.resyncRequestDeliveryFailed(request);
        return;
      }
    }
  }
  dispose() {
    this.detachStdout?.(), this.detachStderr?.(), this.resizeListeners.clear(), this.stdin.close(), this.stdout.close(), this.stderr.close();
  }
};

// dist/src/WebHostApp.js
async function createWebHostApp(options) {
  let manifest = await resolveManifest(options), controller = new InternalWebHostAppController({
    mount: options.mount,
    manifest,
    style: options.style,
    environment: options.environment,
    embeddedHost: options.embeddedHost,
    bridgeFactory: options.bridgeFactory,
    initialSceneId: options.initialSceneId,
    createElement: options.createElement,
    sceneRuntimeFactory: options.sceneRuntimeFactory ?? ((runtimeOptions) => new WebHostSceneRuntime(runtimeOptions)),
    suspendHiddenScenes: options.suspendHiddenScenes,
    visibilityDocument: options.visibilityDocument ?? defaultVisibilityDocument(),
    renderer: options.renderer,
    domFont: options.domFont,
    sceneFrame: options.sceneFrame,
    paintScheduling: options.paintScheduling,
    accessibilitySettings: options.accessibilitySettings
  });
  return await controller.initialize(), controller;
}
var InternalWebHostAppController = class {
  scenes;
  selectedSceneId;
  mount;
  sceneRoot;
  style;
  environment;
  embeddedHost;
  bridgeFactory;
  sceneRuntimeFactory;
  runtimes = /* @__PURE__ */ new Map;
  bridges = /* @__PURE__ */ new Map;
  suspendHiddenScenes;
  renderer;
  domFont;
  sceneFrame;
  paintScheduling;
  visibilityDocument;
  detachVisibilityListener;
  disposed = !1;
  sceneNavigation;
  accessibilitySettings;
  constructor(options) {
    this.renderer = resolveSurfaceRenderer(options.renderer), this.mount = options.mount;
    let settingsEnabled = options.accessibilitySettings ?? !0, initialStyle = {
      ...options.style,
      ...settingsEnabled ? readWebHostAccessibilityPreferences() : {}
    };
    if (this.style = normalizeWebHostTerminalStyle(initialStyle), this.domFont = options.domFont, this.environment = options.environment, this.embeddedHost = options.embeddedHost, this.bridgeFactory = options.bridgeFactory, this.sceneRuntimeFactory = options.sceneRuntimeFactory, this.suspendHiddenScenes = options.suspendHiddenScenes, this.sceneFrame = options.sceneFrame ?? "fill", this.paintScheduling = options.paintScheduling, this.visibilityDocument = options.visibilityDocument, this.scenes = options.manifest.scenes, this.selectedSceneId = options.initialSceneId && options.manifest.scenes.some((scene) => scene.id === options.initialSceneId) ? options.initialSceneId : options.manifest.scenes.find((scene) => scene.id === options.manifest.defaultSceneId)?.id ?? options.manifest.defaultSceneId, this.sceneRoot = (options.createElement ?? defaultCreateElement)("div"), this.sceneRoot.className = "webhost-scene-root", this.sceneRoot.style.boxSizing = "border-box", this.sceneRoot.style.width = "100%", this.sceneRoot.style.height = "100%", this.sceneRoot.style.minWidth = "0", this.sceneRoot.style.minHeight = "0", this.sceneRoot.style.overflow = "hidden", this.sceneFrame === "resizable")
      this.sceneRoot.style.display = "flex", this.sceneRoot.style.justifyContent = "center", this.sceneRoot.style.alignItems = "flex-start";
    else
      this.sceneRoot.style.display = "block";
    let document2 = this.mount.ownerDocument;
    if (document2 && (settingsEnabled || this.scenes.length > 1)) {
      let appRoot = document2.createElement("div");
      if (appRoot.className = "webhost-app", Object.assign(appRoot.style, {
        display: "flex",
        flexDirection: "column",
        width: "100%",
        height: "100%",
        minHeight: "0"
      }), this.scenes.length > 1) {
        let label = document2.createElement("label");
        label.textContent = "Scene ";
        let select = document2.createElement("select");
        select.setAttribute("aria-label", "Scene");
        for (let scene of this.scenes) {
          let option = document2.createElement("option");
          option.value = scene.id, option.textContent = scene.title ?? scene.id, select.append(option);
        }
        select.value = this.selectedSceneId;
        let status = document2.createElement("span");
        status.setAttribute("role", "status"), select.addEventListener("change", async () => {
          select.disabled = !0, status.textContent = "";
          try {
            await this.switchScene(select.value);
          } catch {
            status.textContent = "Unable to open this scene. Try selecting it again.";
          } finally {
            select.disabled = !1, select.focus({ preventScroll: !0 });
          }
        }), this.sceneNavigation = select, label.append(select, status), appRoot.append(label);
      }
      if (settingsEnabled)
        this.accessibilitySettings = createWebHostAccessibilitySettings(document2, this.style, (preferences) => this.setStyle(preferences)), appRoot.append(this.accessibilitySettings.element);
      this.sceneRoot.style.flex = "1 1 auto", appRoot.append(this.sceneRoot), this.mount.replaceChildren(appRoot);
    } else
      this.mount.replaceChildren(this.sceneRoot);
    this.applyHostFrameStyle();
  }
  async initialize() {
    this.installVisibilityListener(), await this.ensureRuntime(this.selectedSceneId), await this.switchScene(this.selectedSceneId);
  }
  async switchScene(id) {
    if (this.disposed)
      throw Error("SwiftTUI host is disposed");
    if (!this.scenes.find((scene) => scene.id === id))
      throw Error(`Unknown scene: ${id}`);
    for (let [sceneId, runtime2] of this.runtimes)
      runtime2.setVisible(sceneId === id);
    let runtime = await this.ensureRuntime(id);
    if (this.disposed)
      return;
    if (runtime.setVisible(!0), this.selectedSceneId = id, this.sceneNavigation)
      this.sceneNavigation.value = id;
  }
  setStyle(style) {
    if (this.disposed)
      return;
    let merged = mergeWebHostTerminalStyle(this.style, style);
    this.style = merged, this.accessibilitySettings?.update(this.style);
    for (let runtime of this.runtimes.values())
      runtime.setStyle(this.style);
    this.applyHostFrameStyle();
  }
  async dispose() {
    if (this.disposed)
      return;
    this.disposed = !0, this.detachVisibilityListener?.(), this.detachVisibilityListener = void 0;
    for (let runtime of this.runtimes.values())
      runtime.dispose();
    for (let bridge of this.bridges.values())
      bridge.dispose();
    this.runtimes.clear(), this.bridges.clear(), this.mount.replaceChildren();
  }
  installVisibilityListener() {
    let visibilityDocument = this.visibilityDocument;
    if (!visibilityDocument)
      return;
    let listener = () => {
      let visible = !visibilityDocument.hidden;
      for (let runtime of this.runtimes.values())
        runtime.setDocumentVisible(visible);
    };
    visibilityDocument.addEventListener("visibilitychange", listener), this.detachVisibilityListener = () => {
      visibilityDocument.removeEventListener("visibilitychange", listener);
    };
  }
  async ensureRuntime(id) {
    if (this.disposed)
      throw Error("SwiftTUI host is disposed");
    let existing = this.runtimes.get(id);
    if (existing)
      return existing;
    let descriptor = this.scenes.find((scene) => scene.id === id);
    if (!descriptor)
      throw Error(`Unknown scene: ${id}`);
    let bridge = this.makeBridge(id, descriptor), runtime = this.sceneRuntimeFactory({
      mount: this.sceneRoot,
      descriptor,
      style: this.style,
      bridge,
      onInput: (chunk) => bridge.sendInput(chunk),
      suspendWhenHidden: this.suspendHiddenScenes,
      renderer: this.renderer,
      domFont: this.domFont,
      sceneFrame: this.sceneFrame,
      paintScheduling: this.paintScheduling
    });
    if (this.bridges.set(id, bridge), this.runtimes.set(id, runtime), await runtime.mount(), runtime.setVisible(id === this.selectedSceneId), this.visibilityDocument)
      runtime.setDocumentVisible(!this.visibilityDocument.hidden);
    return runtime;
  }
  makeBridge(sceneId, descriptor) {
    if (this.bridgeFactory)
      return this.bridgeFactory({
        sceneId,
        descriptor,
        style: this.style,
        environment: this.environment
      });
    if (this.embeddedHost)
      return new WebSocketSceneBridge({
        sceneId,
        token: this.embeddedHost.token,
        baseURL: this.embeddedHost.webSocketBaseURL,
        webSocketFactory: this.embeddedHost.webSocketFactory
      });
    return new BrowserWASIBridge({
      sceneId,
      columns: 80,
      rows: 24,
      environment: this.environment,
      renderStyle: this.style
    });
  }
  applyHostFrameStyle() {
    this.mount.style.background = "linear-gradient(180deg, #0f172a 0%, #111827 100%)", this.mount.style.boxSizing = "border-box", this.mount.style.minWidth = "0", this.mount.style.minHeight = "0", this.mount.style.overflow = "hidden", this.mount.style.display = "block", this.mount.style.padding = "1rem";
  }
};
function defaultVisibilityDocument() {
  if (typeof document > "u")
    return;
  return document;
}
function defaultCreateElement(tagName) {
  if (typeof document > "u")
    throw Error("document is not available");
  return document.createElement(tagName);
}
async function resolveManifest(options) {
  if (options.manifest)
    return loadWebHostSceneManifest(options.manifest);
  if (options.manifestUrl)
    return loadWebHostSceneManifest(options.manifestUrl);
  return normalizeWebHostSceneManifest([{
    id: "main",
    title: "Main",
    isDefault: !0
  }]);
}

// dist/src/browser.js
async function bootstrap() {
  let mount = document.getElementById("webhost-root");
  if (!mount)
    throw Error("webhost root element not found");
  let config = window.__WEBTUI__ ?? {}, pageURL = new URL(globalThis.location?.href ?? import.meta.url), embeddedToken = config.embeddedHost?.token ?? pageURL.searchParams.get("token") ?? void 0, controller = await createWebHostApp({
    mount,
    manifestUrl: tokenizedURL(config.manifestUrl ?? new URL("./scene-manifest.json", pageURL), embeddedToken),
    initialSceneId: config.initialSceneId,
    style: config.style,
    renderer: config.renderer ?? rendererFromQuery(pageURL),
    sceneFrame: config.sceneFrame ?? "resizable",
    embeddedHost: embeddedToken ? {
      token: embeddedToken,
      webSocketBaseURL: config.embeddedHost?.webSocketBaseURL ?? new URL("./", pageURL).href
    } : void 0
  });
  window.__WEBTUI_APP__ = controller;
}
bootstrap().catch((error) => {
  let mount = document.getElementById("webhost-root");
  if (!mount)
    throw error;
  mount.setAttribute("role", "alert"), mount.textContent = error instanceof Error ? error.message : String(error);
});
function rendererFromQuery(pageURL) {
  let renderer = pageURL.searchParams.get("renderer");
  return renderer === "dom" || renderer === "canvas" ? renderer : void 0;
}
function tokenizedURL(value, token) {
  if (!token)
    return value;
  let url = new URL(String(value), globalThis.location?.href ?? import.meta.url);
  return url.searchParams.set("token", token), url;
}
