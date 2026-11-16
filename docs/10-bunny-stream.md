# Bunny Stream: seamless video streaming

Videos the admin panel uploads to a post now stream from **Bunny Stream**
(adaptive HLS) instead of Supabase Storage. Nothing about approval,
audience, or premium rules changed -- only where the video bytes live.

- Images still upload to Supabase Storage, unchanged.
- Videos a *creator* uploads from the app itself (their own channel) are
  also unchanged for now -- only admin-panel uploads use Bunny.
- An existing video keeps playing from Supabase exactly as before;
  `post_items.media_key` and `.bunny_video_id` are mutually exclusive, and
  the app picks whichever one is set.

## How a video gets from the admin panel to a phone

1. Admin picks a video file. The browser calls the `bunny-stream-create`
   Edge Function, which creates the video in Bunny Stream and returns a
   short-lived, video-scoped upload credential (never the raw Bunny API
   key).
2. The browser uploads the file straight to Bunny over TUS (resumable
   upload), then the admin panel inserts the `post_items` row itself, with
   `bunny_video_id` set and `processing_status = 'pending'`.
3. Bunny encodes the video in the background. The admin page shows a
   **Check encoding** button on a pending item; clicking it calls
   `bunny-stream-status`, which asks Bunny and flips the item to `ready`
   once encoding finishes (filling in the real duration/width/height).
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
- Creator-uploaded videos (from the app itself, not the admin panel) still
  go to Supabase Storage.
- Personal Cloud files (user file storage, not post content) are a
  separate, not-yet-built phase -- see the project notes for Bunny Storage.
