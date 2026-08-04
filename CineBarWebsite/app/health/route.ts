export function GET() {
  return Response.json(
    {
      ok: true,
      service: "cinebar-website",
      version: "0.8.3-test.12-build-28",
      utc: new Date().toISOString(),
    },
    {
      headers: {
        "cache-control": "no-store",
        "x-content-type-options": "nosniff",
      },
    },
  );
}
