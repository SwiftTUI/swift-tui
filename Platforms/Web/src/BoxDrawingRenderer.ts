type LineWeight = 0 | 1 | 2 | 3;
type Direction = "north" | "east" | "south" | "west";
type Corner = "topLeft" | "topRight" | "bottomLeft" | "bottomRight";
type Spec = [north: LineWeight, east: LineWeight, south: LineWeight, west: LineWeight];

interface Rect {
  x: number;
  y: number;
  width: number;
  height: number;
}

interface StrokeMetrics {
  light: number;
  heavy: number;
  doubleGap: number;
}

interface BoxDrawingCanvasContext {
  fillRect(x: number, y: number, width: number, height: number): void;
  beginPath(): void;
  moveTo(x: number, y: number): void;
  lineTo(x: number, y: number): void;
  bezierCurveTo(
    control1X: number,
    control1Y: number,
    control2X: number,
    control2Y: number,
    x: number,
    y: number
  ): void;
  stroke(): void;
  setLineDash(lineDash: number[]): void;
  lineWidth: number;
  lineCap: string;
}

const none = 0;
const light = 1;
const heavy = 2;
const double = 3;

const lineSpecs: Record<number, Spec> = {
  0x2500: [none, light, none, light],
  0x2501: [none, heavy, none, heavy],
  0x2502: [light, none, light, none],
  0x2503: [heavy, none, heavy, none],
  0x250c: [none, light, light, none],
  0x250d: [none, heavy, light, none],
  0x250e: [none, light, heavy, none],
  0x250f: [none, heavy, heavy, none],
  0x2510: [none, none, light, light],
  0x2511: [none, none, light, heavy],
  0x2512: [none, none, heavy, light],
  0x2513: [none, none, heavy, heavy],
  0x2514: [light, light, none, none],
  0x2515: [light, heavy, none, none],
  0x2516: [heavy, light, none, none],
  0x2517: [heavy, heavy, none, none],
  0x2518: [light, none, none, light],
  0x2519: [light, none, none, heavy],
  0x251a: [heavy, none, none, light],
  0x251b: [heavy, none, none, heavy],
  0x251c: [light, light, light, none],
  0x251d: [light, heavy, light, none],
  0x251e: [heavy, light, light, none],
  0x251f: [light, light, heavy, none],
  0x2520: [heavy, light, heavy, none],
  0x2521: [heavy, heavy, light, none],
  0x2522: [light, heavy, heavy, none],
  0x2523: [heavy, heavy, heavy, none],
  0x2524: [light, none, light, light],
  0x2525: [light, none, light, heavy],
  0x2526: [heavy, none, light, light],
  0x2527: [light, none, heavy, light],
  0x2528: [heavy, none, heavy, light],
  0x2529: [heavy, none, light, heavy],
  0x252a: [light, none, heavy, heavy],
  0x252b: [heavy, none, heavy, heavy],
  0x252c: [none, light, light, light],
  0x252d: [none, light, light, heavy],
  0x252e: [none, heavy, light, light],
  0x252f: [none, heavy, light, heavy],
  0x2530: [none, light, heavy, light],
  0x2531: [none, light, heavy, heavy],
  0x2532: [none, heavy, heavy, light],
  0x2533: [none, heavy, heavy, heavy],
  0x2534: [light, light, none, light],
  0x2535: [light, light, none, heavy],
  0x2536: [light, heavy, none, light],
  0x2537: [light, heavy, none, heavy],
  0x2538: [heavy, light, none, light],
  0x2539: [heavy, light, none, heavy],
  0x253a: [heavy, heavy, none, light],
  0x253b: [heavy, heavy, none, heavy],
  0x253c: [light, light, light, light],
  0x253d: [light, light, light, heavy],
  0x253e: [light, heavy, light, light],
  0x253f: [light, heavy, light, heavy],
  0x2540: [heavy, light, light, light],
  0x2541: [light, light, heavy, light],
  0x2542: [heavy, light, heavy, light],
  0x2543: [heavy, light, light, heavy],
  0x2544: [heavy, heavy, light, light],
  0x2545: [light, light, heavy, heavy],
  0x2546: [light, heavy, heavy, light],
  0x2547: [heavy, heavy, light, heavy],
  0x2548: [light, heavy, heavy, heavy],
  0x2549: [heavy, light, heavy, heavy],
  0x254a: [heavy, heavy, heavy, light],
  0x254b: [heavy, heavy, heavy, heavy],
  0x2550: [none, double, none, double],
  0x2551: [double, none, double, none],
  0x2552: [none, double, light, none],
  0x2553: [none, light, double, none],
  0x2554: [none, double, double, none],
  0x2555: [none, none, light, double],
  0x2556: [none, none, double, light],
  0x2557: [none, none, double, double],
  0x2558: [light, double, none, none],
  0x2559: [double, light, none, none],
  0x255a: [double, double, none, none],
  0x255b: [light, none, none, double],
  0x255c: [double, none, none, light],
  0x255d: [double, none, none, double],
  0x255e: [light, double, light, none],
  0x255f: [double, light, double, none],
  0x2560: [double, double, double, none],
  0x2561: [light, none, light, double],
  0x2562: [double, none, double, light],
  0x2563: [double, none, double, double],
  0x2564: [none, double, light, double],
  0x2565: [none, light, double, light],
  0x2566: [none, double, double, double],
  0x2567: [light, double, none, double],
  0x2568: [double, light, none, light],
  0x2569: [double, double, none, double],
  0x256a: [light, double, light, double],
  0x256b: [double, light, double, light],
  0x256c: [double, double, double, double],
  0x2574: [none, none, none, light],
  0x2575: [light, none, none, none],
  0x2576: [none, light, none, none],
  0x2577: [none, none, light, none],
  0x2578: [none, none, none, heavy],
  0x2579: [heavy, none, none, none],
  0x257a: [none, heavy, none, none],
  0x257b: [none, none, heavy, none],
  0x257c: [none, heavy, none, light],
  0x257d: [light, none, heavy, none],
  0x257e: [none, light, none, heavy],
  0x257f: [heavy, none, light, none],
};

