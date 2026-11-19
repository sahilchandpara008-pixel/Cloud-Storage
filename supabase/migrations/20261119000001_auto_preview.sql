-- =============================================================================
-- Automatic preview for premium videos without an uploaded preview.
--
-- Rule (admin uploads and user uploads alike):
--   * a preview was uploaded  -> viewers with preview access see that preview;
--   * no preview uploaded     -> they see the start of the main video instead
--                                (first 2 minutes, at most half the video);
--   * with a plan             -> the full video, unchanged.
-- Who may watch a preview is unchanged (creator, admin, or a visible post and
-- ads access or a plan). No app update: the app already plays a preview when
-- has_trailer is true, through the bunny-stream-url function.
--
-- The full video is never signed for preview viewers: the bunny-preview
-- function serves a shortened playlist whose segments are each signed for
-- that one file only.
-- =============================================================================

-- has_trailer = "the app can play a preview": uploaded or automatic.
alter table public.post_items drop column if exists has_trailer;
alter table public.post_items
  add column has_trailer boolean generated always as (
    trailer_key is not null
    or (trailer_bunny_video_id is not null and trailer_status = 'ready')
    or (is_premium and kind = 'video' and bunny_video_id is not null
        and processing_status = 'ready' and trailer_key is null
        and (trailer_bunny_video_id is null or trailer_status is distinct from 'ready'))
  ) stored;

-- auto_preview = the preview is the start of the main video (no upload).
alter table public.post_items
  add column if not exists auto_preview boolean generated always as (
    is_premium and kind = 'video' and bunny_video_id is not null
    and processing_status = 'ready' and trailer_key is null
    and (trailer_bunny_video_id is null or trailer_status is distinct from 'ready')
  ) stored;

grant select (has_trailer, auto_preview) on public.post_items to anon, authenticated;

-- Which Bunny video to use for an item's preview, and whether it is the
-- automatic one. Same permission rule as bunny_trailer_path.
create or replace function public.bunny_preview_info(p_item_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_item public.post_items;
begin
  select * into v_item from public.post_items where id = p_item_id;
  if not found or not v_item.has_trailer or v_item.trailer_key is not null then
    raise exception 'Not allowed';
  end if;
  if not (public.is_admin()
          or public.is_post_creator(v_item.post_id)
          or (public.post_visible(v_item.post_id)
              and (public.has_ads_access() or public.is_premium_user()))) then
    raise exception 'Not allowed';
  end if;
  if v_item.auto_preview then
    return jsonb_build_object('video_id', v_item.bunny_video_id, 'auto', true);
  end if;
  return jsonb_build_object('video_id', v_item.trailer_bunny_video_id, 'auto', false);
end $$;

revoke execute on function public.bunny_preview_info(uuid) from public, anon;
grant execute on function public.bunny_preview_info(uuid) to authenticated;

notify pgrst, 'reload schema';
