import { stat, rename, rm } from "node:fs/promises";
import { resolve } from "node:path";
import { brotliDecompress } from "node:zlib";
import { promisify } from "node:util";

const decompressBrotli = promisify(brotliDecompress);
const wasmPath = resolve(
  import.meta.dir,
  "../../Examples/WebExample/pages-dist/TerminalApp/dist/assets/app.wasm"
);
const compressedWasmPath = `${wasmPath}.br`;
const pagesAssetLimit = 25 * 1024 * 1024;
const compressionOptions = parseCompressionOptions(process.argv.slice(2));

if (await browserWasmCompiles(wasmPath)) {
  await rm(compressedWasmPath, { force: true });
  await runCommand(
    [
      requireExecutable("brotli"),
      "-f",
      "-q",
      String(compressionOptions.quality),
      wasmPath,
      "-o",
      compressedWasmPath,
    ],
    {
      partialOutputPath: compressedWasmPath,
      timeoutMilliseconds: compressionOptions.timeoutMilliseconds,
    }
  );
  await validateCompressedBrowserWasm(compressedWasmPath);
  const size = await enforceCloudflareAssetLimit(compressedWasmPath);
  await rename(compressedWasmPath, wasmPath);
  console.log(`Brotli q${compressionOptions.quality}-compressed WebExample wasm to ${size} bytes`);
} else {
  await validateCompressedBrowserWasm(wasmPath);
  const size = await enforceCloudflareAssetLimit(wasmPath);
  console.log(`Brotli-compressed WebExample wasm already present at ${size} bytes`);
}

interface CompressionOptions {
  quality: number;
  timeoutMilliseconds: number;
}

function parseCompressionOptions(argv: string[]): CompressionOptions {
  let quality = 11;
  let timeoutMilliseconds = 360_000;

  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--quality" || argument === "-q") {
      quality = parseIntegerOption("quality", argv[index + 1]);
      index += 1;
      continue;
    }
    if (argument.startsWith("--quality=")) {
      quality = parseIntegerOption("quality", argument.slice("--quality=".length));
      continue;
    }
    if (argument === "--timeout-ms") {
      timeoutMilliseconds = parseIntegerOption("timeout-ms", argv[index + 1]);
      index += 1;
      continue;
    }
    if (argument.startsWith("--timeout-ms=")) {
      timeoutMilliseconds = parseIntegerOption("timeout-ms", argument.slice("--timeout-ms=".length));
    }
  }

  if (quality < 0 || quality > 11) {
    throw new Error(`Brotli quality must be between 0 and 11; got ${quality}`);
  }

  return {
    quality,
    timeoutMilliseconds,
  };
}

function parseIntegerOption(
  name: string,
  value: string | undefined
): number {
  if (!value) {
    throw new Error(`missing value for --${name}`);
  }

  const parsed = Number.parseInt(value, 10);
  if (!Number.isSafeInteger(parsed)) {
    throw new Error(`--${name} must be an integer; got ${value}`);
  }
  return parsed;
}

function requireExecutable(name: string): string {
  const executable = Bun.which(name);
  if (!executable) {
    throw new Error(`missing ${name} in PATH; install Brotli before packaging Website wasm`);
  }
  return executable;
}

async function browserWasmCompiles(path: string): Promise<boolean> {
  try {
    await WebAssembly.compile(await Bun.file(path).arrayBuffer());
    return true;
  } catch (error) {
    return false;
  }
}

async function validateCompressedBrowserWasm(path: string): Promise<void> {
  const compressedBytes = Buffer.from(await Bun.file(path).arrayBuffer());
  let decompressedBytes: Buffer;
  try {
    decompressedBytes = await decompressBrotli(compressedBytes);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    throw new Error(`Brotli-compressed wasm does not decompress (${path}): ${message}`);
  }

  try {
    await WebAssembly.compile(decompressedBytes);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    throw new Error(
      `Brotli-compressed wasm decompresses to invalid browser WebAssembly (${path}): ${message}`
    );
  }
}

async function enforceCloudflareAssetLimit(path: string): Promise<number> {
  const { size } = await stat(path);
  if (size >= pagesAssetLimit) {
    throw new Error(
      [
        `Brotli-compressed WebExample wasm is ${size} bytes`,
        "Still above Cloudflare Pages' 25 MiB single-file limit",
      ].join("\n")
    );
  }
  return size;
}

interface RunCommandOptions {
  partialOutputPath?: string;
  timeoutMilliseconds?: number;
}

async function runCommand(
  command: string[],
  options: RunCommandOptions = {}
): Promise<void> {
  const process = Bun.spawn({
    cmd: command,
    stdout: "pipe",
    stderr: "pipe",
  });
  let timedOut = false;
  const timeout = options.timeoutMilliseconds
    ? setTimeout(() => {
        timedOut = true;
        process.kill("SIGTERM");
      }, options.timeoutMilliseconds)
    : undefined;
  const [stdout, stderr, exitCode] = await Promise.all([
    new Response(process.stdout).text(),
    new Response(process.stderr).text(),
    process.exited,
  ]);
  if (timeout) {
    clearTimeout(timeout);
  }

  if (timedOut) {
    const partialOutputDescription = options.partialOutputPath
      ? await describePartialOutput(options.partialOutputPath)
      : "";
    throw new Error(
      [
        `command timed out after ${options.timeoutMilliseconds}ms: ${command.join(" ")}`,
        partialOutputDescription,
      ].filter(Boolean).join("\n")
    );
  }

  if (exitCode !== 0) {
    throw new Error([stdout, stderr].filter(Boolean).join("\n").trim() || "command failed");
  }
}

async function describePartialOutput(path: string): Promise<string> {
  try {
    const { size } = await stat(path);
    return `partial output: ${path} (${size} bytes)`;
  } catch {
    return `partial output: ${path} was not created`;
  }
}
