import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { parse } from "yaml";

test("the public gate forwards prebuilt mode to the runner's validation", () => {
  const result = spawnSync("sh", ["Scripts/test_gate.sh", "--prebuilt", "--clean"], {
    cwd: new URL("..", import.meta.url), encoding: "utf8",
  });
  expect(result.status).toBe(1);
  expect(result.stdout + result.stderr).toContain("--clean cannot be combined with --prebuilt");
});

// The cross-compile lanes are the only place WASI- and Android-conditional
// code is built. A lane that is optional, conditional, or absent from the
// aggregator's needs would report green without compiling anything.
describe("cross-compile lanes", () => {
  const jobs = parse(readFileSync(new URL("../.github/workflows/run-tests-linux.yml", import.meta.url), "utf8")).jobs;
  const aggregate = Object.values(jobs).find((j: any) => j.name === "Linux repo gate") as any;
  const android = jobs["android-cross-compile"];
  const runs = (needle: string) => android.steps.findIndex((s: any) => s.run?.includes(needle));
  test("the required gate needs both lanes, and neither can be skipped", () => {
    for (const id of ["wasi-cross-compile", "android-cross-compile"]) {
      expect(aggregate.needs).toContain(id);
      expect(jobs[id].if).toBeUndefined();
      expect(jobs[id]["continue-on-error"]).toBeUndefined();
      expect(jobs[id].container.image).toBe(jobs["native-build"].container.image);
      for (const step of jobs[id].steps) expect(step["continue-on-error"]).toBeUndefined();
    }
  });
  test("the Android lane provisions, compiles the contract triple and retains its evidence", () => {
    const install = runs("Scripts/install_android_cross_compile_tools.sh");
    const arm64 = runs("Scripts/check_android_cross_compile.sh --triple aarch64-unknown-linux-android28");
    expect(runs("Scripts/prepare_ci_container.sh")).toBeGreaterThanOrEqual(0);
    expect(install).toBeGreaterThanOrEqual(0);
    expect(arm64).toBeGreaterThan(install);
    expect(runs("--triple aarch64-unknown-linux-android28 --build-system native")).toBeGreaterThan(arm64);
    expect(runs("Scripts/check_android_cross_compile.sh --triple x86_64-unknown-linux-android28")).toBeGreaterThan(arm64);
    expect(android.env.SWIFTTUI_WARNINGS_AS_ERRORS).toBe("1");
    // The gate's watchdog deadline is this job's cap; it must be able to fire inside it.
    const gate = readFileSync(new URL("check_android_cross_compile.sh", import.meta.url), "utf8");
    expect(gate).toContain(`step_watchdog_deadline_seconds=${android["timeout-minutes"] * 60}\n`);
    expect(android.container.options).toContain("SYS_PTRACE");
    for (const step of android.steps.filter((s: any) => s.run)) expect(step.if).toBeUndefined();
    const upload = android.steps.find((s: any) => s.uses?.startsWith("actions/upload-artifact"));
    expect(upload.if).toBe("always()");
    expect(upload.with.path).toBe(".build/android-cross-compile");
    expect(upload.with["if-no-files-found"]).toBe("error");
    // Only downloaded archives may be cached: an installed SDK or NDK restored
    // from a cache would no longer be a clean-runner install.
    const cache = android.steps.find((s: any) => s.uses?.startsWith("actions/cache"));
    expect(cache.with.path).toBe("~/.cache/swifttui-android-archives");
    expect(cache.with.key).toContain("hashFiles('Scripts/lib/android_cross_compile_pins.sh')");
  });
});

// Exercise the actual workflow DAG and transfer contract. These checks catch
// dropped container settings, cross-architecture restores and missing shards.
for (const name of ["run-tests-linux", "macos-gate"]) {
  describe(name, () => {
    const workflow = parse(readFileSync(new URL(`../.github/workflows/${name}.yml`, import.meta.url), "utf8"));
    const jobs = workflow.jobs;
    const build = jobs["native-build"];
    const consumers = name === "run-tests-linux" ? [jobs.core, jobs.runtime] : [jobs["native-tests"]];
    const archiveName = name === "run-tests-linux" ? "native-tests-linux-${{ matrix.arch }}" : "native-tests-macos";
    test("builds once, then restores the same architecture in every test job", () => {
      expect(build.steps.filter((s: any) => s.run === "Scripts/build_ci_test_bundle.sh")).toHaveLength(1);
      expect(build.env.SWIFTTUI_WARNINGS_AS_ERRORS).toBe("1");
      expect(build.steps.find((s: any) => s.uses?.startsWith("actions/upload-artifact") && s.with.name === archiveName)?.with.path).toBe("ci-test-bundle.tar.gz");
      for (const job of consumers) {
        expect(job.needs).toBe("native-build");
        expect(job.steps.find((s: any) => s.uses?.startsWith("actions/download-artifact"))?.with.name).toBe(archiveName);
        expect(job.steps.some((s: any) => s.run?.includes("tar -xzf ci-test-bundle.tar.gz"))).toBe(true);
        expect(job.steps.some((s: any) => s.run?.includes("test_gate.sh --prebuilt --lane"))).toBe(true);
        expect(job.steps.some((s: any) => s.run?.includes("swift build --build-tests"))).toBe(false);
        if (name === "run-tests-linux") {
          expect(job.container.image).toBe(build.container.image);
          expect(job.container.options).toContain("SYS_PTRACE");
          expect(job["timeout-minutes"]).toBeGreaterThan(25);
        }
      }
    });
    test("retains the complete core and runtime test surface", () => {
      if (name === "macos-gate") {
        for (const job of [build, jobs["native-tests"], jobs["public-semantics"]]) {
          const setup = job.steps.find((s: any) => s.name === "Install swiftly and Swift toolchain");
          // --use rewrites the tracked version file, invalidating the receipt.
          expect(setup.run).toContain('swiftly install --assume-yes "$swift_version"');
          expect(setup.run).not.toContain("swiftly install --use");
        }
        expect(jobs["native-tests"].strategy.matrix.lane).toEqual(["core", "runtime:A", "runtime:B", "runtime:C"]);
        expect(jobs["macos-gate"].name).toBe("macOS repo gate");
        expect(jobs["macos-gate"].needs).toEqual(["changes", "native-build", "native-tests"]);
        expect(jobs["macos-gate"].steps.some((s: any) => s.run?.includes('test "$count" -eq 4'))).toBe(true);
      } else {
        expect(jobs.runtime.strategy.matrix).toContain('"shard":["A","B","C"]');
        const aggregate = Object.values(jobs).find((j: any) => j.name === "Linux repo gate") as any;
        expect(aggregate.needs).toContain("native-build");
        expect(aggregate.needs).toContain("core");
        expect(aggregate.needs).toContain("runtime");
      }
    });
  });
}
