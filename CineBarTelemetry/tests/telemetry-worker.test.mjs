import test from "node:test";
import assert from "node:assert/strict";

import worker, {
  hashInstallID,
  validateInstallPayload,
} from "../worker.js";

class MemoryD1 {
  constructor() {
    this.rows = new Map();
  }

  prepare(sql) {
    return new MemoryStatement(this, sql.replace(/\s+/g, " ").trim());
  }
}

class MemoryStatement {
  constructor(database, sql) {
    this.database = database;
    this.sql = sql;
    this.values = [];
  }

  bind(...values) {
    this.values = values;
    return this;
  }

  async run() {
    if (this.sql.startsWith("INSERT INTO installs")) {
      const [hash, firstSeen, lastSeen, appVersion, build, platform, osMajor,
        architecture, language] = this.values;
      const existing = this.database.rows.get(hash);
      this.database.rows.set(hash, {
        install_hash: hash,
        first_seen_at: existing?.first_seen_at ?? firstSeen,
        last_seen_at: lastSeen,
        app_version: appVersion,
        build,
        platform,
        os_major: osMajor,
        architecture,
        language,
      });
      return { success: true };
    }
    throw new Error(`Unsupported run query: ${this.sql}`);
  }

  async first() {
    if (this.sql.startsWith("SELECT COUNT(*) AS total_installs")) {
      return { total_installs: this.database.rows.size };
    }
    if (this.sql.startsWith("SELECT COUNT(*) AS active_installs")) {
      const [cutoff] = this.values;
      return {
        active_installs: [...this.database.rows.values()]
          .filter((row) => row.last_seen_at >= cutoff).length,
      };
    }
    throw new Error(`Unsupported first query: ${this.sql}`);
  }

  async all() {
    const groupMatch = this.sql.match(
      /SELECT (app_version|os_major|architecture|language), COUNT\(\*\) AS installs FROM installs GROUP BY (app_version|os_major|architecture|language)/,
    );
    if (!groupMatch) throw new Error(`Unsupported all query: ${this.sql}`);
    const key = groupMatch[1];
    const groups = new Map();
    for (const row of this.database.rows.values()) {
      groups.set(row[key], (groups.get(row[key]) ?? 0) + 1);
    }
    return {
      results: [...groups.entries()].map(([value, installs]) => ({
        value,
        installs,
      })),
    };
  }
}

const payload = (overrides = {}) => ({
  install_id: "123e4567-e89b-12d3-a456-426614174000",
  app_version: "0.8.3-test.10",
  build: 26,
  platform: "macOS",
  os_major: 15,
  architecture: "arm64",
  language: "zh-Hans",
  occurred_at: "2026-08-03T08:00:00.000Z",
  ...overrides,
});

const installRequest = (body, headers = {}) => new Request(
  "https://telemetry.cinebar.cc/v1/telemetry/install",
  {
    method: "POST",
    headers: { "content-type": "application/json", ...headers },
    body: JSON.stringify(body),
  },
);

const environment = () => ({
  DB: new MemoryD1(),
  TELEMETRY_HMAC_SECRET: "test-secret",
  TELEMETRY_ADMIN_TOKEN: "admin-token",
});

test("validates the fixed anonymous payload shape", () => {
  assert.equal(validateInstallPayload(payload()), null);
  assert.match(
    validateInstallPayload(payload({ architecture: "Intel" })),
    /architecture/,
  );
  assert.match(
    validateInstallPayload({ ...payload(), extra: true }),
    /unknown field/,
  );
});

test("HMAC hashing is stable without returning the raw install id", async () => {
  const first = await hashInstallID(payload().install_id, "test-secret");
  const second = await hashInstallID(payload().install_id, "test-secret");
  const other = await hashInstallID("223e4567-e89b-12d3-a456-426614174000", "test-secret");
  assert.equal(first, second);
  assert.notEqual(first, other);
  assert.match(first, /^[0-9a-f]{64}$/);
});

test("accepts an install report and upserts the same anonymous installation", async () => {
  const env = environment();
  const first = await worker.fetch(installRequest(payload()), env);
  assert.equal(first.status, 202);
  assert.deepEqual(await first.json(), { accepted: true });
  const second = await worker.fetch(
    installRequest(payload({ app_version: "0.8.3-test.11", build: 27 })),
    env,
  );
  assert.equal(second.status, 202);
  assert.equal(env.DB.rows.size, 1);
  const row = [...env.DB.rows.values()][0];
  assert.equal(row.app_version, "0.8.3-test.11");
  assert.equal(row.build, 27);
  assert.equal(row.install_hash.includes(payload().install_id), false);
});

test("rejects malformed reports and never writes them", async () => {
  const env = environment();
  const response = await worker.fetch(
    installRequest(payload({ install_id: "not-an-id" })),
    env,
  );
  assert.equal(response.status, 400);
  assert.equal(env.DB.rows.size, 0);
});

test("protects the aggregate summary and does not expose hashes", async () => {
  const env = environment();
  await worker.fetch(installRequest(payload()), env);
  const unauthorized = await worker.fetch(
    new Request("https://telemetry.cinebar.cc/v1/telemetry/summary?range=30d"),
    env,
  );
  assert.equal(unauthorized.status, 401);

  const response = await worker.fetch(
    new Request("https://telemetry.cinebar.cc/v1/telemetry/summary?range=30d", {
      headers: { authorization: "Bearer admin-token" },
    }),
    env,
  );
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.total_installs, 1);
  assert.equal(body.active_installs, 1);
  assert.equal("install_hash" in body, false);
  assert.equal("install_id" in body, false);
});

test("health is cache-free and contains the current service version", async () => {
  const response = await worker.fetch(
    new Request("https://telemetry.cinebar.cc/health"),
    environment(),
  );
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.deepEqual(
    { ok: body.ok, service: body.service, version: body.version },
    { ok: true, service: "cinebar-telemetry", version: "0.8.3-test.10" },
  );
  assert.equal(response.headers.get("cache-control"), "no-store");
});
