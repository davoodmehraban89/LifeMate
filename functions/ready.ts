export const onRequest = async (): Promise<Response> =>
  new Response(JSON.stringify({
    status: "degraded",
    reason: "qa_backend_not_connected",
    product: "LifeGuide",
  }), { status: 503, headers: {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
  } });
