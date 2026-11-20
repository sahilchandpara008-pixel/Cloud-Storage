-- Meta: make installs count in Ads Manager (2026-11-20).
--
-- What was wrong
--   Ads Manager showed no installs although Meta accepted every event. On
--   Meta's side the app was flagged "app_install_tracked: false": it had
--   never received an install. Two reasons:
--   1. The install was sent as "AppInstall". That is a custom event name.
--      Meta's name for an app install sent through the Conversions API is
--      "MobileAppInstall" (see Conversions API for App Events); only that one
--      is counted as "App installs".
--   2. Events did not carry the installation ID, so Meta could not tie a
--      sign-up or a purchase to the install of the same phone.
--
-- What changes (server only; the app is not touched)
--   * Every install also sends "MobileAppInstall". "AppInstall" is still
--     sent, because ad sets may already be optimised for it.
--   * Every app event carries user_data.anon_id = the app's installation ID.
--   * Meta's own click reference (the Google Play install referrer of a Meta
--     ad install) is passed back as app_data.install_referrer, only for
--     installs that came from a Meta ad. Other installs send no referrer.
--   * An event without custom data sends no empty custom_data object.
--   * The owner's "Send test event" uses the name "TestEvent" so it is no
--     longer counted as a real ViewContent.

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
  v_anon  uuid;
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

  -- App events: the installation ID (not hashed, as Meta asks). It is the
  -- same on the install event and on everything that phone does later.
  v_anon := coalesce(e.install_id, v_inst.install_id);
  if s.action_source = 'app' and v_anon is not null then
    v_user := v_user || jsonb_build_object('anon_id', v_anon::text);
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
      'advertiser_tracking_enabled', 1,
      'application_tracking_enabled', 1,
      'extinfo', jsonb_build_array('a2', s.app_package, '1.0', '1.0', '13', 'Android', 'en_IN', 'IST',
                                   '', '1080', '2400', '2.75', '8', '64', '32', 'Asia/Kolkata'));
    -- Installed from Google Play through a Meta ad: Google hands the app
    -- Meta's own click reference. Passing it back lets Meta match the
    -- install, and what this phone does later, to the ad.
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

-- One install = "AppInstall" (as before) + Meta's standard "MobileAppInstall".
create or replace function public.meta_on_install()
returns trigger
language plpgsql security definer set search_path = ''
as $function$
begin
  perform public.meta_enqueue('AppInstall', 'install-' || new.install_id, new.first_user_id, new.install_id,
                              jsonb_build_object('source', new.source, 'campaign', new.utm_campaign));
  -- Only meaningful as an app event.
  if exists (select 1 from public.meta_settings where id = 1 and action_source = 'app') then
    perform public.meta_enqueue('MobileAppInstall', 'mobile-install-' || new.install_id,
                                new.first_user_id, new.install_id, '{}'::jsonb);
  end if;
  return new;
end $function$;

-- The owner's test button: a clearly named test event, not a ViewContent.
create or replace function public.admin_meta_test_event()
returns void
language plpgsql security definer set search_path = ''
as $function$
begin
  if not public.is_owner() then raise exception 'only the owner can send test events'; end if;
  if not exists (select 1 from public.meta_settings
                  where id = 1 and enabled and pixel_id is not null and access_token is not null) then
    raise exception 'enter the Pixel ID and access token and turn tracking on first';
  end if;
  perform public.meta_enqueue('TestEvent', 'test-' || gen_random_uuid(), auth.uid(), null,
                              jsonb_build_object('content_type', 'test'));
  perform public.meta_dispatch();
end $function$;
