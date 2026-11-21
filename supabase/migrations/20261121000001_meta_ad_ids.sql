-- Meta ad measurement IDs from app 1.11.4+ (2026-11-21).
--
-- Ads Manager credited no installs or purchases: Meta received every event
-- but could not tell which phone (and so which ad click) each came from.
-- From 1.11.4 the app includes Meta's SDK (it reports installs itself) and
-- sends us two IDs once:
--   * fb_anon_id: the SDK's anonymous install ID, and
--   * ad_id: the phone's advertising ID, only when the user has not turned
--     off ad personalisation.
-- Every event of that install now carries them (user_data.anon_id and
-- user_data.madid), so Meta can match checkouts and purchases to the ad.
-- Events are sent once they are 30 seconds old, so an install's IDs (sent
-- by the app right after the install) are on its first event too.

alter table public.installs add column if not exists fb_anon_id text;
alter table public.installs add column if not exists ad_id text;

create or replace function public.record_ad_ids(p_install_id uuid, p_fb_anon_id text default null, p_ad_id text default null)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_anon text := nullif(left(trim(coalesce(p_fb_anon_id, '')), 100), '');
  v_ad   text := lower(nullif(trim(coalesce(p_ad_id, '')), ''));
begin
  if auth.uid() is null then return; end if;
  if v_ad is not null and (v_ad !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                           or v_ad = '00000000-0000-0000-0000-000000000000') then
    v_ad := null;
  end if;
  if v_anon is not null and v_anon !~ '^[A-Za-z0-9_.:-]+$' then
    v_anon := null;
  end if;
  update public.installs
     set fb_anon_id = coalesce(v_anon, fb_anon_id),
         ad_id      = v_ad,  -- cleared when the user turns ad personalisation off
         updated_at = now()
   where install_id = p_install_id
     and (first_user_id is null or first_user_id = auth.uid()
          or exists (select 1 from public.user_attribution ua
                      where ua.user_id = auth.uid()
                        and p_install_id in (ua.first_touch_install_id, ua.last_touch_install_id)));
end $$;
revoke execute on function public.record_ad_ids(uuid, text, text) from public, anon;
grant execute on function public.record_ad_ids(uuid, text, text) to authenticated;

create or replace function public.meta_event_payload(e public.meta_events, s public.meta_settings)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $function$
declare
  v_email text;
  v_user  jsonb := '{}'::jsonb;
  v_ev    jsonb;
  v_inst  public.installs;
  v_click public.ad_clicks;
  v_ip    text;
  v_ua    text;
  v_app   jsonb;
  v_anon  text;
