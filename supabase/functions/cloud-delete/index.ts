// Deletes Bunny-backed cloud file objects. The mobile app can't call Bunny's
// delete API directly (that needs the storage zone password), so it asks
// this function instead, after removing the cloud_files rows themselves.
//
// Safety: every path must start with the caller's own user id -- the same
// prefix every one of their own bunny_path values already has -- so this
// can never be used to delete someone else's file even if a path were
// guessed or forged.
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const authHeader = req.headers.get("Authorization") ?? "";
  const asUser = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userError } = await asUser.auth.getUser();
  if (userError || !userData.user) return json({ error: "not signed in" }, 401);

  let paths: string[];
  try {
    const body = await req.json();
    paths = Array.isArray(body.paths) ? body.paths.map(String) : [];
  } catch {
    return json({ error: "invalid request body" }, 400);
  }

  const prefix = `${userData.user.id}/`;
  const own = paths.filter((p) => p.startsWith(prefix));

  const zone = Deno.env.get("BUNNY_CLOUD_ZONE")!;
  const endpoint = Deno.env.get("BUNNY_CLOUD_ENDPOINT")!;
  const password = Deno.env.get("BUNNY_CLOUD_PASSWORD")!;
  await Promise.all(
    own.map((p) =>
      fetch(`https://${endpoint}/${zone}/${p}`, { method: "DELETE", headers: { AccessKey: password } }).catch(
        () => {},
      ),
    ),
  );

  return json({ deleted: own.length });
});
