-- =============================================================================
-- Personal cloud files on Bunny Storage instead of Supabase Storage.
--
-- A non-folder row is backed by storage_key (Supabase, existing files) OR
-- bunny_path (Bunny, new uploads) -- exactly one of the two, same pattern as
-- post_items.media_key / .bunny_video_id. Unlike post media, a cloud_files
-- row is only ever visible to its own owner (cloud_files_select below), so
-- bunny_path needs no column-grant hiding or security-definer indirection --
-- the owner's own client may read it directly; only signing the download URL
-- needs the server-side security key (done in the cloud-download-url Edge
-- Function).
-- =============================================================================

alter table public.cloud_files add column if not exists bunny_path text;

alter table public.cloud_files drop constraint if exists cloud_files_check;
alter table public.cloud_files
  add constraint cloud_files_check
  check (is_folder = (storage_key is null and bunny_path is null)
         and not (storage_key is not null and bunny_path is not null));

-- Storage keys/paths of a folder and everything inside it (unchanged shape,
-- now also returns bunny_path so the app can delete both kinds of object).
create or replace function public.cloud_folder_bunny_paths(p_folder_id uuid)
returns setof text language sql stable as $$
  with recursive tree as (
    select id, bunny_path from public.cloud_files where id = p_folder_id
    union all
    select c.id, c.bunny_path from public.cloud_files c join tree t on c.parent_id = t.id
  )
  select bunny_path from tree where bunny_path is not null
$$;
alter function public.cloud_folder_bunny_paths(uuid) set search_path = '';
