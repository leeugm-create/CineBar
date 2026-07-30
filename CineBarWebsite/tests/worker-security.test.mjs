import test, { after, before } from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createServer } from "node:net";
import http from "node:http";
import https from "node:https";

const wrangler = new URL("../node_modules/.bin/wrangler", import.meta.url);
const runningServers = [];

async function reservePort() {
  const server = createServer();
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  const address = server.address();
  await new Promise((resolve, reject) =>
    server.close((error) => (error ? reject(error) : resolve())),
  );
  return address.port;
}

function request({ protocol, port, path = "/", headers = {} }) {
  const client = protocol === "https" ? https : http;
  return new Promise((resolve, reject) => {
    const req = client.request(
      {
        protocol: `${protocol}:`,
        hostname: "127.0.0.1",
        port,
        path,
        method: "GET",
        headers,
        rejectUnauthorized: false,
      },
      (response) => {
        const chunks = [];
        response.on("data", (chunk) => chunks.push(chunk));
        response.on("end", () =>
          resolve({
            status: response.statusCode,
            headers: response.headers,
            body: Buffer.concat(chunks),
          }),
        );
      },
    );
    req.once("error", reject);
    req.end();
  });
}

async function startWrangler(protocol) {
  const port = await reservePort();
  const child = spawn(
    wrangler.pathname,
    [
      "dev",
      "--config",
      "wrangler.public.jsonc",
      "--local",
      "--local-protocol",
      protocol,
      "--port",
      String(port),
      "--persist-to",
      `.wrangler/security-test-${protocol}`,
      "--log-level",
      "error",
    ],
    {
      cwd: new URL("..", import.meta.url),
      env: { ...process.env, CI: "1", NO_COLOR: "1" },
      stdio: ["ignore", "pipe", "pipe"],
    },
  );

  const output = [];
  child.stdout.on("data", (chunk) => output.push(chunk));
  child.stderr.on("data", (chunk) => output.push(chunk));
  runningServers.push(child);

  const deadline = Date.now() + 30_000;
  while (Date.now() < deadline) {
    if (child.exitCode !== null) {
      throw new Error(
        `wrangler ${protocol} exited early:\n${Buffer.concat(output).toString()}`,
      );
    }
    try {
      const response = await request({ protocol, port });
      if (response.status) return { protocol, port };
    } catch {
      // Wrangler has not started listening yet.
    }
    await new Promise((resolve) => setTimeout(resolve, 150));
  }

  throw new Error(
    `wrangler ${protocol} did not become ready:\n${Buffer.concat(output).toString()}`,
  );
}

let httpServer;
let httpsServer;

before(async () => {
  httpServer = await startWrangler("http");
  httpsServer = await startWrangler("https");
});

after(async () => {
  for (const child of runningServers) {
    if (child.exitCode === null) child.kill("SIGTERM");
  }
  await Promise.all(
    runningServers.map(
      (child) =>
        new Promise((resolve) => {
          if (child.exitCode !== null) return resolve();
          child.once("exit", resolve);
          setTimeout(() => {
            if (child.exitCode === null) child.kill("SIGKILL");
          }, 3_000).unref();
        }),
    ),
  );
});

test("ignores forged forwarding headers in public social metadata", async () => {
  const response = await request({
    ...httpsServer,
    headers: {
      host: "cinebar.cc",
      "x-forwarded-host": "attacker.example",
      "x-forwarded-proto": "https",
    },
  });

  assert.equal(response.status, 200);
  const html = response.body.toString();
  assert.match(html, /https:\/\/cinebar\.cc\/og\.png/);
  assert.match(html, /https:\/\/cinebar\.cc\//);
  assert.doesNotMatch(html, /attacker\.example/);
});

test("redirects an apex HTTP path and query to the same HTTPS URL", async () => {
  const response = await request({
    ...httpServer,
    path: "/install?source=wechat&campaign=launch",
    headers: { host: "cinebar.cc" },
  });

  assert.equal(response.status, 308);
  assert.equal(
    response.headers.location,
    "https://cinebar.cc/install?source=wechat&campaign=launch",
  );
});

test("adds HSTS to dynamic and static HTTPS responses", async () => {
  for (const path of ["/", "/health", "/og.png"]) {
    const response = await request({
      ...httpsServer,
      path,
      headers: { host: "cinebar.cc" },
    });
    assert.equal(response.status, 200, path);
    assert.equal(
      response.headers["strict-transport-security"],
      "max-age=31536000; includeSubDomains",
      path,
    );
  }
});
