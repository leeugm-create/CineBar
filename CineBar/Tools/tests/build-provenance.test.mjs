import test from "node:test";
import assert from "node:assert/strict";
import { chmod, cp, mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import { execFile } from "node:child_process";

const run = promisify(execFile);
const helper = new URL("../check_build_provenance.sh", import.meta.url);

test("emits a clean committed-source manifest and rejects dirty build inputs", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "cinebar-provenance-"));
  await run("git", ["init", "-q"], { cwd: root });
  await run("git", ["config", "user.email", "tests@cinebar.local"], { cwd: root });
  await run("git", ["config", "user.name", "CineBar Tests"], { cwd: root });
  await writeFile(path.join(root, "tracked.txt"), "clean\n");
  await run("git", ["add", "tracked.txt"], { cwd: root });
  await run("git", ["commit", "-qm", "fixture"], { cwd: root });
  const script = path.join(root, "check_build_provenance.sh");
  await cp(helper, script);
  await chmod(script, 0o755);

  const clean = await run(script, [root, "0.8.3", "24", "tracked.txt"]);
  const manifest = JSON.parse(clean.stdout);
  assert.equal(manifest.version, "0.8.3");
  assert.equal(manifest.build, "24");
  assert.equal(manifest.sourceTreeStatus, "clean");
  assert.match(manifest.commit, /^[0-9a-f]{40}$/);

  await writeFile(path.join(root, "unrelated.tmp"), "ignored untracked output\n");
  const stillClean = await run(script, [root, "0.8.3", "24", "tracked.txt"]);
  assert.equal(JSON.parse(stillClean.stdout).sourceTreeStatus, "clean");

  await writeFile(path.join(root, "tracked.txt"), "dirty\n");
  await assert.rejects(
    run(script, [root, "0.8.3", "24", "tracked.txt"]),
    (error) => {
      assert.match(error.stderr, /Refusing to build from dirty source inputs/);
      return true;
    },
  );
});
