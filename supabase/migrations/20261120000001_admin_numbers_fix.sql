-- Admin numbers audit (2026-11-20).
--
-- 1. Payments made by admin accounts (the owner's own test payments) were
--    counted as sales: revenue, plans sold, new subscribers, buyers, plan
--    summary and the daily chart included them, while "active subscribers"
--    left them out, so the numbers disagreed. Admin accounts are now left out
--    of every money / subscriber number.
-- 2. The plan summary counted a sale on the day the order was created; the
--    dashboard counts it on the day the payment was approved. Both now use
--    the approval time, so the same range shows the same sales everywhere.
-- 3. The source/campaign report counted any plan (also free ones granted by
--    an admin) as a "buyer" and its revenue at today's plan price. It now
--    counts approved payments and what was actually paid.
-- 4. admin_dashboard: "with an active plan" left admins in (the dashboard's
--    other active count did not), and organic installs missed installs with
--    no source recorded.
-- 5. Users list, sort "Newest": users with a leftover "pending access"
--    status were pinned to the top. Newest is now simply newest first.

create or replace function public.is_admin_user(p_user uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.admins a where a.user_id = p_user);
$$;
revoke execute on function public.is_admin_user(uuid) from public, anon;
grant execute on function public.is_admin_user(uuid) to authenticated;

-- ------------------------------------------------------------ admin_analytics
create or replace function public.admin_analytics(
  p_from timestamptz default null,
  p_to   timestamptz default null)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_owner boolean := public.is_owner();
  v_from  timestamptz;
  v_to    timestamptz := coalesce(p_to, now());
  v       jsonb;
begin
  if not public.is_admin() then
    raise exception 'admins only';
  end if;
  v_from := greatest(coalesce(p_from, v_to - interval '30 days'), v_to - interval '120 days');

  with ins as (
    select i.created_at, i.source, i.geo_blocked,
           public.is_meta_ad_referrer(i.referrer_status, i.raw_referrer) as verified
      from public.installs i
     where (p_from is null or i.created_at >= p_from) and (p_to is null or i.created_at < p_to)
  ), usr as (
    select p.created_at, p.is_guest
      from public.profiles p
     where not public.is_admin_user(p.id)
       and (p_from is null or p.created_at >= p_from) and (p_to is null or p.created_at < p_to)
  ), sales as (
    select o.user_id, o.amount_paise, o.verified_at
      from public.payment_orders o
     where o.status = 'approved' and not public.is_admin_user(o.user_id)
  ), paid as (
    select * from sales
     where (p_from is null or verified_at >= p_from) and (p_to is null or verified_at < p_to)
  ), first_paid as (
    select user_id, min(verified_at) as first_at from sales group by user_id
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
                               and not public.is_admin_user(s.user_id)),
    'purchases',           (select count(*) from paid),
    'new_subscribers',     (select count(*) from first_paid f
                             where (p_from is null or f.first_at >= p_from) and (p_to is null or f.first_at < p_to)),
    'revenue_paise',       case when v_owner then (select coalesce(sum(amount_paise), 0) from paid) end,
    'channels_requested',  (select count(*) from public.channels c
                             where c.created_by is not null
                               and not public.is_admin_user(c.created_by)
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
                'purchases', (select count(*) from sales o
                                  where (o.verified_at at time zone 'Asia/Kolkata')::date = d.day),
                'revenue_paise', case when v_owner then (select coalesce(sum(o.amount_paise), 0) from sales o
                                  where (o.verified_at at time zone 'Asia/Kolkata')::date = d.day) end)
              order by d.day), '[]'::jsonb) from days d))
  into v;
  return v;
end
$$;

-- ----------------------------------------------------------- admin_user_stats
create or replace function public.admin_user_stats(
  p_from timestamptz default null,
  p_to   timestamptz default null)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v jsonb;
