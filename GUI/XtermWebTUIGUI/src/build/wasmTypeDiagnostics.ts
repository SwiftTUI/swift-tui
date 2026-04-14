import { createHash } from "node:crypto";

const wasmMagic = [0x00, 0x61, 0x73, 0x6d] as const;
const wasmVersion = [0x01, 0x00, 0x00, 0x00] as const;
const typeSectionID = 1;
const functionTypeTag = 0x60;
const browserMaxTypeParameterCount = 1000;

interface SectionHeader {
  id: number;
  size: number;
  startOffset: number;
  nextOffset: number;
}

interface ReadUnsignedLEB128Result {
  nextOffset: number;
  value: number;
}

interface WasmTypeSummary {
  maxTypeParameterCount?: number;
  maxTypeParameterTypeIndex?: number;
  note?: string;
  overBrowserLimitTypes: number[];
  topParameterCounts: Array<{
    parameterCount: number;
    typeIndex: number;
  }>;
  typeCount?: number;
}

export function formatWasmTypeDiagnostics(
  bytes: Uint8Array
): string {
  const summary = summarizeWasmTypes(bytes);
  const components = [
    `size=${bytes.byteLength} bytes`,
    `sha256=${createHash("sha256").update(bytes).digest("hex")}`,
  ];

  if (summary.typeCount !== undefined) {
    components.push(`typeCount=${summary.typeCount}`);
  }
  if (summary.maxTypeParameterCount !== undefined) {
    components.push(`maxTypeParameterCount=${summary.maxTypeParameterCount}`);
  }
  if (summary.maxTypeParameterTypeIndex !== undefined) {
    components.push(`maxTypeParameterTypeIndex=${summary.maxTypeParameterTypeIndex}`);
  }
  if (summary.overBrowserLimitTypes.length > 0) {
    components.push(`overBrowserLimitTypes=${summary.overBrowserLimitTypes.join(",")}`);
  }
  if (summary.topParameterCounts.length > 0) {
    components.push(
      `largestTypes=${summary.topParameterCounts.map(formatLargestTypeSummary).join(";")}`
    );
  }
  if (summary.note) {
    components.push(`note=${summary.note}`);
  }

  return `wasm diagnostics: ${components.join(", ")}`;
}

function formatLargestTypeSummary(
  summary: { parameterCount: number; typeIndex: number }
): string {
  return `${summary.typeIndex}:${summary.parameterCount}`;
}

function summarizeWasmTypes(
  bytes: Uint8Array
): WasmTypeSummary {
  if (!hasExpectedPrefix(bytes, 0, wasmMagic)) {
    return {
      note: "missing wasm magic header",
      overBrowserLimitTypes: [],
      topParameterCounts: [],
    };
  }
  if (!hasExpectedPrefix(bytes, wasmMagic.length, wasmVersion)) {
    return {
      note: "missing wasm version header",
      overBrowserLimitTypes: [],
      topParameterCounts: [],
    };
  }

  let offset = 8;
  while (offset < bytes.length) {
    let sectionHeader: SectionHeader;
    try {
      sectionHeader = readSectionHeader(bytes, offset);
    } catch (error) {
      return {
        note: `failed to read section header at byte ${offset}: ${describeError(error)}`,
        overBrowserLimitTypes: [],
        topParameterCounts: [],
      };
    }

    if (sectionHeader.id === typeSectionID) {
      return summarizeTypeSection(bytes, sectionHeader.startOffset, sectionHeader.nextOffset);
    }

    offset = sectionHeader.nextOffset;
  }

  return {
    note: "module has no type section",
    overBrowserLimitTypes: [],
    topParameterCounts: [],
  };
}

