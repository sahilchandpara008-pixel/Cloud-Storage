-- =============================================================================
-- Ads content only for verified ads installs. No other way in.
--
-- 1. Admin approval no longer gives ads content: an organic user can never
--    see ads-audience content, approved or not (set_ads_access cannot
--    approve any more; request_full_access queues nothing).
-- 2. "Ads install" must be verified:
--      * the ads APK (referrer status 'apk', built into the APK), or
--      * a Google Play install whose referrer was written by Meta for THIS
--        app: utm_content holds {"app":1790101855436439, ..., "source":...}.
--    A hand-made Play link such as
--      ...&referrer=utm_source=apps.facebook.com&utm_campaign=fb4a
--    or utm_source=meta no longer counts, because anyone can share it.
-- 3. Gujarat / Maharashtra rule unchanged.
--
-- Checked at access time, so it also applies to existing users. Attribution
-- (reports, Meta events) is not changed.
-- =============================================================================

-- Meta app ID of Flixvault (Meta for Developers). Meta writes it into the
-- Play install referrer of every app-install ad.
create or replace function public.meta_app_id()
returns text language sql immutable set search_path = '' as $$ select '1790101855436439' $$;

-- Is this install referrer a real Meta app-install referrer for our app?
create or replace function public.is_meta_ad_referrer(p_status text, p_referrer text)
returns boolean language plpgsql immutable set search_path = '' as $$
declare
  v_content text;
begin
  if p_status = 'apk' then
    return public.parse_source(p_status, p_referrer) = public.ad_source();
  end if;
  if p_status <> 'ok' or p_referrer is null then return false; end if;
  v_content := lower(coalesce(public.url_decode(public.referrer_param(p_referrer, 'utm_content')), ''));
  return public.parse_source(p_status, p_referrer) = public.ad_source()
     and v_content like '%"app":' || public.meta_app_id() || '%'
     and v_content like '%"source":%';
end $$;

-- The current user is a verified ads user (and not geo-blocked).
create or replace function public.ads_verified()
returns boolean language sql stable security definer set search_path = '' as $$
  select not public.geo_blocked() and exists (
    select 1 from public.user_attribution ua
      join public.installs i on i.install_id = ua.first_touch_install_id
     where ua.user_id = auth.uid()
       and ua.first_touch_source = public.ad_source()
       and public.is_meta_ad_referrer(i.referrer_status, i.raw_referrer))
$$;
revoke execute on function public.ads_verified() from public;
grant execute on function public.ads_verified() to anon, authenticated;

-- Ads content: verified ads users only. Approval no longer counts.
create or replace function public.has_ads_access()
returns boolean language sql stable security definer set search_path = '' as $$
  select public.ads_verified()
$$;

-- Everyone who is not a verified ads user sees organic content.
create or replace function public.can_see(p_audience public.audience)
returns boolean language sql stable set search_path = '' as $$
  select public.is_admin() or case p_audience
    when 'all'     then true
    when 'organic' then not public.ads_verified()
    when 'ads'     then public.ads_verified()
  end
$$;

create or replace function public.my_status()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'user_id',        p.id,
    'display_name',   p.display_name,
    'avatar_url',     p.avatar_url,
    'is_guest',       p.is_guest,
    'source',         case when public.ads_verified() then 'ads' else 'organic' end,
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

-- No more access requests: nothing to approve.
create or replace function public.request_full_access()
returns text language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'please log in'; end if;
  if exists (select 1 from public.profiles where id = auth.uid() and is_guest) then
    raise exception 'please log in';
  end if;
  if public.has_ads_access() then return 'approved'; end if;
  return 'none';
end $$;

-- The owner can still reject / reset, but can no longer approve.
create or replace function public.set_ads_access(p_user_id uuid, p_status public.ads_access_status)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_owner() then
    raise exception 'only the owner can change ads-content access';
  end if;
  if p_status = 'approved' then
    raise exception 'Ads content is only for people who installed from your Meta ads. It cannot be approved by hand.';
  end if;
  update public.profiles
     set ads_access_status = p_status,
         ads_access_decided_by = auth.uid(),
         ads_access_decided_at = now(),
         updated_at = now()
   where id = p_user_id;
  insert into public.audit_logs (actor_id, action, target, meta)
  values (auth.uid(), 'set_ads_access', p_user_id::text, jsonb_build_object('status', p_status));
end $$;

-- Admin user list: show who really gets ads content.
drop function if exists public.admin_users(text, text, integer, integer, timestamptz, timestamptz, text);

