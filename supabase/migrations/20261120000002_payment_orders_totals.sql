-- Payments > Orders (2026-11-20).
--
-- 1. The "Received" total was added up in the browser from the first 500
--    orders shown, and included the owner's own test payments. The totals now
--    come from the database (all matching orders) and leave admin test
--    payments out; those orders are marked "Admin test" in the list.
-- The list is admin_payment_orders_list (admin_payment_orders_filtered
-- plus an admin_test column); the old function is left as it was.
-- 2. With "Success" picked, the date filter now uses the approval time, like
--    the dashboard and the plan summary, so "View orders" from the plan
--    summary lists exactly the orders it counted.

create or replace function public.admin_payment_orders_list(
  p_status text default 'all',
  p_plan   uuid default null,
  p_user   uuid default null,
  p_from   timestamptz default null,
  p_to     timestamptz default null,
  p_sort   text default 'date_desc',
  p_limit  integer default 300)
returns table(id uuid, reference text, user_id uuid, email text, display_name text, source text,
              plan_id uuid, plan_name text, amount_paise integer, status text, status_reason text,
              upi_response text, client_status text, txn_id text, verification_source text,
              reviewed_by_email text, report_count integer, created_at timestamptz,
              updated_at timestamptz, verified_at timestamptz, user_purchases integer,
              admin_test boolean)
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_owner() then raise exception 'only the owner can list payments'; end if;
  perform public.cancel_stale_payment_orders();
  return query
  select o.id, o.reference, o.user_id, u.email::text, p.display_name, public.source_of(o.user_id),
         o.plan_id, pl.name, o.amount_paise, o.status, o.status_reason, o.upi_response, o.client_status,
         o.txn_id, o.verification_source, r.email::text, o.report_count, o.created_at, o.updated_at,
         o.verified_at,
         (select count(*)::int from public.payment_orders x
           where x.user_id = o.user_id and x.status = 'approved'),
         public.is_admin_user(o.user_id)
    from public.payment_orders o
    join auth.users u on u.id = o.user_id
    left join public.profiles p on p.id = o.user_id
    join public.plans pl on pl.id = o.plan_id
    left join auth.users r on r.id = o.reviewed_by
   where (case p_status
           when 'pending' then o.status in ('initiated', 'pending')
           when 'success' then o.status = 'approved'
           when 'failed' then o.status = 'failed'
           when 'cancelled' then o.status = 'cancelled'
           when 'revoked' then o.status = 'revoked'
           else true end)
     and (p_plan is null or o.plan_id = p_plan)
     and (p_user is null or o.user_id = p_user)
     and (p_from is null or (case when p_status = 'success' then o.verified_at else o.created_at end) >= p_from)
     and (p_to is null or (case when p_status = 'success' then o.verified_at else o.created_at end) < p_to)
   order by
     case when p_sort = 'amount_desc' then o.amount_paise end desc nulls last,
     case when p_sort = 'amount_asc'  then o.amount_paise end asc nulls last,
     case when p_sort = 'plan'        then pl.position end asc nulls last,
     case when p_sort = 'plan'        then pl.name end asc nulls last,
     case when p_sort = 'date_asc'    then o.created_at end asc nulls last,
     o.created_at desc
   limit least(greatest(p_limit, 1), 1000);
end $$;
revoke execute on function public.admin_payment_orders_list(text, uuid, uuid, timestamptz, timestamptz, text, integer) from public, anon;
grant execute on function public.admin_payment_orders_list(text, uuid, uuid, timestamptz, timestamptz, text, integer) to authenticated;

-- Totals for the same filters, over every matching order (no limit).
create or replace function public.admin_payment_orders_totals(
  p_status text default 'all',
  p_plan   uuid default null,
  p_user   uuid default null,
  p_from   timestamptz default null,
  p_to     timestamptz default null)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v jsonb;
begin
  if not public.is_owner() then raise exception 'only the owner can list payments'; end if;
  with m as (
    select o.status, o.amount_paise, public.is_admin_user(o.user_id) as admin_test
      from public.payment_orders o
     where (case p_status
             when 'pending' then o.status in ('initiated', 'pending')
             when 'success' then o.status = 'approved'
             when 'failed' then o.status = 'failed'
             when 'cancelled' then o.status = 'cancelled'
             when 'revoked' then o.status = 'revoked'
             else true end)
       and (p_plan is null or o.plan_id = p_plan)
       and (p_user is null or o.user_id = p_user)
       and (p_from is null or (case when p_status = 'success' then o.verified_at else o.created_at end) >= p_from)
       and (p_to is null or (case when p_status = 'success' then o.verified_at else o.created_at end) < p_to)
  )
  select jsonb_build_object(
    'orders',         (select count(*) from m),
    'successful',     (select count(*) from m where status = 'approved' and not admin_test),
    'received_paise', (select coalesce(sum(amount_paise), 0) from m where status = 'approved' and not admin_test),
    'test_orders',    (select count(*) from m where status = 'approved' and admin_test))
  into v;
  return v;
end $$;
revoke execute on function public.admin_payment_orders_totals(text, uuid, uuid, timestamptz, timestamptz) from public, anon;
grant execute on function public.admin_payment_orders_totals(text, uuid, uuid, timestamptz, timestamptz) to authenticated;
