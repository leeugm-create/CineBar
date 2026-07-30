export function GET() {
  return Response.json(
    {
      ok: true,
      service: "cinebar-website",
      version: "0.8.2-test",
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
