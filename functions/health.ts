export const onRequestGet = async (): Promise<Response> =>
  new Response(JSON.stringify({
    status: "ok",
    component: "pwa_gateway_only",
    product: "LifeGuide",
    backend: "not_connected",
  }), { status: 200, headers: {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
  } });
