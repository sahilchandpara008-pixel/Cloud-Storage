-- Payments > Orders in pages (10 / 20 / 50 / 100 / 200 rows) instead of one
-- long list of up to 500: same as admin_payment_orders_list plus an offset.

create or replace function public.admin_payment_orders_page(
  p_status text default 'all',
  p_plan   uuid default null,
  p_user   uuid default null,
  p_from   timestamptz default null,
  p_to     timestamptz default null,
  p_sort   text default 'date_desc',
  p_limit  integer default 20,
  p_offset integer default 0)
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
     o.created_at desc,
     o.id
   limit least(greatest(p_limit, 1), 200)
  offset greatest(coalesce(p_offset, 0), 0);
end $$;
revoke execute on function public.admin_payment_orders_page(text, uuid, uuid, timestamptz, timestamptz, text, integer, integer) from public, anon;
grant execute on function public.admin_payment_orders_page(text, uuid, uuid, timestamptz, timestamptz, text, integer, integer) to authenticated;
