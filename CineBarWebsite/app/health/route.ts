export function GET() {
  return Response.json(
    {
      ok: true,
      service: "cinebar-website",
      version: "0.8.3-test.10-build-26",
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
