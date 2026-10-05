// The group cards' arithmetic (ios/Messages/TogetherCore.swift), compiled with
// swiftc and run on the Mac. Skipped where there is no swiftc.
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { copyFileSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const hasSwift = spawnSync("swiftc", ["--version"]).status === 0;

test("group card arithmetic", { skip: hasSwift ? false : "swiftc not installed" }, () => {
  const dir = mkdtempSync(join(tmpdir(), "together-"));
  copyFileSync(join(here, "../ios/Messages/TogetherCore.swift"), join(dir, "TogetherCore.swift"));
  copyFileSync(join(here, "TogetherCoreTest.swift"), join(dir, "main.swift"));
  const bin = join(dir, "t");
  const built = spawnSync("swiftc", [join(dir, "TogetherCore.swift"), join(dir, "main.swift"), "-o", bin], { encoding: "utf8" });
  assert.equal(built.status, 0, built.stderr);
  const run = spawnSync(bin, { encoding: "utf8" });
  assert.equal(run.status, 0, run.stdout + run.stderr);
});