export function canRenderBoxDrawing(
  text: string
): boolean {
  const codePoint = singleCodePoint(text);
  if (codePoint === undefined) {
    return false;
  }
  return (
    (codePoint >= 0x2500 && codePoint <= 0x259f) ||
    (codePoint >= 0x2800 && codePoint <= 0x28ff)
  );
}

export function drawBoxDrawing(
  context: BoxDrawingCanvasContext,
  text: string,
  rect: Rect
): boolean {
  const codePoint = singleCodePoint(text);
  if (codePoint === undefined) {
    return false;
  }

  if (codePoint >= 0x2500 && codePoint <= 0x257f) {
    return drawBoxDrawingCodePoint(context, codePoint, rect);
  }
  if (codePoint >= 0x2580 && codePoint <= 0x259f) {
    return drawBlockElement(context, codePoint, rect);
  }
  if (codePoint >= 0x2800 && codePoint <= 0x28ff) {
    return drawBraille(context, codePoint, rect);
  }
  return false;
}

function singleCodePoint(
  text: string
): number | undefined {
  const characters = Array.from(text);
  if (characters.length !== 1) {
    return undefined;
  }
  return characters[0]?.codePointAt(0);
}

function drawBoxDrawingCodePoint(
  context: BoxDrawingCanvasContext,
  codePoint: number,
  rect: Rect
): boolean {
  const spec = lineSpecs[codePoint];
  if (spec) {
    drawCellLines(context, spec, rect);
    return true;
  }

  switch (codePoint) {
  case 0x2504: drawDashedHorizontal(context, rect, light, 3); return true;
  case 0x2505: drawDashedHorizontal(context, rect, heavy, 3); return true;
  case 0x2506: drawDashedVertical(context, rect, light, 3); return true;
  case 0x2507: drawDashedVertical(context, rect, heavy, 3); return true;
  case 0x2508: drawDashedHorizontal(context, rect, light, 4); return true;
  case 0x2509: drawDashedHorizontal(context, rect, heavy, 4); return true;
  case 0x250a: drawDashedVertical(context, rect, light, 4); return true;
  case 0x250b: drawDashedVertical(context, rect, heavy, 4); return true;
  case 0x254c: drawDashedHorizontal(context, rect, light, 2); return true;
  case 0x254d: drawDashedHorizontal(context, rect, heavy, 2); return true;
  case 0x254e: drawDashedVertical(context, rect, light, 2); return true;
  case 0x254f: drawDashedVertical(context, rect, heavy, 2); return true;
  case 0x2571: drawDiagonal(context, rect, false); return true;
  case 0x2572: drawDiagonal(context, rect, true); return true;
  case 0x2573:
    drawDiagonal(context, rect, false);
    drawDiagonal(context, rect, true);
    return true;
  case 0x256d: drawArc(context, rect, "topLeft"); return true;
  case 0x256e: drawArc(context, rect, "topRight"); return true;
  case 0x256f: drawArc(context, rect, "bottomRight"); return true;
  case 0x2570: drawArc(context, rect, "bottomLeft"); return true;
  default:
    return false;
  }
}