begin
  if not public.is_owner() then
    raise exception 'only the owner can see user reports';
  end if;
  with users as (
    select p.id, p.is_guest, public.source_of(p.id) as source
      from public.profiles p
     where not public.is_admin_user(p.id)
       and (p_from is null or p.created_at >= p_from)
       and (p_to is null or p.created_at < p_to)
  ), sales as (
    select o.user_id, o.plan_id, o.amount_paise, o.verified_at
      from public.payment_orders o
     where o.status = 'approved' and not public.is_admin_user(o.user_id)
  ), paid as (
    select * from sales
     where (p_from is null or verified_at >= p_from)
       and (p_to is null or verified_at < p_to)
  ), first_paid as (
    select user_id, min(verified_at) as first_at from sales group by user_id
  ), active as (
    select distinct on (s.user_id) s.user_id, s.plan_id
      from public.subscriptions s
     where now() between s.starts_at and s.ends_at
       and not public.is_admin_user(s.user_id)
     order by s.user_id, s.ends_at desc
  )
  select jsonb_build_object(
    'new_users',        (select count(*) from users),
    'registered',       (select count(*) from users where not is_guest),
    'guests',           (select count(*) from users where is_guest),
    'from_ads',         (select count(*) from users where source = 'ads'),
    'organic',          (select count(*) from users where source = 'organic'),
    'purchases',        (select count(*) from paid),
    'revenue_paise',    (select coalesce(sum(amount_paise), 0) from paid),
    'paying_customers', (select count(distinct user_id) from paid),
    'new_customers',    (select count(*) from first_paid f
                          where (p_from is null or f.first_at >= p_from)
                            and (p_to is null or f.first_at < p_to)),
    'repeat_customers', (select count(*) from (select user_id from paid group by user_id having count(*) > 1) r),
    'active_subscribers', (select count(*) from active),
    'all_users',        (select count(*) from public.profiles p where not public.is_admin_user(p.id)),
    'by_plan', (select coalesce(jsonb_agg(jsonb_build_object(
                    'plan', pl.name, 'price_inr', pl.price_inr,
                    'active_now', (select count(*) from active a where a.plan_id = pl.id),
                    'sold', (select count(*) from paid x where x.plan_id = pl.id),
                    'revenue_paise', (select coalesce(sum(x.amount_paise), 0) from paid x where x.plan_id = pl.id))
                  order by pl.position, pl.price_inr), '[]'::jsonb)
                  from public.plans pl))
  into v;
  return v;
end
$$;

-- ----------------------------------------------------------- admin_plan_sales
-- Sales (purchases, buyers, revenue) by approval time; open and failed
-- orders by the time the order was made. Admin test payments left out.
create or replace function public.admin_plan_sales(
  p_from timestamptz default null,
  p_to   timestamptz default null)
returns table (plan_id uuid, plan_name text, price_inr int, active boolean,
               purchases int, buyers int, repeat_buyers int, revenue_paise bigint,
               pending int, failed int, last_purchase_at timestamptz)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not public.is_owner() then raise exception 'only the owner can see plan sales'; end if;
  return query
  with sold as (
    select x.* from public.payment_orders x
     where x.status = 'approved' and not public.is_admin_user(x.user_id)
       and (p_from is null or x.verified_at >= p_from)
       and (p_to is null or x.verified_at < p_to)
  ), made as (
    select x.* from public.payment_orders x
     where not public.is_admin_user(x.user_id)
       and (p_from is null or x.created_at >= p_from)
       and (p_to is null or x.created_at < p_to)
  ), per_user as (
    select s.plan_id, s.user_id, count(*) as n from sold s group by s.plan_id, s.user_id
  )
  select pl.id, pl.name, pl.price_inr, pl.active,
         (select count(*)::int from sold s where s.plan_id = pl.id),
         (select count(*)::int from per_user pu where pu.plan_id = pl.id),
         (select count(*)::int from per_user pu where pu.plan_id = pl.id and pu.n > 1),
         (select coalesce(sum(s.amount_paise), 0)::bigint from sold s where s.plan_id = pl.id),
         (select count(*)::int from made m where m.plan_id = pl.id and m.status in ('initiated', 'pending')),
         (select count(*)::int from made m where m.plan_id = pl.id and m.status in ('failed', 'cancelled')),
         (select max(s.verified_at) from sold s where s.plan_id = pl.id)
    from public.plans pl
   order by pl.position, pl.price_inr;
end
$$;

-- --------------------------------------------------------------- admin_buyers
create or replace function public.admin_buyers(
  p_min_purchases int default 1,
  p_search text default null,
  p_limit int default 300)
