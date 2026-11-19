-- =============================================================================
-- Dashboard analytics for a date range (null = all time).
-- Installs (ads / organic), users, subscriptions, sales, channels, content
-- and a per-day series (Indian days; all time shows the last 30 days).
-- Money only for the owner; content admins get the rest.
-- =============================================================================

create or replace function public.admin_analytics(p_from timestamptz default null, p_to timestamptz default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_owner boolean := public.is_owner();
  v_from  timestamptz;
  v_to    timestamptz := coalesce(p_to, now());
  v       jsonb;
begin
  if not public.is_admin() then
    raise exception 'admins only';
  end if;
  -- Series window: the range, or the last 30 days for all time; at most 120 days.
  v_from := greatest(coalesce(p_from, v_to - interval '30 days'), v_to - interval '120 days');

  with ins as (
    select i.created_at, i.source, i.geo_blocked,
           public.is_meta_ad_referrer(i.referrer_status, i.raw_referrer) as verified
      from public.installs i
     where (p_from is null or i.created_at >= p_from) and (p_to is null or i.created_at < p_to)
  ), usr as (
    select p.created_at, p.is_guest
      from public.profiles p
     where not exists (select 1 from public.admins a where a.user_id = p.id)
       and (p_from is null or p.created_at >= p_from) and (p_to is null or p.created_at < p_to)
  ), paid as (
    select o.user_id, o.amount_paise, o.verified_at
      from public.payment_orders o
     where o.status = 'approved'
       and (p_from is null or o.verified_at >= p_from) and (p_to is null or o.verified_at < p_to)
  ), first_paid as (
    select user_id, min(verified_at) as first_at from public.payment_orders where status = 'approved' group by user_id
  ), ev as (
    select e.event from public.analytics_events e
     where (p_from is null or e.created_at >= p_from) and (p_to is null or e.created_at < p_to)
  ), days as (
    select d::date as day
      from generate_series((v_from at time zone 'Asia/Kolkata')::date,
                           (v_to at time zone 'Asia/Kolkata')::date, interval '1 day') d
  )
  select jsonb_build_object(
    'installs',            (select count(*) from ins),
    'installs_ads',        (select count(*) from ins where source = public.ad_source()),
    'installs_ads_content',(select count(*) from ins where source = public.ad_source() and verified and not geo_blocked),
    'installs_ads_geo',    (select count(*) from ins where source = public.ad_source() and geo_blocked),
    'installs_organic',    (select count(*) from ins where source is distinct from public.ad_source()),
    'users',               (select count(*) from usr),
    'registered',          (select count(*) from usr where not is_guest),
    'guests',              (select count(*) from usr where is_guest),
    'active_subscribers',  (select count(distinct s.user_id) from public.subscriptions s
                             where now() between s.starts_at and s.ends_at
                               and not exists (select 1 from public.admins a where a.user_id = s.user_id)),
    'purchases',           (select count(*) from paid),
    'new_subscribers',     (select count(*) from first_paid f
                             where (p_from is null or f.first_at >= p_from) and (p_to is null or f.first_at < p_to)),
    'revenue_paise',       case when v_owner then (select coalesce(sum(amount_paise), 0) from paid) end,
    'channels_requested',  (select count(*) from public.channels c
                             where c.created_by is not null
                               and not exists (select 1 from public.admins a where a.user_id = c.created_by)
                               and (p_from is null or c.created_at >= p_from) and (p_to is null or c.created_at < p_to)),
    'channels_approved',   (select count(*) from public.channels c where c.review_status = 'approved' and c.reviewed_at is not null
                               and (p_from is null or c.reviewed_at >= p_from) and (p_to is null or c.reviewed_at < p_to)),
    'channels_rejected',   (select count(*) from public.channels c where c.review_status = 'rejected' and c.reviewed_at is not null
                               and (p_from is null or c.reviewed_at >= p_from) and (p_to is null or c.reviewed_at < p_to)),
    'channels_pending',    (select count(*) from public.channels c where c.review_status = 'pending'),
    'posts_published',     (select count(*) from public.posts p where p.status = 'published'
                               and (p_from is null or p.published_at >= p_from) and (p_to is null or p.published_at < p_to)),
    'video_views',         (select count(*) from ev where event = 'content_view'),
    'preview_views',       (select count(*) from ev where event = 'preview_view'),
    'daily', (select coalesce(jsonb_agg(jsonb_build_object(
                'day', d.day,
                'installs_ads', (select count(*) from public.installs i
                                  where (i.created_at at time zone 'Asia/Kolkata')::date = d.day
                                    and i.source = public.ad_source()),
                'installs_organic', (select count(*) from public.installs i
                                  where (i.created_at at time zone 'Asia/Kolkata')::date = d.day
                                    and i.source is distinct from public.ad_source()),
                'purchases', (select count(*) from public.payment_orders o
                                  where o.status = 'approved'
                                    and (o.verified_at at time zone 'Asia/Kolkata')::date = d.day),
                'revenue_paise', case when v_owner then (select coalesce(sum(o.amount_paise), 0) from public.payment_orders o
                                  where o.status = 'approved'
                                    and (o.verified_at at time zone 'Asia/Kolkata')::date = d.day) end)
              order by d.day), '[]'::jsonb) from days d))
  into v;
  return v;
end $$;

revoke execute on function public.admin_analytics(timestamptz, timestamptz) from public, anon;
grant execute on function public.admin_analytics(timestamptz, timestamptz) to authenticated;

notify pgrst, 'reload schema';
