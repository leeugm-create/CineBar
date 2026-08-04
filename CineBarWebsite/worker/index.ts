/** Cloudflare Worker entry point for the vinext-starter template. */
import { handleImageOptimization, DEFAULT_DEVICE_SIZES, DEFAULT_IMAGE_SIZES } from "vinext/server/image-optimization";
import handler from "vinext/server/app-router-entry";

interface Env {
  ASSETS: Fetcher;
  DB: D1Database;
  /** Shared with the telemetry Worker; never sent to browser code. */
  CINEBAR_TELEMETRY_ADMIN_TOKEN?: string;
  IMAGES: {
    input(stream: ReadableStream): {
      transform(options: Record<string, unknown>): {
        output(options: { format: string; quality: number }): Promise<{ response(): Response }>;
      };
    };
  };
}

interface ExecutionContext {
  waitUntil(promise: Promise<unknown>): void;
  passThroughOnException(): void;
}

const OFFICIAL_HOST = "cinebar.cc";
const HSTS_POLICY = "max-age=31536000; includeSubDomains";
const CONTENT_SECURITY_POLICY = "default-src 'self'; base-uri 'self'; form-action 'self' https://www.paypal.com; frame-ancestors 'none'; img-src 'self' data: blob:; object-src 'none'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; connect-src 'self' https://api.cinebar.cc https://share.cinebar.cc; font-src 'self' data:; upgrade-insecure-requests";
const PERMISSIONS_POLICY = "accelerometer=(), camera=(), geolocation=(), microphone=(), payment=(), usb=()";

function isAdminAnalyticsRequest(request: Request, env: Env): boolean {
  const token = env.CINEBAR_TELEMETRY_ADMIN_TOKEN;
  if (!token) return false;

  const authorization = request.headers.get("authorization");
  if (!authorization?.startsWith("Basic ")) return false;

  try {
    return atob(authorization.slice("Basic ".length)) === `admin:${token}`;
  } catch {
    return false;
  }
}

function adminAnalyticsUnauthorized(url: URL): Response {
  const response = new Response("Administrator authentication required.", {
    status: 401,
    headers: {
      "cache-control": "no-store",
      "content-type": "text/plain; charset=utf-8",
      "www-authenticate": 'Basic realm="CineBar Analytics", charset="UTF-8"',
    },
  });
  return addSecurityHeaders(response, url);
}

function addSecurityHeaders(response: Response, url: URL): Response {
  const headers = new Headers(response.headers);
  headers.set("content-security-policy", CONTENT_SECURITY_POLICY);
  headers.set("permissions-policy", PERMISSIONS_POLICY);
  headers.set("referrer-policy", "strict-origin-when-cross-origin");
  headers.set("x-content-type-options", "nosniff");
  headers.set("x-frame-options", "DENY");
  if (url.protocol === "https:") {
    headers.set("strict-transport-security", HSTS_POLICY);
  }
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

// Image security config. SVG sources with .svg extension auto-skip the
// optimization endpoint on the client side (served directly, no proxy).
// To route SVGs through the optimizer (with security headers), set
// dangerouslyAllowSVG: true in next.config.js and uncomment below:
// const imageConfig: ImageConfig = { dangerouslyAllowSVG: true };

const worker = {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);

    if (url.hostname === OFFICIAL_HOST && url.protocol === "http:") {
      url.protocol = "https:";
      return Response.redirect(url, 308);
    }

    // The telemetry API is protected, but the dashboard must be protected too.
    // Otherwise a guessed URL would reveal aggregate installation counts.
    if (url.pathname === "/admin/analytics" && !isAdminAnalyticsRequest(request, env)) {
      return adminAnalyticsUnauthorized(url);
    }

    if (request.method === "GET" || request.method === "HEAD") {
      const assetResponse = await env.ASSETS.fetch(request);
      if (assetResponse.status !== 404) {
        return addSecurityHeaders(assetResponse, url);
      }
    }

    if (url.pathname === "/_vinext/image") {
      const allowedWidths = [...DEFAULT_DEVICE_SIZES, ...DEFAULT_IMAGE_SIZES];
      const response = await handleImageOptimization(request, {
        fetchAsset: (path) => env.ASSETS.fetch(new Request(new URL(path, request.url))),
        transformImage: async (body, { width, format, quality }) => {
          const result = await env.IMAGES.input(body).transform(width > 0 ? { width } : {}).output({ format, quality });
          return result.response();
        },
      }, allowedWidths);
      return addSecurityHeaders(response, url);
    }

    const response = await handler.fetch(request, env, ctx);
    return addSecurityHeaders(response, url);
  },
};

export default worker;