create or replace function public.admin_users(
  p_filter text default 'all',
  p_search text default null,
  p_limit  integer default 50,
  p_offset integer default 0,
  p_from   timestamptz default null,
  p_to     timestamptz default null,
  p_sort   text default 'newest')
returns table(
  id uuid, email text, display_name text, is_guest boolean, source text, campaign text,
  plan_name text, plan_ends_at timestamptz, ads_access_status public.ads_access_status,
  created_at timestamptz, purchases integer, spent_paise bigint, last_purchase_at timestamptz,
  total_count bigint, ads_content boolean)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_owner() then
    raise exception 'only the owner can list users';
  end if;
  return query
  with base as (
    select p.id, u.email::text as email, p.display_name, p.is_guest,
           public.source_of(p.id) as source, ua.first_touch_campaign as campaign,
           cur.name as plan_name, cur.ends_at as plan_ends_at, p.ads_access_status, p.created_at,
           coalesce(pay.n, 0)::int as purchases, coalesce(pay.spent, 0)::bigint as spent_paise,
           pay.last_at as last_purchase_at,
           exists (select 1 from public.subscriptions s where s.user_id = p.id) as ever_subscribed,
           exists (select 1 from public.installs i
                    where i.install_id = ua.first_touch_install_id
                      and ua.first_touch_source = public.ad_source()
                      and not i.geo_blocked
                      and public.is_meta_ad_referrer(i.referrer_status, i.raw_referrer)) as ads_content
      from public.profiles p
      join auth.users u on u.id = p.id
      left join public.user_attribution ua on ua.user_id = p.id
      left join lateral (
        select pl.name, s.ends_at from public.subscriptions s
          join public.plans pl on pl.id = s.plan_id
         where s.user_id = p.id and now() between s.starts_at and s.ends_at
         order by s.ends_at desc limit 1) cur on true
      left join lateral (
        select count(*) as n, sum(o.amount_paise) as spent, max(o.verified_at) as last_at
          from public.payment_orders o
         where o.user_id = p.id and o.status = 'approved') pay on true
     where not exists (select 1 from public.admins a where a.user_id = p.id)
       and (p_from is null or p.created_at >= p_from)
       and (p_to is null or p.created_at < p_to)
       and (p_search is null or p_search = ''
            or u.email ilike '%' || p_search || '%'
            or p.display_name ilike '%' || p_search || '%'
            or p.id::text = p_search)
  )
  select b.id, b.email, b.display_name, b.is_guest, b.source, b.campaign, b.plan_name, b.plan_ends_at,
         b.ads_access_status, b.created_at, b.purchases, b.spent_paise, b.last_purchase_at,
         count(*) over () as total_count, b.ads_content
    from base b
   where case p_filter
           when 'pending'    then b.ads_access_status = 'pending'
           when 'approved'   then b.ads_access_status = 'approved'
           when 'rejected'   then b.ads_access_status = 'rejected'
           when 'premium'    then b.plan_ends_at is not null
           when 'expired'    then b.plan_ends_at is null and b.ever_subscribed
           when 'paying'     then b.purchases > 0
           when 'repeat'     then b.purchases > 1
           when 'never_paid' then b.purchases = 0
           when 'registered' then not b.is_guest
           when 'guest'      then b.is_guest
           when 'ads'        then b.ads_content
           when 'organic'    then not b.ads_content
           else true
         end
   order by
     case when p_sort = 'newest' or p_sort is null then (b.ads_access_status = 'pending') end desc nulls last,
     case when p_sort = 'oldest' then b.created_at end asc,
     case when p_sort = 'name' then lower(coalesce(b.display_name, b.email, '')) end asc,
     case when p_sort = 'spent' then b.spent_paise end desc,
     case when p_sort = 'purchases' then b.purchases end desc,
     case when p_sort = 'plan_end' then b.plan_ends_at end asc nulls last,
     case when p_sort = 'last_purchase' then b.last_purchase_at end desc nulls last,
     b.created_at desc
   limit least(p_limit, 200) offset greatest(p_offset, 0);
end $$;

revoke execute on function public.admin_users(text, text, integer, integer, timestamptz, timestamptz, text) from public, anon;
grant execute on function public.admin_users(text, text, integer, integer, timestamptz, timestamptz, text) to authenticated;

-- Clear any old approvals / pending requests.
update public.profiles
   set ads_access_status = 'none', updated_at = now()
 where ads_access_status in ('approved', 'pending');

notify pgrst, 'reload schema';
