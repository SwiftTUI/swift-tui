// src/DomFontResources.ts
var DOM_FONT_FAMILY = "SwiftTUI Source Code Pro";
var DOM_FONT_ASSET_PATH = "assets/swifttui-fonts/2184c1f2bac4/";
var DOM_FONT_FALLBACK = '"Menlo", "Consolas", "Liberation Mono", monospace';
var DOM_UNICODE_FALLBACK = '"PingFang SC", "Hiragino Sans", "Noto Sans CJK SC", "Apple Color Emoji", "Segoe UI Emoji", "Noto Color Emoji", monospace';
var DOM_FONT_FACES = [
  { file: "SourceCodePro-Regular.ttf.woff2", weight: "400", style: "normal" },
  { file: "SourceCodePro-Bold.ttf.woff2", weight: "700", style: "normal" },
  { file: "SourceCodePro-It.ttf.woff2", weight: "400", style: "italic" },
  { file: "SourceCodePro-BoldIt.ttf.woff2", weight: "700", style: "italic" }
];
var documents = new WeakMap;
var nextAlias = 0;

class DomFontResources {
  disposed = false;
  releaseFaces;
  cancelWait;
  ready;
  constructor(doc, family, size, options = {}) {
    this.ready = this.load(doc, family, size, options).catch(() => {
      this.releaseFaces?.();
      this.releaseFaces = undefined;
      return {
        status: this.disposed ? "disposed" : "fallback",
        family: DOM_FONT_FALLBACK,
        diagnostic: "DOM font configuration failed; using the measured system monospace fallback."
      };
    });
  }
  async load(doc, family, size, options) {
    if (!doc.fonts || typeof FontFace === "undefined")
      return {
        status: "fallback",
        family: DOM_FONT_FALLBACK,
        diagnostic: "Font loading is unavailable; using the measured system monospace fallback."
      };
    let desiredFamily = family;
    let readiness;
    if (family === DOM_FONT_FAMILY) {
      let base;
      try {
        base = new URL(String(options.assetBase ?? DOM_FONT_ASSET_PATH), doc.baseURI);
      } catch {
        return {
          status: "fallback",
          family: DOM_FONT_FALLBACK,
          diagnostic: "Invalid DOM font asset base; using the measured system monospace fallback."
        };
      }
      if (!base.pathname.endsWith("/"))
        base.pathname += "/";
      const key = base.href;
      const shared = documents.get(doc) ?? new Map;
      documents.set(doc, shared);
      let entry = shared.get(key);
      if (!entry) {
        const alias = `SwiftTUIFont${++nextAlias}`;
        const faces = DOM_FONT_FACES.map((face) => new FontFace(alias, `url(${JSON.stringify(new URL(face.file, base).href)})`, { weight: face.weight, style: face.style }));
        entry = { refs: 0, alias, faces, ready: Promise.resolve() };
        const owned2 = entry;
        entry.ready = Promise.all(faces.map((face) => face.load())).then(() => {
          if (owned2.refs > 0)
            for (const face of faces)
              doc.fonts.add(face);
        });
        shared.set(key, entry);
      }
      entry.refs++;
      const owned = entry;
      let released = false;
      this.releaseFaces = () => {
        if (released)
          return;
        released = true;
        if (--owned.refs === 0) {
          for (const face of owned.faces)
            doc.fonts.delete(face);
          if (shared.get(key) === owned)
            shared.delete(key);
        }
      };
      desiredFamily = `"${entry.alias}", ${DOM_UNICODE_FALLBACK}`;
      readiness = entry.ready;
    } else {
      readiness = Promise.all(["", "700 ", "italic ", "italic 700 "].map((prefix) => doc.fonts.load(`${prefix}${size}px ${family}`, "Wé")));
    }
    const waitMs = Math.max(0, Math.min(1e4, Number.isFinite(options.timeoutMs) ? options.timeoutMs : 2000));
    let timer;
    const interrupted = new Promise((resolve) => {
      timer = setTimeout(() => resolve("timeout"), waitMs);
      this.cancelWait = () => resolve("disposed");
    });
    const outcome = await Promise.race([
      readiness.then(() => "ready", () => "failed"),
      interrupted
    ]);
    clearTimeout(timer);
    this.cancelWait = undefined;
    if (this.disposed || outcome === "disposed")
      return { status: "disposed", family: DOM_FONT_FALLBACK };
    if (outcome === "ready")
      return { status: "ready", family: desiredFamily };
    this.releaseFaces?.();
    this.releaseFaces = undefined;
    return {
      status: "fallback",
      family: DOM_FONT_FALLBACK,
      diagnostic: `DOM font ${outcome === "timeout" ? "readiness timed out" : "loading failed"}; using the measured system monospace fallback for this session.`
    };
  }
  dispose() {
    this.disposed = true;
    this.cancelWait?.();
    this.releaseFaces?.();
    this.releaseFaces = undefined;
  }
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

// src/normalizeWireTokens.ts
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
function normalizeScalingMode(value) {
  switch (value) {
    case "stretch":
    case "fit":
    case "fill":
      return value;
    default:
      return "fit";
  }
}
function isSupportedImageFormat(value) {
  return value === "png" || value === "jpeg" || value === "gif";
}

// src/AccessibilityTree.ts
class AccessibilityTreeMounter {
  sendAction;
  element;
  announcerElement;
  nodesById = new Map;
  previousLabelsById = new Map;
  hasLiveRegionBaseline = false;
  modelsById = new Map;
  presenting = false;
  nextRequestID = 0n;
  acknowledgedRequestID = 0n;
  pendingValues = new Map;
  pendingFocus;
  runtimeFocusedElement;
  constructor(sendAction) {
    this.sendAction = sendAction;
    this.element = document.createElement("div");
    this.element.className = "webhost-scene__accessibility-tree";
    this.element.style.position = "absolute";
    this.element.style.inset = "0";
    this.element.style.opacity = "0";
    this.element.style.pointerEvents = "none";
    this.announcerElement = document.createElement("div");
    this.announcerElement.className = "webhost-scene__accessibility-announcer";
    this.announcerElement.setAttribute("aria-atomic", "true");
    applyScreenReaderOnlyStyle(this.announcerElement);
  }
  present(nodes, metrics, announcements = [], options = {}) {
    const activeBeforePresentation = document.activeElement;
    const visibleNodes = nodes.filter((node) => !node.hidden).map((node) => ({
      ...node,
      liveRegion: normalizeLiveRegion(node.liveRegion)
    }));
    const normalizedAnnouncements = announcements.map((announcement) => ({
      ...announcement,
      politeness: normalizePoliteness(announcement.politeness)
    }));
    this.presenting = true;
    if (options.actionResponse) {
      const acknowledged = BigInt(options.actionResponse.requestID);
      if (acknowledged > this.acknowledgedRequestID)
        this.acknowledgedRequestID = acknowledged;
    }
    const previousById = this.nodesById;
    const nextById = new Map;
    const modelsById = new Map(visibleNodes.map((node) => [node.id, node]));
    for (const node of visibleNodes) {
      const existing = previousById.get(node.id);
      const tag = this.elementTag(node);
      const previousModel = this.modelsById.get(node.id);
      const reusable = existing?.tagName.toLowerCase() === tag && previousModel?.actionTarget === node.actionTarget;
      const element2 = reusable ? existing : this.createElement(node, tag);
      if (!reusable) {
        existing?.remove();
        this.pendingValues.delete(node.id);
        if (this.pendingFocus?.id === node.id)
          this.pendingFocus = undefined;
      }
      this.applyNodeAttributes(element2, node, metrics, node.parentId ? modelsById.get(node.parentId) : undefined);
      nextById.set(node.id, element2);
    }
    for (const id of previousById.keys()) {
      if (!nextById.has(id)) {
        previousById.get(id)?.remove();
        this.pendingValues.delete(id);
        if (this.pendingFocus?.id === id)
          this.pendingFocus = undefined;
      }
    }
    this.nodesById = nextById;
    this.modelsById = modelsById;
    const childOffsets = new Map;
    for (const node of visibleNodes) {
      const element2 = nextById.get(node.id);
      if (!element2) {
        continue;
      }
      const parent = node.parentId ? nextById.get(node.parentId) : undefined;
      const container = parent ?? this.element;
      const offset = childOffsets.get(container) ?? 0;
      if (container.children[offset] !== element2) {
        container.insertBefore(element2, container.children[offset] ?? null);
      }
      childOffsets.set(container, offset + 1);
    }
    this.announceLiveRegionChanges(visibleNodes, normalizedAnnouncements);
    const focused = visibleNodes.find((node) => node.isFocused);
    const element = focused ? this.nodesById.get(focused.id) : undefined;
    const pending = this.pendingFocus;
    const focusAcknowledged = pending !== undefined && pending.requestID <= this.acknowledgedRequestID;
    const synchronize = focusAcknowledged ? activeBeforePresentation === this.nodesById.get(pending.id) : element !== this.runtimeFocusedElement || element === activeBeforePresentation;
    this.runtimeFocusedElement = element;
    if (focusAcknowledged) {
      this.pendingFocus = undefined;
    }
    if ((options.synchronizeFocus ?? true) && synchronize && element && this.pendingFocus === undefined) {
      if (document.activeElement !== element)
        element.focus?.({ preventScroll: true });
    }
    this.presenting = false;
  }
  elementTag(node) {
    if (!node.actionTarget || !this.sendAction)
      return "div";
    if (node.role === "textEditor")
      return "textarea";
    if (["textField", "secureField", "slider", "stepper"].includes(node.role))
      return "input";
    return "div";
  }
  createElement(node, tag) {
    const element = document.createElement(tag);
    if (!node.actionTarget || !this.sendAction)
      return element;
    const current = () => this.nodesById.get(node.id) === element ? this.modelsById.get(node.id) : undefined;
    const send = (request) => {
      const model = current();
      if (this.presenting || !model?.actionTarget || model.isEnabled === false || !model.actions?.includes(request.action))
        return;
      const requestID = ++this.nextRequestID;
      if (request.action === "setValue")
        this.pendingValues.set(node.id, requestID);
      if (request.action === "focus")
        this.pendingFocus = { id: node.id, requestID };
      this.sendAction?.(model.actionTarget, request, String(requestID));
    };
    element.addEventListener("focus", () => send({ action: "focus" }));
    element.addEventListener("click", (event) => {
      event.stopPropagation();
      send({ action: "activate" });
    });
    element.addEventListener("keydown", (event) => {
      const model = current();
      if (!model || event.key === "Tab" || event.key === "Escape")
        return;
      if (tag !== "div" && event.key === "Enter" && model.role !== "textEditor")
        return;
      event.stopPropagation();
      let request;
      if (model.actions?.includes("increment") && ["ArrowRight", "ArrowUp"].includes(event.key)) {
        request = { action: "increment" };
      } else if (model.actions?.includes("decrement") && ["ArrowLeft", "ArrowDown"].includes(event.key)) {
        request = { action: "decrement" };
      } else if ((model.role === "slider" || model.role === "stepper") && (event.key === "Home" || event.key === "End")) {
        const value = event.key === "Home" ? model.valueMin : model.valueMax;
        if (value !== undefined)
          request = { action: "setValue", value: { type: "number", value } };
      } else if (tag === "div" && (event.key === "Enter" || event.key === " ")) {
        request = { action: "activate" };
      }
      if (request) {
        event.preventDefault();
        send(request);
      }
    });
    if (tag !== "div") {
      element.addEventListener("blur", () => {
        if (current()?.role === "secureField")
          element.value = "";
      });
      element.addEventListener("paste", (event) => event.stopPropagation());
      element.addEventListener("input", () => {
        const model = current();
        if (!model)
          return;
        const value = element.value;
        if (model.role === "slider" || model.role === "stepper") {
          const number = Number(value);
          if (value !== "" && Number.isFinite(number))
            send({
              action: "setValue",
              value: { type: "number", value: number }
            });
        } else {
          send({ action: "setValue", value: { type: "text", value } });
        }
      });
    }
    return element;
  }
  applyNodeAttributes(element, node, metrics, parent) {
    element.id = `swifttui-a11y-${stableDOMId(node.id)}`;
    element.dataset.accessibilityId = node.id;
    element.tabIndex = node.isFocused ? 0 : -1;
    const role = roleMapping(node.role);
    setOrRemoveAttribute(element, "role", node.role === "secureField" && element.tagName === "INPUT" ? undefined : role.role);
    setOrRemoveAttribute(element, "aria-level", role.level !== undefined ? String(role.level) : undefined);
    setOrRemoveAttribute(element, "aria-label", node.label || undefined);
    setOrRemoveAttribute(element, "aria-description", node.hint || undefined);
    setOrRemoveAttribute(element, "aria-live", node.liveRegion || undefined);
    if (node.isFocused) {
      element.dataset.focused = "true";
    } else {
      delete element.dataset.focused;
    }
    setOrRemoveAttribute(element, "aria-disabled", node.isEnabled === false ? "true" : undefined);
    setOrRemoveAttribute(element, "aria-checked", node.role === "toggle" && node.value?.type === "boolean" ? String(node.value.value) : undefined);
    setOrRemoveAttribute(element, "aria-expanded", node.role === "disclosureGroup" && node.value?.type === "boolean" ? String(node.value.value) : undefined);
    setOrRemoveAttribute(element, "aria-valuenow", node.value?.type === "number" ? String(node.value.value) : undefined);
    setOrRemoveAttribute(element, "aria-valuemin", node.valueMin === undefined ? undefined : String(node.valueMin));
    setOrRemoveAttribute(element, "aria-valuemax", node.valueMax === undefined ? undefined : String(node.valueMax));
    if (element.tagName === "INPUT" || element.tagName === "TEXTAREA") {
      const input = element;
      if (element.tagName === "INPUT") {
        input.type = node.role === "secureField" ? "password" : node.role === "slider" ? "range" : node.role === "stepper" ? "number" : "text";
      }
      input.disabled = node.isEnabled === false;
      setOrRemoveAttribute(element, "min", node.valueMin === undefined ? undefined : String(node.valueMin));
      setOrRemoveAttribute(element, "max", node.valueMax === undefined ? undefined : String(node.valueMax));
      setOrRemoveAttribute(element, "step", node.valueStep === undefined ? undefined : String(node.valueStep));
      const value = node.value ? String(node.value.value) : "";
      const pending = this.pendingValues.get(node.id);
      if (pending === undefined || pending <= this.acknowledgedRequestID) {
        this.pendingValues.delete(node.id);
        if (node.role !== "secureField" && input.value !== value)
          input.value = value;
      }
    }
    const [x, y, width, height] = node.rect;
    const [parentX, parentY] = parent?.rect ?? [0, 0];
    element.style.position = "absolute";
    element.style.left = `${(x - parentX) * metrics.cellWidth}px`;
    element.style.top = `${(y - parentY) * metrics.cellHeight}px`;
    element.style.width = `${Math.max(1, width) * metrics.cellWidth}px`;
    element.style.height = `${Math.max(1, height) * metrics.cellHeight}px`;
    element.style.boxSizing = "border-box";
    element.style.margin = "0";
    element.style.padding = "0";
    element.style.border = "0";
    element.style.minWidth = "0";
    element.style.minHeight = "0";
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
    const ordered = [
      ...assertive,
      ...imperativeAssertive,
      ...polite,
      ...imperativePolite
    ];
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
function setOrRemoveAttribute(element, name, value) {
  if (value === undefined) {
    element.removeAttribute(name);
    return;
  }
  element.setAttribute(name, value);
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

// src/SurfaceTypography.ts
function fontForStyle(terminalStyle, style) {
  const emphasis = style?.em ?? 0;
  const italic = (emphasis & 2) !== 0 ? "italic " : "";
  const weight = (emphasis & 1) !== 0 ? "700 " : "";
  return `${italic}${weight}${terminalStyle.fontSize}px ${terminalStyle.fontFamily}`;
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
  const pixels = density === "light" ? [[0, 0]] : density === "medium" ? [
    [0, 0],
    [1, 1]
  ] : [
    [0, 0],
    [1, 0],
    [0, 1]
  ];
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

// src/HostWireBudget.ts
var HOST_WIRE_MAX_RECORD_BYTES = 4 * 1024 * 1024;
var HOST_WIRE_MAX_GRID_DIMENSION = 1024;
var HOST_WIRE_MAX_GRID_CELLS = 65536;
var HOST_WIRE_MAX_IMAGES = 1024;
var HOST_WIRE_MAX_METADATA_ENTRIES = 65536;
var HOST_WIRE_MAX_CELL_TEXT_BYTES = 256;
var HOST_WIRE_MAX_STYLE_BYTES = 1024;
var HOST_WIRE_MAX_JSON_DEPTH = 32;
function fitsUTF8(text, limit) {
  let bytes = 0;
  for (const scalar of text) {
    const code = scalar.codePointAt(0);
    bytes += code <= 127 ? 1 : code <= 2047 ? 2 : code <= 65535 ? 3 : 4;
    if (bytes > limit)
      return false;
  }
  return true;
}
function fitsWireGrid(width, height) {
  return Number.isInteger(width) && Number.isInteger(height) && width >= 0 && height >= 0 && width <= HOST_WIRE_MAX_GRID_DIMENSION && height <= HOST_WIRE_MAX_GRID_DIMENSION && width * height <= HOST_WIRE_MAX_GRID_CELLS;
}
function wireStyleLimit(width, height) {
  return Math.max(1024, width * height + 1);
}
function fitsStyleContent(style) {
  let remaining = HOST_WIRE_MAX_STYLE_BYTES;
  const chargeString = (text) => {
    for (const scalar of text) {
      const code = scalar.codePointAt(0);
      remaining -= code <= 127 ? 1 : code <= 2047 ? 2 : code <= 65535 ? 3 : 4;
      if (remaining < 0)
        return false;
    }
    return true;
  };
  const visit = (value) => {
    remaining -= 8;
    if (remaining < 0)
      return false;
    if (typeof value === "string")
      return chargeString(value);
    if (Array.isArray(value))
      return value.every(visit);
    if (value !== null && typeof value === "object") {
      return Object.entries(value).every(([key, item]) => chargeString(key) && visit(item));
    }
    return true;
  };
  return visit(style);
}
function fitsJSONDepth(text) {
  let depth = 0;
  let quoted = false;
  let escaped = false;
  for (const character of text) {
    if (quoted) {
      if (escaped)
        escaped = false;
      else if (character === "\\")
        escaped = true;
      else if (character === '"')
        quoted = false;
    } else if (character === '"')
      quoted = true;
    else if (character === "[" || character === "{") {
      if (++depth > HOST_WIRE_MAX_JSON_DEPTH)
        return false;
    } else if (character === "]" || character === "}")
      depth--;
  }
  return true;
}
function fitsSurfaceBudget(frame) {
  const { width, height } = frame;
  if (!fitsWireGrid(width, height))
    return false;
  if (frame.styles.length + (frame.stylesBase ?? 0) > wireStyleLimit(width, height))
    return false;
  if (!frame.styles.every(fitsStyleContent))
    return false;
  if ((frame.rows?.length ?? 0) > height || (frame.deltaRows?.length ?? 0) > height)
    return false;
  const validCells = (cells) => {
    if (cells.length > width)
      return false;
    let end = 0;
    for (const [x, text, span, style] of cells) {
      if (!Number.isInteger(x) || !Number.isInteger(span) || x < end || span < 1 || x > width - span || !fitsUTF8(text, HOST_WIRE_MAX_CELL_TEXT_BYTES) || !Number.isInteger(style) || style < 0 || style >= frame.styles.length + (frame.stylesBase ?? 0))
        return false;
      end = x + span;
    }
    return true;
  };
  if (frame.rows && !frame.rows.every(validCells))
    return false;
  const seen = new Set;
  for (const [y, cells] of frame.deltaRows ?? []) {
    if (y < 0 || y >= height || seen.has(y) || !validCells(cells))
      return false;
    seen.add(y);
  }
  if ((frame.images?.length ?? 0) > HOST_WIRE_MAX_IMAGES)
    return false;
  for (const image of frame.images ?? []) {
    if (!fitsUTF8(image.id, 1024))
      return false;
    if (image.pixelSize) {
      const [w, h] = image.pixelSize;
      if (!Number.isInteger(w) || !Number.isInteger(h) || w < 0 || h < 0 || w > 8192 || h > 8192 || w * h > 16 * 1024 * 1024)
        return false;
    }
  }
  for (const entries of [
    frame.accessibilityTree,
    frame.accessibilityAnnouncements,
    frame.scrollRegions,
    frame.linkTargets
  ]) {
    if ((entries?.length ?? 0) > HOST_WIRE_MAX_METADATA_ENTRIES)
      return false;
  }
  for (const dimension of [
    frame.preferredGridWidth,
    frame.preferredGridHeight
  ]) {
    if (dimension !== undefined && dimension > HOST_WIRE_MAX_GRID_DIMENSION)
      return false;
  }
  if (!fitsWireGrid(frame.preferredGridWidth ?? 0, frame.preferredGridHeight ?? 0))
    return false;
  if ((frame.links?.length ?? 0) > height || (frame.damage?.textRows.length ?? 0) > height)
    return false;
  for (const rows of [frame.links, frame.damage?.textRows]) {
    const seenRows = new Set;
    for (const [y, ranges] of rows ?? []) {
      if (!Number.isInteger(y) || y < 0 || y >= height || seenRows.has(y) || ranges.length > width)
        return false;
      seenRows.add(y);
      let end = 0;
      for (const range of ranges) {
        const [start, lengthOrEnd] = range;
        const stop = range.length === 3 ? start + lengthOrEnd : lengthOrEnd;
        if (!Number.isInteger(start) || !Number.isInteger(stop) || start < 0 || range.length === 3 && start < end || stop < start || stop > width)
          return false;
        end = stop;
      }
    }
  }
  return true;
}

// src/RasterAllocationBudget.ts
var MAX_RASTER_DIMENSION = 8192;
var MAX_RASTER_PIXELS = 16 * 1024 * 1024;
function boundedCanvasSize(cssWidth, cssHeight, scale) {
  if (![cssWidth, cssHeight, scale].every((value) => Number.isFinite(value) && value > 0)) {
    return { width: 1, height: 1, scale: 1 };
  }
  const requestedWidth = Math.ceil(cssWidth * scale);
  const requestedHeight = Math.ceil(cssHeight * scale);
  if (requestedWidth <= MAX_RASTER_DIMENSION && requestedHeight <= MAX_RASTER_DIMENSION && requestedWidth * requestedHeight <= MAX_RASTER_PIXELS) {
    return { width: requestedWidth, height: requestedHeight, scale };
  }
  const boundedScale = Math.min(scale, MAX_RASTER_DIMENSION / cssWidth, MAX_RASTER_DIMENSION / cssHeight, Math.sqrt(MAX_RASTER_PIXELS / cssWidth / cssHeight));
  return {
    width: Math.max(1, Math.floor(cssWidth * boundedScale)),
    height: Math.max(1, Math.floor(cssHeight * boundedScale)),
    scale: boundedScale
  };
}

// src/ImageAllocationBudget.ts
function admitsImageBytes(bytes) {
  const size = imageSize(bytes);
  return size !== undefined && admitsImageSize(...size);
}
function admitsImageSize(width, height) {
  return Number.isInteger(width) && Number.isInteger(height) && width > 0 && height > 0 && width <= MAX_RASTER_DIMENSION && height <= MAX_RASTER_DIMENSION && width * height <= MAX_RASTER_PIXELS;
}
function admitsImagePayload(payload) {
  if (payload.length > HOST_WIRE_MAX_RECORD_BYTES)
    return false;
  try {
    const binary = atob(payload);
    return admitsImageBytes(Uint8Array.from(binary, (character) => character.charCodeAt(0)));
  } catch {
    return false;
  }
}
function imageSize(bytes) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  if (bytes.length >= 24 && view.getUint32(0) === 2303741511 && view.getUint32(4) === 218765834 && view.getUint32(12) === 1229472850) {
    return [view.getUint32(16), view.getUint32(20)];
  }
  if (bytes.length >= 10 && view.getUint32(0) === 1195984440 && (bytes[4] === 55 || bytes[4] === 57) && bytes[5] === 97) {
    return [view.getUint16(6, true), view.getUint16(8, true)];
  }
  if (bytes.length < 4 || view.getUint16(0) !== 65496)
    return;
  let offset = 2;
  while (offset < bytes.length) {
    if (bytes[offset++] !== 255)
      return;
    while (bytes[offset] === 255)
      offset++;
    const marker = bytes[offset++];
    if (marker === undefined || marker === 218 || marker === 217)
      return;
    if (marker === 1 || marker >= 208 && marker <= 215)
      continue;
    if (offset + 2 > bytes.length)
      return;
    const length = view.getUint16(offset);
    if (length < 2 || offset + length > bytes.length)
      return;
    if (marker >= 192 && marker <= 207 && marker !== 196 && marker !== 200 && marker !== 204) {
      if (length < 8)
        return;
      return [view.getUint16(offset + 5), view.getUint16(offset + 3)];
    }
    offset += length;
  }
  return;
}

// src/SurfacePainterConformanceControl.ts
var canvasControls = new WeakMap;
var domControls = new WeakMap;
function registerCanvasSurfacePainterConformanceControl(painter, control) {
  canvasControls.set(painter, control);
}
function registerDomSurfacePainterConformanceControl(painter, control) {
  domControls.set(painter, control);
}

// src/SurfaceRenderer.ts
function resolvedSurfaceForeground(style, terminalStyle) {
  if ((style?.em ?? 0) & 16) {
    return style?.bg ?? terminalStyle.theme.background;
  }
  return style?.fg ?? terminalStyle.theme.foreground;
}
function resolvedSurfaceBackground(style, terminalStyle) {
  if ((style?.em ?? 0) & 16) {
    return style?.fg ?? terminalStyle.theme.foreground;
  }
  return style?.bg;
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
function encodeAccessibilityActionMessage(target, request, requestID) {
  const value = request.action === "setValue" ? `:${request.value.type}:${encodeURIComponent(String(request.value.value))}` : "";
  return new TextEncoder().encode(`\x1Eaccessibility:${requestID === undefined ? "" : `${requestID}:`}${encodeURIComponent(target)}:${request.action}${value}
`);
}
var recordPrefix = "\x1E";
var textEncoder = new TextEncoder;
var MAX_IMAGE_RECOVERY_ID_BYTES = 1024;
var MAX_OUTSTANDING_IMAGE_RECOVERY_IDS = 1024;
function isWebHostImageRecoveryId(id) {
  return id.length > 0 && id.length <= MAX_IMAGE_RECOVERY_ID_BYTES && textEncoder.encode(id).byteLength <= MAX_IMAGE_RECOVERY_ID_BYTES;
}
var SUPPORTED_SURFACE_VERSION = 3;

class WebHostOutputDecoder {
  textDecoder = new TextDecoder;
  bufferedText = "";
  bufferedBytes = 0;
  discardingLine = false;
  lastSurfaceFrame;
  lastEpoch;
  lastGen;
  lastPresentedEpoch;
  keyframeResyncOutstanding = false;
  keyframeResyncPending = false;
  imageResyncOutstandingIds = new Set;
  imageResyncPendingIds = new Set;
  feed(chunk) {
    const records = [];
    let offset = 0;
    while (offset < chunk.length) {
      const newline = chunk.indexOf(10, offset);
      const end = newline < 0 ? chunk.length : newline;
      if (!this.discardingLine) {
        if (end - offset > HOST_WIRE_MAX_RECORD_BYTES - this.bufferedBytes) {
          this.bufferedText = "";
          this.bufferedBytes = 0;
          this.textDecoder.decode();
          this.discardingLine = true;
          records.push(this.refuseBudget());
        } else {
          this.bufferedBytes += end - offset;
          this.bufferedText += this.textDecoder.decode(chunk.subarray(offset, end), { stream: true });
        }
      }
      if (newline >= 0) {
        if (!this.discardingLine) {
          this.bufferedText += this.textDecoder.decode();
          records.push(this.decodeLine(this.bufferedText));
        }
        this.bufferedText = "";
        this.bufferedBytes = 0;
        this.discardingLine = false;
      }
      offset = end + 1;
    }
    if (this.bufferedText.length > 4096 && !this.bufferedText.startsWith(recordPrefix)) {
      records.push({ type: "text", text: this.bufferedText });
      this.bufferedText = "";
      this.bufferedBytes = 0;
    }
    return records;
  }
  flush() {
    this.bufferedText += this.textDecoder.decode();
    this.bufferedBytes = 0;
    this.discardingLine = false;
    if (!this.bufferedText) {
      return [];
    }
    const text = this.bufferedText;
    this.bufferedText = "";
    return [this.decodeLine(text)];
  }
  rejectOversizedMessage() {
    this.bufferedText = "";
    this.bufferedBytes = 0;
    this.discardingLine = false;
    this.textDecoder.decode();
    return this.refuseBudget();
  }
  takeResyncRequest(maximumEncodedBytes) {
    if (this.keyframeResyncPending) {
      this.keyframeResyncPending = false;
      return { scope: "keyframe" };
    }
    if (this.imageResyncPendingIds.size === 0) {
      return;
    }
    const sortedIds = [...this.imageResyncPendingIds].sort();
    const { ids, rejectedIds } = boundedImageResyncIds(sortedIds, maximumEncodedBytes);
    for (const id of rejectedIds) {
      this.imageResyncPendingIds.delete(id);
      this.imageResyncOutstandingIds.delete(id);
    }
    for (const id of ids) {
      this.imageResyncPendingIds.delete(id);
    }
    if (ids.length === 0) {
      return;
    }
    return { scope: "images", ids };
  }
  requestImagePayloads(ids) {
    const acceptedIds = new Set;
    for (const id of ids) {
      if (!isWebHostImageRecoveryId(id)) {
        continue;
      }
      if (this.imageResyncOutstandingIds.has(id)) {
        acceptedIds.add(id);
        continue;
      }
      if (this.imageResyncOutstandingIds.size >= MAX_OUTSTANDING_IMAGE_RECOVERY_IDS) {
        continue;
      }
      this.imageResyncOutstandingIds.add(id);
      this.imageResyncPendingIds.add(id);
      acceptedIds.add(id);
    }
    return [...acceptedIds];
  }
  prepareToPresentSurface(frame) {
    const recoveredImagePayloadIds = this.recoveredImagePayloadIds(frame.images);
    this.resetImageResyncForEpoch(frame.epoch);
    this.sweepImageResyncForPresentedImages(frame.images);
    this.clearArrivedImagePayloads(frame.images);
    if (frame.epoch !== undefined) {
      this.lastPresentedEpoch = frame.epoch;
    }
    return recoveredImagePayloadIds;
  }
  resyncRequestDeliveryFailed(request) {
    if (request.scope === "keyframe") {
      if (this.keyframeResyncOutstanding) {
        this.keyframeResyncPending = true;
      }
      return;
    }
    for (const id of request.ids ?? []) {
      if (this.imageResyncOutstandingIds.has(id)) {
        this.imageResyncPendingIds.add(id);
      }
    }
  }
  decodeLine(line) {
    if (line.startsWith(recordPrefix) && !fitsJSONDepth(line)) {
      return this.refuseBudget();
    }
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
    if (line.startsWith(`${recordPrefix}frameDiagnostic:`)) {
      try {
        const record = JSON.parse(line.slice(`${recordPrefix}frameDiagnostic:`.length));
        if (isWebHostFrameDiagnosticRecord(record)) {
          return { type: "frameDiagnostic", diagnostic: record };
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
      if (declaresNewerSurfaceVersion(frame)) {
        return {
          type: "runtimeIssue",
          issue: {
            severity: "error",
            code: "surface.unsupportedVersion",
            message: `SwiftTUI surface version ${frame.version} is newer than the supported ${SUPPORTED_SURFACE_VERSION}`,
            description: "The app emitted a surface record with version " + `${frame.version}, but this @swifttui/web runtime understands ` + `versions up to ${SUPPORTED_SURFACE_VERSION}. Update @swifttui/web ` + "to render it."
          }
        };
      }
      if (isWebHostSurfaceFrame(frame)) {
        if (!fitsSurfaceBudget(frame))
          return this.refuseBudget();
        this.lastSurfaceFrame = frame;
        this.lastEpoch = frame.epoch;
        this.lastGen = frame.gen;
        this.keyframeResyncOutstanding = false;
        this.keyframeResyncPending = false;
        return { type: "surface", frame };
      }
      if (isWebHostSurfaceDeltaFrame(frame)) {
        if (!fitsSurfaceBudget(frame))
          return this.refuseBudget();
        const carriesDeliveryStamps = frame.epoch !== undefined || frame.gen !== undefined || frame.baselineGen !== undefined;
        if (!this.lastSurfaceFrame || this.lastSurfaceFrame.width !== frame.width || this.lastSurfaceFrame.height !== frame.height) {
          if (carriesDeliveryStamps) {
            this.requestKeyframeResync();
          }
          return { type: "surfaceDropped", reason: "noBaseline" };
        }
        if (carriesDeliveryStamps && (frame.epoch === undefined || frame.gen === undefined || frame.baselineGen === undefined || frame.epoch !== this.lastEpoch || frame.baselineGen !== this.lastGen)) {
          this.requestKeyframeResync();
          return { type: "surfaceDropped", reason: "staleBaseline" };
        }
        const materialized = this.materializeDeltaFrame(frame);
        if (materialized) {
          this.lastSurfaceFrame = materialized;
          this.lastEpoch = frame.epoch;
          this.lastGen = frame.gen;
          return { type: "surface", frame: materialized };
        }
        this.requestKeyframeResync();
      }
    } catch {}
    return { type: "text", text: `${line}
` };
  }
  requestKeyframeResync() {
    if (this.keyframeResyncOutstanding) {
      return;
    }
    this.keyframeResyncOutstanding = true;
    this.keyframeResyncPending = true;
  }
  refuseBudget() {
    this.requestKeyframeResync();
    return { type: "surfaceDropped", reason: "budgetExceeded" };
  }
  resetImageResyncForEpoch(epoch) {
    if (epoch === undefined || epoch === this.lastPresentedEpoch) {
      return;
    }
    this.imageResyncOutstandingIds.clear();
    this.imageResyncPendingIds.clear();
  }
  clearArrivedImagePayloads(images) {
    for (const image of images ?? []) {
      if (image.dataBase64 === undefined) {
        continue;
      }
      this.imageResyncOutstandingIds.delete(image.id);
      this.imageResyncPendingIds.delete(image.id);
    }
  }
  recoveredImagePayloadIds(images) {
    const recoveredIds = new Set;
    for (const image of images ?? []) {
      if (image.dataBase64 !== undefined && this.imageResyncOutstandingIds.has(image.id)) {
        recoveredIds.add(image.id);
      }
    }
    return [...recoveredIds].sort();
  }
  sweepImageResyncForPresentedImages(images) {
    const presentedIds = new Set;
    for (const image of images ?? []) {
      if (this.imageResyncOutstandingIds.has(image.id)) {
        presentedIds.add(image.id);
      }
    }
    for (const id of this.imageResyncOutstandingIds) {
      if (presentedIds.has(id)) {
        continue;
      }
      this.imageResyncOutstandingIds.delete(id);
      this.imageResyncPendingIds.delete(id);
    }
  }
  materializeDeltaFrame(frame) {
    const baseline = this.lastSurfaceFrame;
    if (!baseline) {
      return;
    }
    const styles = this.materializeDeltaStyles(frame, baseline);
    if (!styles) {
      return;
    }
    const rows = baseline.rows.slice();
    for (const [row, cells] of frame.deltaRows) {
      if (!Number.isSafeInteger(row) || row < 0 || row >= frame.height) {
        return;
      }
      rows[row] = cells;
    }
    return {
      version: baseline.version,
      epoch: frame.epoch,
      gen: frame.gen,
      sequence: frame.sequence,
      width: frame.width,
      height: frame.height,
      styles,
      rows,
      images: frame.images,
      damage: frame.damage,
      accessibilityTree: frame.accessibilityTree,
      accessibilityActionResponse: frame.accessibilityActionResponse,
      accessibilityAnnouncements: frame.accessibilityAnnouncements,
      scrollRegions: frame.scrollRegions,
      links: frame.links,
      linkTargets: frame.linkTargets,
      focusPresentation: frame.focusPresentation,
      preferredGridWidth: frame.preferredGridWidth,
      preferredGridHeight: frame.preferredGridHeight
    };
  }
  materializeDeltaStyles(frame, baseline) {
    if (frame.stylesBase === undefined) {
      return frame.styles;
    }
    if (frame.stylesBase !== baseline.styles.length) {
      return;
    }
    return baseline.styles.concat(frame.styles);
  }
}
function boundedImageResyncIds(sortedIds, maximumEncodedBytes) {
  if (maximumEncodedBytes === undefined || !Number.isFinite(maximumEncodedBytes)) {
    return { ids: sortedIds, rejectedIds: [] };
  }
  const emptyRequestBytes = encodeResyncControlMessage({
    scope: "images",
    ids: []
  }).byteLength;
  const normalizedMaximum = Math.max(0, Math.floor(maximumEncodedBytes));
  const ids = [];
  const rejectedIds = [];
  let encodedBytes = emptyRequestBytes;
  for (const id of sortedIds) {
    const separatorBytes = ids.length === 0 ? 0 : 1;
    const idBytes = textEncoder.encode(JSON.stringify(id)).byteLength;
    if (encodedBytes + separatorBytes + idBytes > normalizedMaximum) {
      if (ids.length === 0) {
        rejectedIds.push(id);
        continue;
      }
      break;
    }
    ids.push(id);
    encodedBytes += separatorBytes + idBytes;
    if (encodedBytes >= normalizedMaximum) {
      break;
    }
  }
  return { ids, rejectedIds };
}
function declaresNewerSurfaceVersion(value) {
  if (!value || typeof value !== "object") {
    return false;
  }
  const version = value.version;
  return typeof version === "number" && Number.isSafeInteger(version) && version > SUPPORTED_SURFACE_VERSION;
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
function isWebHostFrameDiagnosticRecord(value) {
  if (!value || typeof value !== "object") {
    return false;
  }
  const record = value;
  return record.format === "swift-tui-frame-diagnostics-v1" && Array.isArray(record.header) && record.header.every((field) => typeof field === "string") && Array.isArray(record.fields) && record.fields.every((field) => typeof field === "string");
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
function encodeCapabilitiesControlMessage() {
  return textEncoder.encode(`${recordPrefix}caps:{"acceptsDeltaFrames":true,"styleAppend":true}
`);
}
function encodePointerCapabilitiesControlMessage(supportsScrollPanning) {
  return textEncoder.encode(`${recordPrefix}pointer:panning=${supportsScrollPanning ? 1 : 0}
`);
}
function encodeResyncControlMessage(request) {
  const payload = request.scope === "keyframe" ? { scope: "keyframe" } : {
    scope: "images",
    ...request.ids === undefined ? {} : { ids: request.ids }
  };
  return textEncoder.encode(`${recordPrefix}resync:${JSON.stringify(payload)}
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
  return (frame.version === 1 || frame.version === 2) && (frame.sequence === undefined || Number.isSafeInteger(frame.sequence) && frame.sequence >= 0) && isSurfaceGridDimension(frame.width) && isSurfaceGridDimension(frame.height) && Array.isArray(frame.styles) && Array.isArray(frame.rows) && frame.rows.every(isWebHostSurfaceRow) && (frame.images === undefined || isWebHostSurfaceImages(frame.images)) && (frame.damage === undefined || isWebHostSurfaceDamage(frame.damage)) && (frame.accessibilityActionResponse === undefined || isAccessibilityActionResponse(frame.accessibilityActionResponse)) && (frame.accessibilityTree === undefined || isWebHostAccessibilityNodes(frame.accessibilityTree)) && (frame.accessibilityAnnouncements === undefined || isWebHostAccessibilityAnnouncements(frame.accessibilityAnnouncements)) && (frame.scrollRegions === undefined || isWebHostScrollRegions(frame.scrollRegions)) && hasValidAdditiveFrameFields(frame);
}
function isWebHostSurfaceDeltaFrame(value) {
  if (!value || typeof value !== "object") {
    return false;
  }
  const frame = value;
  return frame.version === 3 && frame.encoding === "delta" && (frame.sequence === undefined || Number.isSafeInteger(frame.sequence) && frame.sequence >= 0) && isSurfaceGridDimension(frame.width) && isSurfaceGridDimension(frame.height) && Array.isArray(frame.styles) && Array.isArray(frame.deltaRows) && frame.deltaRows.every(isWebHostSurfaceDeltaRow) && isOptionalSafeInteger(frame.baselineGen) && isOptionalSafeInteger(frame.stylesBase) && (frame.images === undefined || isWebHostSurfaceImages(frame.images)) && (frame.damage === undefined || isWebHostSurfaceDamage(frame.damage)) && (frame.accessibilityActionResponse === undefined || isAccessibilityActionResponse(frame.accessibilityActionResponse)) && (frame.accessibilityTree === undefined || isWebHostAccessibilityNodes(frame.accessibilityTree)) && (frame.accessibilityAnnouncements === undefined || isWebHostAccessibilityAnnouncements(frame.accessibilityAnnouncements)) && (frame.scrollRegions === undefined || isWebHostScrollRegions(frame.scrollRegions)) && hasValidAdditiveFrameFields(frame);
}
function isSurfaceGridDimension(value) {
  return typeof value === "number" && Number.isInteger(value) && value >= 0 && value <= 2147483647;
}
function hasValidAdditiveFrameFields(frame) {
  return isOptionalSafeInteger(frame.epoch) && isOptionalSafeInteger(frame.gen) && (frame.links === undefined || isWebHostSurfaceLinks(frame.links)) && (frame.linkTargets === undefined || isWebHostSurfaceLinkTargets(frame.linkTargets)) && (frame.focusPresentation === undefined || isWebHostFocusPresentation(frame.focusPresentation)) && (frame.preferredGridWidth === undefined || Number.isSafeInteger(frame.preferredGridWidth) && frame.preferredGridWidth >= 0) && (frame.preferredGridHeight === undefined || Number.isSafeInteger(frame.preferredGridHeight) && frame.preferredGridHeight >= 0);
}
function isOptionalSafeInteger(value) {
  return value === undefined || Number.isSafeInteger(value);
}
function isWebHostSurfaceLinks(value) {
  return Array.isArray(value) && value.every(isWebHostSurfaceLinkRow);
}
function isWebHostSurfaceLinkRow(value) {
  return Array.isArray(value) && value.length === 2 && Number.isSafeInteger(value[0]) && value[0] >= 0 && Array.isArray(value[1]) && value[1].every(isWebHostSurfaceLinkRun);
}
function isWebHostSurfaceLinkRun(value) {
  if (!Array.isArray(value) || value.length !== 3) {
    return false;
  }
  const [x, span, targetIndex] = value;
  return Number.isSafeInteger(x) && x >= 0 && Number.isSafeInteger(span) && span >= 1 && Number.isSafeInteger(targetIndex) && targetIndex >= 0;
}
function isWebHostSurfaceLinkTargets(value) {
  return Array.isArray(value) && value.every((entry) => typeof entry === "string");
}
function isWebHostFocusPresentation(value) {
  if (!value || typeof value !== "object") {
    return false;
  }
  const presentation = value;
  return (presentation.focusedIdentity === undefined || typeof presentation.focusedIdentity === "string") && typeof presentation.semantics === "string" && typeof presentation.prefersTextInput === "boolean" && typeof presentation.hasFocusedRegion === "boolean";
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
  if (!value || typeof value !== "object") {
    return false;
  }
  const node = value;
  return typeof node.id === "string" && (node.parentId === undefined || typeof node.parentId === "string") && isWebHostSurfaceRect(node.rect) && typeof node.role === "string" && (node.label === undefined || typeof node.label === "string") && (node.hint === undefined || typeof node.hint === "string") && (node.hidden === undefined || typeof node.hidden === "boolean") && (node.liveRegion === undefined || typeof node.liveRegion === "string") && (node.cursorAnchor === undefined || isWebHostAccessibilityPoint(node.cursorAnchor)) && (node.isFocused === undefined || typeof node.isFocused === "boolean") && (node.actionTarget === undefined || typeof node.actionTarget === "string") && (node.actions === undefined || Array.isArray(node.actions) && node.actions.every((action) => typeof action === "string")) && (node.isEnabled === undefined || typeof node.isEnabled === "boolean") && (node.value === undefined || isAccessibilityValue(node.value)) && [node.valueMin, node.valueMax, node.valueStep].every((value2) => value2 === undefined || typeof value2 === "number" && Number.isFinite(value2));
}
function isAccessibilityActionResponse(value) {
  if (!value || typeof value !== "object")
    return false;
  const response = value;
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
    return false;
  const candidate = value;
  switch (candidate.type) {
    case "text":
      return typeof candidate.value === "string";
    case "boolean":
      return typeof candidate.value === "boolean";
    case "number":
      return typeof candidate.value === "number" && Number.isFinite(candidate.value);
    default:
      return false;
  }
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
  return typeof announcement.message === "string" && typeof announcement.politeness === "string";
}
function isWebHostSurfaceImages(value) {
  return Array.isArray(value) && value.every(isWebHostSurfaceImage);
}
function isWebHostSurfaceImage(value) {
  if (!value || typeof value !== "object") {
    return false;
  }
  const image = value;
  return typeof image.id === "string" && isWebHostSurfaceImageFormat(image.format) && isWebHostSurfaceRect(image.bounds) && isWebHostSurfaceRect(image.visibleBounds) && isWebHostSurfaceScalingMode(image.scalingMode) && (image.opacity === undefined || typeof image.opacity === "number" && Number.isFinite(image.opacity)) && (image.pixelSize === undefined || isWebHostSurfaceSize(image.pixelSize)) && (image.dataBase64 === undefined || typeof image.dataBase64 === "string");
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
  return typeof value === "string";
}
function isWebHostScrollRegions(value) {
  return Array.isArray(value) && value.every(isWebHostScrollRegion);
}
function isWebHostScrollRegion(value) {
  if (!value || typeof value !== "object") {
    return false;
  }
  const region = value;
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

// src/CanvasSurfacePainter.ts
var MAX_IMAGE_DECODE_ATTEMPTS = 3;
var MAX_UNRESOLVED_IMAGE_CACHE_ENTRIES = 256;
var MAX_UNRESOLVED_IMAGE_PAYLOAD_CHARACTERS = 64 * 1024 * 1024;
var MAX_DECODED_IMAGE_CACHE_ENTRIES = 256;
var MAX_DECODED_IMAGE_CACHE_BYTES = 64 * 1024 * 1024;

class CanvasSurfacePainter {
  imageCache = new Map;
  unresolvedImageIds = new Set;
  unresolvedImagePayloadCharacters = 0;
  imageDecoder;
  onImagePayloadMiss;
  maxDecodedImageCacheEntries;
  maxDecodedImageCacheBytes;
  decodedImageCount = 0;
  decodedImageBytes = 0;
  visibleImageIds = new Set;
  inactiveDecodedImageIds = new Set;
  disposed = false;
  canvas;
  requestRedraw = () => {};
  lastEpoch;
  pendingImagePayloadMissIds = new Set;
  imagePayloadMissScheduled = false;
  constructor(options = {}) {
    this.imageDecoder = options.decodeImage ?? decodeImage;
    this.onImagePayloadMiss = options.onImagePayloadMiss ?? (() => {});
    this.maxDecodedImageCacheEntries = cacheLimit(options.maxDecodedImageCacheEntries, MAX_DECODED_IMAGE_CACHE_ENTRIES);
    this.maxDecodedImageCacheBytes = cacheLimit(options.maxDecodedImageCacheBytes, MAX_DECODED_IMAGE_CACHE_BYTES);
    registerCanvasSurfacePainterConformanceControl(this, {
      evictImages: (ids) => {
        for (const id of ids) {
          this.removeCachedImage(id);
        }
      },
      visibleImageIDs: (images) => [
        ...new Set(images.filter(isPaintableSurfaceImage).filter((image) => this.imageCache.get(image.id)?.image !== undefined).map((image) => image.id))
      ].sort()
    });
  }
  attach(canvas, requestRedraw) {
    if (this.disposed) {
      return;
    }
    this.canvas = canvas;
    this.requestRedraw = requestRedraw;
  }
  paint(metrics, frame, damage, recoveredImagePayloadIds = []) {
    if (this.disposed) {
      return;
    }
    const canvas = this.canvas;
    const context = canvas?.getContext("2d");
    if (!canvas || !context) {
      return;
    }
    if (frame?.epoch !== undefined && frame.epoch !== this.lastEpoch) {
      this.lastEpoch = frame.epoch;
      for (const cached of this.imageCache.values()) {
        if (!cached.image) {
          cached.missReported = false;
        }
      }
    }
    this.sweepUnresolvedImages(frame?.images);
    this.visibleImageIds = new Set((frame?.images ?? []).filter(isPaintableSurfaceImage).map((image) => image.id));
    this.inactiveDecodedImageIds.clear();
    for (const [id, cached] of this.imageCache) {
      if (cached.image && !this.visibleImageIds.has(id) && isWebHostImageRecoveryId(id)) {
        this.inactiveDecodedImageIds.add(id);
      }
    }
    this.trimDecodedImages();
    const dirtyRegion = frame ? this.dirtyRegionForDamage(damage, frame, metrics) : undefined;
    const recoveredPayloadIds = new Set(recoveredImagePayloadIds);
    if (dirtyRegion?.rects.length === 0) {
      this.prepareImages(frame?.images ?? [], recoveredPayloadIds);
      return;
    }
    const scale = metrics.pixelScale ?? (globalThis.window?.devicePixelRatio || 1);
    context.setTransform(scale, 0, 0, scale, 0, 0);
    context.textBaseline = "alphabetic";
    context.fillStyle = webTUITerminalBackgroundColor(metrics.style);
    if (dirtyRegion) {
      for (const rect of dirtyRegion.rects) {
        context.clearRect(rect.x, rect.y, rect.width, rect.height);
        context.fillRect(rect.x, rect.y, rect.width, rect.height);
      }
    } else {
      context.clearRect(0, 0, canvas.width / scale, canvas.height / scale);
      context.fillRect(0, 0, canvas.width / scale, canvas.height / scale);
    }
    if (!frame) {
      return;
    }
    if (dirtyRegion) {
      context.save();
      context.beginPath();
      for (const rect of dirtyRegion.rects) {
        context.rect(rect.x, rect.y, rect.width, rect.height);
      }
      context.clip();
    }
    try {
      this.drawRows(context, frame, metrics, dirtyRegion);
      this.drawImages(context, frame.images ?? [], metrics, dirtyRegion, recoveredPayloadIds);
    } finally {
      if (dirtyRegion) {
        context.restore();
      }
    }
  }
  dispose() {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    this.canvas = undefined;
    this.requestRedraw = () => {};
    for (const id of this.imageCache.keys()) {
      this.removeCachedImage(id);
    }
    this.visibleImageIds.clear();
    this.inactiveDecodedImageIds.clear();
    this.pendingImagePayloadMissIds.clear();
  }
  drawRows(context, frame, metrics, dirtyRegion) {
    if (dirtyRegion) {
      for (const [y, ranges] of dirtyRegion.rows) {
        const row = frame.rows[y] ?? [];
        this.drawRow(context, frame, metrics, row, y, ranges);
      }
      return;
    }
    for (let y = 0;y < frame.rows.length; y += 1) {
      const row = frame.rows[y] ?? [];
      this.drawRow(context, frame, metrics, row, y);
    }
  }
  drawRow(context, frame, metrics, row, y, ranges) {
    for (const cell of row) {
      const [x, text, span, styleIndex] = cell;
      if (ranges !== undefined && !cellIntersectsRanges(x, span, ranges)) {
        continue;
      }
      const style = frame.styles[styleIndex] ?? undefined;
      this.drawCell(context, metrics, x, y, text, span, style);
    }
  }
  drawImages(context, images, metrics, dirtyRegion, recoveredPayloadIds) {
    const missingPayloadIds = new Set;
    for (const image of images) {
      if (!isPaintableSurfaceImage(image)) {
        continue;
      }
      this.drawImage(context, image, metrics, dirtyRegion, missingPayloadIds, recoveredPayloadIds);
    }
    this.reportImagePayloadMisses(missingPayloadIds);
  }
  prepareImages(images, recoveredPayloadIds) {
    const missingPayloadIds = new Set;
    for (const image of images) {
      if (!isPaintableSurfaceImage(image)) {
        continue;
      }
      this.cachedImage(image, missingPayloadIds, recoveredPayloadIds);
    }
    this.reportImagePayloadMisses(missingPayloadIds);
  }
  drawImage(context, image, metrics, dirtyRegion, missingPayloadIds, recoveredPayloadIds) {
    const [boundsX, boundsY, boundsWidth, boundsHeight] = image.bounds;
    const [clipX, clipY, clipWidth, clipHeight] = image.visibleBounds;
    if (boundsWidth <= 0 || boundsHeight <= 0 || clipWidth <= 0 || clipHeight <= 0) {
      return;
    }
    const decodedImage = this.cachedImage(image, missingPayloadIds, recoveredPayloadIds);
    if (!decodedImage) {
      return;
    }
    if (dirtyRegion && !dirtyRegionIntersectsCellRect(dirtyRegion, clipX, clipY, clipWidth, clipHeight)) {
      return;
    }
    context.save();
    context.beginPath();
    context.rect(clipX * metrics.cellWidth, clipY * metrics.cellHeight, clipWidth * metrics.cellWidth, clipHeight * metrics.cellHeight);
    context.clip();
    context.globalAlpha = normalizedImageOpacity(image.opacity);
    context.drawImage(decodedImage, boundsX * metrics.cellWidth, boundsY * metrics.cellHeight, boundsWidth * metrics.cellWidth, boundsHeight * metrics.cellHeight);
    context.restore();
  }
  cachedImage(image, missingPayloadIds, recoveredPayloadIds) {
    if (!isSupportedImageFormat(image.format)) {
      return;
    }
    let cached = this.imageCache.get(image.id);
    if (cached?.image) {
      this.imageCache.delete(image.id);
      this.imageCache.set(image.id, cached);
      return cached.image;
    }
    const beginsRecoveredGeneration = image.dataBase64 !== undefined && recoveredPayloadIds.delete(image.id);
    if (image.dataBase64 !== undefined && (cached?.payload === undefined || beginsRecoveredGeneration)) {
      if (!this.canTrackUnresolvedImage(image.id, image.dataBase64)) {
        return;
      }
      cached = {
        payload: image.dataBase64,
        retries: 0
      };
      this.setUnresolvedImage(image.id, cached);
    } else if (!cached) {
      if (!isWebHostImageRecoveryId(image.id)) {
        return;
      }
      if (!this.canTrackUnresolvedImage(image.id)) {
        return;
      }
      cached = { missReported: false };
      this.setUnresolvedImage(image.id, cached);
      missingPayloadIds.add(image.id);
      return;
    }
    const attempts = cached.retries ?? 0;
    if (cached.payload === undefined) {
      if (!cached.missReported) {
        cached.missReported = true;
        missingPayloadIds.add(image.id);
      }
      return;
    }
    if (attempts >= MAX_IMAGE_DECODE_ATTEMPTS) {
      if (!cached.missReported) {
        cached.missReported = true;
        missingPayloadIds.add(image.id);
      }
      return;
    }
    if (!cached.promise) {
      const nextAttempts = attempts + 1;
      const promise = this.imageDecoder(cached.payload, image.format, image.id);
      cached.promise = promise;
      cached.retries = nextAttempts;
      promise.then((decodedImage) => {
        const latest = this.imageCache.get(image.id);
        if (latest?.promise !== promise) {
          closeDecodedImage(decodedImage);
          return;
        }
        this.removeUnresolvedImage(image.id);
        const decodedBytes = estimatedDecodedImageBytes(decodedImage);
        this.imageCache.delete(image.id);
        this.imageCache.set(image.id, { image: decodedImage, decodedBytes });
        this.decodedImageCount += 1;
        this.decodedImageBytes += decodedBytes;
        this.trimDecodedImages();
        this.requestRedraw();
      }).catch(() => {
        const latest = this.imageCache.get(image.id);
        if (latest?.promise !== promise) {
          return;
        }
        latest.promise = undefined;
        if ((latest.retries ?? 0) >= MAX_IMAGE_DECODE_ATTEMPTS && !latest.missReported) {
          latest.missReported = true;
          if (isWebHostImageRecoveryId(image.id)) {
            this.scheduleImagePayloadMiss(image.id);
          }
        }
        this.requestRedraw();
      });
    }
    return;
  }
  canTrackUnresolvedImage(id, payload) {
    const existing = this.imageCache.get(id);
    const existingPayloadCharacters = existing?.image ? 0 : existing?.payload?.length ?? 0;
    const nextPayloadCharacters = this.unresolvedImagePayloadCharacters - existingPayloadCharacters + (payload?.length ?? 0);
    return (this.unresolvedImageIds.has(id) || this.unresolvedImageIds.size < MAX_UNRESOLVED_IMAGE_CACHE_ENTRIES) && nextPayloadCharacters <= MAX_UNRESOLVED_IMAGE_PAYLOAD_CHARACTERS;
  }
  removeCachedImage(id) {
    const cached = this.imageCache.get(id);
    if (cached?.image) {
      this.decodedImageCount -= 1;
      this.decodedImageBytes -= cached.decodedBytes ?? 0;
      closeDecodedImage(cached.image);
    }
    this.removeUnresolvedImage(id);
    this.imageCache.delete(id);
    this.inactiveDecodedImageIds.delete(id);
    this.pendingImagePayloadMissIds.delete(id);
  }
  trimDecodedImages() {
    for (const id of this.inactiveDecodedImageIds) {
      if (this.decodedImageCount <= this.maxDecodedImageCacheEntries && this.decodedImageBytes <= this.maxDecodedImageCacheBytes) {
        break;
      }
      this.removeCachedImage(id);
    }
  }
  setUnresolvedImage(id, cached) {
    const existing = this.imageCache.get(id);
    if (this.unresolvedImageIds.has(id)) {
      this.unresolvedImagePayloadCharacters -= existing?.payload?.length ?? 0;
    }
    this.imageCache.set(id, cached);
    this.unresolvedImageIds.add(id);
    this.unresolvedImagePayloadCharacters += cached.payload?.length ?? 0;
    this.pendingImagePayloadMissIds.delete(id);
  }
  removeUnresolvedImage(id) {
    if (!this.unresolvedImageIds.delete(id)) {
      return;
    }
    this.unresolvedImagePayloadCharacters -= this.imageCache.get(id)?.payload?.length ?? 0;
    this.pendingImagePayloadMissIds.delete(id);
  }
  sweepUnresolvedImages(images) {
    const presentedIds = new Set;
    for (const image of images ?? []) {
      if (!this.unresolvedImageIds.has(image.id)) {
        continue;
      }
      if (isPaintableSurfaceImage(image)) {
        presentedIds.add(image.id);
      }
    }
    for (const id of this.unresolvedImageIds) {
      if (presentedIds.has(id)) {
        continue;
      }
      this.removeUnresolvedImage(id);
      this.imageCache.delete(id);
    }
  }
  reportImagePayloadMisses(ids) {
    if (ids.size === 0) {
      return;
    }
    const candidateIds = [...ids].sort();
    this.applyImagePayloadMissAdmission(candidateIds, this.onImagePayloadMiss(candidateIds));
  }
  scheduleImagePayloadMiss(id) {
    this.pendingImagePayloadMissIds.add(id);
    if (this.imagePayloadMissScheduled) {
      return;
    }
    this.imagePayloadMissScheduled = true;
    queueMicrotask(() => {
      this.imagePayloadMissScheduled = false;
      if (this.disposed) {
        return;
      }
      const ids = [...this.pendingImagePayloadMissIds].sort();
      this.pendingImagePayloadMissIds.clear();
      if (ids.length > 0) {
        this.applyImagePayloadMissAdmission(ids, this.onImagePayloadMiss(ids));
      }
    });
  }
  applyImagePayloadMissAdmission(candidateIds, admittedIds) {
    const acceptedIds = new Set(Array.isArray(admittedIds) ? admittedIds : candidateIds);
    for (const id of candidateIds) {
      const cached = this.imageCache.get(id);
      if (cached && !cached.image) {
        cached.missReported = acceptedIds.has(id);
      }
    }
  }
  drawCell(context, metrics, x, y, text, span, style) {
    const rectX = x * metrics.cellWidth;
    const rectY = y * metrics.cellHeight;
    const width = Math.max(1, span) * metrics.cellWidth;
    const background = resolvedSurfaceBackground(style, metrics.style);
    const foreground = resolvedSurfaceForeground(style, metrics.style);
    const opacity = style?.opacity ?? 1;
    if (background) {
      context.globalAlpha = opacity;
      context.fillStyle = background;
      context.fillRect(rectX, rectY, width, metrics.cellHeight);
    }
    if (text !== " " || style?.underline || style?.strikethrough) {
      context.save();
      context.beginPath();
      context.rect(rectX, rectY, width, metrics.cellHeight);
      context.clip();
      try {
        context.globalAlpha = opacity;
        if (text !== " ") {
          context.fillStyle = foreground;
          context.strokeStyle = foreground;
          if (!canRenderBoxDrawing(text) || !drawBoxDrawing(context, text, {
            x: rectX,
            y: rectY,
            width,
            height: metrics.cellHeight
          })) {
            context.font = fontForStyle(metrics.style, style);
            context.fillText(text, rectX, rectY + Math.floor((metrics.cellHeight + metrics.style.fontSize) / 2) - 2);
          }
        }
        this.drawTextLine(context, metrics, rectX, rectY, width, style?.underline, "underline", foreground);
        this.drawTextLine(context, metrics, rectX, rectY, width, style?.strikethrough, "strike", foreground);
      } finally {
        context.restore();
      }
    }
    context.globalAlpha = 1;
  }
  dirtyRegionForDamage(damage, frame, metrics) {
    if (!damage || damage.requiresFullTextRepaint || damage.requiresFullGraphicsReplay) {
      return;
    }
    const rects = [];
    const rows = new Map;
    for (const [row, ranges] of damage.textRows) {
      if (row < 0 || row >= frame.height) {
        continue;
      }
      if (ranges.length === 0) {
        rects.push(cellRect(metrics, 0, row, frame.width));
        rows.set(row, "full");
        continue;
      }
      const rowRanges = rows.get(row) === "full" ? [] : [...rows.get(row) ?? []];
      for (const [start, end] of ranges) {
        const lowerBound = Math.max(0, Math.min(frame.width, Math.floor(start)));
        const upperBound = Math.max(lowerBound, Math.min(frame.width, Math.ceil(end)));
        if (lowerBound >= upperBound) {
          continue;
        }
        rects.push(cellRect(metrics, lowerBound, row, upperBound - lowerBound));
        rowRanges.push({ start: lowerBound, end: upperBound });
      }
      if (rows.get(row) !== "full" && rowRanges.length > 0) {
        rows.set(row, normalizeCellRanges(rowRanges));
      }
    }
    return { rects, rows };
  }
  drawTextLine(context, metrics, x, y, width, line, placement, fallbackColor) {
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
    const lineY = placement === "underline" ? y + metrics.cellHeight - 2 : y + Math.floor(metrics.cellHeight / 2);
    context.beginPath();
    context.moveTo(x, lineY);
    context.lineTo(x + width, lineY);
    context.stroke();
    context.setLineDash([]);
  }
}
function cacheLimit(value, fallback) {
  return value !== undefined && Number.isFinite(value) ? Math.max(0, Math.floor(value)) : fallback;
}
function estimatedDecodedImageBytes(image) {
  const dimensions = image;
  const width = dimensions.naturalWidth ?? dimensions.width;
  const height = dimensions.naturalHeight ?? dimensions.height;
  if (typeof width !== "number" || typeof height !== "number" || !Number.isFinite(width) || !Number.isFinite(height) || width < 0 || height < 0) {
    return 0;
  }
  return Math.min(Number.MAX_SAFE_INTEGER, Math.ceil(width) * Math.ceil(height) * 4);
}
function closeDecodedImage(image) {
  const closable = image;
  closable.close?.();
}
function normalizedImageOpacity(opacity) {
  if (opacity === undefined || !Number.isFinite(opacity)) {
    return 1;
  }
  return Math.max(0, Math.min(1, opacity));
}
function isPaintableSurfaceImage(image) {
  const [, , boundsWidth, boundsHeight] = image.bounds;
  const [, , clipWidth, clipHeight] = image.visibleBounds;
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
  const bytes = decodeBase64Bytes(dataBase64);
  if (!admitsImageBytes(bytes))
    throw new Error("Image exceeds the raster budget or has an unsupported container");
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
function normalizeCellRanges(ranges) {
  const sorted = ranges.filter((range) => range.end > range.start).sort((lhs, rhs) => lhs.start - rhs.start || lhs.end - rhs.end);
  const normalized = [];
  for (const range of sorted) {
    const previous = normalized[normalized.length - 1];
    if (previous && range.start <= previous.end) {
      previous.end = Math.max(previous.end, range.end);
      continue;
    }
    normalized.push({ ...range });
  }
  return normalized;
}
function cellIntersectsRanges(x, span, ranges) {
  if (ranges === "full") {
    return true;
  }
  const start = Math.floor(x);
  const end = start + Math.max(1, Math.ceil(span));
  return ranges.some((range) => start < range.end && end > range.start);
}
function dirtyRegionIntersectsCellRect(region, x, y, width, height) {
  const startRow = Math.max(0, Math.floor(y));
  const endRow = Math.max(startRow, Math.ceil(y + height));
  const rectRange = {
    start: Math.floor(x),
    end: Math.floor(x) + Math.max(1, Math.ceil(width))
  };
  for (let row = startRow;row < endRow; row += 1) {
    const ranges = region.rows.get(row);
    if (!ranges) {
      continue;
    }
    if (cellIntersectsRanges(rectRange.start, rectRange.end - rectRange.start, ranges)) {
      return true;
    }
  }
  return false;
}

// src/DomCellMetrics.ts
class DomCellProbe {
  mount;
  element;
  faces;
  styleKey;
  constructor(mount) {
    this.mount = mount;
    const doc = mount.ownerDocument ?? document;
    this.element = doc.createElement("div");
    this.element.setAttribute("aria-hidden", "true");
    Object.assign(this.element.style, {
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
    });
    this.faces = [0, 1, 2, 3].map(() => {
      const line = doc.createElement("div");
      const text = doc.createElement("span");
      const baseline = doc.createElement("span");
      Object.assign(baseline.style, {
        display: "inline-block",
        width: "0",
        height: "0",
        padding: "0",
        margin: "0",
        border: "0",
        verticalAlign: "baseline"
      });
      line.append(text, baseline);
      this.element.appendChild(line);
      return { line, text, baseline };
    });
    mount.appendChild(this.element);
  }
  configure(style) {
    const key = fontForStyle(style);
    if (key === this.styleKey)
      return;
    this.styleKey = key;
    this.faces.forEach(({ line, text }, em) => {
      Object.assign(line.style, {
        display: "block",
        width: "max-content",
        height: "auto",
        padding: "0",
        margin: "0",
        border: "0",
        font: fontForStyle(style, { em }),
        lineHeight: "1.5",
        whiteSpace: "pre"
      });
      Object.assign(text.style, {
        display: "inline",
        font: "inherit",
        lineHeight: "1.5",
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
      });
      text.textContent = "W".repeat(64);
    });
  }
  measure(style, scaleX = 1, scaleY = scaleX) {
    this.configure(style);
    let width = 0, height = 0, baseline = 0;
    for (const face2 of this.faces) {
      const rect = face2.text.getBoundingClientRect();
      const line = face2.line.getBoundingClientRect();
      if (!(rect.width > 0 && line.height > 0))
        return;
      width = Math.max(width, rect.width / scaleX / 64);
      height = Math.max(height, line.height / scaleY);
      baseline = Math.max(baseline, (face2.baseline.getBoundingClientRect().top - line.top) / scaleY);
    }
    const baseAdvance = width;
    const face = this.faces[0];
    for (const [sample, span] of [
      [" ", 1],
      ["é", 1],
      ["漢", 2],
      ["\uD83D\uDE42", 2],
      ["\uD83D\uDC69‍\uD83D\uDCBB", 2]
    ]) {
      face.text.textContent = sample;
      const rect = face.text.getBoundingClientRect();
      width = Math.max(width, rect.width / scaleX / span);
      height = Math.max(height, face.line.getBoundingClientRect().height / scaleY);
    }
    face.text.textContent = "W".repeat(64);
    if (![width, height, baseline].every(Number.isFinite) || width <= 0 || height <= 0)
      return;
    const computed = this.mount.ownerDocument?.defaultView?.getComputedStyle(face.text);
    return {
      width: Math.ceil(width - 1 / 32),
      height: Math.ceil(height - 1 / 32),
      advance: baseAdvance,
      baseline,
      fontSize: Number.parseFloat(computed?.fontSize ?? "") || style.fontSize
    };
  }
  dispose() {
    this.element.remove();
  }
}

// src/DomGeometry.ts
function makeDomGeometry(revision, fontIdentity, cells, content) {
  const numbers = [
    revision,
    cells.width,
    cells.height,
    cells.baseline,
    cells.fontSize,
    ...Object.values(content)
  ];
  if (!Number.isSafeInteger(revision) || revision < 1 || !numbers.every(Number.isFinite) || content.width <= 0 || content.height <= 0 || cells.width <= 0 || cells.height <= 0 || content.scaleX <= 0 || content.scaleY <= 0)
    return;
  const cellWidth = Math.ceil(cells.width), cellHeight = Math.ceil(cells.height);
  const requestedColumns = Math.floor(content.width / cellWidth), requestedRows = Math.floor(content.height / cellHeight);
  if (requestedColumns < 1 || requestedRows < 1)
    return;
  const columns = Math.min(HOST_WIRE_MAX_GRID_DIMENSION, requestedColumns);
  const rows = Math.min(HOST_WIRE_MAX_GRID_DIMENSION, requestedRows, Math.floor(HOST_WIRE_MAX_GRID_CELLS / columns));
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
  const view = mount.ownerDocument?.defaultView;
  if (!view)
    return;
  for (let node = mount;node; node = node.parentElement) {
    const css = view.getComputedStyle(node);
    if (css.perspective !== "none" || css.rotate && css.rotate !== "none" && css.rotate !== "0deg")
      throw new Error("DOM host supports positive axis-aligned scale and translation; rotation, skew and perspective require a different embedding.");
    if (css.scale && css.scale !== "none" && css.scale.split(/\s+/).some((v) => Number(v) <= 0))
      throw new Error("DOM host requires a positive embedding scale.");
    if (css.transform !== "none") {
      const matrix = new DOMMatrixReadOnly(css.transform);
      if (!matrix.is2D || Math.abs(matrix.b) > 0.00000001 || Math.abs(matrix.c) > 0.00000001 || matrix.a <= 0 || matrix.d <= 0)
        throw new Error("DOM host supports positive axis-aligned scale and translation; rotation, skew and perspective require a different embedding.");
    }
  }
}
function measureDomContentBox(mount) {
  const rect = mount.getBoundingClientRect();
  if (!(rect.width > 0 && rect.height > 0))
    return;
  validateTransforms(mount);
  const css = mount.ownerDocument?.defaultView?.getComputedStyle(mount);
  const number = (value) => Number.parseFloat(value ?? "") || 0;
  const pl = number(css?.paddingLeft), pr = number(css?.paddingRight), pt = number(css?.paddingTop), pb = number(css?.paddingBottom);
  const bl = number(css?.borderLeftWidth), br = number(css?.borderRightWidth), bt = number(css?.borderTopWidth), bb = number(css?.borderBottomWidth);
  const borderBox = css?.boxSizing === "border-box";
  const width = css ? number(css.width) - (borderBox ? pl + pr + bl + br : 0) : rect.width;
  const height = css ? number(css.height) - (borderBox ? pt + pb + bt + bb : 0) : rect.height;
  const scaleX = rect.width / (width + pl + pr + bl + br), scaleY = rect.height / (height + pt + pb + bt + bb);
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

class DomGeometryController {
  mount;
  probe;
  pending;
  presented;
  typography;
  constructor(mount) {
    this.mount = mount;
    this.probe = new DomCellProbe(mount);
  }
  measure(style) {
    const content = measureDomContentBox(this.mount);
    if (!content)
      return;
    let cells = this.probe.measure(style, content.scaleX, content.scaleY);
    if (!cells)
      return;
    const prior = this.typography;
    if (prior?.identity === style.fontFamily && prior.cells.fontSize === cells.fontSize && Math.abs(prior.cells.advance - cells.advance) <= 1 / 32 && prior.cells.height === cells.height) {
      cells = prior.cells;
    } else
      this.typography = { identity: style.fontFamily, cells };
    const previous = this.pending;
    const next = makeDomGeometry(previous?.revision ?? 1, style.fontFamily, cells, content);
    if (!next)
      return;
    const layoutChanged = previous && [
      "fontIdentity",
      "fontSize",
      "cellWidth",
      "cellHeight",
      "columns",
      "rows"
    ].some((key) => previous[key] !== next[key]);
    if (layoutChanged && previous.revision >= Number.MAX_SAFE_INTEGER)
      throw new Error("DOM geometry revision exhausted; remount the scene.");
    this.pending = Object.freeze({
      ...next,
      revision: next.revision + (layoutChanged ? 1 : 0)
    });
    return this.pending;
  }
  present(snapshot) {
    this.presented = snapshot;
  }
  dispose() {
    this.probe.dispose();
    this.pending = undefined;
    this.presented = undefined;
  }
}

// src/DomGlyphBackground.ts
class DomGlyphBackground {
  cache = new Map;
  clear() {
    this.cache.clear();
  }
  image(text, color, width, height) {
    if (!canRenderBoxDrawing(text))
      return;
    const key = JSON.stringify([text, color, width, height]);
    const cached = this.cache.get(key);
    if (cached)
      return cached;
    const shapes = [];
    let path = "";
    let dash = [];
    const context = {
      lineWidth: 1,
      lineCap: "butt",
      fillRect(x, y, w, h) {
        shapes.push(`<rect x="${x}" y="${y}" width="${w}" height="${h}"/>`);
      },
      beginPath() {
        path = "";
      },
      moveTo(x, y) {
        path += `M${x} ${y}`;
      },
      lineTo(x, y) {
        path += `L${x} ${y}`;
      },
      bezierCurveTo(a, b, c, d, x, y) {
        path += `C${a} ${b} ${c} ${d} ${x} ${y}`;
      },
      setLineDash(value) {
        dash = value;
      },
      stroke() {
        shapes.push(`<path d="${path}" fill="none" stroke="currentColor" stroke-width="${this.lineWidth}" stroke-linecap="${this.lineCap}" stroke-dasharray="${dash.join(" ")}"/>`);
      }
    };
    if (!drawBoxDrawing(context, text, { x: 0, y: 0, width, height }))
      return;
    const escapedColor = color.replaceAll("&", "&amp;").replaceAll('"', "&quot;").replaceAll("<", "&lt;");
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}" color="${escapedColor}" fill="currentColor">${shapes.join("")}</svg>`;
    const result = `url("data:image/svg+xml,${encodeURIComponent(svg)}")`;
    if (this.cache.size >= 512)
      this.cache.delete(this.cache.keys().next().value);
    this.cache.set(key, result);
    return result;
  }
}

// src/DomSurfacePainter.ts
class DomSurfacePainter {
  onImagePayloadMiss;
  root;
  rowsLayer;
  imagesLayer;
  rowElements = [];
  cells = [];
  renderedImages = new Map;
  appliedMetricsKey;
  renderedGridKey;
  renderedLinksKey;
  linkCells = new Map;
  hasRenderedFrame = false;
  reportedMissingImageIds = new Set;
  lastImageRecoveryFrame;
  lastEpoch;
  glyphs = new DomGlyphBackground;
  styleCache = new Map;
  appliedCellStyles = new WeakMap;
  onOpenHyperlink;
  constructor(options = {}) {
    this.onOpenHyperlink = options.onOpenHyperlink;
    this.onImagePayloadMiss = options.onImagePayloadMiss ?? (() => {});
    registerDomSurfacePainterConformanceControl(this, {
      evictImages: (ids) => {
        for (const id of ids) {
          this.renderedImages.get(id)?.container.remove();
          this.renderedImages.delete(id);
          this.reportedMissingImageIds.delete(id);
        }
      },
      visibleImageIDs: () => [...this.renderedImages.keys()].sort()
    });
  }
  attach(root) {
    this.root = root;
    const rowsLayer = createElement("div");
    rowsLayer.className = "webhost-scene__surface-rows";
    fillContainer(rowsLayer.style);
    const imagesLayer = createElement("div");
    imagesLayer.className = "webhost-scene__surface-images";
    fillContainer(imagesLayer.style);
    imagesLayer.style.pointerEvents = "none";
    this.rowsLayer = rowsLayer;
    this.imagesLayer = imagesLayer;
    root.replaceChildren(rowsLayer, imagesLayer);
    this.rowElements = [];
    this.cells = [];
    this.renderedImages = new Map;
    this.appliedMetricsKey = undefined;
    this.renderedGridKey = undefined;
    this.renderedLinksKey = undefined;
    this.hasRenderedFrame = false;
    this.reportedMissingImageIds.clear();
    this.lastImageRecoveryFrame = undefined;
    this.lastEpoch = undefined;
  }
  paint(metrics, frame, damage, _recoveredImagePayloadIds) {
    const root = this.root;
    const rowsLayer = this.rowsLayer;
    if (!root || !rowsLayer) {
      return;
    }
    const clearSelection = selectionInvalidator();
    if (frame?.epoch !== undefined && frame.epoch !== this.lastEpoch) {
      this.lastEpoch = frame.epoch;
      this.reportedMissingImageIds.clear();
    }
    const metricsKey = metricsKeyFor(metrics);
    const metricsChanged = metricsKey !== this.appliedMetricsKey;
    if (metricsChanged) {
      this.styleCache.clear();
      this.appliedCellStyles = new WeakMap;
      this.glyphs.clear();
      this.applyRootStyle(root, metrics);
      this.appliedMetricsKey = metricsKey;
    }
    if (!frame) {
      clearSelection(rowsLayer);
      this.rowElements = [];
      this.cells = [];
      this.linkCells.clear();
      rowsLayer.replaceChildren();
      this.lastImageRecoveryFrame = undefined;
      this.reconcileImages([], metrics, false);
      this.renderedGridKey = undefined;
      this.renderedLinksKey = undefined;
      this.hasRenderedFrame = false;
      return;
    }
    const gridKey = `${frame.width}x${frame.height}x${frame.rows.length}`;
    const linksKey = JSON.stringify([
      frame.width,
      frame.links,
      frame.linkTargets
    ]);
    const linksChanged = linksKey !== this.renderedLinksKey;
    this.renderedLinksKey = linksKey;
    if (linksChanged) {
      this.linkCells.clear();
      for (const [y, runs] of frame.links ?? []) {
        for (const [x, span, targetIndex] of runs) {
          const target = frame.linkTargets?.[targetIndex];
          if (target === undefined)
            continue;
          for (let column = Math.max(0, x);column < Math.min(frame.width, x + span); column += 1) {
            const key = y * frame.width + column;
            if (!this.linkCells.has(key))
              this.linkCells.set(key, target);
          }
        }
      }
    }
    const fullRepaint = linksChanged || metricsChanged || !this.hasRenderedFrame || gridKey !== this.renderedGridKey || !damage || damage.requiresFullTextRepaint || damage.requiresFullGraphicsReplay;
    this.renderedGridKey = gridKey;
    if (fullRepaint) {
      for (let y = this.rowElements.length;y > frame.rows.length; y -= 1) {
        const row = this.rowElements[y - 1];
        if (row)
          clearSelection(row);
        row?.remove();
        this.cells.pop();
      }
      this.rowElements.length = Math.min(this.rowElements.length, frame.rows.length);
      for (let y = 0;y < frame.rows.length; y += 1) {
        this.rebuildRow(y, frame, metrics, clearSelection);
      }
    } else {
      for (const [row] of damage.textRows) {
        if (row < 0 || row >= frame.rows.length) {
          continue;
        }
        this.rebuildRow(row, frame, metrics, clearSelection);
      }
    }
    const allowRecoveryRequests = frame !== this.lastImageRecoveryFrame;
    this.lastImageRecoveryFrame = frame;
    this.reconcileImages(frame.images ?? [], metrics, allowRecoveryRequests);
    this.hasRenderedFrame = true;
  }
  invalidateFontMetrics() {
    this.appliedMetricsKey = undefined;
  }
  dispose() {
    this.styleCache.clear();
    this.appliedCellStyles = new WeakMap;
    this.glyphs.clear();
    this.linkCells.clear();
    this.root?.replaceChildren();
    this.root = undefined;
    this.rowsLayer = undefined;
    this.imagesLayer = undefined;
    this.rowElements = [];
    this.cells = [];
    this.renderedImages.clear();
    this.reportedMissingImageIds.clear();
    this.lastImageRecoveryFrame = undefined;
  }
  rebuildRow(y, frame, metrics, clearSelection) {
    const rowElement = this.ensureRowElement(y, metrics);
    const previous = this.cells[y] ?? new Map;
    const next = new Map;
    const retainedColumns = new Set((frame.rows[y] ?? []).map((cell) => cell[0]));
    for (const [x, element] of previous) {
      if (!retainedColumns.has(x)) {
        clearSelection(element);
        element.remove();
      }
    }
    let position = 0;
    for (const [x, text, span, styleIndex] of frame.rows[y] ?? []) {
      const cellStyle = frame.styles[styleIndex] ?? undefined;
      const target = this.linkCells.get(y * frame.width + x);
      const isLink = target !== undefined && (/^https?:/i.test(target) || !!this.onOpenHyperlink);
      const tag = isLink ? "A" : "SPAN";
      let element = previous.get(x);
      if (element && element.tagName !== tag) {
        clearSelection(element);
        element.remove();
        element = undefined;
      }
      if (!element)
        element = createElement(tag.toLowerCase());
      if (element.textContent !== text) {
        clearSelection(element);
        element.textContent = text;
      }
      const key = JSON.stringify(cellStyle ?? null);
      let resolved = this.styleCache.get(key);
      if (!resolved) {
        resolved = resolveCellStyle(cellStyle, metrics);
        if (this.styleCache.size >= 512)
          this.styleCache.delete(this.styleCache.keys().next().value);
        this.styleCache.set(key, resolved);
      }
      const geometricText = canRenderBoxDrawing(text) ? text : "";
      const presentationKey = JSON.stringify([key, x, span, geometricText]);
      if (this.appliedCellStyles.get(element) !== presentationKey) {
        Object.assign(element.style, resolved, {
          left: `${x * metrics.cellWidth}px`,
          width: `${Math.max(1, span) * metrics.cellWidth}px`
        });
        const glyph = this.glyphs.image(geometricText, resolved.color ?? "", Math.max(1, span) * metrics.cellWidth, metrics.cellHeight);
        element.style.backgroundImage = glyph ?? "none";
        element.style.backgroundSize = "100% 100%";
        element.style.backgroundRepeat = "no-repeat";
        element.style.color = glyph ? "transparent" : resolved.color ?? "";
        this.appliedCellStyles.set(element, presentationKey);
      }
      if (isLink && target !== undefined && element.getAttribute("data-surface-link") !== target) {
        element.setAttribute("data-surface-link", target);
        element.setAttribute("tabindex", "-1");
        element.setAttribute("rel", "noopener noreferrer");
        element.setAttribute("target", "_blank");
        element.setAttribute("href", /^https?:/i.test(target) ? target : "#");
        const activate = (event) => {
          if (event.altKey || document.getSelection()?.isCollapsed === false) {
            event.preventDefault();
          } else if (this.onOpenHyperlink) {
            event.preventDefault();
            this.onOpenHyperlink(target);
          } else if (!/^https?:/i.test(target)) {
            event.preventDefault();
          }
        };
        element.onclick = activate;
        element.onauxclick = activate;
      }
      next.set(x, element);
      if (rowElement.children[position] !== element) {
        rowElement.insertBefore(element, rowElement.children[position] ?? null);
      }
      position += 1;
    }
    this.cells[y] = next;
  }
  ensureRowElement(y, metrics) {
    let rowElement = this.rowElements[y];
    if (!rowElement) {
      rowElement = createElement("div");
      rowElement.className = "webhost-scene__surface-row";
      Object.assign(rowElement.style, scopedBoxStyle, {
        font: "inherit",
        lineHeight: "inherit",
        letterSpacing: "0px",
        wordSpacing: "0px"
      });
      rowElement.style.position = "absolute";
      rowElement.style.left = "0";
      this.rowElements[y] = rowElement;
      this.rowsLayer?.appendChild(rowElement);
    }
    rowElement.style.top = `${y * metrics.cellHeight}px`;
    rowElement.style.height = `${metrics.cellHeight}px`;
    rowElement.style.width = `${metrics.columns * metrics.cellWidth}px`;
    return rowElement;
  }
  applyRootStyle(root, metrics) {
    const style = root.style;
    Object.assign(style, scopedBoxStyle);
    style.position = "relative";
    style.overflow = "hidden";
    style.background = webTUITerminalBackgroundColor(metrics.style);
    style.font = fontForStyle(metrics.style);
    style.lineHeight = `${metrics.cellHeight}px`;
    style.letterSpacing = "0px";
    style.wordSpacing = "0px";
    style.fontKerning = "none";
    style.fontSynthesis = "none";
    style.direction = "ltr";
    style.unicodeBidi = "isolate";
    style.fontVariantLigatures = "none";
    style.userSelect = "text";
  }
  reconcileImages(images, metrics, allowRecoveryRequests) {
    const layer = this.imagesLayer;
    if (!layer) {
      return;
    }
    const next = new Map;
    const currentMissingImageIds = new Set;
    const newlyMissingImageIds = new Set;
    for (const rawImage of images) {
      if (!isSupportedImageFormat(rawImage.format)) {
        continue;
      }
      const image = {
        ...rawImage,
        scalingMode: normalizeScalingMode(rawImage.scalingMode)
      };
      const [boundsX, boundsY, boundsWidth, boundsHeight] = image.bounds;
      const [clipX, clipY, clipWidth, clipHeight] = image.visibleBounds;
      const existing = this.renderedImages.get(image.id);
      if (image.dataBase64 !== undefined && !admitsImagePayload(image.dataBase64))
        continue;
      if (boundsWidth <= 0 || boundsHeight <= 0 || clipWidth <= 0 || clipHeight <= 0) {
        continue;
      }
      if (!existing && image.dataBase64 === undefined) {
        if (!isWebHostImageRecoveryId(image.id)) {
          continue;
        }
        currentMissingImageIds.add(image.id);
        if (!this.reportedMissingImageIds.has(image.id)) {
          newlyMissingImageIds.add(image.id);
        }
        continue;
      }
      const entry = existing ?? makeImageEntry();
      entry.container.style.left = `${clipX * metrics.cellWidth}px`;
      entry.container.style.top = `${clipY * metrics.cellHeight}px`;
      entry.container.style.width = `${clipWidth * metrics.cellWidth}px`;
      entry.container.style.height = `${clipHeight * metrics.cellHeight}px`;
      entry.image.style.left = `${(boundsX - clipX) * metrics.cellWidth}px`;
      entry.image.style.top = `${(boundsY - clipY) * metrics.cellHeight}px`;
      entry.image.style.width = `${boundsWidth * metrics.cellWidth}px`;
      entry.image.style.height = `${boundsHeight * metrics.cellHeight}px`;
      entry.image.style.opacity = String(normalizedImageOpacity2(image.opacity));
      if (image.dataBase64) {
        const source = `data:image/${image.format};base64,${image.dataBase64}`;
        if (entry.source !== source) {
          entry.image.setAttribute("src", source);
          entry.source = source;
        }
      }
      if (!existing) {
        layer.appendChild(entry.container);
      }
      next.set(image.id, entry);
    }
    for (const [id, entry] of this.renderedImages) {
      if (!next.has(id)) {
        entry.container.remove();
      }
    }
    this.renderedImages = next;
    for (const id of this.reportedMissingImageIds) {
      if (!currentMissingImageIds.has(id)) {
        this.reportedMissingImageIds.delete(id);
      }
    }
    if (allowRecoveryRequests && newlyMissingImageIds.size > 0) {
      const candidateIds = [...newlyMissingImageIds].sort();
      const admittedIds = this.onImagePayloadMiss(candidateIds);
      const acceptedIds = Array.isArray(admittedIds) ? admittedIds : candidateIds;
      const candidates = new Set(candidateIds);
      for (const id of acceptedIds) {
        if (candidates.has(id)) {
          this.reportedMissingImageIds.add(id);
        }
      }
    }
  }
}
function normalizedImageOpacity2(opacity) {
  if (opacity === undefined || !Number.isFinite(opacity)) {
    return 1;
  }
  return Math.max(0, Math.min(1, opacity));
}
function metricsKeyFor(metrics) {
  return [
    metrics.columns,
    metrics.rows,
    metrics.cellWidth,
    metrics.cellHeight,
    fontForStyle(metrics.style),
    metrics.style.theme.foreground,
    metrics.style.theme.background,
    metrics.style.theme.windowBackground,
    metrics.style.backgroundOpacity
  ].join("|");
}
function resolveCellStyle(style, metrics) {
  const elementStyle = {
    position: "absolute",
    display: "block",
    boxSizing: "border-box",
    padding: "0",
    margin: "0",
    border: "0",
    textIndent: "0",
    textTransform: "none",
    fontFamily: "inherit",
    fontSize: "inherit",
    lineHeight: "inherit",
    letterSpacing: "0px",
    wordSpacing: "0px",
    fontKerning: "none",
    fontSynthesis: "none",
    fontVariantLigatures: "none",
    top: "0",
    height: "100%",
    whiteSpace: "pre",
    overflow: "hidden",
    direction: "ltr",
    unicodeBidi: "isolate",
    color: resolvedSurfaceForeground(style, metrics.style),
    backgroundColor: resolvedSurfaceBackground(style, metrics.style) ?? "transparent",
    fontWeight: (style?.em ?? 0) & 1 ? "700" : "normal",
    fontStyle: (style?.em ?? 0) & 2 ? "italic" : "normal",
    opacity: String(style?.opacity ?? 1),
    textDecorationLine: "none",
    textDecorationStyle: "solid",
    textDecorationColor: resolvedSurfaceForeground(style, metrics.style)
  };
  applyTextDecoration(elementStyle, style);
  return elementStyle;
}
function applyTextDecoration(elementStyle, style) {
  const lines = [];
  if (style?.underline) {
    lines.push("underline");
  }
  if (style?.strikethrough) {
    lines.push("line-through");
  }
  if (lines.length === 0) {
    return;
  }
  elementStyle.textDecorationLine = lines.join(" ");
  const pattern = style?.underline?.pattern ?? style?.strikethrough?.pattern;
  elementStyle.textDecorationStyle = decorationStyleFor(pattern);
  const color = style?.underline?.color ?? style?.strikethrough?.color;
  if (color) {
    elementStyle.textDecorationColor = color;
  }
}
function decorationStyleFor(pattern) {
  switch (pattern) {
    case "dot":
      return "dotted";
    case "dash":
    case "dashDot":
    case "dashDotDot":
      return "dashed";
    case "double":
      return "double";
    case "curly":
      return "wavy";
    default:
      return "solid";
  }
}
function fillContainer(style) {
  Object.assign(style, scopedBoxStyle, {
    font: "inherit",
    lineHeight: "inherit"
  });
  style.position = "absolute";
  style.left = "0";
  style.top = "0";
  style.width = "100%";
  style.height = "100%";
}
function makeImageEntry() {
  const container = createElement("div");
  container.className = "webhost-scene__surface-image";
  Object.assign(container.style, scopedBoxStyle);
  container.style.position = "absolute";
  container.style.overflow = "hidden";
  const image = createElement("img");
  Object.assign(image.style, scopedBoxStyle);
  image.style.position = "absolute";
  image.setAttribute("alt", "");
  image.setAttribute("draggable", "false");
  container.appendChild(image);
  return { container, image, source: "" };
}
var scopedBoxStyle = {
  boxSizing: "border-box",
  margin: "0",
  padding: "0",
  border: "0",
  textAlign: "left",
  textIndent: "0",
  textTransform: "none"
};
function createElement(tagName) {
  if (typeof document === "undefined") {
    throw new Error("document is not available");
  }
  return document.createElement(tagName);
}
function selectionInvalidator() {
  let selection = globalThis.document?.getSelection?.();
  if (!selection || selection.isCollapsed)
    return () => {};
  const ranges = Array.from({ length: selection.rangeCount }, (_, index) => selection.getRangeAt(index));
  return (element) => {
    if (selection && ranges.some((range) => range.intersectsNode(element))) {
      selection.removeAllRanges();
      selection = null;
    }
  };
}

// src/InputEventEncoder.ts
class InputEventEncoder {
  encodeKey(event) {
    const key = keyInputFromKeyboardEvent(event);
    if (!key) {
      return;
    }
    return encodeKeyInputMessage({
      ...key,
      modifiers: modifierMask(event)
    });
  }
  encodePaste(text) {
    return encodePasteInputMessage(text);
  }
  encodePointerDown(location, button, event) {
    return encodeMouseInputMessage({
      kind: "down",
      x: location.x,
      y: location.y,
      button,
      modifiers: modifierMask(event)
    });
  }
  encodePointerUp(location, button, event) {
    return encodeMouseInputMessage({
      kind: "up",
      x: location.x,
      y: location.y,
      button,
      modifiers: modifierMask(event)
    });
  }
  encodePointerMove(location, button, event) {
    return encodeMouseInputMessage({
      kind: event.buttons ? "dragged" : "moved",
      x: location.x,
      y: location.y,
      button,
      modifiers: modifierMask(event)
    });
  }
  encodeWheel(location, event) {
    return encodeMouseInputMessage({
      kind: "scrolled",
      x: location.x,
      y: location.y,
      deltaX: normalizedWheelDelta(event.deltaX),
      deltaY: normalizedWheelDelta(event.deltaY),
      modifiers: modifierMask(event)
    });
  }
  pointerButton(button) {
    return pointerButton(button);
  }
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

// src/PointerGeometry.ts
function cellLocationForEvent(event, metrics) {
  const location = rawCellLocationForEvent(event, metrics);
  if (!location) {
    return;
  }
  const cellX = Math.floor(location.x);
  const cellY = Math.floor(location.y);
  if (cellX < 0 || cellY < 0 || cellX >= metrics.columns || cellY >= metrics.rows) {
    return;
  }
  return location;
}
function rawCellLocationForEvent(event, metrics) {
  const rect = metrics.rect;
  if (!rect) {
    return;
  }
  const x = (event.clientX - rect.left) / metrics.cellWidth;
  const y = (event.clientY - rect.top) / metrics.cellHeight;
  return { x, y };
}
function linkTargetAt(links, linkTargets, location) {
  if (!links || !linkTargets || linkTargets.length === 0) {
    return;
  }
  const cellX = Math.floor(location.x);
  const cellY = Math.floor(location.y);
  for (const [row, runs] of links) {
    if (row !== cellY) {
      continue;
    }
    for (const [x, span, targetIndex] of runs) {
      if (cellX >= x && cellX < x + span) {
        return linkTargets[targetIndex];
      }
    }
  }
  return;
}
function wheelTargetCanScroll(regions, location, deltaX, deltaY) {
  if (!regions || regions.length === 0) {
    return false;
  }
  const cellX = Math.floor(location.x);
  const cellY = Math.floor(location.y);
  for (const region of regions) {
    const [rx, ry, rw, rh] = region.rect;
    if (cellX < rx || cellY < ry || cellX >= rx + rw || cellY >= ry + rh) {
      continue;
    }
    if (regionCanScrollInDirection(region, deltaX, deltaY)) {
      return true;
    }
  }
  return false;
}
function regionCanScrollInDirection(region, deltaX, deltaY) {
  const [, , viewportWidth, viewportHeight] = region.rect;
  const [offsetX, offsetY] = region.offset;
  const [contentWidth, contentHeight] = region.content;
  const maxX = Math.max(0, contentWidth - viewportWidth);
  const maxY = Math.max(0, contentHeight - viewportHeight);
  const clampedX = Math.min(Math.max(0, offsetX), maxX);
  const clampedY = Math.min(Math.max(0, offsetY), maxY);
  if (deltaY > 0 && clampedY < maxY) {
    return true;
  }
  if (deltaY < 0 && clampedY > 0) {
    return true;
  }
  if (deltaX > 0 && clampedX < maxX) {
    return true;
  }
  if (deltaX < 0 && clampedX > 0) {
    return true;
  }
  return false;
}

// src/SurfacePaintScheduler.ts
function defaultAnimationFrameScheduler() {
  const request = globalThis.requestAnimationFrame;
  const cancel = globalThis.cancelAnimationFrame;
  if (typeof request !== "function" || typeof cancel !== "function") {
    return;
  }
  return {
    requestAnimationFrame: (callback) => request.call(globalThis, callback),
    cancelAnimationFrame: (handle) => cancel.call(globalThis, handle)
  };
}

class SurfacePaintScheduler {
  animationFrames;
  paint;
  pending;
  lastPaintedFrame;
  handle;
  disposed = false;
  held = false;
  presentedFrames = 0;
  paints = 0;
  coalescedFrames = 0;
  constructor(animationFrames, paint) {
    this.animationFrames = animationFrames;
    this.paint = paint;
  }
  get statistics() {
    return {
      presentedFrames: this.presentedFrames,
      paints: this.paints,
      coalescedFrames: this.coalescedFrames,
      pending: this.pending !== undefined
    };
  }
  get batchesPaints() {
    return this.animationFrames !== undefined;
  }
  present(frame, recoveredImagePayloadIds = []) {
    if (this.disposed) {
      return;
    }
    this.presentedFrames += 1;
    const pending = this.pending;
    const previous = pending ? pending.frame : this.lastPaintedFrame;
    const damage = promotesToFullRepaint(previous, frame) ? undefined : pending ? unionSurfaceDamage(pending.damage, frame.damage) : frame.damage;
    const next = pending ?? {
      frame: undefined,
      damage: undefined,
      carriedImagePayloads: new Map,
      recoveredImagePayloadIds: new Set,
      accessibilityAnnouncements: [],
      coalescedFrameCount: 0
    };
    if (pending?.frame && pending.frame !== this.lastPaintedFrame) {
      for (const image of pending.frame.images ?? []) {
        if (image.dataBase64 !== undefined) {
          next.carriedImagePayloads.set(image.id, image.dataBase64);
        }
      }
      next.coalescedFrameCount += 1;
      this.coalescedFrames += 1;
    }
    next.frame = frame;
    next.damage = damage;
    for (const id of recoveredImagePayloadIds) {
      next.recoveredImagePayloadIds.add(id);
    }
    next.accessibilityAnnouncements.push(...frame.accessibilityAnnouncements ?? []);
    this.pending = next;
    this.schedule();
  }
  requestRepaint() {
    if (this.disposed) {
      return;
    }
    this.promoteToFullRepaint();
    this.schedule();
  }
  repaintNow() {
    if (this.disposed) {
      return;
    }
    this.promoteToFullRepaint();
    this.flush();
  }
  flush() {
    if (this.disposed || this.held) {
      return;
    }
    this.cancelScheduled();
    const pending = this.pending;
    if (!pending) {
      return;
    }
    this.pending = undefined;
    const frame = pending.frame ? spliceCarriedImagePayloads(pending.frame, pending.carriedImagePayloads) : undefined;
    this.lastPaintedFrame = frame;
    this.paints += 1;
    this.paint({
      frame,
      damage: pending.damage,
      recoveredImagePayloadIds: [...pending.recoveredImagePayloadIds].sort(),
      accessibilityAnnouncements: pending.accessibilityAnnouncements,
      coalescedFrameCount: pending.coalescedFrameCount
    });
  }
  dispose() {
    if (this.disposed) {
      return;
    }
    this.cancelScheduled();
    this.pending = undefined;
    this.lastPaintedFrame = undefined;
    this.disposed = true;
  }
  promoteToFullRepaint() {
    if (this.pending) {
      this.pending.damage = undefined;
      return;
    }
    this.pending = {
      frame: this.lastPaintedFrame,
      damage: undefined,
      carriedImagePayloads: new Map,
      recoveredImagePayloadIds: new Set,
      accessibilityAnnouncements: [],
      coalescedFrameCount: 0
    };
  }
  schedule() {
    if (this.held)
      return;
    if (!this.animationFrames) {
      this.flush();
      return;
    }
    if (this.handle !== undefined) {
      return;
    }
    this.handle = this.animationFrames.requestAnimationFrame(() => {
      this.handle = undefined;
      this.flush();
    });
  }
  cancelScheduled() {
    if (this.handle === undefined) {
      return;
    }
    this.animationFrames?.cancelAnimationFrame(this.handle);
    this.handle = undefined;
  }
  setHeld(held) {
    if (this.disposed || held === this.held)
      return;
    this.held = held;
    if (held)
      this.cancelScheduled();
    else if (this.pending)
      this.schedule();
  }
}
function promotesToFullRepaint(previous, frame) {
  return previous === undefined || previous.width !== frame.width || previous.height !== frame.height || previous.epoch !== frame.epoch || frame.damage === undefined;
}
function spliceCarriedImagePayloads(frame, carried) {
  if (carried.size === 0 || !frame.images?.length) {
    return frame;
  }
  let spliced = false;
  const images = frame.images.map((image) => {
    if (image.dataBase64 !== undefined) {
      return image;
    }
    const payload = carried.get(image.id);
    if (payload === undefined) {
      return image;
    }
    spliced = true;
    return { ...image, dataBase64: payload };
  });
  return spliced ? { ...frame, images } : frame;
}
function unionSurfaceDamage(a, b) {
  if (!a || !b) {
    return;
  }
  const rows = new Map;
  for (const [row, ranges] of [...a.textRows, ...b.textRows]) {
    const existing = rows.get(row);
    if (existing === "full") {
      continue;
    }
    if (ranges.length === 0) {
      rows.set(row, "full");
      continue;
    }
    rows.set(row, existing ? [...existing, ...ranges] : [...ranges]);
  }
  const textRows = [...rows.entries()].sort(([left], [right]) => left - right).map(([row, ranges]) => [
    row,
    ranges === "full" ? [] : mergeDamageRanges(ranges)
  ]);
  return {
    textRows,
    requiresFullTextRepaint: a.requiresFullTextRepaint || b.requiresFullTextRepaint,
    requiresFullGraphicsReplay: a.requiresFullGraphicsReplay || b.requiresFullGraphicsReplay
  };
}
function mergeDamageRanges(ranges) {
  const sorted = [...ranges].sort(([left], [right]) => left - right);
  const merged = [];
  for (const [start, end] of sorted) {
    const last = merged[merged.length - 1];
    if (last && start <= last[1]) {
      merged[merged.length - 1] = [last[0], Math.max(last[1], end)];
    } else {
      merged.push([start, end]);
    }
  }
  return merged;
}

// src/WebHostSceneRuntime.ts
function legacyWheelMode(captureWheelInput) {
  if (captureWheelInput === undefined) {
    return "chain";
  }
  return captureWheelInput ? "capture" : "passive";
}
function coarsePointerQuery() {
  if (typeof globalThis.matchMedia !== "function") {
    return;
  }
  try {
    return globalThis.matchMedia("(pointer: coarse)");
  } catch {
    return;
  }
}
function coarsePrimaryPointer() {
  return coarsePointerQuery()?.matches ?? false;
}

class WebHostSceneRuntime {
  descriptor;
  element;
  terminalMount;
  bridge;
  onInput;
  onFrameDiagnostic;
  synchronizeAccessibilityFocus;
  wheelMode;
  rendererKind;
  sceneFrame;
  painter;
  paintScheduler;
  inputEncoder = new InputEventEncoder;
  currentStyle;
  canvas;
  canvasScale = 1;
  domSurfaceRoot;
  lastDomSurfaceSize;
  domGeometry;
  embeddingMount;
  geometryRefreshHandle;
  geometryDiagnostic;
  disposed = false;
  domFontOptions;
  fontResources;
  activeFontResources;
  fontPending = false;
  fontResult;
  loadingFont;
  accessibilityTree;
  diagnosticText;
  resizeObserver;
  detachMetricObservers;
  nativePointerGesture = false;
  detachInputHandlers;
  currentFrame;
  columns = 80;
  rows = 24;
  cellWidth = 8;
  cellHeight = 18;
  surfaceCSSWidth;
  surfaceCSSHeight;
  activePointerButton = "primary";
  hasCapturedPointer = false;
  onOpenHyperlink;
  pointerDownLinkTarget;
  lastSentResize;
  isVisible = false;
  documentVisible = true;
  runtimeSuspended = false;
  suspendWhenHidden;
  lastSentPointerCapabilities = false;
  detachPointerParadigmObserver;
  constructor(options) {
    this.descriptor = options.descriptor;
    this.embeddingMount = options.mount;
    this.currentStyle = normalizeWebHostTerminalStyle(options.renderer === "dom" && !options.style.fontFamily ? { ...options.style, fontFamily: DOM_FONT_FAMILY } : options.style);
    this.domFontOptions = options.domFont;
    this.bridge = options.bridge;
    this.onInput = options.onInput;
    this.onFrameDiagnostic = options.onFrameDiagnostic;
    this.synchronizeAccessibilityFocus = options.synchronizeAccessibilityFocus ?? true;
    this.wheelMode = options.wheelMode ?? legacyWheelMode(options.captureWheelInput);
    this.rendererKind = options.renderer ?? "canvas";
    this.sceneFrame = options.sceneFrame ?? "fill";
    const onImagePayloadMiss = (ids) => {
      return this.bridge?.requestImagePayloads?.(ids);
    };
    this.painter = this.rendererKind === "dom" ? new DomSurfacePainter({
      onImagePayloadMiss,
      onOpenHyperlink: options.onOpenHyperlink
    }) : new CanvasSurfacePainter({ onImagePayloadMiss });
    const paintScheduling = options.paintScheduling ?? defaultAnimationFrameScheduler();
    this.paintScheduler = new SurfacePaintScheduler(paintScheduling === "synchronous" ? undefined : paintScheduling, (request) => this.paint(request));
    this.onOpenHyperlink = options.onOpenHyperlink;
    this.suspendWhenHidden = options.suspendWhenHidden ?? true;
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
    if (this.surfaceElement) {
      return;
    }
    if (this.painter instanceof DomSurfacePainter) {
      const surfaceRoot = document.createElement("div");
      surfaceRoot.className = "webhost-scene__surface webhost-scene__surface--dom";
      surfaceRoot.setAttribute("aria-hidden", "true");
      this.domSurfaceRoot = surfaceRoot;
      this.painter.attach(surfaceRoot);
    } else {
      const canvas = document.createElement("canvas");
      canvas.className = "webhost-scene__surface";
      canvas.setAttribute("aria-hidden", "true");
      this.canvas = canvas;
      this.painter.attach(canvas, () => this.paintScheduler.requestRepaint());
    }
    this.accessibilityTree = new AccessibilityTreeMounter((target, request, requestID) => {
      this.onInput(encodeAccessibilityActionMessage(target, request, requestID));
    });
    this.terminalMount.replaceChildren(this.surfaceElement, this.accessibilityTree.element, this.accessibilityTree.announcerElement);
    if (this.domSurfaceRoot) {
      this.domGeometry = new DomGeometryController(this.terminalMount);
      this.paintScheduler.setHeld(true);
    }
    this.installInputHandlers();
    this.installResizeObserver();
    this.bridge?.bindOutput({
      presentSurface: (frame, recoveredImagePayloadIds) => this.presentSurface(frame, recoveredImagePayloadIds),
      writeClipboard: (text) => this.writeClipboard(text),
      notifyRuntimeIssue: (issue) => this.notifyRuntimeIssue(issue),
      recordFrameDiagnostic: (diagnostic) => this.recordFrameDiagnostic(diagnostic),
      writeOutput: (text) => this.writeOutput(text),
      writeError: (text) => this.writeOutput(text)
    });
    this.applyStyle(this.currentStyle);
    if (this.domGeometry)
      this.loadDomFont(this.currentStyle);
    this.installPointerParadigmObserver();
    this.sendPointerCapabilitiesIfChanged(coarsePrimaryPointer());
    this.measureCells();
    this.resizeToMount();
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
    this.updateRuntimeSuspension();
  }
  setDocumentVisible(visible) {
    const becameVisible = visible && !this.documentVisible;
    this.documentVisible = visible;
    this.updateRuntimeSuspension();
    if (becameVisible && this.paintScheduler.statistics.pending) {
      this.paintScheduler.repaintNow();
    }
  }
  get paintStatistics() {
    return this.paintScheduler.statistics;
  }
  updateRuntimeSuspension() {
    const suspended = this.suspendWhenHidden && (!this.isVisible || !this.documentVisible);
    if (suspended === this.runtimeSuspended) {
      return;
    }
    this.runtimeSuspended = suspended;
    this.onRuntimeSuspensionChange(suspended);
  }
  onRuntimeSuspensionChange(_suspended) {}
  setStyle(style) {
    const next = normalizeWebHostTerminalStyle(this.domGeometry && !style.fontFamily ? { ...style, fontFamily: DOM_FONT_FAMILY } : style);
    if (this.domGeometry) {
      this.loadDomFont(next);
      return;
    }
    this.currentStyle = next;
    this.applyStyle(this.currentStyle);
    this.bridge?.updateRenderStyle(this.currentStyle);
    this.measureCells();
    this.resizeToMount();
  }
  resize(columns, rows) {
    this.columns = Math.max(1, Math.round(columns));
    this.rows = Math.max(1, Math.round(rows));
    this.paintScheduler.repaintNow();
  }
  writeOutput(text) {
    if (!this.diagnosticText) {
      const diagnosticText = document.createElement("pre");
      diagnosticText.className = "webhost-scene__diagnostic";
      if (this.rendererKind === "dom") {
        diagnosticText.setAttribute("role", "status");
        Object.assign(diagnosticText.style, {
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
      }
      this.diagnosticText = diagnosticText;
      this.terminalMount.appendChild(diagnosticText);
    }
    this.diagnosticText.textContent = `${this.diagnosticText.textContent ?? ""}${text}`.slice(-16384);
  }
  notifyRuntimeIssue(issue) {
    this.writeOutput(`${issue.description}
`);
  }
  recordFrameDiagnostic(diagnostic) {
    this.onFrameDiagnostic?.(diagnostic);
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
    this.disposed = true;
    this.fontResources?.dispose();
    if (this.activeFontResources !== this.fontResources)
      this.activeFontResources?.dispose();
    if (this.geometryRefreshHandle !== undefined)
      globalThis.cancelAnimationFrame?.(this.geometryRefreshHandle);
    this.domGeometry?.dispose();
    this.paintScheduler.dispose();
    this.painter.dispose();
    this.detachInputHandlers?.();
    this.detachPointerParadigmObserver?.();
    this.resizeObserver?.disconnect();
    this.detachMetricObservers?.();
    this.element.remove();
  }
  sendPointerCapabilitiesIfChanged(supportsScrollPanning) {
    if (this.lastSentPointerCapabilities === supportsScrollPanning) {
      return;
    }
    this.lastSentPointerCapabilities = supportsScrollPanning;
    this.bridge?.updatePointerCapabilities?.(supportsScrollPanning);
  }
  installPointerParadigmObserver() {
    const query = coarsePointerQuery();
    if (!query?.addEventListener) {
      return;
    }
    const handleChange = (event) => {
      this.sendPointerCapabilitiesIfChanged(event.matches);
    };
    query.addEventListener("change", handleChange);
    this.detachPointerParadigmObserver = () => {
      query.removeEventListener?.("change", handleChange);
    };
  }
  presentSurface(frame, recoveredImagePayloadIds) {
    this.currentFrame = frame;
    this.columns = Math.max(1, Math.round(frame.width));
    this.rows = Math.max(1, Math.round(frame.height));
    this.paintScheduler.present(frame, recoveredImagePayloadIds);
  }
  get preferredGridSize() {
    const frame = this.currentFrame;
    if (frame?.preferredGridWidth === undefined || frame.preferredGridHeight === undefined) {
      return;
    }
    return {
      width: frame.preferredGridWidth,
      height: frame.preferredGridHeight
    };
  }
  get focusPresentation() {
    const presentation = this.currentFrame?.focusPresentation;
    if (!presentation) {
      return;
    }
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
    if (!/^https?:/i.test(url)) {
      return;
    }
    window.open(url, "_blank", "noopener,noreferrer");
  }
  applyStyle(style) {
    applyWebHostTerminalStyle(this.element, style);
    this.element.style.boxSizing = "border-box";
    if (this.sceneFrame === "resizable") {
      this.element.style.width = "80%";
      this.element.style.height = "80%";
      this.element.style.maxWidth = "100%";
      this.element.style.maxHeight = "100%";
      this.element.style.resize = "both";
      this.element.style.flex = "0 0 auto";
    } else {
      this.element.style.width = "100%";
      this.element.style.height = "100%";
    }
    this.element.style.minWidth = "0";
    this.element.style.minHeight = "0";
    this.element.style.padding = "0.75rem";
    this.element.style.borderRadius = "16px";
    this.element.style.boxShadow = "0 20px 50px rgba(0, 0, 0, 0.28)";
    this.element.style.overflow = "hidden";
    this.element.style.gap = "0.5rem";
    this.element.style.gridTemplateRows = "auto minmax(0, 1fr)";
    this.terminalMount.style.position = "relative";
    this.terminalMount.style.gridRow = "2";
    this.terminalMount.style.boxSizing = "border-box";
    this.terminalMount.style.width = "100%";
    if (this.sceneFrame === "resizable") {
      this.terminalMount.style.height = "auto";
      this.terminalMount.style.alignSelf = "stretch";
    } else {
      this.terminalMount.style.height = "100%";
    }
    this.terminalMount.style.minWidth = "0";
    this.terminalMount.style.minHeight = "0";
    this.terminalMount.style.overflow = "hidden";
    this.terminalMount.style.overscrollBehavior = this.wheelMode === "capture" ? "contain" : "auto";
    this.terminalMount.style.outline = "none";
    this.terminalMount.style.background = webTUITerminalBackgroundColor(this.currentStyle);
    if (this.canvas) {
      this.canvas.style.display = "block";
      this.canvas.style.width = "100%";
      this.canvas.style.height = "100%";
    }
    if (this.domSurfaceRoot) {
      this.domSurfaceRoot.style.display = "block";
      this.domSurfaceRoot.style.position = "relative";
    }
  }
  get surfaceElement() {
    return this.canvas ?? this.domSurfaceRoot;
  }
  applyVisibility() {
    this.element.hidden = !this.isVisible;
    this.element.style.setProperty("display", this.isVisible ? "grid" : "none", "important");
  }
  installResizeObserver() {
    const refresh = () => {
      if (this.domGeometry) {
        this.refreshGeometry();
        return;
      }
      if (this.painter instanceof DomSurfacePainter)
        this.painter.invalidateFontMetrics();
      this.resizeToMount();
    };
    if (typeof ResizeObserver !== "undefined") {
      this.resizeObserver = new ResizeObserver(refresh);
      this.resizeObserver.observe(this.terminalMount);
      if (this.domGeometry)
        this.resizeObserver.observe(this.embeddingMount);
      if (this.domGeometry)
        this.resizeObserver.observe(this.domGeometry.probe.element);
    }
    const fonts = document.fonts;
    fonts?.addEventListener?.("loadingdone", refresh);
    fonts?.addEventListener?.("loadingerror", refresh);
    globalThis.window?.addEventListener?.("resize", refresh);
    globalThis.window?.visualViewport?.addEventListener("resize", refresh);
    let dpr;
    const watchDpr = () => {
      dpr?.removeEventListener?.("change", changedDpr);
      dpr = globalThis.matchMedia?.(`(resolution: ${globalThis.devicePixelRatio || 1}dppx)`);
      dpr?.addEventListener?.("change", changedDpr);
    };
    const changedDpr = () => {
      watchDpr();
      refresh();
    };
    watchDpr();
    this.detachMetricObservers = () => {
      fonts?.removeEventListener?.("loadingdone", refresh);
      fonts?.removeEventListener?.("loadingerror", refresh);
      globalThis.window?.removeEventListener?.("resize", refresh);
      globalThis.window?.visualViewport?.removeEventListener("resize", refresh);
      dpr?.removeEventListener?.("change", changedDpr);
    };
  }
  installInputHandlers() {
    const handleKeyDown = (event) => {
      if (event.metaKey || event.isComposing || this.rendererKind === "dom" && event.ctrlKey && (event.key.toLowerCase() === "f" || event.key.toLowerCase() === "c" && document.getSelection?.()?.isCollapsed === false)) {
        return;
      }
      const message = this.inputEncoder.encodeKey(event);
      if (!message) {
        return;
      }
      this.onInput(message);
      event.preventDefault();
    };
    const handlePaste = (event) => {
      const text = event.clipboardData?.getData("text/plain") ?? "";
      if (!text) {
        return;
      }
      this.onInput(this.inputEncoder.encodePaste(text));
      event.preventDefault();
    };
    const handlePointerDown = (event) => {
      if (event.pointerType === "touch" || event.pointerType === "mouse") {
        this.sendPointerCapabilitiesIfChanged(event.pointerType === "touch");
      }
      if (this.allowsNativeTextSelection(event) || this.isNativeLink(event)) {
        this.nativePointerGesture = true;
        return;
      }
      const location = this.cellLocation(event);
      if (!location) {
        return;
      }
      this.nativePointerGesture = false;
      const button = this.inputEncoder.pointerButton(event.button);
      this.activePointerButton = button;
      this.hasCapturedPointer = true;
      this.pointerDownLinkTarget = button === "primary" ? this.linkTarget(location) : undefined;
      this.terminalMount.focus?.({ preventScroll: true });
      this.terminalMount.setPointerCapture?.(event.pointerId);
      this.onInput(this.inputEncoder.encodePointerDown(location, button, event));
      event.preventDefault();
    };
    const handlePointerUp = (event) => {
      if (!this.hasCapturedPointer && (this.nativePointerGesture || this.allowsNativeTextSelection(event) || this.isNativeLink(event))) {
        this.nativePointerGesture = false;
        return;
      }
      const location = this.hasCapturedPointer ? this.rawCellLocation(event) : this.cellLocation(event);
      this.terminalMount.releasePointerCapture?.(event.pointerId);
      this.hasCapturedPointer = false;
      const downLinkTarget = this.pointerDownLinkTarget;
      this.pointerDownLinkTarget = undefined;
      if (!location) {
        return;
      }
      const button = this.inputEncoder.pointerButton(event.button) ?? this.activePointerButton;
      this.onInput(this.inputEncoder.encodePointerUp(location, button, event));
      if (downLinkTarget !== undefined && this.linkTarget(location) === downLinkTarget) {
        this.openHyperlink(downLinkTarget);
      }
      event.preventDefault();
    };
    const handlePointerMove = (event) => {
      if (!this.hasCapturedPointer && (this.nativePointerGesture || this.allowsNativeTextSelection(event) || this.isNativeLink(event))) {
        return;
      }
      const location = event.buttons && this.hasCapturedPointer ? this.rawCellLocation(event) : this.cellLocation(event);
      if (!location) {
        return;
      }
      if (!this.hasCapturedPointer) {
        this.terminalMount.style.cursor = this.linkTarget(location) !== undefined ? "pointer" : "";
      }
      this.onInput(this.inputEncoder.encodePointerMove(location, this.activePointerButton, event));
    };
    const handleWheel = (event) => {
      if (this.wheelMode === "passive") {
        return;
      }
      const location = this.cellLocation(event);
      if (!location) {
        return;
      }
      if (this.wheelMode === "chain" && !wheelTargetCanScroll(this.currentFrame?.scrollRegions, location, event.deltaX, event.deltaY)) {
        return;
      }
      this.onInput(this.inputEncoder.encodeWheel(location, event));
      event.preventDefault();
    };
    const endNativeDrag = () => {
      this.nativePointerGesture = false;
    };
    document.addEventListener?.("pointerup", endNativeDrag);
    document.addEventListener?.("pointercancel", endNativeDrag);
    this.terminalMount.addEventListener("keydown", handleKeyDown);
    this.terminalMount.addEventListener("paste", handlePaste);
    this.terminalMount.addEventListener("pointerdown", handlePointerDown);
    this.terminalMount.addEventListener("pointerup", handlePointerUp);
    this.terminalMount.addEventListener("pointermove", handlePointerMove);
    this.terminalMount.addEventListener("wheel", handleWheel, {
      passive: false
    });
    this.detachInputHandlers = () => {
      document.removeEventListener?.("pointerup", endNativeDrag);
      document.removeEventListener?.("pointercancel", endNativeDrag);
      this.terminalMount.removeEventListener("keydown", handleKeyDown);
      this.terminalMount.removeEventListener("paste", handlePaste);
      this.terminalMount.removeEventListener("pointerdown", handlePointerDown);
      this.terminalMount.removeEventListener("pointerup", handlePointerUp);
      this.terminalMount.removeEventListener("pointermove", handlePointerMove);
      this.terminalMount.removeEventListener("wheel", handleWheel);
    };
  }
  resizeToMount() {
    if (this.disposed)
      return;
    if (this.fontPending)
      return;
    if (this.domGeometry) {
      let snapshot;
      try {
        snapshot = this.domGeometry.measure(this.currentStyle);
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        if (message !== this.geometryDiagnostic)
          this.writeOutput(`${message}
`);
        this.geometryDiagnostic = message;
      }
      if (!snapshot) {
        this.paintScheduler.setHeld(true);
        return;
      }
      this.cellWidth = snapshot.cellWidth;
      this.cellHeight = snapshot.cellHeight;
      this.columns = snapshot.columns;
      this.rows = snapshot.rows;
      this.surfaceCSSWidth = snapshot.content.width;
      this.surfaceCSSHeight = snapshot.content.height;
      if (snapshot.bounded && this.geometryDiagnostic !== "bounded") {
        this.writeOutput(`DOM viewport exceeds the supported grid; showing a bounded viewport.
`);
        this.geometryDiagnostic = "bounded";
      } else if (!snapshot.bounded)
        this.geometryDiagnostic = undefined;
      this.sendResizeIfNeeded();
      this.paintScheduler.setHeld(false);
      this.paintScheduler.repaintNow();
      return;
    }
    this.measureCells();
    const rect = this.terminalMount.getBoundingClientRect?.();
    const width = this.terminalMount.clientWidth || (rect?.width && rect.width > 0 ? rect.width : this.columns * this.cellWidth);
    const height = this.terminalMount.clientHeight || (rect?.height && rect.height > 0 ? rect.height : this.rows * this.cellHeight);
    this.surfaceCSSWidth = width;
    this.surfaceCSSHeight = height;
    const nextColumns = Math.max(1, Math.floor(width / this.cellWidth));
    const nextRows = Math.max(1, Math.floor(height / this.cellHeight));
    this.columns = nextColumns;
    this.rows = nextRows;
    this.sendResizeIfNeeded();
    this.paintScheduler.repaintNow();
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
  resizeSurface() {
    const gridCSSWidth = Math.max(1, this.columns * this.cellWidth);
    const gridCSSHeight = Math.max(1, this.rows * this.cellHeight);
    if (this.domSurfaceRoot) {
      const last = this.lastDomSurfaceSize;
      if (last && last.width === gridCSSWidth && last.height === gridCSSHeight) {
        return false;
      }
      this.lastDomSurfaceSize = { width: gridCSSWidth, height: gridCSSHeight };
      this.domSurfaceRoot.style.width = `${gridCSSWidth}px`;
      this.domSurfaceRoot.style.height = `${gridCSSHeight}px`;
      return true;
    }
    if (!this.canvas) {
      return false;
    }
    const scale = globalThis.window?.devicePixelRatio || 1;
    const cssWidth = Math.max(1, this.surfaceCSSWidth ?? gridCSSWidth);
    const cssHeight = Math.max(1, this.surfaceCSSHeight ?? gridCSSHeight);
    const bounded = boundedCanvasSize(cssWidth, cssHeight, scale);
    const { width, height } = bounded;
    const scaleChanged = this.canvasScale !== bounded.scale;
    this.canvasScale = bounded.scale;
    const styleWidth = "100%";
    const styleHeight = "100%";
    if (this.canvas.width === width && this.canvas.height === height && this.canvas.style.width === styleWidth && this.canvas.style.height === styleHeight && !scaleChanged) {
      return false;
    }
    this.canvas.width = width;
    this.canvas.height = height;
    this.canvas.style.width = styleWidth;
    this.canvas.style.height = styleHeight;
    return true;
  }
  measureCells() {
    if (this.domSurfaceRoot) {
      return;
    }
    const canvas = this.canvas ?? document.createElement("canvas");
    const context = canvas.getContext?.("2d");
    if (!context) {
      this.cellWidth = Math.max(1, Math.round(this.currentStyle.fontSize * 0.62));
      this.cellHeight = Math.max(1, Math.round(this.currentStyle.fontSize * 1.35));
      return;
    }
    context.font = fontForStyle(this.currentStyle);
    this.cellWidth = Math.max(1, Math.ceil(context.measureText("W").width));
    this.cellHeight = Math.max(1, Math.ceil(this.currentStyle.fontSize * 1.35));
  }
  paint(request) {
    if (this.domGeometry?.pending) {
      const pending = this.domGeometry.pending;
      const snapshot = Object.freeze({
        ...pending,
        columns: request.frame?.width ?? pending.columns,
        rows: request.frame?.height ?? pending.rows
      });
      this.domGeometry.present(snapshot);
      this.cellWidth = snapshot.cellWidth;
      this.cellHeight = snapshot.cellHeight;
      this.columns = Math.max(1, snapshot.columns);
      this.rows = Math.max(1, snapshot.rows);
      if (this.accessibilityTree) {
        Object.assign(this.accessibilityTree.element.style, {
          inset: "auto",
          left: `${snapshot.content.offsetX}px`,
          top: `${snapshot.content.offsetY}px`,
          width: `${this.columns * snapshot.cellWidth}px`,
          height: `${this.rows * snapshot.cellHeight}px`
        });
      }
    }
    const resized = this.resizeSurface();
    this.painter.paint(this.surfaceMetrics(), request.frame, resized ? undefined : request.damage, request.recoveredImagePayloadIds);
    this.syncAccessibilityTree(request.frame, request.accessibilityAnnouncements);
  }
  syncAccessibilityTree(frame, announcements) {
    const tree = this.accessibilityTree;
    if (!tree || !frame) {
      return;
    }
    tree.present(frame.accessibilityTree ?? [], {
      cellWidth: this.cellWidth,
      cellHeight: this.cellHeight
    }, [...announcements], {
      synchronizeFocus: this.synchronizeAccessibilityFocus,
      actionResponse: frame.accessibilityActionResponse
    });
  }
  surfaceMetrics() {
    return {
      columns: this.columns,
      rows: this.rows,
      cellWidth: this.cellWidth,
      cellHeight: this.cellHeight,
      pixelScale: this.canvasScale,
      style: this.currentStyle
    };
  }
  pointerMetrics() {
    const domRect = this.domSurfaceRoot?.getBoundingClientRect?.();
    const presented = this.domGeometry?.presented;
    const columns = presented?.columns ?? this.columns;
    const rows = presented?.rows ?? this.rows;
    return {
      rect: this.surfaceElement?.getBoundingClientRect?.() ?? this.terminalMount.getBoundingClientRect?.(),
      cellWidth: domRect?.width ? domRect.width / columns : this.cellWidth,
      cellHeight: domRect?.height ? domRect.height / rows : this.cellHeight,
      columns,
      rows
    };
  }
  refreshGeometry() {
    if (this.disposed || this.geometryRefreshHandle !== undefined)
      return;
    if (!globalThis.requestAnimationFrame) {
      this.resizeToMount();
      return;
    }
    this.geometryRefreshHandle = requestAnimationFrame(() => {
      this.geometryRefreshHandle = undefined;
      this.resizeToMount();
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
  loadDomFont(style) {
    if (this.fontResources !== this.activeFontResources)
      this.fontResources?.dispose();
    this.fontPending = true;
    this.paintScheduler.setHeld(true);
    this.terminalMount.setAttribute("aria-busy", "true");
    if (!this.loadingFont) {
      this.loadingFont = document.createElement("div");
      this.loadingFont.setAttribute("role", "status");
      this.loadingFont.textContent = "Loading display font…";
      this.terminalMount.appendChild(this.loadingFont);
    }
    const resources = new DomFontResources(this.terminalMount.ownerDocument ?? document, style.fontFamily, style.fontSize, this.domFontOptions);
    this.fontResources = resources;
    resources.ready.then((result) => {
      if (this.disposed || resources !== this.fontResources || result.status === "disposed")
        return;
      this.fontResult = result;
      const previousResources = this.activeFontResources;
      this.activeFontResources = resources;
      this.fontPending = false;
      this.loadingFont?.remove();
      this.loadingFont = undefined;
      this.terminalMount.removeAttribute("aria-busy");
      this.currentStyle = { ...style, fontFamily: result.family };
      this.applyStyle(this.currentStyle);
      this.bridge?.updateRenderStyle(this.currentStyle);
      if (result.diagnostic)
        this.writeOutput(`${result.diagnostic}
`);
      this.resizeToMount();
      previousResources?.dispose();
    }).catch((error) => {
      if (this.disposed || resources !== this.fontResources)
        return;
      this.fontPending = false;
      this.writeOutput(`DOM font configuration failed: ${String(error)}
`);
    });
  }
  isNativeLink(event) {
    return this.rendererKind === "dom" && !!event.target?.closest?.("a[data-surface-link]");
  }
  allowsNativeTextSelection(event) {
    return this.rendererKind === "dom" && event.altKey;
  }
  cellLocation(event) {
    return cellLocationForEvent(event, this.pointerMetrics());
  }
  rawCellLocation(event) {
    return rawCellLocationForEvent(event, this.pointerMetrics());
  }
}

// src/WebSocketSceneBridge.ts
var socketOpenState = 1;
var normalClosureCode = 1000;
var textEncoder2 = new TextEncoder;
function defaultReconnectDelayMilliseconds(attempt) {
  return Math.min(250 * 2 ** (attempt - 1), 8000);
}

class WebSocketSceneBridge {
  url;
  socket;
  createSocket;
  reconnectDelayMilliseconds;
  decoder = new WebHostOutputDecoder;
  queuedInput = [];
  queuedOutput = [];
  sink;
  disposed = false;
  reconnectAttempts = 0;
  reconnectTimer;
  lastRenderStyleMessage;
  lastResizeMessage;
  lastPointerCapabilitiesMessage;
  handleOpen = () => {
    this.reconnectAttempts = 0;
    this.flushQueuedInput();
  };
  handleMessage = (event) => {
    this.receive(event.data);
  };
  handleClose = (event) => {
    for (const record of this.decoder.flush()) {
      this.deliver(record);
    }
    if (this.disposed || event.code === normalClosureCode) {
      return;
    }
    this.queuedInput.length = 0;
    this.scheduleReconnect();
  };
  handleError = () => {};
  constructor(options) {
    this.url = webSocketSceneURL(options);
    this.createSocket = options.webSocketFactory ?? defaultWebSocketFactory;
    this.reconnectDelayMilliseconds = options.reconnectDelayMilliseconds ?? defaultReconnectDelayMilliseconds;
    this.socket = this.createSocket(this.url);
    this.attachSocket(this.socket);
    this.sendInput(encodeCapabilitiesControlMessage());
  }
  bindOutput(sink) {
    this.sink = sink;
    while (this.queuedOutput.length > 0) {
      this.deliver(this.queuedOutput.shift());
    }
  }
  resize(columns, rows, cellWidth, cellHeight) {
    const message = encodeResizeControlMessage(columns, rows, cellWidth, cellHeight);
    this.lastResizeMessage = message;
    this.sendInput(message);
  }
  updateRenderStyle(style) {
    const message = encodeRenderStyleControlMessage(style);
    this.lastRenderStyleMessage = message;
    this.sendInput(message);
  }
  updatePointerCapabilities(supportsScrollPanning) {
    const message = encodePointerCapabilitiesControlMessage(supportsScrollPanning);
    this.lastPointerCapabilitiesMessage = message;
    this.sendInput(message);
  }
  sendInput(chunk) {
    if (this.disposed) {
      return;
    }
    const copy = new Uint8Array(chunk);
    this.queuedInput.push(copy);
    if (this.socket.readyState === socketOpenState) {
      this.flushQueuedInput();
    }
  }
  requestImagePayloads(ids) {
    if (this.disposed) {
      return [];
    }
    const acceptedIds = this.decoder.requestImagePayloads(ids);
    this.sendPendingResyncRequests();
    return acceptedIds;
  }
  dispose() {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    if (this.reconnectTimer !== undefined) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = undefined;
    }
    this.detachSocket(this.socket);
    this.queuedInput.length = 0;
    this.queuedOutput.length = 0;
    this.socket.close(1000, "WebHost scene disposed");
  }
  attachSocket(socket) {
    socket.binaryType = "arraybuffer";
    socket.addEventListener("open", this.handleOpen);
    socket.addEventListener("message", this.handleMessage);
    socket.addEventListener("close", this.handleClose);
    socket.addEventListener("error", this.handleError);
  }
  detachSocket(socket) {
    socket.removeEventListener("open", this.handleOpen);
    socket.removeEventListener("message", this.handleMessage);
    socket.removeEventListener("close", this.handleClose);
    socket.removeEventListener("error", this.handleError);
  }
  scheduleReconnect() {
    if (this.reconnectTimer !== undefined) {
      return;
    }
    this.reconnectAttempts += 1;
    const delay = Math.max(0, this.reconnectDelayMilliseconds(this.reconnectAttempts));
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = undefined;
      this.reconnect();
    }, delay);
  }
  reconnect() {
    if (this.disposed) {
      return;
    }
    this.detachSocket(this.socket);
    let socket;
    try {
      socket = this.createSocket(this.url);
    } catch {
      this.scheduleReconnect();
      return;
    }
    this.socket = socket;
    this.attachSocket(socket);
    const handshake = [encodeCapabilitiesControlMessage()];
    if (this.lastRenderStyleMessage) {
      handshake.push(this.lastRenderStyleMessage);
    }
    if (this.lastResizeMessage) {
      handshake.push(this.lastResizeMessage);
    }
    if (this.lastPointerCapabilitiesMessage) {
      handshake.push(this.lastPointerCapabilitiesMessage);
    }
    this.queuedInput.unshift(...handshake.map((chunk) => new Uint8Array(chunk)));
    if (this.socket.readyState === socketOpenState) {
      this.flushQueuedInput();
    }
  }
  async receive(message) {
    if (this.disposed) {
      return;
    }
    const limit = HOST_WIRE_MAX_RECORD_BYTES * 2;
    const oversized = typeof message === "string" ? !fitsUTF8(message, limit) : message instanceof ArrayBuffer || ArrayBuffer.isView(message) ? message.byteLength > limit : typeof Blob !== "undefined" && message instanceof Blob ? message.size > limit : false;
    const bytes = await (oversized ? undefined : bytesFromWebSocketMessage(message));
    if (oversized) {
      this.deliver(this.decoder.rejectOversizedMessage());
      this.sendPendingResyncRequests();
      return;
    }
    if (!bytes) {
      return;
    }
    for (const record of this.decoder.feed(bytes)) {
      this.deliver(record);
    }
    this.sendPendingResyncRequests();
  }
  deliver(record) {
    const sink = this.sink;
    if (!sink) {
      this.queuedOutput.push(record);
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
    if (this.disposed || this.socket.readyState !== socketOpenState) {
      return;
    }
    while (this.queuedInput.length > 0) {
      try {
        this.socket.send(this.queuedInput[0]);
        this.queuedInput.shift();
      } catch {
        return;
      }
    }
  }
  sendPendingResyncRequests() {
    while (true) {
      const request = this.decoder.takeResyncRequest();
      if (!request) {
        return;
      }
      try {
        this.sendInput(encodeResyncControlMessage(request));
      } catch {
        this.decoder.resyncRequestDeliveryFailed(request);
        return;
      }
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

// src/wasi/SharedInputQueue.ts
var capacityWaitTimeoutMilliseconds = 50;
var writeDeadlineMilliseconds = 500;
var sharedInputQueueDefaultCapacity = 64 * 1024;
function hydrateSharedInputQueue(buffers) {
  return {
    control: new Int32Array(buffers.controlBuffer),
    data: new Uint8Array(buffers.dataBuffer)
  };
}

class SharedInputQueueWriter {
  queue;
  writeChain = Promise.resolve();
  pendingWrites = 0;
  constructor(buffers) {
    this.queue = hydrateSharedInputQueue(buffers);
  }
  writeAsync(chunk, options = {}) {
    const bytes = normalizeChunk(chunk);
    if (bytes.length === 0) {
      return Promise.resolve({ status: "written" });
    }
    if (Atomics.load(this.queue.control, 2 /* closed */) !== 0) {
      return Promise.resolve({ status: "closed", bytesWritten: 0 });
    }
    if (this.pendingWrites === 0 && bytes.length <= this.availableCapacity()) {
      this.writeSegment(bytes);
      return Promise.resolve({ status: "written" });
    }
    this.pendingWrites += 1;
    const attempt = this.writeChain.then(() => this.performChunkedWrite(bytes, options), () => this.performChunkedWrite(bytes, options));
    this.writeChain = attempt;
    return attempt.finally(() => {
      this.pendingWrites -= 1;
    });
  }
  async performChunkedWrite(bytes, options) {
    const now = options.now ?? (() => Date.now());
    const deadline = now() + Math.max(0, options.deadlineMilliseconds ?? writeDeadlineMilliseconds);
    let written = 0;
    while (written < bytes.length) {
      if (Atomics.load(this.queue.control, 2 /* closed */) !== 0) {
        return { status: "closed", bytesWritten: written };
      }
      const free = this.availableCapacity();
      if (free > 0) {
        const segment = Math.min(free, bytes.length - written);
        this.writeSegment(bytes.subarray(written, written + segment));
        written += segment;
        continue;
      }
      const remainingBudget = deadline - now();
      if (remainingBudget <= 0) {
        return {
          status: "partial",
          bytesWritten: written,
          bytesRemaining: bytes.length - written
        };
      }
      await this.waitForCapacity(1, {
        timeoutMilliseconds: Math.min(capacityWaitTimeoutMilliseconds, remainingBudget),
        singleWait: true
      });
    }
    return { status: "written" };
  }
  writeSegment(segment) {
    const length = this.queue.data.length;
    const writeIndex = Atomics.load(this.queue.control, 1 /* writeIndex */);
    writeToRingBuffer(this.queue.data, segment, writeIndex);
    Atomics.store(this.queue.control, 1 /* writeIndex */, ringAdvance(writeIndex, segment.length, length));
    Atomics.notify(this.queue.control, 1 /* writeIndex */);
  }
  write(chunk) {
    if (Atomics.load(this.queue.control, 2 /* closed */) !== 0) {
      return;
    }
    const bytes = normalizeChunk(chunk);
    if (bytes.length === 0) {
      return;
    }
    const length = this.queue.data.length;
    const readIndex = Atomics.load(this.queue.control, 0 /* readIndex */);
    const writeIndex = Atomics.load(this.queue.control, 1 /* writeIndex */);
    const usedCapacity = ringUsed(readIndex, writeIndex, length);
    const availableCapacity = length - usedCapacity;
    if (bytes.length > availableCapacity) {
      throw new Error(`Shared input queue overflow: cannot enqueue ${bytes.length} byte(s) into ${availableCapacity} byte(s) of free space.`);
    }
    writeToRingBuffer(this.queue.data, bytes, writeIndex);
    Atomics.store(this.queue.control, 1 /* writeIndex */, ringAdvance(writeIndex, bytes.length, length));
    Atomics.notify(this.queue.control, 1 /* writeIndex */);
  }
  availableCapacity() {
    const length = this.queue.data.length;
    const readIndex = Atomics.load(this.queue.control, 0 /* readIndex */);
    const writeIndex = Atomics.load(this.queue.control, 1 /* writeIndex */);
    return length - ringUsed(readIndex, writeIndex, length);
  }
  async waitForCapacity(minimumBytes, options = {}) {
    const required = Math.max(0, Math.ceil(minimumBytes));
    if (required > this.queue.data.length) {
      return false;
    }
    const timeout = options.timeoutMilliseconds ?? capacityWaitTimeoutMilliseconds;
    while (true) {
      const readIndex = Atomics.load(this.queue.control, 0 /* readIndex */);
      if (Atomics.load(this.queue.control, 2 /* closed */) !== 0) {
        return false;
      }
      if (this.availableCapacity() >= required) {
        return true;
      }
      if (typeof Atomics.waitAsync === "function") {
        const waiting = Atomics.waitAsync(this.queue.control, 0 /* readIndex */, readIndex, timeout);
        if (waiting.async) {
          await waiting.value;
        }
      } else {
        await new Promise((resolve) => {
          setTimeout(resolve, 1);
        });
      }
      if (options.singleWait) {
        return this.availableCapacity() >= required;
      }
    }
  }
  close() {
    Atomics.store(this.queue.control, 2 /* closed */, 1);
    Atomics.notify(this.queue.control, 1 /* writeIndex */);
    Atomics.notify(this.queue.control, 0 /* readIndex */);
  }
}
function normalizeChunk(chunk) {
  return typeof chunk === "string" ? new TextEncoder().encode(chunk) : new Uint8Array(chunk);
}
function ringUsed(readIndex, writeIndex, length) {
  const span = 2 * length;
  return ((writeIndex - readIndex) % span + span) % span;
}
function ringAdvance(index, delta, length) {
  return (index + delta) % (2 * length);
}
function writeToRingBuffer(buffer, chunk, startIndex) {
  const offset = startIndex % buffer.length;
  const firstSegmentLength = Math.min(chunk.length, buffer.length - offset);
  buffer.set(chunk.subarray(0, firstSegmentLength), offset);
  if (firstSegmentLength < chunk.length) {
    buffer.set(chunk.subarray(firstSegmentLength), 0);
  }
}

// src/wasi/StdIOPipe.ts
class StdIOPipe {
  chunks = [];
  waiters = [];
  listeners = new Set;
  closed = false;
  write(chunk) {
    if (this.closed) {
      return false;
    }
    const bytes = typeof chunk === "string" ? new TextEncoder().encode(chunk) : new Uint8Array(chunk);
    const waiter = this.waiters.shift();
    if (waiter) {
      waiter({ done: false, value: bytes });
      return true;
    }
    this.chunks.push(bytes);
    let accepted = true;
    for (const listener of this.listeners) {
      if (listener(bytes) === false) {
        accepted = false;
      }
    }
    return accepted;
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

// src/wasi/WasmEngineCapabilities.ts
function collectWasmEngineProbeSignals() {
  const probe = new Error("wasm-engine-probe");
  const wasm = globalThis.WebAssembly;
  return {
    errorStack: readProbe(() => typeof probe.stack === "string" ? probe.stack : "", ""),
    errorHasGeckoFileName: readProbe(() => ("fileName" in probe), false),
    errorHasJSCSourceURL: readProbe(() => ("sourceURL" in probe), false),
    wasmSuspendingType: readProbe(() => typeof wasm?.Suspending, "undefined"),
    wasmPromisingType: readProbe(() => typeof wasm?.promising, "undefined")
  };
}
function classifyWasmEngineFamily(signals) {
  const v8 = /^\s*at /m.test(signals.errorStack);
  const atFrames = /^[^\n]*@/m.test(signals.errorStack);
  const gecko = signals.errorHasGeckoFileName;
  const jsc = signals.errorHasJSCSourceURL;
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
  const engine = classifyWasmEngineFamily(signals);
  return {
    engine,
    supportsJSPI: signals.wasmSuspendingType === "function" && signals.wasmPromisingType === "function",
    stackLeanRecommended: engine !== "v8"
  };
}
function stackProfileEnvironmentDefaults(capabilities) {
  if (capabilities.engine === "v8") {
    return { SWIFTTUI_STACK_LEAN_PROFILE: "0" };
  }
  return { SWIFTTUI_LEAN_RETAINED_REUSE: "1" };
}
function readProbe(read, fallback) {
  try {
    return read();
  } catch {
    return fallback;
  }
}

// src/wasi/BrowserWASIBridge.ts
var maximumWASIResyncControlBytes = sharedInputQueueDefaultCapacity - 1;

class BrowserWASIBridge {
  stdin = new StdIOPipe;
  stdout = new StdIOPipe;
  stderr = new StdIOPipe;
  environment;
  detachStdout;
  detachStderr;
  decoder = new WebHostOutputDecoder;
  resizeListeners = new Set;
  latestResize;
  constructor(options) {
    this.environment = {
      SWIFTTUI_MODE: "browser",
      SWIFTTUI_TRANSPORT: "surface",
      SWIFTTUI_SURFACE_DELTA: "1",
      SWIFTTUI_SCENE: options.sceneId,
      SWIFTTUI_COLUMNS: String(Math.max(1, options.columns)),
      SWIFTTUI_ROWS: String(Math.max(1, options.rows)),
      SWIFTTUI_RENDER_MODE: "async-no-cancel",
      ...stackProfileEnvironmentDefaults(options.engineCapabilities ?? resolveWasmEngineCapabilities()),
      ...options.environment,
      ...options.renderStyle ? {
        SWIFTTUI_RENDER_STYLE: encodeWebHostTerminalRenderStyleBase64(options.renderStyle)
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
    this.decoder = new WebHostOutputDecoder;
    this.detachStdout = this.stdout.subscribe((chunk) => {
      for (const record of this.decoder.feed(chunk)) {
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
      this.sendPendingResyncRequests();
    });
    this.detachStderr = this.stderr.subscribe((chunk) => {
      sink.writeError?.(new TextDecoder().decode(chunk));
    });
  }
  resize(columns, rows, cellWidth, cellHeight) {
    const normalizedColumns = Math.max(1, columns);
    const normalizedRows = Math.max(1, rows);
    this.environment.SWIFTTUI_COLUMNS = String(normalizedColumns);
    this.environment.SWIFTTUI_ROWS = String(normalizedRows);
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
    this.environment.SWIFTTUI_RENDER_STYLE = encodeWebHostTerminalRenderStyleBase64(style);
    this.stdin.write(encodeRenderStyleControlMessage(style));
  }
  updatePointerCapabilities(supportsScrollPanning) {
    this.stdin.write(encodePointerCapabilitiesControlMessage(supportsScrollPanning));
  }
  sendInput(chunk) {
    this.stdin.write(chunk);
  }
  requestImagePayloads(ids) {
    const acceptedIds = this.decoder.requestImagePayloads(ids);
    this.sendPendingResyncRequests();
    return acceptedIds;
  }
  notifyInputCapacityAvailable() {
    this.sendPendingResyncRequests();
  }
  subscribeResize(listener) {
    this.resizeListeners.add(listener);
    listener(this.latestResize.columns, this.latestResize.rows, this.latestResize.cellWidth, this.latestResize.cellHeight);
    return () => {
      this.resizeListeners.delete(listener);
    };
  }
  sendPendingResyncRequests() {
    while (true) {
      const request = this.decoder.takeResyncRequest(maximumWASIResyncControlBytes);
      if (!request) {
        return;
      }
      const accepted = this.stdin.write(encodeResyncControlMessage(request));
      if (!accepted) {
        this.decoder.resyncRequestDeliveryFailed(request);
        return;
      }
    }
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
    sceneRuntimeFactory: options.sceneRuntimeFactory ?? ((runtimeOptions) => new WebHostSceneRuntime(runtimeOptions)),
    suspendHiddenScenes: options.suspendHiddenScenes,
    visibilityDocument: options.visibilityDocument ?? defaultVisibilityDocument(),
    renderer: options.renderer,
    domFont: options.domFont,
    sceneFrame: options.sceneFrame,
    paintScheduling: options.paintScheduling
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
  suspendHiddenScenes;
  renderer;
  domFont;
  sceneFrame;
  paintScheduling;
  visibilityDocument;
  detachVisibilityListener;
  constructor(options) {
    this.mount = options.mount;
    this.style = normalizeWebHostTerminalStyle(options.renderer === "dom" && !options.style?.fontFamily ? { ...options.style, fontFamily: DOM_FONT_FAMILY } : options.style ?? {});
    this.domFont = options.domFont;
    this.environment = options.environment;
    this.embeddedHost = options.embeddedHost;
    this.bridgeFactory = options.bridgeFactory;
    this.sceneRuntimeFactory = options.sceneRuntimeFactory;
    this.suspendHiddenScenes = options.suspendHiddenScenes;
    this.renderer = options.renderer;
    this.sceneFrame = options.sceneFrame ?? "fill";
    this.paintScheduling = options.paintScheduling;
    this.visibilityDocument = options.visibilityDocument;
    this.scenes = options.manifest.scenes;
    this.selectedSceneId = options.initialSceneId && options.manifest.scenes.some((scene) => scene.id === options.initialSceneId) ? options.initialSceneId : options.manifest.scenes.find((scene) => scene.id === options.manifest.defaultSceneId)?.id ?? options.manifest.defaultSceneId;
    this.sceneRoot = (options.createElement ?? defaultCreateElement)("div");
    this.sceneRoot.className = "webhost-scene-root";
    this.sceneRoot.style.boxSizing = "border-box";
    this.sceneRoot.style.width = "100%";
    this.sceneRoot.style.height = "100%";
    this.sceneRoot.style.minWidth = "0";
    this.sceneRoot.style.minHeight = "0";
    this.sceneRoot.style.overflow = "hidden";
    if (this.sceneFrame === "resizable") {
      this.sceneRoot.style.display = "flex";
      this.sceneRoot.style.justifyContent = "center";
      this.sceneRoot.style.alignItems = "flex-start";
    } else {
      this.sceneRoot.style.display = "block";
    }
    this.mount.replaceChildren(this.sceneRoot);
    this.applyHostFrameStyle();
  }
  async initialize() {
    this.installVisibilityListener();
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
    this.detachVisibilityListener?.();
    this.detachVisibilityListener = undefined;
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
  installVisibilityListener() {
    const visibilityDocument = this.visibilityDocument;
    if (!visibilityDocument) {
      return;
    }
    const listener = () => {
      const visible = !visibilityDocument.hidden;
      for (const runtime of this.runtimes.values()) {
        runtime.setDocumentVisible(visible);
      }
    };
    visibilityDocument.addEventListener("visibilitychange", listener);
    this.detachVisibilityListener = () => {
      visibilityDocument.removeEventListener("visibilitychange", listener);
    };
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
      onInput: (chunk) => bridge.sendInput(chunk),
      suspendWhenHidden: this.suspendHiddenScenes,
      renderer: this.renderer,
      domFont: this.domFont,
      sceneFrame: this.sceneFrame,
      paintScheduling: this.paintScheduling
    });
    this.bridges.set(id, bridge);
    this.runtimes.set(id, runtime);
    await runtime.mount();
    runtime.setVisible(id === this.selectedSceneId);
    if (this.visibilityDocument) {
      runtime.setDocumentVisible(!this.visibilityDocument.hidden);
    }
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
    this.mount.style.boxSizing = "border-box";
    this.mount.style.width = "100%";
    this.mount.style.height = "100%";
    this.mount.style.minWidth = "0";
    this.mount.style.minHeight = "0";
    this.mount.style.overflow = "hidden";
    this.mount.style.display = "block";
    this.mount.style.padding = "1rem";
  }
}
function defaultVisibilityDocument() {
  if (typeof document === "undefined") {
    return;
  }
  return document;
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
    renderer: config.renderer ?? rendererFromQuery(pageURL),
    sceneFrame: config.sceneFrame ?? "resizable",
    embeddedHost: embeddedToken ? {
      token: embeddedToken,
      webSocketBaseURL: config.embeddedHost?.webSocketBaseURL ?? new URL("./", pageURL).href
    } : undefined
  });
  window.__WEBTUI_APP__ = controller;
}
bootstrap();
function rendererFromQuery(pageURL) {
  const renderer = pageURL.searchParams.get("renderer");
  return renderer === "dom" || renderer === "canvas" ? renderer : undefined;
}
function tokenizedURL(value, token) {
  if (!token) {
    return value;
  }
  const url = new URL(String(value), globalThis.location?.href ?? import.meta.url);
  url.searchParams.set("token", token);
  return url;
}