begin
  if e.ad_click_id is not null then
    select * into v_click from public.ad_clicks where id = e.ad_click_id;
  end if;
  select * into v_inst from public.installs i
   where i.install_id = coalesce(
           e.install_id,
           (select coalesce(ua.last_touch_install_id, ua.first_touch_install_id)
              from public.user_attribution ua where ua.user_id = e.user_id),
           (select i2.install_id from public.installs i2 where i2.first_user_id = e.user_id
             order by i2.created_at desc limit 1));
  if v_click.id is null and v_inst.ad_click_id is not null then
    select * into v_click from public.ad_clicks where id = v_inst.ad_click_id;
  end if;

  if e.user_id is not null then
    select email into v_email from auth.users where id = e.user_id;
    v_user := jsonb_build_object('external_id', jsonb_build_array(public.meta_sha256(e.user_id::text)));
    if v_email is not null then
      v_user := v_user || jsonb_build_object('em', jsonb_build_array(public.meta_sha256(v_email)));
    end if;
  elsif e.install_id is not null then
    v_user := jsonb_build_object('external_id', jsonb_build_array(public.meta_sha256(e.install_id::text)));
  elsif v_click.id is not null then
    v_user := jsonb_build_object('external_id', jsonb_build_array(public.meta_sha256(v_click.id::text)));
  end if;
  v_user := v_user || jsonb_build_object('country', jsonb_build_array(public.meta_sha256('in')));

  v_ip := coalesce(e.client_ip, v_click.client_ip, v_inst.client_ip);
  v_ua := coalesce(v_click.user_agent, e.user_agent, v_inst.user_agent);
  if coalesce(v_click.fbc, v_inst.fbc) is not null then
    v_user := v_user || jsonb_build_object('fbc', coalesce(v_click.fbc, v_inst.fbc));
  end if;
  if coalesce(v_click.fbp, v_inst.fbp) is not null then
    v_user := v_user || jsonb_build_object('fbp', coalesce(v_click.fbp, v_inst.fbp));
  end if;
  if v_ip is not null then v_user := v_user || jsonb_build_object('client_ip_address', v_ip); end if;
  if v_ua is not null then v_user := v_user || jsonb_build_object('client_user_agent', v_ua); end if;

  if s.action_source = 'app' then
    -- The Meta SDK's install ID when the app sent it (1.11.4+), so Meta ties
    -- these events to the install the SDK reported; else our own install ID.
    v_anon := coalesce(v_inst.fb_anon_id, e.install_id::text, v_inst.install_id::text);
    if v_anon is not null then
      v_user := v_user || jsonb_build_object('anon_id', v_anon);
    end if;
    -- Advertising ID (not hashed, as Meta asks); only stored when the user
    -- has not turned off ad personalisation.
    if v_inst.ad_id is not null then
      v_user := v_user || jsonb_build_object('madid', v_inst.ad_id);
    end if;
  end if;

  v_ev := jsonb_build_object(
    'event_name', e.event_name,
    'event_time', extract(epoch from e.event_time)::bigint,
    'event_id', e.event_id,
    'action_source', s.action_source,
    'user_data', v_user);
  if e.custom_data is not null and e.custom_data <> '{}'::jsonb then
    v_ev := v_ev || jsonb_build_object('custom_data', e.custom_data);
  end if;

  if s.action_source = 'app' then
    v_app := jsonb_build_object(
      'advertiser_tracking_enabled', case when v_inst.ad_id is not null or v_inst.fb_anon_id is null then 1 else 0 end,
      'application_tracking_enabled', 1,
      'extinfo', jsonb_build_array('a2', s.app_package, '1.0', '1.0', '13', 'Android', 'en_IN', 'IST',
                                   '', '1080', '2400', '2.75', '8', '64', '32', 'Asia/Kolkata'));
    if v_inst.referrer_status = 'ok' and v_inst.source = public.ad_source()
       and coalesce(v_inst.raw_referrer, '') <> '' then
      v_app := v_app || jsonb_build_object(
        'install_referrer', v_inst.raw_referrer,
        'installer_package', 'com.android.vending');
    end if;
    v_ev := v_ev || jsonb_build_object('app_data', v_app);
  else
    v_ev := v_ev || jsonb_build_object('event_source_url',
      coalesce(v_click.page_url, s.website_url, 'https://example.com'));
  end if;
  return v_ev;
end $function$;

-- Same sender as before; only events at least 30 seconds old are sent.
create or replace function public.meta_dispatch()
returns integer
language plpgsql security definer set search_path = ''
as $function$
declare
  s     public.meta_settings;
  v_ids bigint[];
  v_req bigint;
  v_n   int := 0;
begin
  if to_regclass('net.http_request_queue') is null then
    return 0;  -- pg_net not installed (local tests)
  end if;

  execute $q$
    update public.meta_events e
       set status = case when r.status_code between 200 and 299 then 'ok'
                         when e.attempts >= 5 then 'failed' else 'queued' end,
           response = left(coalesce(r.content::text, r.error_msg, ''), 1000)
      from net._http_response r
     where e.status = 'sent' and r.id = e.request_id
  $q$;
  update public.meta_events
     set status = case when attempts >= 5 then 'failed' else 'queued' end,
         response = coalesce(response, 'no response from Meta')
   where status = 'sent' and sent_at < now() - interval '10 minutes';

  select * into s from public.meta_settings where id = 1;
  if not found or not s.enabled or s.pixel_id is null or s.access_token is null then
    return 0;
  end if;

  select array_agg(id order by id) into v_ids
    from (select id from public.meta_events
           where status = 'queued' and created_at < now() - interval '30 seconds'
           order by id limit 50) q;
  if v_ids is null then return 0; end if;

  execute $q$
    select net.http_post(
      url     := 'https://graph.facebook.com/v21.0/' || $1 || '/events',
      body    := $2,
      params  := jsonb_build_object('access_token', $3),
      headers := '{"Content-Type": "application/json"}'::jsonb,
      timeout_milliseconds := 30000)
  $q$
  into v_req
  using s.pixel_id,
        jsonb_strip_nulls(jsonb_build_object(
          'data', (select jsonb_agg(public.meta_event_payload(e, s) order by e.id)
                     from public.meta_events e where e.id = any (v_ids)),
          'test_event_code', nullif(trim(coalesce(s.test_event_code, '')), ''))),
        s.access_token;

  update public.meta_events
     set status = 'sent', request_id = v_req, attempts = attempts + 1, sent_at = now()
   where id = any (v_ids);
  get diagnostics v_n = row_count;
  return v_n;
