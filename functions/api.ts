// Covers the bare /api path, separate from /api/*.
export const onRequest = async (): Promise<Response> =>
  new Response(JSON.stringify({error:"lifeguide_api_not_ready",status:"degraded"}), {
    status:503,
    headers:{"Content-Type":"application/json; charset=utf-8","Cache-Control":"no-store","X-Content-Type-Options":"nosniff"},
  });
