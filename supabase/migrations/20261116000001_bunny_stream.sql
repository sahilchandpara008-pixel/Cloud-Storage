-- =============================================================================
-- Bunny Stream for videos: seamless adaptive (HLS) streaming, delivered from
-- Bunny instead of Supabase Storage. Admin-approved content, audience and
-- premium rules are unchanged -- only where the video bytes live changes.
--
-- An item can be backed by Supabase Storage (media_key, existing items) OR by
-- Bunny Stream (bunny_video_id, new uploads). Exactly one of the two is set.
-- The app asks `bunny_video_access()`/`bunny_video_path()` for playback; the
-- Edge Function that calls these never exposes the raw video id to anyone it
-- doesn't already allow to watch the item.
-- =============================================================================

alter table public.post_items
  add column if not exists bunny_video_id uuid,
  alter column media_key drop not null;

alter table public.post_items
  drop constraint if exists post_items_media_source_check;
alter table public.post_items
  add constraint post_items_media_source_check
  check (media_key is not null or bunny_video_id is not null);

-- Column grants: hide bunny_video_id the same way media_key/hls_key/preview_key
-- are hidden -- the app never needs the raw id, only a signed playback URL.
grant select (id, post_id, position, kind, is_premium, thumb_key, duration_s, width, height,
              processing_status, created_at) on public.post_items to authenticated;

-- Same visibility + premium rule as can_read_media(), keyed by item id so the
-- Edge Function can check access without ever reading media_key/bunny_video_id
-- back to the client.
create or replace function public.bunny_video_access(p_item_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.is_admin() or exists (
    select 1 from public.post_items i
     where i.id = p_item_id
       and public.post_visible(i.post_id)
       and (not i.is_premium or public.is_premium_user()))
$$;

-- Returns the Bunny video id to sign a playback URL for, or null when the
-- item isn't Bunny-backed (caller falls back to the legacy signed-URL path).
-- Raises when the caller isn't allowed to watch the item at all.
create or replace function public.bunny_video_path(p_item_id uuid)
returns uuid language plpgsql stable security definer set search_path = '' as $$
declare
  v_id uuid;
begin
  if not public.bunny_video_access(p_item_id) then
    raise exception 'Not allowed';
  end if;
  select bunny_video_id into v_id from public.post_items where id = p_item_id;
  return v_id;
end $$;

revoke execute on function public.bunny_video_access(uuid) from public, anon;
revoke execute on function public.bunny_video_path(uuid) from public, anon;
grant execute on function public.bunny_video_access(uuid) to authenticated;
grant execute on function public.bunny_video_path(uuid) to authenticated;
