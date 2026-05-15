import { accessSync } from "node:fs";
import { delimiter, join } from "node:path";
import { spawn } from "node:child_process";

export interface RunCommandOptions {
  cwd?: string;
  env?: Record<string, string | undefined>;
}

export async function runCommand(
  cmd: string[],
  options: RunCommandOptions = {}
): Promise<string> {
  const executable = cmd[0];
  if (!executable) {
    throw new Error("cannot run an empty command");
  }

  const proc = spawn(executable, cmd.slice(1), {
    cwd: options.cwd,
    env: normalizeEnvironment(options.env),
    stdio: ["ignore", "pipe", "pipe"],
  });

  const stdoutChunks: Buffer[] = [];
  const stderrChunks: Buffer[] = [];
  proc.stdout.on("data", (chunk: Buffer) => {
    stdoutChunks.push(chunk);
  });
  proc.stderr.on("data", (chunk: Buffer) => {
    stderrChunks.push(chunk);
  });

  const exitCode = await new Promise<number | null>((resolve, reject) => {
    proc.on("error", reject);
    proc.on("close", resolve);
  });
  const stdout = Buffer.concat(stdoutChunks).toString();
  const stderr = Buffer.concat(stderrChunks).toString();

  if (exitCode !== 0) {
    throw new Error([stdout, stderr].filter(Boolean).join("\n").trim() || `command failed: ${cmd.join(" ")}`);
  }

  return stdout;
}

export function findExecutable(
  name: string,
  pathValue: string | undefined = process.env.PATH
): string | undefined {
  for (const directory of pathValue?.split(delimiter) ?? []) {
    if (!directory) {
      continue;
    }
    const candidate = join(directory, name);
    try {
      accessSync(candidate);
      return candidate;
    } catch {
      continue;
    }
  }
  return undefined;
}

function normalizeEnvironment(
  env: Record<string, string | undefined> | undefined
): NodeJS.ProcessEnv | undefined {
  if (!env) {
    return undefined;
  }

  const normalized: NodeJS.ProcessEnv = {};
  for (const [key, value] of Object.entries(env)) {
    if (value !== undefined) {
      normalized[key] = value;
    }
  }
  return normalized;
}
