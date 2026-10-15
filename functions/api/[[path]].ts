// LifeGuide QA fail-closed backend placeholder.
// An HTTP 503 JSON response is intentional until signed family sessions and
// Supabase Postgres authorization are implemented in a trusted runtime.
// NEVER rewrite this to proxy raw Supabase Data API with a service-role key.
const headers = {
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store",
  "X-Content-Type-Options": "nosniff",
};
export const onRequest = async (): Promise<Response> =>
  new Response(JSON.stringify({
    error: "lifeguide_api_not_ready",
    status: "degraded",
    service: "lifeguide_qa",
  }), { status: 503, headers });
