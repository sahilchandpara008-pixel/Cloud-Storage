-- Free mode: the app is free for everyone (no plans, no payments shown).
-- The audience / approval flow stays the same:
--   * ads users (and organic users the owner approved) get full access:
--     premium videos in full, ads-only content, downloads;
--   * organic users see the "everyone" + "organic" content, and can ask for
--     full access; the request appears in admin Approvals as before.
-- Every logged-in user gets 15 GB of cloud storage; active paid plans keep 2 TB.
-- Turn paid plans back on later with:
--   update public.app_mode set free_mode = false where id = 1;

create table if not exists public.app_mode (
  id         int primary key default 1 check (id = 1),
  free_mode  boolean not null default true,
  updated_at timestamptz not null default now()
);
insert into public.app_mode (id) values (1) on conflict (id) do nothing;
alter table public.app_mode enable row level security;
drop policy if exists app_mode_owner on public.app_mode;
create policy app_mode_owner on public.app_mode for all
  using (public.is_owner()) with check (public.is_owner());

create or replace function public.free_mode()
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((select free_mode from public.app_mode where id = 1), false)
$$;

create or replace function public.is_premium_user()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.subscriptions
                  where user_id = auth.uid() and now() between starts_at and ends_at)
      or (public.free_mode()
          and exists (select 1 from public.profiles where id = auth.uid() and not is_guest)
          and public.has_ads_access())
$$;

create or replace function public.quota_bytes(p_user_id uuid)
returns bigint language sql stable security definer set search_path = '' as $$
  select case
    when exists (select 1 from public.subscriptions
                  where user_id = p_user_id and now() between starts_at and ends_at)
      then 2199023255552::bigint   -- 2 TB for paid plans
    when public.free_mode()
         and exists (select 1 from public.profiles where id = p_user_id and not is_guest)
      then greatest(16106127360::bigint,   -- 15 GB for every logged-in user
                    coalesce((select free_cloud_bytes from public.profiles where id = p_user_id), 0))
    else coalesce((select free_cloud_bytes from public.profiles where id = p_user_id), 0)
  end
$$;

-- Organic user asks the owner for full access (shows in admin Approvals).
create or replace function public.request_full_access()
returns text language plpgsql security definer set search_path = '' as $$
declare
  v_status public.ads_access_status;
begin
  if auth.uid() is null then raise exception 'please log in'; end if;
  if exists (select 1 from public.profiles where id = auth.uid() and is_guest) then
    raise exception 'please log in';
  end if;
  if public.has_ads_access() then return 'approved'; end if;
  update public.profiles
     set ads_access_status = 'pending', updated_at = now()
   where id = auth.uid() and ads_access_status = 'none';
  select ads_access_status into v_status from public.profiles where id = auth.uid();
  return v_status::text;
end $$;

revoke execute on function public.free_mode() from public;
grant execute on function public.free_mode() to anon, authenticated;
revoke execute on function public.request_full_access() from public, anon;
grant execute on function public.request_full_access() to authenticated;

create or replace function public.my_status()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'user_id',        p.id,
    'display_name',   p.display_name,
    'avatar_url',     p.avatar_url,
    'is_guest',       p.is_guest,
    'source',         public.source_of(p.id),
    'has_ads_access', public.has_ads_access(),
    'is_premium',     public.is_premium_user(),
    'plan_name',      cur.name,
    'plan_ends_at',   cur.ends_at,
    'used_bytes',     p.used_bytes,
    'quota_bytes',    public.quota_bytes(p.id),
    'open_request',   (select pl.name from public.plan_requests r join public.plans pl on pl.id = r.plan_id
                        where r.user_id = p.id and r.status = 'open' limit 1),
    'free_mode',      public.free_mode(),
    'access_status',  p.ads_access_status)
    from public.profiles p
    left join lateral (
      select pl.name, s.ends_at from public.subscriptions s join public.plans pl on pl.id = s.plan_id
       where s.user_id = p.id and now() between s.starts_at and s.ends_at
       order by s.ends_at desc limit 1) cur on true
   where p.id = auth.uid()
$$;
