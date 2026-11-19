-- =============================================================================
-- Admin reports: users and subscribers by date range.
--
-- admin_users gains a sign-up date range, more filters, sorting, purchase
-- totals per user and the total number of matches (for paging). The first
-- four parameters keep their order, so existing calls keep working.
-- admin_user_stats gives the numbers for the summary tiles. Dates are passed
-- as timestamps (the admin turns Indian dates into IST day boundaries).
-- Owner only, like before.
-- =============================================================================

drop function if exists public.admin_users(text, text, integer, integer);

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
  total_count bigint)
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
           exists (select 1 from public.subscriptions s where s.user_id = p.id) as ever_subscribed
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
         count(*) over () as total_count
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
           when 'ads'        then b.source = 'ads'
           when 'organic'    then b.source = 'organic'
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

-- Summary numbers for a date range (null = all time).
create or replace function public.admin_user_stats(p_from timestamptz default null, p_to timestamptz default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v jsonb;
begin
  if not public.is_owner() then
    raise exception 'only the owner can see user reports';
  end if;
  with users as (
    select p.id, p.is_guest, public.source_of(p.id) as source
      from public.profiles p
     where not exists (select 1 from public.admins a where a.user_id = p.id)
       and (p_from is null or p.created_at >= p_from)
       and (p_to is null or p.created_at < p_to)
  ), paid as (
    select o.user_id, o.plan_id, o.amount_paise, o.verified_at
      from public.payment_orders o
     where o.status = 'approved'
       and (p_from is null or o.verified_at >= p_from)
       and (p_to is null or o.verified_at < p_to)
  ), first_paid as (
    select o.user_id, min(o.verified_at) as first_at
      from public.payment_orders o where o.status = 'approved' group by o.user_id
  ), active as (
    select distinct on (s.user_id) s.user_id, s.plan_id
      from public.subscriptions s
     where now() between s.starts_at and s.ends_at
       and not exists (select 1 from public.admins a where a.user_id = s.user_id)
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
    'all_users',        (select count(*) from public.profiles p
                          where not exists (select 1 from public.admins a where a.user_id = p.id)),
    'by_plan', (select coalesce(jsonb_agg(jsonb_build_object(
                    'plan', pl.name, 'price_inr', pl.price_inr,
                    'active_now', (select count(*) from active a where a.plan_id = pl.id),
                    'sold', (select count(*) from paid x where x.plan_id = pl.id),
                    'revenue_paise', (select coalesce(sum(x.amount_paise), 0) from paid x where x.plan_id = pl.id))
                  order by pl.position, pl.price_inr), '[]'::jsonb)
                  from public.plans pl))
  into v;
  return v;
end $$;

revoke execute on function public.admin_user_stats(timestamptz, timestamptz) from public, anon;
grant execute on function public.admin_user_stats(timestamptz, timestamptz) to authenticated;

notify pgrst, 'reload schema';
