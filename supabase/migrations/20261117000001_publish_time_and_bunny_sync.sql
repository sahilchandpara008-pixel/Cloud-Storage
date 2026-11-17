-- =============================================================================
-- Why a freshly uploaded video could stay invisible in the app:
--
-- 1. The bulk uploader stamped posts.published_at with the ADMIN'S COMPUTER
--    CLOCK. A clock that is ahead (wrong time zone / date) scheduled the post
--    hours into the future, and post_visible() (published_at <= now()) hid it.
--    The server now owns "publish now": a published post without a time gets
--    now() from the database clock.
--
-- 2. post_visible() also hides a post until every item is processing_status =
--    'ready', but the only thing that flipped a Bunny video to ready was the
--    admin's browser polling bunny-stream-status while the page was open.
--    Close the tab and the post stayed hidden forever. bunny_sync_tick() now
--    asks the bunny-stream-sync Edge Function to check Bunny every minute.
-- =============================================================================

-- ---- 1. Server-side publish time -------------------------------------------
create or replace function public.posts_default_publish_time()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.status = 'published' and new.published_at is null then
    new.published_at := now();
  end if;
  return new;
end $$;

drop trigger if exists posts_default_publish_time on public.posts;
create trigger posts_default_publish_time
  before insert or update of status, published_at on public.posts
  for each row execute function public.posts_default_publish_time();

-- ---- 2. Automatic "ready" sweeper ------------------------------------------
-- Where to call. Left empty here so the migration is portable; set it once per
-- project:  update public.bunny_sync_settings set function_url =
--   'https://<project-ref>.supabase.co/functions/v1/bunny-stream-sync';
create table if not exists public.bunny_sync_settings (
  id           int primary key default 1 check (id = 1),
  function_url text
);
insert into public.bunny_sync_settings (id) values (1) on conflict do nothing;
alter table public.bunny_sync_settings enable row level security;
revoke all on public.bunny_sync_settings from anon, authenticated;

create or replace function public.bunny_sync_tick()
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_url text;
begin
  select function_url into v_url from public.bunny_sync_settings where id = 1;
  if v_url is null then return; end if;
  if not exists (
    select 1 from public.post_items
     where bunny_video_id is not null
       and (processing_status = 'pending'
            or (processing_status = 'ready' and thumb_key is null
                and created_at > now() - interval '3 days'))
  ) then
    return;
  end if;
  if to_regclass('net.http_request_queue') is null then return; end if;  -- pg_net missing (local tests)
  execute 'select net.http_post(url := $1, body := ''{}''::jsonb, headers := ''{"Content-Type": "application/json"}''::jsonb)'
    using v_url;
end $$;

revoke execute on function public.bunny_sync_tick() from public, anon, authenticated;

do $$
begin
  perform cron.schedule('bunny-sync', '* * * * *', 'select public.bunny_sync_tick()');
exception when others then
  raise notice 'bunny sync not scheduled: %', sqlerrm;
end $$;