returns table (user_id uuid, email text, display_name text, source text, purchases int,
               total_paise bigint, first_purchase_at timestamptz, last_purchase_at timestamptz,
               current_plan text, plan_ends_at timestamptz, history jsonb)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not public.is_owner() then raise exception 'only the owner can list buyers'; end if;
  return query
  with b as (
    select o.user_id,
           count(*)::int as purchases,
           sum(o.amount_paise)::bigint as total,
           min(coalesce(o.verified_at, o.created_at)) as first_at,
           max(coalesce(o.verified_at, o.created_at)) as last_at,
           jsonb_agg(jsonb_build_object(
             'reference', o.reference,
             'plan', pl.name,
             'amount_paise', o.amount_paise,
             'at', coalesce(o.verified_at, o.created_at),
             'utr', o.txn_id)
             order by coalesce(o.verified_at, o.created_at)) as history
      from public.payment_orders o
      join public.plans pl on pl.id = o.plan_id
     where o.status = 'approved' and not public.is_admin_user(o.user_id)
     group by o.user_id
  )
  select b.user_id, u.email::text, p.display_name, public.source_of(b.user_id), b.purchases,
         b.total, b.first_at, b.last_at,
         s.plan_name, s.ends_at, b.history
    from b
    join auth.users u on u.id = b.user_id
    left join public.profiles p on p.id = b.user_id
    left join lateral (
      select pl.name as plan_name, sub.ends_at
        from public.subscriptions sub
        join public.plans pl on pl.id = sub.plan_id
       where sub.user_id = b.user_id and sub.ends_at > now()
       order by sub.ends_at desc
       limit 1
    ) s on true
   where b.purchases >= greatest(coalesce(p_min_purchases, 1), 1)
     and (p_search is null or p_search = ''
          or u.email ilike '%' || p_search || '%'
          or p.display_name ilike '%' || p_search || '%')
   order by b.purchases desc, b.last_at desc
   limit least(greatest(p_limit, 1), 1000);
end
$$;

-- --------------------------------------------------------- attribution_report
-- Buyers / revenue from approved payments (what was actually paid), not from
-- every plan a user ever had at today's prices.
create or replace function public.attribution_report(
  p_from timestamptz default '-infinity',
  p_to   timestamptz default 'infinity')
returns table (source text, campaign text, installs bigint, registrations bigint,
               buyers bigint, subscriptions bigint, revenue_inr bigint)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not public.is_owner() then
    raise exception 'only the owner can view the attribution report';
  end if;
  return query
  with inst as (
    select i.source, coalesce(i.utm_campaign, '') as campaign, count(*) as n
      from public.installs i
     where i.created_at between p_from and p_to
     group by 1, 2),
  users as (
    select ua.first_touch_source as source, coalesce(ua.first_touch_campaign, '') as campaign,
           count(distinct ua.user_id) filter (where not pr.is_guest) as registrations,
           count(distinct o.user_id) as buyers,
           count(o.id) as subs,
           coalesce(sum(o.amount_paise), 0) / 100 as revenue
      from public.user_attribution ua
      join public.profiles pr on pr.id = ua.user_id
      left join public.payment_orders o on o.user_id = ua.user_id and o.status = 'approved'
     where ua.first_touch_at between p_from and p_to
       and not public.is_admin_user(ua.user_id)
     group by 1, 2)
  select coalesce(inst.source, users.source), coalesce(inst.campaign, users.campaign),
         coalesce(inst.n, 0), coalesce(users.registrations, 0), coalesce(users.buyers, 0),
         coalesce(users.subs, 0), coalesce(users.revenue, 0)::bigint
    from inst full join users on users.source = inst.source and users.campaign = inst.campaign
   order by 3 desc;
end
$$;

-- ------------------------------------------------------------ admin_dashboard
create or replace function public.admin_dashboard()
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception 'admins only';
  end if;
  return jsonb_build_object(
    'pending_approvals', (select count(*) from public.profiles where ads_access_status = 'pending'),
    'pending_channels',  (select count(*) from public.channels where review_status = 'pending'),
    'users',             (select count(*) from public.profiles p where not public.is_admin_user(p.id)),
    'registered',        (select count(*) from public.profiles p where not p.is_guest
                             and not public.is_admin_user(p.id)),
    'premium',           (select count(distinct user_id) from public.subscriptions s
                           where now() between s.starts_at and s.ends_at
                             and not public.is_admin_user(s.user_id)),
    'installs_ads',      (select count(*) from public.installs where source = public.ad_source()),
    'installs_organic',  (select count(*) from public.installs where source is distinct from public.ad_source()),
    'channels',          (select count(*) from public.channels where review_status = 'approved'),
    'posts_published',   (select count(*) from public.posts where status = 'published'));
end
$$;

-- ---------------------------------------------------------------- admin_users
-- Same as before; only "Newest" no longer pins pending-access users first.
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
     case when p_sort = 'oldest' then b.created_at end asc,
     case when p_sort = 'name' then lower(coalesce(b.display_name, b.email, '')) end asc,
     case when p_sort = 'spent' then b.spent_paise end desc,
     case when p_sort = 'purchases' then b.purchases end desc,
     case when p_sort = 'plan_end' then b.plan_ends_at end asc nulls last,
     case when p_sort = 'last_purchase' then b.last_purchase_at end desc nulls last,
     b.created_at desc
   limit least(p_limit, 200) offset greatest(p_offset, 0);
end $$;
