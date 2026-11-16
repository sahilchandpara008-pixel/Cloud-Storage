-- =============================================================================
-- Guest checkout: a guest (anonymous session) may now buy a plan without
-- signing up first. Nothing else changes -- the order/subscription are
-- still tied to auth.uid() exactly as before, and a guest who later signs
-- up with email or Google keeps that same user id (see the app's own
-- "upgrade a guest's account in place" sign-up/sign-in flow), so their plan
-- carries over automatically. The only real difference: if a guest never
-- links an account and loses their session (uninstall, clear data, new
-- phone), the purchase can't be recovered -- there's no email to recover it
-- with. That trade-off is intentional, in exchange for a faster checkout.
-- =============================================================================

create or replace function public.create_payment_order(p_plan_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid      uuid := auth.uid();
  v_plan     public.plans;
  v_settings public.payment_settings;
  v_order    public.payment_orders;
begin
  if v_uid is null then
    raise exception 'login required';
  end if;
  select * into v_settings from public.payment_settings where id = 1;
  if not found or not v_settings.enabled then
    raise exception 'payments are not available right now';
  end if;
  select * into v_plan from public.plans where id = p_plan_id and active;
  if not found then raise exception 'plan not available'; end if;

  perform public.cancel_stale_payment_orders();

  -- Reuse the open order for the same plan (24 h) if its price is unchanged.
  select * into v_order from public.payment_orders
   where user_id = v_uid and plan_id = p_plan_id and status in ('initiated', 'pending')
     and amount_paise = v_plan.price_inr * 100
     and created_at > now() - interval '24 hours'
   order by created_at desc limit 1;

  -- Close the user's other open orders.
  with c as (
    update public.payment_orders
       set status = 'cancelled', status_reason = 'replaced by a new order', updated_at = now()
     where user_id = v_uid and status in ('initiated', 'pending')
       and (v_order.id is null or id <> v_order.id)
    returning id)
  insert into public.payment_events (order_id, kind, detail, actor_id)
  select id, 'cancelled', 'replaced by a new order', v_uid from c;

  if v_order.id is null then
    insert into public.payment_orders (reference, user_id, plan_id, amount_paise)
    values ('CS' || to_char(now() at time zone 'Asia/Kolkata', 'YYMMDD')
                 || upper(substr(md5(gen_random_uuid()::text), 1, 12)),
            v_uid, v_plan.id, v_plan.price_inr * 100)
    returning * into v_order;
    insert into public.payment_events (order_id, kind, detail, actor_id)
    values (v_order.id, 'created', v_plan.code, v_uid);
  end if;

  return jsonb_build_object(
    'order_id',   v_order.id,
    'reference',  v_order.reference,
    'amount',     to_char(v_order.amount_paise / 100.0, 'FM999999990.00'),
    'plan_name',  v_plan.name,
    'upi_id',     v_settings.upi_id,
    'payee_name', v_settings.payee_name,
    'status',     v_order.status);
end $$;
