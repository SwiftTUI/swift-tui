export interface RunCommandOptions {
  cwd?: string;
  env?: Record<string, string | undefined>;
}

export async function runCommand(
  cmd: string[],
  options: RunCommandOptions = {}
): Promise<string> {
  const proc = Bun.spawn({
    cmd,
    cwd: options.cwd,
    env: options.env,
    stdout: "pipe",
    stderr: "pipe",
  });
  const [stdout, stderr, exitCode] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
    proc.exited,
  ]);

  if (exitCode !== 0) {
    throw new Error([stdout, stderr].filter(Boolean).join("\n").trim() || `command failed: ${cmd.join(" ")}`);
  }

  return stdout;
}