function strokeMetrics(
  rect: Rect
): StrokeMetrics {
  const unit = Math.max(1, Math.round(Math.min(rect.width, rect.height) / 16));
  return {
    light: unit,
    heavy: unit * 2,
    doubleGap: unit,
  };
}

function drawCellLines(
  context: BoxDrawingCanvasContext,
  spec: Spec,
  rect: Rect
): void {
  const metrics = strokeMetrics(rect);
  const edges: Array<[LineWeight, Direction]> = [
    [spec[0], "north"],
    [spec[1], "east"],
    [spec[2], "south"],
    [spec[3], "west"],
  ];
  for (const [weight, direction] of edges.sort((lhs, rhs) => lhs[0] - rhs[0])) {
    drawHalfStroke(context, weight, direction, rect, metrics);
  }
}

function drawHalfStroke(
  context: BoxDrawingCanvasContext,
  weight: LineWeight,
  direction: Direction,
  rect: Rect,
  metrics: StrokeMetrics
): void {
  if (weight === none) {
    return;
  }

  const cx = rect.x + rect.width / 2;
  const cy = rect.y + rect.height / 2;
  const maxX = rect.x + rect.width;
  const maxY = rect.y + rect.height;

  const segment = (thickness: number, offset: number) => {
    switch (direction) {
    case "north":
      context.fillRect(cx - thickness / 2 + offset, rect.y, thickness, cy - rect.y + thickness / 2);
      break;
    case "south":
      context.fillRect(
        cx - thickness / 2 + offset,
        cy - thickness / 2,
        thickness,
        maxY - cy + thickness / 2
      );
      break;
    case "west":
      context.fillRect(rect.x, cy - thickness / 2 + offset, cx - rect.x + thickness / 2, thickness);
      break;
    case "east":
      context.fillRect(
        cx - thickness / 2,
        cy - thickness / 2 + offset,
        maxX - cx + thickness / 2,
        thickness
      );
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

function drawDashedHorizontal(
  context: BoxDrawingCanvasContext,
  rect: Rect,
  weight: LineWeight,
  segments: number
): void {
  const metrics = strokeMetrics(rect);
  const thickness = weight === heavy ? metrics.heavy : metrics.light;
  const segmentWidth = rect.width / segments;
  const dashWidth = segmentWidth * 0.55;
  const gapWidth = segmentWidth - dashWidth;
  const cy = rect.y + rect.height / 2;
  for (let index = 0; index < segments; index += 1) {
    const x = rect.x + index * segmentWidth + gapWidth / 2;
    context.fillRect(x, cy - thickness / 2, dashWidth, thickness);
  }
}

function drawDashedVertical(
  context: BoxDrawingCanvasContext,
  rect: Rect,
  weight: LineWeight,
  segments: number
): void {
  const metrics = strokeMetrics(rect);
  const thickness = weight === heavy ? metrics.heavy : metrics.light;
  const segmentHeight = rect.height / segments;
  const dashHeight = segmentHeight * 0.55;
  const gapHeight = segmentHeight - dashHeight;
  const cx = rect.x + rect.width / 2;
  for (let index = 0; index < segments; index += 1) {
    const y = rect.y + index * segmentHeight + gapHeight / 2;
    context.fillRect(cx - thickness / 2, y, thickness, dashHeight);
  }
}

function drawDiagonal(
  context: BoxDrawingCanvasContext,
  rect: Rect,
  descending: boolean
): void {
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

function drawArc(
  context: BoxDrawingCanvasContext,
  rect: Rect,
  corner: Corner
): void {
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

function drawBlockElement(
  context: BoxDrawingCanvasContext,
  codePoint: number,
  rect: Rect
): boolean {
  const maxX = rect.x + rect.width;
  const maxY = rect.y + rect.height;

  const lowerEighths = (count: number) => {
    const height = rect.height * count / 8;
    context.fillRect(rect.x, maxY - height, rect.width, height);
  };
  const leftEighths = (count: number) => {
    const width = rect.width * count / 8;
    context.fillRect(rect.x, rect.y, width, rect.height);
  };

  switch (codePoint) {
  case 0x2580: context.fillRect(rect.x, rect.y, rect.width, rect.height / 2); return true;
  case 0x2581: lowerEighths(1); return true;
  case 0x2582: lowerEighths(2); return true;
  case 0x2583: lowerEighths(3); return true;
  case 0x2584: lowerEighths(4); return true;
  case 0x2585: lowerEighths(5); return true;
  case 0x2586: lowerEighths(6); return true;
  case 0x2587: lowerEighths(7); return true;
  case 0x2588: context.fillRect(rect.x, rect.y, rect.width, rect.height); return true;
  case 0x2589: leftEighths(7); return true;
  case 0x258a: leftEighths(6); return true;
  case 0x258b: leftEighths(5); return true;
  case 0x258c: leftEighths(4); return true;
  case 0x258d: leftEighths(3); return true;
  case 0x258e: leftEighths(2); return true;
  case 0x258f: leftEighths(1); return true;
  case 0x2590:
    context.fillRect(rect.x + rect.width / 2, rect.y, rect.width / 2, rect.height);
    return true;
  case 0x2591: drawShade(context, rect, "light"); return true;
  case 0x2592: drawShade(context, rect, "medium"); return true;
  case 0x2593: drawShade(context, rect, "dark"); return true;
  case 0x2594: context.fillRect(rect.x, rect.y, rect.width, rect.height / 8); return true;
  case 0x2595:
    context.fillRect(maxX - rect.width / 8, rect.y, rect.width / 8, rect.height);
    return true;
  case 0x2596: fillQuadrants(context, rect, ["bottomLeft"]); return true;
  case 0x2597: fillQuadrants(context, rect, ["bottomRight"]); return true;
  case 0x2598: fillQuadrants(context, rect, ["topLeft"]); return true;
  case 0x2599: fillQuadrants(context, rect, ["topLeft", "bottomLeft", "bottomRight"]); return true;
  case 0x259a: fillQuadrants(context, rect, ["topLeft", "bottomRight"]); return true;
  case 0x259b: fillQuadrants(context, rect, ["topLeft", "topRight", "bottomLeft"]); return true;
  case 0x259c: fillQuadrants(context, rect, ["topLeft", "topRight", "bottomRight"]); return true;
  case 0x259d: fillQuadrants(context, rect, ["topRight"]); return true;
  case 0x259e: fillQuadrants(context, rect, ["topRight", "bottomLeft"]); return true;
  case 0x259f: fillQuadrants(context, rect, ["topRight", "bottomLeft", "bottomRight"]); return true;
  default:
    return false;
  }
}

function fillQuadrants(
  context: BoxDrawingCanvasContext,
  rect: Rect,
  quadrants: Corner[]
): void {
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

function drawShade(
  context: BoxDrawingCanvasContext,
  rect: Rect,
  density: "light" | "medium" | "dark"
): void {
  const pixels = density === "light"
    ? [[0, 0]]
    : density === "medium"
      ? [[0, 0], [1, 1]]
      : [[0, 0], [1, 0], [0, 1]];

  for (let y = rect.y; y < rect.y + rect.height; y += 2) {
    for (let x = rect.x; x < rect.x + rect.width; x += 2) {
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

// Bit -> (column, row) layout for the 2x4 braille mosaic. Mirrors
// `BrailleCell.bit(x:y:)` in `Sources/Core/BrailleCanvas.swift` so that
// every glyph emitted by `BrailleCanvas` round-trips visually. Each set
// bit fills its sub-cell rectangle solid (rather than drawing a font-style
// dot) so that adjacent set bits — both within and across cells — connect
// without visible mid-fill spacing, and a fully-set mask renders identical
// to U+2588 FULL BLOCK.
const brailleSubpixels: ReadonlyArray<readonly [bit: number, col: number, row: number]> = [
  [0x01, 0, 0], [0x08, 1, 0],
  [0x02, 0, 1], [0x10, 1, 1],
  [0x04, 0, 2], [0x20, 1, 2],
  [0x40, 0, 3], [0x80, 1, 3],
];

function drawBraille(
  context: BoxDrawingCanvasContext,
  codePoint: number,
  rect: Rect
): boolean {
  const mask = codePoint - 0x2800;
  if (mask === 0) {
    // U+2800 (BRAILLE PATTERN BLANK) renders as whitespace.
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
