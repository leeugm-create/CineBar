import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import {
  chmodSync,
  copyFileSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const toolsDirectory = dirname(dirname(fileURLToPath(import.meta.url)));
const publisher = join(toolsDirectory, "publish_sparkle_update.sh");

const createFixture = () => {
  const root = mkdtempSync(join(tmpdir(), "cinebar-publisher-test."));
  const fixturePublisher = join(root, "CineBar/Tools/publish_sparkle_update.sh");
  const signer = join(
    root,
    "CineBar/.vendor/Sparkle-2.9.2/bin/sign_update",
  );
  const archive = join(root, "update.zip");
  const appcast = join(root, "CineBarWebsite/public/appcast.xml");

  mkdirSync(dirname(fixturePublisher), { recursive: true });
  mkdirSync(dirname(signer), { recursive: true });
  mkdirSync(dirname(appcast), { recursive: true });
  copyFileSync(publisher, fixturePublisher);
  chmodSync(fixturePublisher, 0o755);
  writeFileSync(
    signer,
    `#!/bin/bash
set -euo pipefail
length=$(wc -c < "$1" | tr -d ' ')
printf 'sparkle:edSignature="fixture-signature" length="%s"\\n' "$length"
`,
  );
  chmodSync(signer, 0o755);
  writeFileSync(archive, "fixture archive");

  const publish = (build, publishedAt = "2026-07-30") =>
    spawnSync(
      fixturePublisher,
      [
        archive,
        `https://example.com/CineBar-${build}.zip`,
        "0.8.3",
        String(build),
        publishedAt,
      ],
      { encoding: "utf8" },
    );
  const xpath = (expression) =>
    execFileSync("xmllint", ["--xpath", expression, appcast], {
      encoding: "utf8",
    }).trimEnd();

  return { appcast, publish, root, xpath };
};

test("publishes self-contained Build 17 notes and an RFC822 UTC date", (t) => {
  const fixture = createFixture();
  t.after(() => rmSync(fixture.root, { recursive: true, force: true }));

  const result = fixture.publish(17);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(
    fixture.xpath(
      'string(//*[local-name()="item"]/*[local-name()="pubDate"])',
    ),
    "Thu, 30 Jul 2026 00:00:00 +0000",
  );
  const description = fixture.xpath(
    'string(//*[local-name()="item"]/*[local-name()="description"])',
  );
  assert.match(description, /新增经过 CineBar 独立签名验证的应用内更新/);
  assert.match(description, /后续版本可在 CineBar 内安装并重新启动/);
  assert.match(description, /Build 16 用户本次需要从 GitHub Releases 手动安装/);
});

test("rejects an invalid calendar date without changing the appcast", (t) => {
  const fixture = createFixture();
  t.after(() => rmSync(fixture.root, { recursive: true, force: true }));

  assert.equal(fixture.publish(17).status, 0);
  const before = readFileSync(fixture.appcast);
  const result = fixture.publish(18, "2026-02-30");

  assert.notEqual(result.status, 0);
  assert.deepEqual(readFileSync(fixture.appcast), before);
});

test("rejects lower and equal builds atomically but accepts a higher build", (t) => {
  const fixture = createFixture();
  t.after(() => rmSync(fixture.root, { recursive: true, force: true }));

  assert.equal(fixture.publish(17).status, 0);
  const before = readFileSync(fixture.appcast);
  assert.notEqual(fixture.publish(16).status, 0);
  assert.deepEqual(readFileSync(fixture.appcast), before);
  assert.notEqual(fixture.publish(17).status, 0);
  assert.deepEqual(readFileSync(fixture.appcast), before);

  const result = fixture.publish(18);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(
    fixture.xpath(
      'string(//*[local-name()="enclosure"]/@*[local-name()="version"])',
    ),
    "18",
  );
});
