-- =============================================================================
-- Previews (trailers) on Bunny Stream.
--
-- Until now a trailer was a plain file in Supabase Storage (50 MB cap, no
-- adaptive streaming). A trailer can now be a second Bunny Stream video of the
-- same item, played the same seamless way as the full video. Old trailers
-- (trailer_key) keep working; an item has one or the other.
--
-- Who may watch a trailer is unchanged -- creators, admins, and viewers with
-- ads access (installed from ads, or organic users the owner approved) on a
-- visible post -- plus users who already have a plan, since the app already
-- offers them the Trailer button.
-- =============================================================================

alter table public.post_items
  add column if not exists trailer_bunny_video_id uuid,
  add column if not exists trailer_status public.processing_status;

-- "Does this item have a playable trailer?" without exposing any id or key.
alter table public.post_items
  add column if not exists has_trailer boolean generated always as (
    trailer_key is not null
    or (trailer_bunny_video_id is not null and trailer_status = 'ready')
  ) stored;

-- trailer_bunny_video_id stays hidden (like bunny_video_id / media_key).
grant select (has_trailer, trailer_status) on public.post_items to anon, authenticated;

create or replace function public.bunny_trailer_path(p_item_id uuid)
returns uuid language plpgsql stable security definer set search_path = '' as $$
declare
  v_id uuid;
begin
  if not (public.is_admin() or exists (
        select 1 from public.post_items i
         where i.id = p_item_id
           and i.trailer_status = 'ready'
           and (public.is_post_creator(i.post_id)
                or (public.post_visible(i.post_id)
                    and (public.has_ads_access() or public.is_premium_user()))))) then
    raise exception 'Not allowed';
  end if;
  select trailer_bunny_video_id into v_id from public.post_items where id = p_item_id;
  return v_id;
end $$;

revoke execute on function public.bunny_trailer_path(uuid) from public, anon;
grant execute on function public.bunny_trailer_path(uuid) to authenticated;

-- The sweeper now also has work when only a trailer is still encoding.
create or replace function public.bunny_sync_tick()
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_url text;
begin
  select function_url into v_url from public.bunny_sync_settings where id = 1;
  if v_url is null then return; end if;
  if not exists (
    select 1 from public.post_items
     where (bunny_video_id is not null
            and (processing_status = 'pending'
                 or (processing_status = 'ready' and thumb_key is null
                     and created_at > now() - interval '3 days')))
        or (trailer_bunny_video_id is not null and trailer_status = 'pending')
  ) then
    return;
  end if;
  if to_regclass('net.http_request_queue') is null then return; end if;
  execute 'select net.http_post(url := $1, body := ''{}''::jsonb, headers := ''{"Content-Type": "application/json"}''::jsonb)'
    using v_url;
end $$;

revoke execute on function public.bunny_sync_tick() from public, anon, authenticated;
