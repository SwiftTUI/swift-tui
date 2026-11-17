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

// The release lane transfers one release build to every part. A part that
// builds for itself, restores a foreign bundle, or drops out of the matrix
// would still report green, so the DAG and the transfer are pinned here.
describe("release-soundness", () => {
  const workflow = parse(readFileSync(new URL("../.github/workflows/release-soundness.yml", import.meta.url), "utf8"));
  const jobs = workflow.jobs;
  const build = jobs["release-build"];
  const parts = jobs["release-soundness"];
  const race = jobs["race-checks"];
  const archiveName = "release-tests-linux-amd64";
  const runs = (job: any, needle: string) => job.steps.filter((s: any) => s.run?.includes(needle));
  test("builds release once and publishes the release-kind bundle", () => {
    expect(build.steps.filter((s: any) => s.run === "Scripts/build_ci_release_test_bundle.sh")).toHaveLength(1);
    expect(runs(build, "ci_test_bundle.py pack --kind release")).toHaveLength(1);
    expect(build.steps.find((s: any) => s.uses?.startsWith("actions/upload-artifact") && s.with.name === archiveName)?.with.path).toBe("ci-test-bundle.tar.gz");
    // The memory record is the build's only diagnostic when the compiler is killed.
    const record = build.steps.find((s: any) => s.with?.name === "release-build-record");
    expect(record.if).toBe("always()");
    expect(record.with.path).toBe(".build/ci-release-build");
    const wrapper = readFileSync(new URL("build_ci_release_test_bundle.sh", import.meta.url), "utf8");
    expect(wrapper).toContain("sh ./Scripts/release_soundness_lane.sh --build-only");
    expect(wrapper).toContain('record_root=${SWIFTTUI_RELEASE_BUILD_RECORD_ROOT:-.build/ci-release-build}');
  });
  test("every part restores that bundle and never builds", () => {
    expect(parts.needs).toContain("release-build");
    expect(parts.container.image).toBe(build.container.image);
    expect(parts.container.options).toContain("SYS_PTRACE");
    expect(parts.steps.find((s: any) => s.uses?.startsWith("actions/download-artifact"))?.with.name).toBe(archiveName);
    expect(runs(parts, "tar -xzf ci-test-bundle.tar.gz")).toHaveLength(1);
    expect(runs(parts, 'release_soundness_lane.sh --prebuilt --part "$PART"')).toHaveLength(1);
    expect(runs(parts, "release_soundness_lane.sh --prebuilt --flaky-only")).toHaveLength(1);
    for (const step of parts.steps.filter((s: any) => s.run?.includes("release_soundness_lane.sh"))) {
      expect(step.run).toContain("--prebuilt");
    }
    expect(parts.steps.some((s: any) => s.uses?.startsWith("actions/cache"))).toBe(false);
  });
  test("the parts are core plus every manifest shard, and the record counts them", () => {
    const shards = readFileSync(new URL("data/runtime-shards.txt", import.meta.url), "utf8")
      .split("\n").filter((row) => /^[A-Za-z0-9_-]+\|/.test(row) && !row.startsWith("isolated|"))
      .map((row) => row.split("|")[0]);
    expect(shards.length).toBeGreaterThan(0);
    expect(parts.strategy.matrix.part).toEqual(["core", ...shards]);
    expect(parts.strategy["fail-fast"]).toBe(false);
    expect(runs(jobs.record, `"$count" -ne ${shards.length + 1}`)).toHaveLength(1);
    expect(jobs.record.needs).toEqual(["changes", "release-soundness", "race-checks"]);
  });
  test("the race variant keeps its own build: its flag changes the build signature", () => {
    expect(race.needs).toBe("changes");
    expect(runs(race, "release_soundness_lane.sh --race-checks")).toHaveLength(1);
    expect(runs(race, "--prebuilt")).toHaveLength(0);
    const refused = spawnSync("sh", ["Scripts/release_soundness_lane.sh", "--dry-run", "--prebuilt", "--race-checks"], {
      cwd: new URL("..", import.meta.url), encoding: "utf8",
    });
    expect(refused.status).toBe(2);
    expect(refused.stderr).toContain("--prebuilt cannot be combined with --race-checks");
  });
  test("a prebuilt part verifies the release bundle before its first launch", () => {
    const dryRun = spawnSync("sh", ["Scripts/release_soundness_lane.sh", "--dry-run", "--prebuilt", "--part", "core"], {
      cwd: new URL("..", import.meta.url), encoding: "utf8",
    });
    expect(dryRun.status).toBe(0);
    const lines = dryRun.stdout.split("\n").filter((line) => line.startsWith("==> "));
    expect(lines[0]).toBe("==> python3 Scripts/ci_test_bundle.py verify --kind release");
    expect(lines.some((line) => line.includes(" swift build "))).toBe(false);
    expect(lines.length).toBeGreaterThan(1);
    for (const line of lines.slice(1)) {
      expect(line).toContain(" swift test --build-system native -c release --skip-build ");
    }
  });
  // The watchdog validates its bounds against a deadline that is supposed to
  // be the job's cap. A cap lowered without its deadline leaves a watchdog
  // that cannot fire inside the job (Scripts/lib/step_watchdog.sh).
  test("each watchdog deadline is its job's cap, and the bounds fit inside it", () => {
    const seconds = (value: string) => Number.parseInt(value, 10);
    const partDeadline = seconds(workflow.env.SWIFTTUI_TEST_STEP_WATCHDOG_DEADLINE_SECONDS);
    const raceDeadline = seconds(race.env.SWIFTTUI_TEST_STEP_WATCHDOG_DEADLINE_SECONDS);
    expect(partDeadline).toBe(parts["timeout-minutes"] * 60);
    expect(raceDeadline).toBe(race["timeout-minutes"] * 60);
    const idle = seconds(workflow.env.SWIFTTUI_TEST_STEP_TIMEOUT_SECONDS);
    const busy = seconds(workflow.env.SWIFTTUI_TEST_STEP_BUSY_GRACE_SECONDS);
    const absolute = seconds(workflow.env.SWIFTTUI_TEST_STEP_ABSOLUTE_TIMEOUT_SECONDS);
    for (const deadline of [partDeadline, raceDeadline]) {
      expect(idle + busy + 10).toBeLessThan(deadline);
      expect(absolute + 10).toBeLessThan(deadline);
    }
    // The parts no longer build: a cap sized for a build would hide a hang.
    expect(parts["timeout-minutes"]).toBeLessThan(build["timeout-minutes"]);
  });
  // The bundle is built per file with the native build system. A launch that
  // named another build system would look for its products in another layout.
  test("the build and every launch name the same build system and per-file test compile", () => {
    const lane = readFileSync(new URL("release_soundness_lane.sh", import.meta.url), "utf8");
    expect(lane).toContain("SWIFTTUI_RELEASE_TESTS_PER_FILE=1 && export SWIFTTUI_RELEASE_TESTS_PER_FILE");
    const dryRun = spawnSync("sh", ["Scripts/release_soundness_lane.sh", "--dry-run"], {
      cwd: new URL("..", import.meta.url), encoding: "utf8",
    });
    expect(dryRun.status).toBe(0);
    const lines = dryRun.stdout.split("\n").filter((line) => line.startsWith("==> "));
    expect(lines[0]).toContain(" swift build --build-system native -c release --build-tests -Xswiftc -enable-testing");
    expect(lines.filter((line) => line.includes(" swift build "))).toHaveLength(1);
    for (const line of lines) expect(line).toContain(" --build-system native -c release ");
    const manifest = readFileSync(new URL("../Package.swift", import.meta.url), "utf8");
    expect(manifest).toContain('environment["SWIFTTUI_RELEASE_TESTS_PER_FILE"] == "1"');
    expect(manifest).toContain('["-no-whole-module-optimization", "-enable-batch-mode"], .when(configuration: .release)');
    expect(manifest).toContain("swiftSettings: swiftSettings() + perFileReleaseSwiftSettings,");
  });
});
