// Isolated, JWT-gated Supabase Edge runtime probe.
// NOT the LifeGuide v0.7.1 Express API. No user data or database access.
const jsonHeaders: Record<string, string> = {
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store",
  "x-content-type-options": "nosniff",
  "allow": "GET",
};

Deno.serve((request: Request) => {
  if (request.method !== "GET") {
    return new Response(JSON.stringify({ error: "method_not_allowed" }), {
      status: 405,
      headers: jsonHeaders,
    });
  }
  return new Response(
    JSON.stringify({ status: "ok", service: "lifeguide-qa-health", scope: "runtime_probe_only" }),
    { status: 200, headers: jsonHeaders },
  );
});
