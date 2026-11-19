// Automatic preview: serves a shortened HLS playlist of a premium video that
// has no uploaded preview (the first 2 minutes, at most half the video).
//
// The video player fetches these playlists without an Authorization header,
// so this function runs with verify_jwt = false and trusts only the signed
// token in the path, which bunny-stream-url issues after the database
// (public.bunny_preview_info) allowed the viewer.
//
// Security: the full video's folder is never signed. Each segment in the
// shortened playlist carries its own Bunny token valid for that one file, so
// a viewer cannot rebuild the rest of the video.
//
// URL shape (ends in .m3u8 so the player detects HLS):
//   /functions/v1/bunny-preview/<token>/master.m3u8
//   /functions/v1/bunny-preview/<token>/v.m3u8      (token also names the variant)

const PREVIEW_MAX_SECONDS = 120;

type Claims = { v: string; e: number; p: string };

const enc = new TextEncoder();

function b64url(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function b64urlDecode(s: string): string {
  const pad = s.length % 4 ? "=".repeat(4 - (s.length % 4)) : "";
  return atob(s.replace(/-/g, "+").replace(/_/g, "/") + pad);
}

async function hmac(key: string, message: string): Promise<Uint8Array> {
  const k = await crypto.subtle.importKey("raw", enc.encode(key), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return new Uint8Array(await crypto.subtle.sign("HMAC", k, enc.encode(message)));
}

function secret(): string {
  return "flixvault-preview:" + Deno.env.get("BUNNY_STREAM_TOKEN_KEY")!;
}

async function makePreviewToken(claims: Claims): Promise<string> {
  const body = b64url(enc.encode(JSON.stringify(claims)));
  return `${body}.${b64url(await hmac(secret(), body))}`;
}

async function readToken(token: string): Promise<Claims | null> {
  const [body, sig] = token.split(".");
  if (!body || !sig) return null;
  const expected = b64url(await hmac(secret(), body));
  if (expected.length !== sig.length) return null;
  let diff = 0;
  for (let i = 0; i < sig.length; i++) diff |= expected.charCodeAt(i) ^ sig.charCodeAt(i);
  if (diff !== 0) return null;
  try {
    const c = JSON.parse(b64urlDecode(body)) as Claims;
    if (!/^[0-9a-f-]{36}$/.test(c.v) || typeof c.e !== "number" || c.e < Date.now() / 1000) return null;
    if (c.p !== "" && !/^[0-9a-z]+\/video\.m3u8$/.test(c.p)) return null;
    return c;
  } catch {
    return null;
  }
}

// Bunny "Advanced Token Authentication" for one file only (HS256).
async function signFile(host: string, key: string, path: string, expires: number): Promise<string> {
  const token = "HS256-" + b64url(await hmac(key, path + String(expires)));
  return `https://${host}${path}?token=${token}&expires=${expires}`;
}

// Directory token, used only for this function's own fetches from Bunny.
async function fetchFromBunny(host: string, key: string, videoId: string, file: string): Promise<string | null> {
  const dir = `/${videoId}/`;
  const expires = Math.floor(Date.now() / 1000) + 300;
  const token = "HS256-" + b64url(await hmac(key, dir + String(expires) + `token_path=${dir}`));
  const url = `https://${host}/bcdn_token=${token}&token_path=${encodeURIComponent(dir)}&expires=${expires}${dir}${file}`;
  const res = await fetch(url);
  return res.ok ? await res.text() : null;
}

function playlist(text: string): Response {
  return new Response(text, {
    headers: {
      "Content-Type": "application/vnd.apple.mpegurl",
      "Cache-Control": "no-store",
      "Access-Control-Allow-Origin": "*",
    },
  });
}

const notFound = () => new Response("not found", { status: 404 });

Deno.serve(async (req) => {
  if (req.method !== "GET") return notFound();
  const parts = new URL(req.url).pathname.split("/").filter(Boolean);
  const at = parts.indexOf("bunny-preview");
  const token = parts[at + 1];
  if (at < 0 || !token) return notFound();
  const claims = await readToken(token);
  if (!claims) return new Response("expired or invalid", { status: 403 });

  const host = Deno.env.get("BUNNY_STREAM_HOST")!;
  const key = Deno.env.get("BUNNY_STREAM_TOKEN_KEY")!;
  const base = `${Deno.env.get("SUPABASE_URL")}/functions/v1/bunny-preview`;

  // Master playlist: point every quality at this function.
  if (claims.p === "") {
    const master = await fetchFromBunny(host, key, claims.v, "playlist.m3u8");
    if (master === null) return notFound();
    const out: string[] = [];
    for (const raw of master.split(/\r?\n/)) {
      const line = raw.trim();
      if (!line || line.startsWith("#")) {
        out.push(line);
        continue;
      }
      if (!/^[0-9a-z]+\/video\.m3u8$/.test(line)) continue;
      const variantToken = await makePreviewToken({ v: claims.v, e: claims.e, p: line });
      out.push(`${base}/${variantToken}/v.m3u8`);
    }
    return playlist(out.join("\n") + "\n");
  }

  // One quality: keep only the first part, each segment signed on its own.
  const variant = await fetchFromBunny(host, key, claims.v, claims.p);
  if (variant === null) return notFound();
  const lines = variant.split(/\r?\n/).map((l) => l.trim());
  let total = 0;
  for (const l of lines) if (l.startsWith("#EXTINF:")) total += parseFloat(l.slice(8)) || 0;
  const limit = Math.min(PREVIEW_MAX_SECONDS, total / 2);
  const dir = `/${claims.v}/${claims.p.slice(0, claims.p.lastIndexOf("/") + 1)}`;

  const out: string[] = [];
  let used = 0;
  let pending: string | null = null;
  for (const line of lines) {
    if (!line) continue;
    if (line === "#EXT-X-ENDLIST") continue;
    if (line.startsWith("#EXTINF:")) {
      if (used > 0 && used >= limit) break;
      used += parseFloat(line.slice(8)) || 0;
      pending = line;
      continue;
    }
    if (line.startsWith("#")) {
      if (pending === null) out.push(line); // header tags
      continue;
    }
    if (pending === null || !/^[\w.-]+$/.test(line)) continue;
    out.push(pending, await signFile(host, key, dir + line, claims.e));
    pending = null;
  }
  out.push("#EXT-X-ENDLIST");
  return playlist(out.join("\n") + "\n");
});

