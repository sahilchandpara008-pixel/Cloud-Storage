# Bunny Storage: personal cloud files

A user's personal Cloud files (not post content -- their own uploaded files)
now save to **Bunny Storage** instead of Supabase Storage. Nothing about
premium access, quota, or folder structure changed -- only where the bytes
live.

- An existing file keeps working from Supabase exactly as before;
  `cloud_files.storage_key` and `.bunny_path` are mutually exclusive, and the
  app picks whichever one is set.
- A folder has neither set.

## How a file gets from the phone to Bunny

1. The app sends the file's bytes to the `cloud-upload` Edge Function
   (`X-File-Name` / `X-Parent-Id` / `X-File-Mime` headers carry the rest).
   The function checks the user is premium and under quota, streams the
   bytes straight to Bunny Storage (the zone's password never reaches the
   phone), and inserts the `cloud_files` row itself with `bunny_path` set.
2. Files up to **300 MB** are supported this way (a proxy through a server
   function, not a direct-from-device upload like Bunny Stream's TUS, so it
   stays well inside the function's execution limits).
3. To open or download a file, the app calls `cloud-download-url` with the
   file's id. Ownership is enforced by `cloud_files`' own row-level security
   (select only your own rows) -- the function never uses the service role,
   so it can never sign a path belonging to someone else's file.
4. Deleting a file or folder calls `cloud-delete` with the Bunny paths
   involved (from `cloud_folder_bunny_paths` for a folder). The function only
   ever deletes a path that starts with the caller's own user id.

## Required secrets

Set these as **Edge Function secrets** (Supabase dashboard -> Edge
Functions -> Secrets), and ideally also as GitHub repository secrets so the
`supabase-deploy` workflow can push them automatically on future pushes:

| Secret | Value | Where to find it |
|---|---|---|
| `BUNNY_CLOUD_ZONE` | the storage zone's name (e.g. `flixvault-cloud`) | Bunny dashboard -> Storage -> your zone |
| `BUNNY_CLOUD_PASSWORD` | the storage zone's password | Storage zone -> Access (FTP & API Access) |
| `BUNNY_CLOUD_ENDPOINT` | the storage zone's region endpoint hostname (e.g. `sg.storage.bunnycdn.com`) | same page |
| `BUNNY_CLOUD_HOST` | the connected Pull Zone's hostname (e.g. `flixvault-cloud.b-cdn.net`) | CDN -> your pull zone |
| `BUNNY_CLOUD_TOKEN_KEY` | the pull zone's Token Authentication Key | Pull zone -> Security -> Token authentication |

On the Pull Zone's Security page: **Token authentication** must be **on**
(this project already has it on).

## Known limits

- 300 MB per file (see above). A future move to Bunny's S3-compatible
  Storage mode could remove this cap by letting the app upload directly with
  a presigned URL instead of proxying through a function -- not done yet,
  since S3 compatibility is a creation-time setting for a zone (this
  project's zone predates it).
- Post content (videos/images on channels) is a separate, already-built
  feature -- see `docs/10-bunny-stream.md`.
