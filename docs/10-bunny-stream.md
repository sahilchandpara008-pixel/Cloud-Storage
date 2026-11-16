# Bunny Stream: seamless video streaming

Videos posted to a channel -- by the admin panel, or by any creator posting
into their own approved channel from the app -- now stream from **Bunny
Stream** (adaptive HLS) instead of Supabase Storage. Nothing about
approval, audience, or premium rules changed -- only where the video bytes
live, and the ceiling on how big a video can be (no practical limit from
Bunny; 3 GB per file in the app's own picker, 2 GB in the admin panel).

- Images still upload to Supabase Storage, unchanged, on both the admin
  panel and the app.
- A video's trailer (shown to ads users before they buy) also still goes to
  Supabase Storage either way -- only the main video moved to Bunny.
- An existing video keeps playing from Supabase exactly as before;
  `post_items.media_key` and `.bunny_video_id` are mutually exclusive, and
  the app picks whichever one is set.
- Who may start a Bunny upload for a channel is exactly `can_post_in()`:
  admin for any channel, or the channel's own creator once it's approved --
  the same rule that already gates every other write to that channel's
  posts. Audience type (everyone / organic-only / ads-only) has no bearing
  on this; it only decides who may later *watch* the content.

## How a video gets from a device to a phone

1. The uploader (admin panel, or the app's New Post screen) calls the
   `bunny-stream-create` Edge Function with the target `channel_id`. It
   checks `can_post_in(channel_id)`, creates the video in Bunny Stream, and
   returns a short-lived, video-scoped upload credential (never the raw
   Bunny API key).
2. The uploader's device uploads the file straight to Bunny over TUS
   (resumable upload) -- the browser (admin) or the phone itself (app) --
   then inserts the `post_items` row itself, with `bunny_video_id` set and
   `processing_status = 'pending'`.
3. Bunny encodes the video in the background. The admin page shows a
   **Check encoding** button on a pending item; the app polls
   automatically for about a minute right after posting. Either way it
   calls `bunny-stream-status`, which checks the caller can manage that
   item (admin, or `can_post_in()` on its channel -- enforced by RLS, not a
   hand-rolled check) before asking Bunny and flipping the item to `ready`
   once encoding finishes (filling in the real duration/width/height). A
   post stays invisible to everyone, including its own creator's audience,
   until every one of its items is `ready` (`post_visible()`) -- so nobody
   ever sees a half-encoded video.
4. When a user opens the item, the app calls `bunny-stream-url` with the
   item's id. That function re-checks the exact same visibility + premium
   rule as the Supabase signed-URL path (`public.bunny_video_access`/
   `public.bunny_video_path`, in `20261116000001_bunny_stream.sql`), then
   returns a signed, time-limited Bunny playback URL good for one hour.
   Nothing the user doesn't already have access to ever gets a Bunny id,
   let alone a working link.

## Required secrets

Set these as **GitHub repository secrets** (Settings -> Secrets and
variables -> Actions) -- the `supabase-deploy` workflow pushes them on to
Supabase as Edge Function secrets on every push to `supabase/**`:

| Secret | Value | Where to find it |
|---|---|---|
| `SUPABASE_ACCESS_TOKEN` | a Supabase personal access token | Supabase dashboard -> Account -> Access Tokens |
| `SUPABASE_PROJECT_REF` | `lcfiohprmviolzwglkhm` | already Flixvault's project ref |
| `SUPABASE_DB_PASSWORD` | the project's database password | Supabase dashboard -> Project Settings -> Database |
| `BUNNY_STREAM_LIBRARY_ID` | the Stream library's numeric id | Bunny dashboard -> Stream -> your library -> API |
| `BUNNY_STREAM_API_KEY` | the Stream library's API key | same page |
| `BUNNY_STREAM_TOKEN_KEY` | the Stream library's Token Authentication Key | Stream library -> Security -> General |
| `BUNNY_STREAM_HOST` | the library's video delivery hostname, e.g. `vz-xxxxxxxx-xxx.b-cdn.net` | shown once a video is uploaded (any video's `thumbnailUrl`), or Bunny support |

On the Stream library's Security page: **CDN token authentication** must be
**on**, and **Block direct url file access** must be **off** (that one is a
separate, referer-based check that would also reject the app's own
requests, which never send a browser referer).

## Known limits (next steps, not done yet)

- Downloads are not available for Bunny-backed videos yet (the app tells
  the user so); only legacy Supabase-hosted items can still be downloaded.
- Personal Cloud files (user file storage, not post content) are on Bunny
  Storage separately -- see `docs/11-bunny-cloud-storage.md`.