end $function$;

-- ------------------------------------------------------------ payment funnel
-- Admin "Payment funnel": of the phones that installed the app in the range,
-- how many started a payment, how many paid and how many never managed to
-- pay; split by ads / organic. Plus every order made in the range by
-- outcome and the most common reasons orders did not go through.
-- Admin accounts (own test payments) are left out.
create or replace function public.admin_payment_funnel(
  p_from timestamptz default null,
  p_to   timestamptz default null)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v jsonb;
begin
  if not public.is_owner() then raise exception 'only the owner can see payment reports'; end if;
  with pay as (
    select o.user_id,
           true as tried,
           bool_or(o.status = 'approved') as paid,
           bool_or(o.status in ('initiated', 'pending')) as open
      from public.payment_orders o
     group by o.user_id
  ), per as (
    select case when i.source = public.ad_source() then 'ads' else 'organic' end as grp,
           coalesce(p.tried, false) as tried,
           coalesce(p.paid, false) as paid,
           coalesce(p.open and not p.paid, false) as waiting
      from public.installs i
      left join pay p on p.user_id = i.first_user_id
     where (p_from is null or i.created_at >= p_from) and (p_to is null or i.created_at < p_to)
       and not exists (select 1 from public.admins a where a.user_id = i.first_user_id)
  ), grp as (
    select g.grp,
           count(*) as installs,
           count(*) filter (where tried) as tried,
           count(*) filter (where paid) as paid,
           count(*) filter (where tried and not paid and waiting) as waiting,
           count(*) filter (where tried and not paid and not waiting) as not_paid
      from (select 'all' as grp, tried, paid, waiting from per
            union all select grp, tried, paid, waiting from per) g
     group by g.grp
  ), ord as (
    select o.* from public.payment_orders o
     where not exists (select 1 from public.admins a where a.user_id = o.user_id)
       and (p_from is null or o.created_at >= p_from) and (p_to is null or o.created_at < p_to)
  )
  select jsonb_build_object(
    'groups', (select coalesce(jsonb_object_agg(grp, jsonb_build_object(
                 'installs', installs, 'tried', tried, 'paid', paid, 'not_paid', not_paid, 'waiting', waiting)), '{}'::jsonb) from grp),
    'orders', (select jsonb_build_object(
                 'total', count(*),
                 'approved', count(*) filter (where status = 'approved'),
                 'failed', count(*) filter (where status = 'failed'),
                 'cancelled', count(*) filter (where status = 'cancelled'),
                 'pending', count(*) filter (where status in ('initiated', 'pending')),
                 'revoked', count(*) filter (where status = 'revoked')) from ord),
    'reasons', (select coalesce(jsonb_agg(jsonb_build_object('reason', reason, 'n', n) order by n desc), '[]'::jsonb)
                  from (select coalesce(nullif(trim(status_reason), ''), case status when 'cancelled' then 'Cancelled (no answer within 24 h or closed by the user)' else 'No reason given' end) as reason,
                               count(*) as n
                          from ord where status in ('failed', 'cancelled')
                         group by 1 order by 2 desc limit 6) r))
  into v;
  return v;
end $$;
revoke execute on function public.admin_payment_funnel(timestamptz, timestamptz) from public, anon;
grant execute on function public.admin_payment_funnel(timestamptz, timestamptz) to authenticated;