function summarizeTypeSection(
  bytes: Uint8Array,
  startOffset: number,
  endOffset: number
): WasmTypeSummary {
  let offset = startOffset;
  let typeCount: number;

  try {
    const result = readUnsignedLEB128(bytes, offset);
    typeCount = result.value;
    offset = result.nextOffset;
  } catch (error) {
    return {
      note: `failed to read type vector length: ${describeError(error)}`,
      overBrowserLimitTypes: [],
      topParameterCounts: [],
    };
  }

  let maxTypeParameterCount = -1;
  let maxTypeParameterTypeIndex = -1;
  const overBrowserLimitTypes: number[] = [];
  const topParameterCounts: Array<{ parameterCount: number; typeIndex: number }> = [];

  for (let typeIndex = 0; typeIndex < typeCount; typeIndex += 1) {
    if (offset >= endOffset) {
      return {
        note: `type section ended early while reading type ${typeIndex}`,
        overBrowserLimitTypes,
        topParameterCounts,
        typeCount,
      };
    }

    const typeTag = bytes[offset];
    offset += 1;
    if (typeTag !== functionTypeTag) {
      return {
        note: `unexpected type tag 0x${typeTag.toString(16)} at type ${typeIndex}`,
        overBrowserLimitTypes,
        topParameterCounts,
        typeCount,
      };
    }

    let parameterCount: number;
    try {
      const result = readUnsignedLEB128(bytes, offset);
      parameterCount = result.value;
      offset = result.nextOffset;
    } catch (error) {
      return {
        note: `failed to read parameter count for type ${typeIndex}: ${describeError(error)}`,
        overBrowserLimitTypes,
        topParameterCounts,
        typeCount,
      };
    }

    if (parameterCount > maxTypeParameterCount) {
      maxTypeParameterCount = parameterCount;
      maxTypeParameterTypeIndex = typeIndex;
    }
    if (parameterCount > browserMaxTypeParameterCount) {
      overBrowserLimitTypes.push(typeIndex);
    }
    updateLargestTypeSummaries(topParameterCounts, typeIndex, parameterCount);

    offset += parameterCount;
    if (offset > endOffset) {
      return {
        note: `parameter vector for type ${typeIndex} overruns type section`,
        overBrowserLimitTypes,
        topParameterCounts,
        typeCount,
      };
    }

    let resultCount: number;
    try {
      const result = readUnsignedLEB128(bytes, offset);
      resultCount = result.value;
      offset = result.nextOffset;
    } catch (error) {
      return {
        note: `failed to read result count for type ${typeIndex}: ${describeError(error)}`,
        overBrowserLimitTypes,
        topParameterCounts,
        typeCount,
      };
    }

    offset += resultCount;
    if (offset > endOffset) {
      return {
        note: `result vector for type ${typeIndex} overruns type section`,
        overBrowserLimitTypes,
        topParameterCounts,
        typeCount,
      };
    }
  }

  return {
    maxTypeParameterCount: maxTypeParameterCount >= 0 ? maxTypeParameterCount : undefined,
    maxTypeParameterTypeIndex: maxTypeParameterTypeIndex >= 0 ? maxTypeParameterTypeIndex : undefined,
    overBrowserLimitTypes,
    topParameterCounts,
    typeCount,
  };
}

function updateLargestTypeSummaries(
  summaries: Array<{ parameterCount: number; typeIndex: number }>,
  typeIndex: number,
  parameterCount: number
): void {
  summaries.push({ parameterCount, typeIndex });
  summaries.sort((left, right) => {
    if (right.parameterCount === left.parameterCount) {
      return left.typeIndex - right.typeIndex;
    }
    return right.parameterCount - left.parameterCount;
  });
  summaries.splice(5);
}

function readSectionHeader(
  bytes: Uint8Array,
  offset: number
): SectionHeader {
  if (offset >= bytes.length) {
    throw new Error("unexpected end of file");
  }

  const id = bytes[offset];
  const size = readUnsignedLEB128(bytes, offset + 1);
  const startOffset = size.nextOffset;
  const nextOffset = startOffset + size.value;
  if (nextOffset > bytes.length) {
    throw new Error(`section ${id} overruns file bounds`);
  }

  return {
    id,
    size: size.value,
    startOffset,
    nextOffset,
  };
}

function readUnsignedLEB128(
  bytes: Uint8Array,
  offset: number
): ReadUnsignedLEB128Result {
  let shift = 0;
  let value = 0;
  let nextOffset = offset;

  while (nextOffset < bytes.length) {
    const byte = bytes[nextOffset];
    nextOffset += 1;
    value |= (byte & 0x7f) << shift;
    if ((byte & 0x80) === 0) {
      return {
        nextOffset,
        value,
      };
    }
    shift += 7;
  }

  throw new Error("unterminated LEB128 value");
}

function hasExpectedPrefix(
  bytes: Uint8Array,
  startOffset: number,
  expected: readonly number[]
): boolean {
  if (startOffset + expected.length > bytes.length) {
    return false;
  }

  for (let index = 0; index < expected.length; index += 1) {
    if (bytes[startOffset + index] !== expected[index]) {
      return false;
    }
  }

  return true;
}

function describeError(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
